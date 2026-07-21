# PetAssistant 🐉

**[English](README.md) · [中文](README.zh.md)**

> 一只住在你桌面上的小龙:**听、记、理、提醒**。把零散的话丢给它,它帮你整理任务、生成每日记录、到点提醒;还能看图、读文件、记住你说过的事。它不写代码、不干重活。

<p align="center">
  <img src="docs/screenshots/hero.png" width="220" alt="桌宠小龙">
</p>

**🎨 主题换肤**

![themes](docs/screenshots/themes.png)

**🐲 可切换龙角**

![horns](docs/screenshots/horns.png)

## 能力
- **桌面宠物**:底边踱步、自发小动作、主题换肤、可切换龙角;鼠标滑到它身上会停下来问你「有什么事」,走路遇到静止的鼠标会拱起来绕过去;可在 ⚙️ 里开「静止不动」模式让它待在原地不游走
- **聊天大脑**:接你自己的 LLM(OpenAI / Anthropic 接口格式),带多轮上下文,回复支持 Markdown 格式化显示
- **记忆**:本地向量记忆(中英双语,语义 + 关键词混合检索),越用越懂你
- **文件分析**:文档(pdf / word / txt / 代码 / 日志)+ 图片(截图),支持 📎 选择 / 拖拽 / Cmd+V 粘贴
- **技能挂载**:对齐 Claude Agent Skills(`SKILL.md`),把技能文件夹丢进 `skills/` 重启即用,可直接用从 Claude / 网上拿的标准技能
- **提醒**:到点推送(可接 Matrx 群等);可选挂 `matrx-watch` 技能,Matrx 一来新消息就让二蛋响一声+弹醒目气泡(纯看文件时间戳,不读内容)

## 首次安装
```bash
cd ~/Desktop/PetAssistant/pet-app

# 1) 向量记忆的 Python 环境(本地、无 torch,约 210MB)
python3 -m venv mem/.venv
mem/.venv/bin/pip install -r mem/requirements.txt

# 2) 启动(首次会从 .example 生成 pet-config.json / pet-data 等本地文件,并编译 App)
./start_pet.sh
```
启动后点开小龙 → ⚙️ 设置里:
1. **配模型**:填你的 LLM 接口(地址 / 模型 ID / API Key)。没配也能用,消息会先记进收件箱。
2. **起名**:在「🐣 名字」给它起个名。(界面默认英文,想用中文在「🌐 语言」里切。)
3. (可选)选主题颜色、龙角样式。
4. (可选)分支日报:把要跟踪的 GitLab 仓库填进 `skills/branch-report/data/repos.txt`。

**开机自启**(可选):`cd pet-app && ./autostart.sh` —— 登录时自动拉起二蛋(装一个 LaunchAgent,`./autostart.sh off` 关闭)。重启电脑不再消失。

> 也可以在本目录开 Claude Code 会话来驱动它(`cd ~/Desktop/PetAssistant && claude`)。

## 内置技能 & 使用流程

技能都在 `skills/`,对齐 [Claude Agent Skills](https://docs.claude.com/en/docs/claude-code/skills)(每个子目录一个 `SKILL.md`)。想用就留着,不用删文件夹即可;从 Claude / 网上拿的标准技能丢进来重启也能用。

### 📰 科技资讯(tech-news)
对二蛋说「看看今天科技圈有啥」,它就抓 **Hacker News** + 你在 `skills/tech-news/sources.txt` 配置的 **RSS 源**,整理成摘要(纯本地、无需 API Key):

![tech-news](docs/screenshots/tech-news.png)

### 💬 微信收发(wechat,双向)
基于微信 iLink Bot 协议,能发也能收。先在终端**扫码登录一次**(建议用小号,非官方通道有封号风险):
```bash
cd ~/Desktop/PetAssistant
echo '{"action":"login"}' | python3 skills/wechat/run.py   # 打开输出的链接,手机微信扫码
```
登录后凭证存 `skills/wechat/wechat.conf`(不入库)。之后就能让二蛋发/收微信:

![wechat](docs/screenshots/wechat.png)

> 目前「收消息」是拉一次(`action=receive`);常驻自动监听在路线图里。

### 🔔 让二蛋替你盯着 Claude(可选)
二蛋每 2 秒看一个本地信号文件 `pet-data/pet-notify.log`——**任何程序往里追加一行,二蛋就响一声 + 弹醒目气泡**(那行文字就是提醒内容,零权限)。拿它接 Claude Code 的通知最顺手:在 `~/.claude/settings.json` 加 Notification hook,Claude **需要你授权 / 干完在等你** 时二蛋当场提醒(开了 auto 权限就没授权弹窗,不打扰):
```json
{ "hooks": { "Notification": [
  { "matcher": "permission_prompt", "hooks": [{ "type": "command",
    "command": "echo '🔔 Claude 在等你授权' >> ~/Desktop/PetAssistant/pet-data/pet-notify.log" }] },
  { "matcher": "idle_prompt", "hooks": [{ "type": "command",
    "command": "echo '✅ Claude 干完了,等你下一步' >> ~/Desktop/PetAssistant/pet-data/pet-notify.log" }] }
] } }
```
> 命令行(CLI)确认可用;桌面 App / IDE 是否跑 settings.json 的 hook 需自行实测。

## 目录结构
| 路径 | 作用 |
|------|------|
| `pet-app/` | 桌宠 App(Swift + WebView):`Sources/` 大脑、`web/` 界面与动画、`mem/` 向量记忆 |
| `pet-data/` | 它的记忆(**你的私有数据,不入库**):`inbox.md`、`tasks.md`、`about-you.md`、`daily/` |
| `skills/` | 可扩展技能:分支日报、群消息推送、科技资讯抓取、微信收发等(对齐 Claude Agent Skills,每个子目录一个 `SKILL.md`,丢进来重启即用) |
| `CLAUDE.md` | 人格与行为准则 |
| `docs/` | 需求与设计、项目地图 |
| `*.example.*` | 种子/示例文件,首次运行据此生成你的本地文件 |

## 隐私
真实数据(`pet-data/*.md`、`pet-config.json`、`repos.txt`、聊天日志、向量索引、venv)都已 `.gitignore`,**不会进仓库**。`pet-data/` 是它的全部记忆,想备份请存到你自己的私有位置。
