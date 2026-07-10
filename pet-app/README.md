# ErDanPet — 二蛋桌面宠物

macOS 桌面悬浮小龙:精美插画形象,在桌面底部自由走/跑/跳/发呆,点它聊天。大脑是**会用工具、带完整记忆的 Agent**,跑在你自配的模型上。

## 启动
```bash
zsh ~/Desktop/PetAssistant/pet-app/start_pet.sh
```
(开发:`cd pet-app && swift run`)

## 三层架构
| 层 | 文件 | 职责 |
|----|------|------|
| 壳 | `Sources/ErDanPet/main.swift` | 无边框透明悬浮窗;30fps 游走引擎(窗口在桌面移动,发 motion 给页面);Agent 大脑;工具执行;提醒定时器;模型配置 |
| 形象+动画 | `web/dragon.svg` + `web/engine.js` | 插画(可换皮)+ 逐帧骨骼动画:头点头/尾巴摆/手臂晃/呼吸挤压/眨眼/张嘴/走跑跳蹦跳前倾 |
| 交互 | `web/pet.html` | 气泡、聊天输入、随机弹题、睡觉、模型设置面板 |

## 大脑:带记忆+工具的 Agent(模型无关)
每收到一句话:
1. 原话先写入 `pet-data/inbox.md`(永不丢话)
2. 把**完整记忆**(about-you + 全部 tasks + 最近 inbox)+ 工具说明喂给当前模型
3. 模型按 ReAct 协议逐步输出 `{"action":...}` 调工具 / `{"reply":...}` 收尾;App 执行工具并回灌结果,最多 7 步

**内置工具**(Swift,直接操作 pet-data):add_task / complete_task / add_event / remember / set_reminder / write_report / list_tasks。
**动态技能**(`../skills/` 下,可扩展):run_branch_report、send_matrx…… 启动时扫描 `skills/`,按 `skill.json` 动态生成工具清单;加技能=丢文件夹,详见 [skills/README.md](../skills/README.md)。
所以你能直接说"给群里发个分支日报",它会:run_branch_report 采集 → write_report 写报告 → send_matrx 发群 → 回你一句。

## 模型配置(⚙️)
多模型可加可切,存 `~/Desktop/PetAssistant/pet-config.json`(权限 600,Key 不回传页面)。支持 OpenAI / Anthropic 两种接口格式。已预置公司自部署 Gemma(`/model/gemma-4-31b-it`,已验证可调用工具)。

## 交互速查
点小龙=打招呼+开/关聊天框 · 回车发送 · 🌙睡觉 · ⚙️模型 · ✕退出 · 拖动=挪窝 · 清醒时每 35~70 分钟弹个小问题(35% 概率结合真实待办)。

## 换皮
替换 `web/dragon.svg`,保留分组 id:`tail/body/belly/arms/head(内含 eyes/mouth/ears/horns/mane)`,动画按这些 id 驱动。历史候选在 `web/candidates/`(chunky/festive/pastel)。

## 预览调试
浏览器开 `web/pet.html?demo=1` 循环播放走/跑/跳(注意:后台标签页会冻结动画,属浏览器 rAF 限制,桌面悬浮窗始终可见不受影响)。
