# 二蛋 Skills(动态技能)

宠物启动时扫描本目录,每个子文件夹 = 一个 skill,自动出现在二蛋能调用的工具清单里。**加技能 = 丢一个文件夹进来;删技能 = 删文件夹。** 无需改 App、无需重新编译(重启宠物即可加载)。

## 一个 skill 的结构

```
skills/<技能名>/
├── skill.json     # 清单(必需)
└── run.sh / run.py # 可执行脚本(必需,按扩展名选解释器:.sh→bash,.py→python3)
└── (其它自带的数据/配置,自包含)
```

## skill.json 格式

```json
{
  "name": "send_matrx",                     // 工具名(模型调用时用;英文、下划线)
  "description": "给用户的 Matrx 群发一条文本消息。用户说'发到群里'时用。",
  "args": { "text": "要发送的消息正文" },     // 参数名 → 说明;无参数写 {}
  "run": "run.py"                            // 入口脚本文件名
}
```

## 执行约定

- 二蛋调用时,把参数以 **JSON 字符串从 stdin** 传给脚本,例如 `{"text":"hello"}`。
- 脚本工作目录 = 该 skill 文件夹(所以可以放自己的配置/数据,相对路径引用)。
- 脚本把**结果打印到 stdout**,这段文字会回灌给模型继续决策(最多取前 6000 字)。
- 退出码非 0 也没关系,有 stdout 就用 stdout。

## 现有 skill

- **branch-report**:采集所有配置仓库(`data/repos.txt`)的分支新提交,返回原始增量。数据(repos/cache/state)在 `data/`,自包含。
- **matrx-send**:发消息到 Matrx 群,webhook 地址在 `webhook.conf`(私密)。
- **daily-report**:每日分支日报——调 branch-report 采集 → 整理成报告写桌面 BranchReports → 调 matrx-send 发群摘要。确定性、无需模型,可被定时调用。宠物 App 内置定时器每天按 `pet-config.json` 的 `dailyReportTime`(默认 09:03)自动触发,你也可以直接说"发个日报"。

## 写一个新 skill 的最小例子

```
skills/hello/skill.json   {"name":"say_hello","description":"打个招呼","args":{"who":"对谁"},"run":"run.sh"}
skills/hello/run.sh       #!/bin/bash
                          who=$(python3 -c "import json,sys;print(json.load(sys.stdin).get('who','世界'))")
                          echo "你好,$who!"
```
重启宠物,对二蛋说"跟张三打个招呼",它就会调用 say_hello。
