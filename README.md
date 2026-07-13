# PetAssistant 🐉

**[中文](README.md) · [English](README.en.md)**

> 一只住在你桌面上的小龙:**听、记、理、提醒**。把零散的话丢给它,它帮你整理任务、生成每日记录、到点提醒;还能看图、读文件、记住你说过的事。它不写代码、不干重活。

<p align="center">
  <img src="docs/screenshots/hero.png" width="220" alt="桌宠小龙">
</p>

**🎨 主题换肤**

![themes](docs/screenshots/themes.png)

**🐲 可切换龙角**

![horns](docs/screenshots/horns.png)

## 能力
- **桌面宠物**:底边踱步、自发小动作、主题换肤、可切换龙角
- **聊天大脑**:接你自己的 LLM(OpenAI / Anthropic 接口格式),带多轮上下文
- **记忆**:本地向量记忆(中英双语,语义 + 关键词混合检索),越用越懂你
- **文件分析**:文档(pdf / word / txt / 代码 / 日志)+ 图片(截图),支持 📎 选择 / 拖拽 / Cmd+V 粘贴
- **提醒**:到点推送(可接 Matrx 群等)

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
2. **起名**:在「🐣 名字」给它起个名。
3. (可选)选主题颜色、龙角样式。
4. (可选)分支日报:把要跟踪的 GitLab 仓库填进 `skills/branch-report/data/repos.txt`。

> 也可以在本目录开 Claude Code 会话来驱动它(`cd ~/Desktop/PetAssistant && claude`)。

## 目录结构
| 路径 | 作用 |
|------|------|
| `pet-app/` | 桌宠 App(Swift + WebView):`Sources/` 大脑、`web/` 界面与动画、`mem/` 向量记忆 |
| `pet-data/` | 它的记忆(**你的私有数据,不入库**):`inbox.md`、`tasks.md`、`about-you.md`、`daily/` |
| `skills/` | 可扩展技能:分支日报、群消息推送等(对齐 Claude Agent Skills,每个子目录一个 `SKILL.md`,丢进来重启即用) |
| `CLAUDE.md` | 人格与行为准则 |
| `docs/` | 需求与设计、项目地图 |
| `*.example.*` | 种子/示例文件,首次运行据此生成你的本地文件 |

## 隐私
真实数据(`pet-data/*.md`、`pet-config.json`、`repos.txt`、聊天日志、向量索引、venv)都已 `.gitignore`,**不会进仓库**。`pet-data/` 是它的全部记忆,想备份请存到你自己的私有位置。
