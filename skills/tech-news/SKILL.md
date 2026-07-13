---
name: tech_news
description: 抓取科技资讯(Hacker News + 可配置 RSS 源),返回 Markdown 摘要。用户说'看看科技新闻/今天科技圈有啥/抓点资讯'时用。不做 AI 摘要(交给你自己的模型提炼)、不发消息。
entry: run.py
args: {"limit":"每个源取几条,默认 5","source":"all|hn|rss,默认 all"}
---
# 科技资讯聚合

抓取科技资讯并返回 Markdown 摘要,纯 Python 标准库,无需 API Key。

- 入口:`run.py`,stdin 收 JSON `{"limit": 5, "source": "all"}`。
- **Hacker News**:官方 Firebase API,取热榜前 N 条(标题 + 链接 + 热度)。
- **RSS**:读同目录 `sources.txt`(每行 `名字 | RSS地址`),首次启动从 `sources.txt.example` 生成,自己按需增删。
- 单个源抓取失败会在输出里标注,不影响其它源。

拿到结果后,你可以直接把 Markdown 发给用户,或用自己的模型再提炼成几条要点。用户要「发到微信/群里」时,再配合 `wechat` / `send_matrx`。
