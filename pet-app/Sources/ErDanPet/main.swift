import AppKit
import WebKit

// MARK: - 路径
let petHome = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Desktop/PetAssistant")
let webDir = petHome.appendingPathComponent("pet-app/web")
let tasksFile = petHome.appendingPathComponent("pet-data/tasks.md")
let inboxFile = petHome.appendingPathComponent("pet-data/inbox.md")
let chatLogFile = petHome.appendingPathComponent("pet-data/chat.log")   // 完整聊天流水:用户/模型原始输出/工具结果/回复
let memDir = petHome.appendingPathComponent("pet-app/mem")               // 向量记忆服务(fastembed+zvec,常驻)
let aboutFile = petHome.appendingPathComponent("pet-data/about-you.md")
let dailyDir = petHome.appendingPathComponent("pet-data/daily")
let configFile = petHome.appendingPathComponent("pet-config.json")
let remindersFile = petHome.appendingPathComponent("pet-data/reminders.json")
let reportsDir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Desktop/BranchReports")
let skillsDir = petHome.appendingPathComponent("skills")   // 动态 skill:每个子目录一个 skill.json + 脚本

let MAX_AGENT_STEPS = 7

// 一个动态 skill(来自 skills/<name>/skill.json)
struct PetSkill { let name: String; let desc: String; let args: [String: String]; let runPath: String; let dir: String }

// MARK: - 无边框窗口须重写才能收键盘
final class PetWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class DraggableWebView: WKWebView {
    var onDrag: (() -> Void)?
    var onDragEnd: (() -> Void)?
    var onDropFile: ((String) -> Void)?
    private var initialLocation: NSPoint?

