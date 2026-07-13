#!/usr/bin/env python3
"""科技资讯聚合(自包含,纯标准库)。
stdin 收 JSON {"limit": 每源条数默认5, "source": "all|hn|rss"}。
- Hacker News:官方 Firebase API(无需 key)。
- RSS:读同目录 sources.txt(每行 "名字 | RSS地址",# 注释)。
输出 Markdown 摘要,二蛋会用自己的模型再提炼/总结。不做 AI 摘要、不发消息(要发用 wechat / send_matrx)。
"""
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from xml.etree import ElementTree as ET

DIR = os.path.dirname(os.path.abspath(__file__))
UA = "Mozilla/5.0 (PetAssistant tech-news)"
TIMEOUT = 12


def _get(url):
    # 用 curl(走系统信任链,兼容企业自签/代理证书),与项目里 matrx-send 一致
    p = subprocess.run(["curl", "-sSL", "--max-time", str(TIMEOUT), "-A", UA, url],
                       capture_output=True)
    if p.returncode != 0:
        raise RuntimeError(p.stderr.decode("utf-8", "replace").strip() or f"curl 退出码 {p.returncode}")
    return p.stdout


def _get_json(url):
    return json.loads(_get(url).decode("utf-8", "replace"))


def hacker_news(limit):
    ids = _get_json("https://hacker-news.firebaseio.com/v0/topstories.json")[:limit]
    def one(i):
        try:
            it = _get_json(f"https://hacker-news.firebaseio.com/v0/item/{i}.json")
            return (it.get("title", "?"), it.get("url") or f"https://news.ycombinator.com/item?id={i}", it.get("score", 0))
        except Exception:
            return None
    with ThreadPoolExecutor(max_workers=8) as ex:
        rows = [r for r in ex.map(one, ids) if r]
    lines = [f"{n}. [{t}]({u}) · 👍{s}" for n, (t, u, s) in enumerate(rows, 1)]
    return "🔥 Hacker News", lines


def _text(el):
    return (el.text or "").strip() if el is not None else ""


def parse_feed(raw, limit):
    root = ET.fromstring(raw)
    tag = lambda e: e.tag.split("}")[-1]
    items, out = [], []
    for e in root.iter():
        if tag(e) in ("item", "entry"):
            items.append(e)
    for it in items[:limit]:
        title, link = "", ""
        for c in it:
            t = tag(c)
            if t == "title" and not title:
                title = _text(c)
            elif t == "link" and not link:
                link = _text(c) or c.get("href", "")
        if title:
            out.append(f"- [{title}]({link})" if link else f"- {title}")
    return out


def rss_sources(limit):
    path = os.path.join(DIR, "sources.txt")
    if not os.path.exists(path):
        return []
    blocks = []
    with open(path, encoding="utf-8") as f:
        feeds = []
        for line in f:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            name, _, url = line.partition("|")
            name, url = name.strip(), url.strip()
            if url:
                feeds.append((name or url, url))
    def one(nf):
        name, url = nf
        try:
            lines = parse_feed(_get(url), limit)
            return (name, lines) if lines else None
        except Exception as e:
            return (name, [f"- (抓取失败:{e})"])
    with ThreadPoolExecutor(max_workers=6) as ex:
        for res in ex.map(one, feeds):
            if res:
                blocks.append(res)
    return blocks


def main():
    try:
        args = json.load(sys.stdin)
    except Exception:
        args = {}
    limit = int(args.get("limit", 5) or 5)
    source = (args.get("source") or "all").lower()

    sections = []
    if source in ("all", "hn"):
        try:
            title, lines = hacker_news(limit)
            if lines:
                sections.append((title, lines))
        except Exception as e:
            sections.append(("🔥 Hacker News", [f"- (抓取失败:{e})"]))
    if source in ("all", "rss"):
        sections += rss_sources(limit)

    if not sections:
        print("没抓到内容。检查网络,或在 skills/tech-news/sources.txt 里配置 RSS 源。")
        return
    parts = ["# 📰 科技资讯速览\n"]
    for title, lines in sections:
        parts.append(f"### {title}")
        parts.append("\n".join(lines))
        parts.append("")
    print("\n".join(parts).strip())


if __name__ == "__main__":
    main()
