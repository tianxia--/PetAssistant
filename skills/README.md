# 二蛋 Skills(动态技能,对齐 Claude Agent Skills)

宠物启动时扫描本目录,每个含 `SKILL.md` 的子文件夹 = 一个 skill。**加技能 = 丢一个文件夹进来;删技能 = 删文件夹。** 无需改 App、无需重新编译(重启宠物即可加载)。

格式对齐 [Claude Agent Skills](https://docs.claude.com/en/docs/claude-code/skills):从 Claude / 网上拿的 `SKILL.md` 技能可以直接丢进来用。

## 一个 skill 的结构

```
skills/<技能名>/
├── SKILL.md          # 清单 + 说明(必需)
├── run.sh / run.py   # 可执行脚本(可选;.sh→bash,.py→python3)
├── scripts/          # 可选:更多脚本
├── references/       # 可选:更多参考文档
└── (其它自带的数据/配置,自包含)
```

## SKILL.md 格式

YAML frontmatter(`---` 之间)+ Markdown 正文:

```markdown
---
name: send_matrx                              # 工具名(模型调用时用;英文、下划线)
description: 给用户的 Matrx 群发一条文本消息。用户说'发到群里'时用。
entry: run.py                                 # 可选:直接可调用的脚本入口
args: {"text":"要发送的消息正文"}               # 可选:参数名→说明(一行 JSON)
---
# 说明正文

给模型看的详细说明:这个 skill 做什么、怎么用、有哪些脚本和参数。
正文只有在模型 use_skill 时才加载(渐进式,省上下文)。
```

- `name` / `description`:**必需**,标准字段。始终注入到二蛋的技能清单里(只占一两行)。
- `entry`:**PetAssistant 扩展字段(可选)**。填了就能被二蛋当工具**直接按 name 调用**(一步到位);不填的纯文档式 skill,二蛋会先 `use_skill` 读正文、再按正文用 `run_script` 执行其中脚本。从 Claude 拿来的标准 skill 一般没有 `entry`,走后者。
- `args`:可选,一行 JSON,参数名→说明;仅在有 `entry` 时展示给模型。

## 渐进式加载(二蛋内置工具)

- `use_skill {"name"}` —— 读某 skill 的完整正文 + 列出目录下文件。
- `run_script {"skill","script","args"}` —— 执行该 skill 目录内的脚本(限目录内,防越界)。
- `read_file {"skill","path"}` —— 查看该 skill 目录内的文件。

## 执行约定

- 脚本参数以 **JSON 字符串从 stdin** 传入,例如 `{"text":"hello"}`。
- 脚本工作目录 = 该 skill 文件夹(可放自己的配置/数据,用相对路径引用)。
- 脚本把**结果打印到 stdout**,回灌给模型继续决策(最多取前 6000 字)。
- 退出码非 0 也没关系,有 stdout 就用 stdout。

## 现有 skill

- **branch-report**:采集所有配置仓库(`data/repos.txt`)的分支新提交,返回原始增量。数据(repos/cache/state)在 `data/`,自包含。
- **recent-commits**:看各仓库最近 N 天的全部提交(不推进增量进度),复用 branch-report 的采集脚本。
- **matrx-send**:发消息到 Matrx 群,webhook 地址在 `webhook.conf`(私密)。
- **daily-report**:每日分支日报——采集 → 整理成报告写桌面 BranchReports → 发群摘要。确定性、无需模型,可被定时调用。App 内置定时器每天按 `pet-config.json` 的 `dailyReportTime`(默认 09:03)自动触发,你也可以直接说"发个日报"。

## 写一个新 skill 的最小例子

```
skills/hello/SKILL.md    ---
                         name: say_hello
                         description: 打个招呼
                         entry: run.sh
                         args: {"who":"对谁"}
                         ---
                         # 打招呼
                         对某人说声你好。

skills/hello/run.sh      #!/bin/bash
                         who=$(python3 -c "import json,sys;print(json.load(sys.stdin).get('who','世界'))")
                         echo "你好,$who!"
```
重启宠物,对二蛋说"跟张三打个招呼",它就会调用 say_hello。
