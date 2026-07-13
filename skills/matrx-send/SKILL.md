---
name: send_matrx
description: 给用户的 Matrx 群发一条文本消息。用户说'发到群里/告诉大家/发个通知'时用。
entry: run.py
args: {"text":"要发送的消息正文(纯文本)"}
---
# 发送 Matrx 群消息

给用户的 Matrx 群发一条纯文本。

- 入口:`run.py`,从 stdin 收 JSON `{"text":"..."}`(也兼容纯文本)。
- webhook 地址读同目录 `webhook.conf`(需自行配置,已 gitignore)。
- 底层用 curl,兼容企业自签证书。