    // 拖文件到宠物上 → 当附件
    override func draggingEntered(_ s: NSDraggingInfo) -> NSDragOperation {
        s.draggingPasteboard.canReadObject(forClasses: [NSURL.self]) ? .copy : []
    }
    override func performDragOperation(_ s: NSDraggingInfo) -> Bool {
        guard let urls = s.draggingPasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
              let u = urls.first else { return false }
        onDropFile?(u.path); return true
    }
    private var dragged = false
    private var totalMove: CGFloat = 0
    override func mouseDown(with event: NSEvent) { initialLocation = event.locationInWindow; dragged = false; totalMove = 0; super.mouseDown(with: event) }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let initial = initialLocation else { super.mouseDragged(with: event); return }
        let cur = event.locationInWindow
        let dx = cur.x - initial.x, dy = cur.y - initial.y
        totalMove += abs(dx) + abs(dy)
        if totalMove < 4 { super.mouseDragged(with: event); return }   // 小抖动仍算点击
        dragged = true
        onDrag?()
        var o = window.frame.origin
        o.x += dx; o.y += dy
        window.setFrameOrigin(o)
    }
    override func mouseUp(with event: NSEvent) {
        if dragged { onDragEnd?() }   // 发生过拖动 → 抑制这次点击
        super.mouseUp(with: event)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, WKScriptMessageHandler, WKNavigationDelegate {
    var window: PetWindow!
    var webView: DraggableWebView!
    enum Motion: String { case idle, walk, run, jump }
    var motion: Motion = .idle
    var dir: CGFloat = -1        // 朝向:-1=脸朝右(尾在左),+1=脸朝左(尾在右);起步朝右
    var stateRemain: TimeInterval = 2
    var baseY: CGFloat = 0
    var snapPending = false        // 拖动结束后,下一帧吸附到最近的边
    var paused = false
    var uiOpen = false
    var skills: [PetSkill] = []
    var dragPauseUntil = Date.distantPast
    var engineTimer: Timer?
    var history: [[String: String]] = []        // 最近几轮"用户↔二蛋"对话(供模型理解上下文)
    let HISTORY_MAX = 8                            // 最多保留 8 条(约 4 轮一问一答)
    var memProc: Process?                          // 常驻的向量记忆服务进程
    let MEM_PORT = 8790
    struct Attachment { let name: String; let isImage: Bool; let text: String; let dataURL: String }
    var pendingAttach: Attachment?                 // 待发送的附件(📎选择或拖入,随下一条消息带上)
    let idleSize = NSSize(width: 170, height: 210)   // 待机:只有小龙
    let chatSize = NSSize(width: 288, height: 366)   // 对话:聊天卡片
    var chatMode = false

    func applicationDidFinishLaunching(_ n: Notification) {
        guard let screen = NSScreen.main else { NSApp.terminate(nil); return }
        baseY = screen.visibleFrame.minY
        let origin = NSPoint(x: screen.visibleFrame.maxX - idleSize.width - 40, y: baseY)
        window = PetWindow(contentRect: NSRect(origin: origin, size: idleSize), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false; window.backgroundColor = .clear
        window.level = .floating; window.hasShadow = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .nonPersistent()   // 不缓存,避免换素材后仍显示旧图
        cfg.userContentController.add(self, name: "pet")
        webView = DraggableWebView(frame: NSRect(origin: .zero, size: idleSize), configuration: cfg)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = self
        webView.onDrag = { [weak self] in self?.dragPauseUntil = Date().addingTimeInterval(3) }
        webView.onDragEnd = { [weak self] in self?.snapPending = true; self?.webView.evaluateJavaScript("window.__dragSuppress=(window.performance.now())", completionHandler: nil) }
        webView.onDropFile = { [weak self] path in self?.attachFile(path) }
        webView.registerForDraggedTypes([.fileURL])
        window.contentView = webView
        webView.loadFileURL(webDir.appendingPathComponent("pet.html"), allowingReadAccessTo: webDir)

        loadSkills()
        startMemService()          // 后台拉起向量记忆服务(模型加载 + 建索引在它自己进程里)
        installEditMenu()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        Timer.scheduledTimer(withTimeInterval: 1800, repeats: true) { [weak self] _ in self?.pushTasks() }
        Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in self?.checkReminders(); self?.checkDailyReport() }
        // 鼠标跟踪:只有指针在宠物一带(或面板展开)才让窗口可点,其余空白区域点击穿透,不挡其他应用
        Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in self?.updateClickThrough() }
    }

    func applicationWillTerminate(_ n: Notification) { stopMemService() }

    func updateClickThrough() {
        let m = NSEvent.mouseLocation                 // 屏幕坐标(左下原点)
        let f = window.frame
        // 巡逻时宠物会绕到任意边,窗口不大,指针落在窗口内即视为可交互(便于随处点它开聊天)
        let inWindow = m.x >= f.minX && m.x <= f.maxX && m.y >= f.minY && m.y <= f.maxY
        let interactive = uiOpen || chatMode || inWindow
        if window.ignoresMouseEvents == interactive { window.ignoresMouseEvents = !interactive }
    }

    // 页面加载完成后,直接把插画和动画引擎注入 DOM(不走 file:// fetch)
    func webView(_ w: WKWebView, didFinish navigation: WKNavigation!) {
        guard let svg = try? String(contentsOf: webDir.appendingPathComponent("dragon.svg"), encoding: .utf8),
              let eng = try? String(contentsOf: webDir.appendingPathComponent("engine.js"), encoding: .utf8) else { return }
        // 用 JSON 编码把 SVG 安全塞进 JS 字符串
        guard let d = try? JSONSerialization.data(withJSONObject: [svg]),
              let arr = String(data: d, encoding: .utf8) else { return }
        w.evaluateJavaScript("document.getElementById('dragon-wrap').innerHTML = (\(arr))[0];") { _, _ in
            w.evaluateJavaScript(eng, completionHandler: nil)
        }
    }

    func installEditMenu() {
        let main = NSMenu(); let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit"); editItem.submenu = edit
        func add(_ t: String, _ s: Selector, _ k: String) { edit.addItem(NSMenuItem(title: t, action: s, keyEquivalent: k)) }
        add("Cut", #selector(NSText.cut(_:)), "x"); add("Copy", #selector(NSText.copy(_:)), "c")
        add("Paste", #selector(NSText.paste(_:)), "v"); add("Select All", #selector(NSText.selectAll(_:)), "a")
        NSApp.mainMenu = main
    }

    // MARK: 游走引擎(窗口在桌面移动;龙内部播放对应步态)
    func startEngine() {
        engineTimer?.invalidate()
        engineTimer = Timer.scheduledTimer(withTimeInterval: 1.0/30, repeats: true) { [weak self] _ in self?.tick(1.0/30) }
    }
    func tick(_ dt: TimeInterval) {
        guard let screen = NSScreen.main else { return }
        if paused || Date() < dragPauseUntil { if motion != .idle { setMotion(.idle) }; return }
        if snapPending { snapToBottom(); snapPending = false }
        stateRemain -= dt
        if stateRemain <= 0 { chooseNext() }
        var frame = window.frame
        let vf = screen.visibleFrame
        let minX = vf.minX, maxX = vf.maxX - frame.width
        let speed: CGFloat = motion == .run ? 200 : (motion == .walk ? 70 : 0)
        if speed > 0 {
            frame.origin.x += speed * -dir * CGFloat(dt)     // dir=-1 脸朝右→向右移;dir=+1 脸朝左→向左移
            if frame.origin.x <= minX { frame.origin.x = minX; dir = -1; notifyMotion() }   // 撞左墙 → 镜像掉头朝右
            if frame.origin.x >= maxX { frame.origin.x = maxX; dir = 1; notifyMotion() }     // 撞右墙 → 镜像掉头朝左
        }
        frame.origin.y = baseY                                // 始终贴底边
        window.setFrame(frame, display: true)
    }
    func chooseNext() {
        let r = Double.random(in: 0..<1)
        if r < 0.22 { setMotion(.idle); stateRemain = .random(in: 1.5...3.5) }
        else if r < 0.8 { setMotion(.walk); stateRemain = .random(in: 3...7) }
        else { setMotion(.run); stateRemain = .random(in: 1.5...3) }
    }
    func snapToBottom() {                                  // 拖走松手后回到底边继续踱步
        guard let vf = NSScreen.main?.visibleFrame else { return }
        var f = window.frame
        f.origin.y = vf.minY
        f.origin.x = min(max(f.origin.x, vf.minX), vf.maxX - f.width)
        window.setFrame(f, display: true)
    }
    // 待机/对话 两态:窗口按状态缩放(底边固定、水平居中,限制在屏内)
    func setWindowMode(_ mode: String) {
        chatMode = (mode == "chat")
        paused = chatMode
        let target = chatMode ? chatSize : idleSize
        guard let vf = NSScreen.main?.visibleFrame else { return }
        let f = window.frame
        var newX = f.midX - target.width / 2
        newX = min(max(newX, vf.minX), vf.maxX - target.width)
        let newFrame = NSRect(x: newX, y: baseY, width: target.width, height: target.height)
        window.setFrame(newFrame, display: true)
        webView.frame = NSRect(origin: .zero, size: target)
        if !chatMode { dir = -1; notifyMotion() }   // 退出聊天回底部,朝右
    }
    func setMotion(_ m: Motion) { motion = m; notifyMotion() }
    func notifyMotion() { send(["type": "motion", "state": motion.rawValue, "dir": dir > 0 ? 1 : -1]) }

    // MARK: 向量记忆服务(常驻子进程;装好 venv 才启用,否则聊天照常无检索)
    func startMemService() {
        let py = memDir.appendingPathComponent(".venv/bin/python").path
        guard FileManager.default.isExecutableFile(atPath: py) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: py)
        p.arguments = [memDir.appendingPathComponent("mem_service.py").path, "serve", "\(MEM_PORT)"]
        p.standardOutput = FileHandle.nullDevice; p.standardError = FileHandle.nullDevice
        do { try p.run(); memProc = p } catch { logChat("⚠️ 记忆服务启动失败: \(error)") }
    }
    func stopMemService() { memProc?.terminate(); memProc = nil }

    // MARK: 文件附件(📎 选择 / 拖入 → 处理成图片 base64 或文档文本,挂到 pendingAttach)
    func pickFile() {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseFiles = true; panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        panel.begin { [weak self] resp in
            if resp == .OK, let u = panel.url { self?.attachFile(u.path) }
        }
    }
    func attachFile(_ path: String) {
        let url = URL(fileURLWithPath: path)
        let name = url.lastPathComponent
        let ext = url.pathExtension.lowercased()
        let imgExt = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "heic"]
        if imgExt.contains(ext) {
            guard let data = try? Data(contentsOf: url) else {
                send(["type": "attachError", "text": "读不了这张图:\(name)"]); return
            }
            let mime = (ext == "jpg") ? "jpeg" : ext
            let dataURL = "data:image/\(mime);base64,\(data.base64EncodedString())"
            pendingAttach = Attachment(name: name, isImage: true, text: "", dataURL: dataURL)
            send(["type": "attached", "name": name, "kind": "图片"])
        } else {
            let py = memDir.appendingPathComponent(".venv/bin/python").path
            var text = ""
            if FileManager.default.isExecutableFile(atPath: py) {
                let (out, _) = runProc([py, memDir.appendingPathComponent("file_extract.py").path, path], stdin: nil)
                text = out.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                text = (try? String(contentsOf: url, encoding: .utf8)) ?? "[无法读取该文件]"
            }
            if text.isEmpty || text.hasPrefix("[") && text.hasSuffix("]") {
                send(["type": "attachError", "text": text.isEmpty ? "文件是空的" : text]); return
            }
            pendingAttach = Attachment(name: name, isImage: false, text: text, dataURL: "")
            send(["type": "attached", "name": name, "kind": "文档"])
        }
    }
    // 按当前问题检索相关记忆(短超时;服务没起来/没就绪就返回空,不阻塞聊天)
    func memRecall(_ query: String, k: Int = 5) -> [String] {
        guard let u = URL(string: "http://127.0.0.1:\(MEM_PORT)/recall") else { return [] }
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 4
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: ["query": query, "k": k])
        var lines: [String] = []; let sema = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, _, _ in
            defer { sema.signal() }
            guard let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let rs = o["results"] as? [[String: Any]] else { return }
            for r in rs where (r["text"] as? String) != nil {
                lines.append("[\(r["src"] as? String ?? "")] \(r["text"] as! String)")
            }
        }.resume()
        _ = sema.wait(timeout: .now() + 4.5)
        return lines
    }
    // 记忆有更新(新增任务/事件/长期事实)后,让服务增量重建索引(fire-and-forget)
    func memIngest() {
        guard let u = URL(string: "http://127.0.0.1:\(MEM_PORT)/ingest") else { return }
        var req = URLRequest(url: u); req.httpMethod = "POST"; req.timeoutInterval = 30
        req.httpBody = Data("{}".utf8)
        URLSession.shared.dataTask(with: req).resume()
    }

    // MARK: JS → Swift
    func userContentController(_ u: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let b = message.body as? [String: Any], let type = b["type"] as? String else { return }
        switch type {
        case "ready": pushTasks(); sendConfig(); notifyMotion(); startEngine()
        case "chat": if let t = b["text"] as? String { handleChat(t) }
        case "pause": paused = true
        case "resume": paused = false
        case "setMode": setWindowMode((b["mode"] as? String) ?? "idle")
        case "uiState": uiOpen = (b["open"] as? Bool) ?? false
        case "pickFile": pickFile()
        case "clearAttach": pendingAttach = nil
        case "pasteImage":
            if let durl = b["dataURL"] as? String, durl.hasPrefix("data:image/") {
                let name = (b["name"] as? String) ?? "剪贴板图片.png"
                pendingAttach = Attachment(name: name, isImage: true, text: "", dataURL: durl)
                send(["type": "attached", "name": name, "kind": "图片"])
            }
        case "setTheme": if let th = b["theme"] as? String { mutateConfig { $0["theme"] = th } }
        case "setPart":
            if let part = b["part"] as? String, let style = b["style"] as? String {
                mutateConfig { c in var p = c["parts"] as? [String: String] ?? [:]; p[part] = style; c["parts"] = p }
            }
        case "setPetName":
            if let name = b["name"] as? String { mutateConfig { $0["petName"] = name }; sendConfig() }
        case "quit": stopMemService(); NSApp.terminate(nil)
        case "getConfig": sendConfig()
        case "saveModel": if let m = b["model"] as? [String: String] { saveModel(m) }
        case "selectModel": if let name = b["name"] as? String { mutateConfig { $0["active"] = name }; sendConfig() }
        case "deleteModel":
            if let name = b["name"] as? String {
                mutateConfig { c in
                    var ms = c["models"] as? [[String: String]] ?? []
                    ms.removeAll { $0["name"] == name }; c["models"] = ms
                    if c["active"] as? String == name { c["active"] = ms.first?["name"] ?? "" }
                }
                sendConfig()
            }
        default: break
        }
    }
    func send(_ p: [String: Any]) {
        guard let d = try? JSONSerialization.data(withJSONObject: p), let j = String(data: d, encoding: .utf8) else { return }
        DispatchQueue.main.async { self.webView.evaluateJavaScript("window.petReceive(\(j))", completionHandler: nil) }
    }

    // MARK: 配置
    func loadConfig() -> [String: Any] {
        guard let d = try? Data(contentsOf: configFile), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any]
        else { return ["models": [[String: String]](), "active": ""] }
        return o
    }
    func mutateConfig(_ change: (inout [String: Any]) -> Void) {
        var c = loadConfig(); change(&c)
        if let d = try? JSONSerialization.data(withJSONObject: c, options: [.prettyPrinted]) {
            try? d.write(to: configFile)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configFile.path)
        }
    }
    func saveModel(_ m: [String: String]) {
        mutateConfig { c in
            var ms = c["models"] as? [[String: String]] ?? []
            var e = m
            if (e["apiKey"]?.isEmpty ?? true), let old = ms.first(where: { $0["name"] == m["name"] }) { e["apiKey"] = old["apiKey"] }
            ms.removeAll { $0["name"] == m["name"] }; ms.append(e)
            c["models"] = ms; c["active"] = m["name"]
        }
        sendConfig()
    }
    func sendConfig() {
        let c = loadConfig()
        let ms = (c["models"] as? [[String: String]] ?? []).map { m -> [String: String] in var v = m; v["apiKey"] = nil; return v }
        send(["type": "config", "models": ms, "active": c["active"] as? String ?? "", "theme": c["theme"] as? String ?? "origin", "parts": c["parts"] as? [String: String] ?? [:], "petName": c["petName"] as? String ?? ""])
    }
    func petName() -> String { (loadConfig()["petName"] as? String) ?? "" }
    func activeModel() -> [String: String]? {
        let c = loadConfig(); let ms = c["models"] as? [[String: String]] ?? []
        guard let name = c["active"] as? String, !name.isEmpty else { return ms.first }
        return ms.first { $0["name"] == name } ?? ms.first
    }

    // MARK: 待办 → 弹题素材
    func pushTasks() { send(["type": "tasks", "items": currentTodos()]) }

    // MARK: 动态 skill 加载 / 执行
    func loadSkills() {
        skills = []
        guard let subs = try? FileManager.default.contentsOfDirectory(at: skillsDir, includingPropertiesForKeys: nil) else { return }
        for dir in subs {
            let manifest = dir.appendingPathComponent("skill.json")
            guard let d = try? Data(contentsOf: manifest),
                  let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let name = o["name"] as? String,
                  let run = o["run"] as? String else { continue }
            let args = (o["args"] as? [String: String]) ?? [:]
            skills.append(PetSkill(name: name, desc: o["description"] as? String ?? "",
                                   args: args, runPath: dir.appendingPathComponent(run).path, dir: dir.path))
        }
    }
    func runSkill(_ name: String, _ args: [String: Any]) -> String {
        guard let sk = skills.first(where: { $0.name == name }) else { return "没有名为 \(name) 的 skill" }
        let interp = sk.runPath.hasSuffix(".py") ? "/usr/bin/python3" : "/bin/bash"
        let argJSON = (try? JSONSerialization.data(withJSONObject: args)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        let (out, code) = runProc([interp, sk.runPath], stdin: argJSON, cwd: sk.dir)
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "(skill \(name) 执行完毕,退出码 \(code),无输出)" : String(trimmed.prefix(6000))
    }
    func sendMatrx(_ text: String) -> String { runSkill("send_matrx", ["text": text]) }

    // ======================================================================
    // MARK: - Agent 大脑(ReAct 循环,模型无关)
    // ======================================================================
    func handleChat(_ text: String) {
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            self.appendLine("- [\(self.now("yyyy-MM-dd HH:mm"))] \(text)", to: inboxFile)   // 永不丢话
            self.logChat("👤 用户: \(text)")
            guard let m = self.activeModel(), !((m["apiKey"] ?? "").isEmpty) else {
                self.logChat("⚠️ 未配置模型,仅记入收件箱")
                self.send(["type": "error", "needConfig": true,
                           "text": "记到收件箱啦~还没配置模型,点 ⚙️ 配一个我就能聊天+干活了"]); return
            }
            let recalled = self.memRecall(text)                     // 按这句话检索相关的沉淀记忆
            if !recalled.isEmpty { self.logChat("📚 召回记忆: \(recalled.joined(separator: " | ").prefix(300))") }
            var convo: [[String: Any]] = [["role": "system", "content": self.agentSystemPrompt(recall: recalled)]]
            convo += self.history.map { $0 as [String: Any] }        // 带上最近几轮上下文(纯文本)
            // 组装本轮用户消息:带附件时把文档文本拼进去,或把图片作为结构化 content
            var userContent: Any = text
            var histUser = text                                     // 存进历史的精简版(不含 base64/长文本)
            if let a = self.pendingAttach {
                if a.isImage {
                    userContent = [["type": "text", "text": text.isEmpty ? "帮我看看这张图" : text],
                                   ["type": "image_url", "image_url": ["url": a.dataURL]]]
                    histUser = "\(text) [图片:\(a.name)]"
                } else {
                    userContent = "【附件:\(a.name)】\n\(a.text)\n\n【我的问题】\n\(text.isEmpty ? "帮我看看这个文件" : text)"
                    histUser = "\(text) [文档:\(a.name)]"
                }
                self.logChat("📎 附件: \(a.name) (\(a.isImage ? "图片" : "文档"))")
                self.pendingAttach = nil                             // 用掉就清
            }
            convo.append(["role": "user", "content": userContent])
            for step in 1...MAX_AGENT_STEPS {
                let (out, err) = self.chat(convo)
                guard let out else {
                    self.logChat("❌ 模型调用失败(第\(step)步): \(err ?? "未知")")
                    self.send(["type": "error", "needConfig": false, "text": "已记到收件箱;模型没回话:\(err ?? "未知")"]); return
                }
                self.logChat("🧠 模型(第\(step)步): \(out.prefix(1500))")
                let obj = self.extractJSON(out)
                if let reply = obj?["reply"] as? String, !reply.isEmpty {
                    self.logChat("💬 回复用户: \(reply)")
                    self.remember(turn: histUser, reply: reply)
                    self.pushTasks(); self.send(["type": "reply", "text": reply]); return
                }
                guard let action = obj?["action"] as? String else {
                    // 模型没按协议 → 当作直接回复
                    let plain = self.stripToText(out)
                    self.logChat("💬 回复用户(非协议原样): \(plain)")
                    self.remember(turn: histUser, reply: plain)
                    self.pushTasks(); self.send(["type": "reply", "text": plain]); return
                }
                let args = obj?["args"] as? [String: Any] ?? [:]
                let result = self.runTool(action, args)
                self.logChat("🔧 工具[\(action)] args=\(args) → \(result.prefix(800))")
                if ["add_task", "add_event", "remember", "complete_task"].contains(action) { self.memIngest() }
                convo.append(["role": "assistant", "content": out])
                convo.append(["role": "user", "content": "【工具\(action)结果】\n\(result)\n\n请继续:要么再调用工具,要么给出最终 {\"reply\":\"...\"}。"])
            }
            self.logChat("🔁 达到最大步数(\(MAX_AGENT_STEPS))未收敛")
            self.pushTasks()
            self.send(["type": "reply", "text": "嗯…我绕进去了,先记下了,稍后再帮你弄细 🙈"])
        }
    }
    func logChat(_ s: String) { appendLine("[\(now("yyyy-MM-dd HH:mm:ss"))] \(s)", to: chatLogFile) }
    // 记入对话历史(只保留干净的一问一答,不含工具 JSON 噪声),滚动截断
    func remember(turn user: String, reply: String) {
        history.append(["role": "user", "content": user])
        history.append(["role": "assistant", "content": reply])
        if history.count > HISTORY_MAX { history.removeFirst(history.count - HISTORY_MAX) }
    }

    func agentSystemPrompt(recall: [String] = []) -> String {
        let about = readFile(aboutFile)
        let tasks = readFile(tasksFile)
        let inboxTail = tailLines(inboxFile, 12)
        let recallBlock = recall.isEmpty ? "(无)" : recall.map { "- " + $0 }.joined(separator: "\n")
        return """
        你是主人的桌面宠物小龙\(petName().isEmpty ? "(还没有名字——第一次见面时请主人给你起个名,记到 about-you)" : "「\(petName())」"),是主人的贴身记录助手兼小伙伴。语气简短、温暖、亲密,默认中文。主人是谁、在做什么,看下面「关于主人」的记忆,不要凭空假设。
        现在时间:\(now("yyyy-MM-dd HH:mm EEEE"))。

        你有长期记忆(下面这些就是你的记忆,请据此回答"我有什么任务/我上次说过啥"这类问题,不要瞎编):
        ===== 关于用户 about-you =====
        \(about)
        ===== 当前任务清单 tasks =====
        \(tasks)
        ===== 最近收件箱 inbox(用户近期说的话)=====
        \(inboxTail)
        ===== 相关记忆(按用户这句话从记忆里检索出来的,可能有用;不相关就忽略)=====
        \(recallBlock)
        =====

        你可以调用工具来"干活"。每一步只输出一个 JSON 对象,不要有别的文字:
        · 调用工具:{"action":"工具名","args":{...}}
        · 结束并回复用户:{"reply":"给用户看的话,纯文本"}(平时尽量简短 50 字内;但在解读图片/文件、做解释说明时可以写详细些)

        内置工具:
        - add_task {"text":"任务内容","due":"可选截止,如 2026-07-10"} 新增待办
        - complete_task {"match":"任务编号或关键词"} 把某任务标记完成
        - add_event {"text":"YYYY-MM-DD HH:mm 事情"} 记一个有时间点的安排
        - remember {"fact":"关于用户的长期事实/偏好/黑话"} 写入长期记忆
        - set_reminder {"when":"YYYY-MM-DD HH:mm","text":"提醒内容"} 到点通过 Matrx 提醒用户
        - write_report {"date":"YYYY-MM-DD","markdown":"报告全文"} 把报告写到桌面 BranchReports
        - list_tasks {} 重新读取最新任务清单

        技能(skills,可扩展):
        \(skillsDoc())

        你天生的能力(不是工具,是你自己就会的):**看懂用户发来的图片、读懂用户发来的文件**。
        用户发图片时,图像会直接出现在这条消息里;发文件时,文件内容会以「【附件:文件名】」开头附在消息里。
        遇到这种情况,你要【直接】看图/读文,进行描述、分析、总结、回答——这是你做得到的,绝不能说"我不能分析图片/文件"。

        铁律(必须遵守,违反会误导用户):
        1. 分析用户发来的图片/文件 = 你能做(见上)。除此之外,只有工具/技能清单里的事你才能做;清单里没有的(比如 git 合并、发版上线、改代码、跑构建)才是你【做不到】的——如实告诉用户"这个我做不了,得去对应项目里弄",绝不假装能做,也绝不把"看图/读文件"这种本来会的事推辞掉。
        2. 你【没有后台任务】,不能"稍后/在后台帮你处理"。一轮对话里能用工具做完就做完;做不完或没有对应工具就当场说清楚,禁止用"我在后台跑着呢/稍等一下/正在整理"这类拖延或假装进度的话。
        3. 报告里的提交/分支/人名/数字,只能来自工具真实返回的内容,一个字都不许编。工具说"无提交"就是无提交,不要臆造。
        4. 两个看提交的工具要分清:
           · recent_commits —— 看"最近 N 天的全部提交"(反复看结果一致)。用户问"最近有什么提交/某仓库有没有提交/这几天谁改了啥"时用这个。
           · run_branch_report —— 出"自上次以来的增量日报"(跑完会推进进度,主要给每天定时日报用)。用户明确要"发日报到群"时才用。
           拿不准就用 recent_commits。

        典型:用户说"给群里发个分支日报" → run_branch_report → write_report → send_matrx 精简摘要 → reply;
        用户说"最近各仓库有啥提交" → recent_commits → 据真实结果 reply。
        用户随口说的任务/完成/安排,顺手用对应工具记下来,再温暖地 reply。纯闲聊直接 reply 即可。
        """
    }
    func skillsDoc() -> String {
        if skills.isEmpty { return "(暂无)" }
        return skills.map { sk in
            let a = sk.args.isEmpty ? "{}" : "{" + sk.args.map { "\"\($0.key)\":\"\($0.value)\"" }.joined(separator: ",") + "}"
            return "- \(sk.name) \(a) \(sk.desc)"
        }.joined(separator: "\n")
    }

    // 通用模型调用(OpenAI / Anthropic 格式)。content 可为 String 或结构化数组(带图片)。
    func chat(_ messages: [[String: Any]]) -> (String?, String?) {
        guard let m = activeModel() else { return (nil, "未配置模型") }
        let base = (m["baseURL"] ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "/ "))
        guard !base.isEmpty, let key = m["apiKey"], !key.isEmpty else { return (nil, "模型信息不完整") }
        var req: URLRequest
        if (m["format"] ?? "openai") == "anthropic" {
            let url = base.hasSuffix("/v1") ? base + "/messages" : base + "/v1/messages"
            guard let u = URL(string: url) else { return (nil, "地址无效") }
            req = URLRequest(url: u)
            req.addValue(key, forHTTPHeaderField: "x-api-key")
            req.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let sys = (messages.first { ($0["role"] as? String) == "system" }?["content"] as? String) ?? ""
            let msgs = messages.filter { ($0["role"] as? String) != "system" }
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                "model": m["model"] ?? "", "max_tokens": 900, "system": sys, "messages": msgs] as [String: Any])
        } else {
            let hasVer = base.hasSuffix("/v1") || base.range(of: "/v\\d", options: .regularExpression) != nil
            let url = hasVer ? base + "/chat/completions" : base + "/v1/chat/completions"
            guard let u = URL(string: url) else { return (nil, "地址无效") }
            req = URLRequest(url: u)
            req.addValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.httpBody = try? JSONSerialization.data(withJSONObject: [
                "model": m["model"] ?? "", "temperature": 0.4, "max_tokens": 1000, "messages": messages] as [String: Any])
        }
        req.httpMethod = "POST"
        req.addValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 90
        var result: (String?, String?) = (nil, "请求超时")
        let sema = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: req) { data, resp, error in
            defer { sema.signal() }
            if let error { result = (nil, error.localizedDescription); return }
            guard let data, let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { result = (nil, "响应解析失败"); return }
            if let code = (resp as? HTTPURLResponse)?.statusCode, code >= 300 {
                result = (nil, ((obj["error"] as? [String: Any])?["message"] as? String) ?? "HTTP \(code)"); return
            }
            if let ch = obj["choices"] as? [[String: Any]], let msg = ch.first?["message"] as? [String: Any], let c = msg["content"] as? String { result = (c, nil); return }
            if let cs = obj["content"] as? [[String: Any]], let tp = cs.first(where: { $0["type"] as? String == "text" }), let c = tp["text"] as? String { result = (c, nil); return }
            result = (nil, "未识别的响应结构")
        }.resume()
        _ = sema.wait(timeout: .now() + 95)
        return result
    }

    // MARK: 工具执行
    func runTool(_ action: String, _ args: [String: Any]) -> String {
        switch action {
        case "add_task":
            guard let t = args["text"] as? String, !t.isEmpty else { return "缺少 text" }
            let due = (args["due"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "-"
            insertUnderSection("## 待办", "- [ ] T\(String(format: "%03d", nextTaskNumber())) \(t) |记录:\(now("yyyy-MM-dd")) |截止:\(due) |提醒:-")
            return "已加入待办:\(t)"
        case "complete_task":
            let match = (args["match"] as? String) ?? ""
            return completeTask(match)
        case "add_event":
            guard let t = args["text"] as? String, !t.isEmpty else { return "缺少 text" }
            insertUnderSection("## 事件", "- \(t)"); return "已记入事件:\(t)"
        case "remember":
            guard let f = args["fact"] as? String, !f.isEmpty else { return "缺少 fact" }
            appendLine("- \(f)(\(now("MM-dd")) 记)", to: aboutFile); return "记住啦:\(f)"
        case "set_reminder":
            guard let when = args["when"] as? String, let t = args["text"] as? String else { return "缺少 when/text" }
            addReminder(when: when, text: t); return "已设提醒:\(when) → \(t)"
        case "write_report":
            guard let date = args["date"] as? String, let md = args["markdown"] as? String else { return "缺少 date/markdown" }
            try? FileManager.default.createDirectory(at: reportsDir, withIntermediateDirectories: true)
            let f = reportsDir.appendingPathComponent("\(date).md")
            try? md.write(to: f, atomically: true, encoding: .utf8)
            return "报告已写入 \(f.path)"
        case "list_tasks":
            return readFile(tasksFile)
        default:
            return runSkill(action, args)   // 动态 skill
        }
    }

    // 运行子进程(可指定工作目录;继承登录环境的 PATH/凭证)
    func runProc(_ argv: [String], stdin: String?, cwd: String? = nil) -> (String, Int32) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: argv[0])
        p.arguments = Array(argv.dropFirst())
        if let cwd { p.currentDirectoryURL = URL(fileURLWithPath: cwd) }
        let out = Pipe(); p.standardOutput = out; p.standardError = out
        let inp = Pipe(); p.standardInput = inp
        do { try p.run() } catch { return ("启动失败", -1) }
        if let stdin { inp.fileHandleForWriting.write(stdin.data(using: .utf8)!) }
        inp.fileHandleForWriting.closeFile()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (String(data: data, encoding: .utf8) ?? "", p.terminationStatus)
    }

    // MARK: 提醒
    func loadReminders() -> [[String: Any]] {
        guard let d = try? Data(contentsOf: remindersFile), let a = try? JSONSerialization.jsonObject(with: d) as? [[String: Any]] else { return [] }
        return a
    }
    func saveReminders(_ a: [[String: Any]]) {
        if let d = try? JSONSerialization.data(withJSONObject: a, options: [.prettyPrinted]) { try? d.write(to: remindersFile) }
    }
    func addReminder(when: String, text: String) {
        var a = loadReminders(); a.append(["when": when, "text": text, "fired": false]); saveReminders(a)
    }
    func checkReminders() {
        var a = loadReminders(); var changed = false; let nowStr = now("yyyy-MM-dd HH:mm")
        for i in a.indices {
            if (a[i]["fired"] as? Bool) == false, let w = a[i]["when"] as? String, w <= nowStr {
                let text = a[i]["text"] as? String ?? ""
                _ = sendMatrx("⏰ 提醒:\(text)")
                send(["type": "reply", "text": "⏰ 提醒:\(text)"])
                a[i]["fired"] = true; changed = true
            }
        }
        if changed { saveReminders(a) }
    }

    // MARK: 每日日报调度(宠物常驻进程自己触发,无需 cron/launchd)
    func checkDailyReport() {
        let cfg = loadConfig()
        let target = (cfg["dailyReportTime"] as? String) ?? "09:03"
        guard now("HH:mm") == target else { return }
        let lastFile = petHome.appendingPathComponent("pet-data/.daily-report-last")
        let today = now("yyyy-MM-dd")
        if readFile(lastFile).trimmingCharacters(in: .whitespacesAndNewlines) == today { return }  // 今天已跑
        try? today.write(to: lastFile, atomically: true, encoding: .utf8)
        DispatchQueue.global().async { [weak self] in
            guard let self else { return }
            _ = self.runSkill("daily_report", [:])
            self.send(["type": "reply", "text": "📋 今天的分支日报我整理好、发到群里啦~"])
        }
    }

    // MARK: 文件工具
    func readFile(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "(空)" }
    func tailLines(_ url: URL, _ n: Int) -> String {
        let lines = readFile(url).components(separatedBy: "\n").filter { $0.hasPrefix("- [") }
        return lines.suffix(n).joined(separator: "\n")
    }
    func now(_ fmt: String) -> String { let f = DateFormatter(); f.locale = Locale(identifier: "zh_CN"); f.dateFormat = fmt; return f.string(from: Date()) }
    func currentTodos() -> [String] {
        var items: [String] = []; var inTodo = false
        for line in readFile(tasksFile).components(separatedBy: "\n") {
            if line.hasPrefix("## ") { inTodo = line.contains("待办"); continue }
            if inTodo, line.hasPrefix("- [ ]") {
                var t = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                if let bar = t.range(of: "|") { t = String(t[..<bar.lowerBound]).trimmingCharacters(in: .whitespaces) }
                items.append(t)
            }
        }
        return items
    }
    func nextTaskNumber() -> Int {
        var maxN = 0
        for m in readFile(tasksFile).components(separatedBy: "T") {
            let digits = m.prefix(while: { $0.isNumber }); if digits.count >= 3, let n = Int(digits) { maxN = max(maxN, n) }
        }
        return maxN + 1
    }
    func completeTask(_ match: String) -> String {
        guard var lines = try? String(contentsOf: tasksFile, encoding: .utf8).components(separatedBy: "\n") else { return "读取失败" }
        let key = match.trimmingCharacters(in: .whitespaces)
        for i in lines.indices where lines[i].hasPrefix("- [ ]") && lines[i].contains(key) && !key.isEmpty {
            var done = lines[i].replacingOccurrences(of: "- [ ]", with: "- [x]")
            if let bar = done.range(of: "|记录") { done = String(done[..<bar.lowerBound]) }
            done += "|完成:\(now("yyyy-MM-dd"))"
            lines.remove(at: i)
            if let di = lines.firstIndex(where: { $0.hasPrefix("## 已完成") }) { lines.insert(done, at: di + 1) }
            else { lines.append(done) }
            try? lines.joined(separator: "\n").write(to: tasksFile, atomically: true, encoding: .utf8)
            return "已完成:\(key)"
        }
        return "没找到匹配「\(key)」的待办"
    }
    func insertUnderSection(_ header: String, _ newLine: String) {
        guard var lines = try? String(contentsOf: tasksFile, encoding: .utf8).components(separatedBy: "\n") else {
            try? "\(header)\n\(newLine)\n".write(to: tasksFile, atomically: true, encoding: .utf8); return
        }
        if let idx = lines.firstIndex(where: { $0.hasPrefix(header) }) {
            var at = lines.count
            for i in (idx + 1)..<lines.count where lines[i].hasPrefix("## ") { at = i; break }
            while at > idx + 1 && lines[at - 1].trimmingCharacters(in: .whitespaces).isEmpty { at -= 1 }
            lines.insert(newLine, at: at)
        } else { lines.append(""); lines.append(header); lines.append(newLine) }
        try? lines.joined(separator: "\n").write(to: tasksFile, atomically: true, encoding: .utf8)
    }
    func appendLine(_ line: String, to url: URL) {
        if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write((line + "\n").data(using: .utf8)!); try? h.close() }
        else { try? (line + "\n").write(to: url, atomically: true, encoding: .utf8) }
    }

    // MARK: JSON 抽取
    func extractJSON(_ s: String) -> [String: Any]? {
        var str = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = str.firstIndex(of: "{"), let end = str.lastIndex(of: "}") { str = String(str[start...end]) }
        guard let d = str.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: d) as? [String: Any]
    }
    func stripToText(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "```json", with: "").replacingOccurrences(of: "```", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        return String(t.prefix(2000))   // 只防超长,别切掉正常的分析回复
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
