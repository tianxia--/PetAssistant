#!/usr/bin/env python3
"""每日分支日报(自包含)。
流程:调 branch-report 采集原始增量 → 确定性整理成报告 → 写桌面 BranchReports/日期.md
      → 调 matrx-send 把精简摘要发到群。无需模型,可被定时任务直接调用。
输出:一句执行结果。"""
import datetime
import json
import os
import re
import subprocess

DIR = os.path.dirname(os.path.abspath(__file__))
SKILLS = os.path.dirname(DIR)
GATHER = os.path.join(SKILLS, "branch-report", "run.sh")
MATRX = os.path.join(SKILLS, "matrx-send", "run.py")
REPORTS = os.path.expanduser("~/Desktop/BranchReports")
TODAY = datetime.date.today().isoformat()


def gather():
    p = subprocess.run(["/bin/bash", GATHER], input=b"{}", capture_output=True, timeout=300)
    return p.stdout.decode(errors="replace")


def parse(raw):
    """把 gather 原始输出解析成 {repo: [(branch, count, [msgs])]}"""
    repos, cur_repo, cur_branch = {}, None, None
    for line in raw.splitlines():
        m = re.match(r"### REPO (.+)", line)
        if m:
            cur_repo = m.group(1).strip(); repos.setdefault(cur_repo, []); cur_branch = None; continue
        m = re.match(r"\s*## BRANCH (.+?)\s+\(\+(\d+)", line)
        if m and cur_repo:
            cur_branch = {"name": m.group(1), "count": int(m.group(2)), "msgs": []}
            repos[cur_repo].append(cur_branch); continue
        m = re.match(r"\s*- \w+ [\d-]+ [\d:]+ .+?: (.+)", line)
        if m and cur_branch is not None and len(cur_branch["msgs"]) < 4:
            cur_branch["msgs"].append(m.group(1).strip())
    return repos


def build(repos):
    active = [(r, bs) for r, bs in repos.items() if bs]
    total = sum(len(bs) for _, bs in active)
    if total == 0:
        report = f"# 分支变更报告 — {TODAY}\n\n> 今日各项目无新提交。\n"
        digest = f"📋 分支日报 {TODAY}\n今日各项目无新提交 ✅"
        return report, digest, 0
    rl = [f"# 分支变更报告 — {TODAY}", "", f"> 共 {len(active)} 个项目、{total} 个分支有新提交。", ""]
    dl = [f"📋 分支日报 {TODAY}", f"{len(active)} 个项目 / {total} 个分支有新提交:"]
    for repo, bs in active:
        rl.append(f"## {repo}")
        for b in bs:
            rl.append(f"### {b['name']}  (+{b['count']})")
            for msg in b["msgs"]:
                rl.append(f"- {msg}")
            rl.append("")
            head = ";".join(b["msgs"][:2])
            dl.append(f"• {repo}/{b['name']} +{b['count']}:{head}")
    rl.append("---\n*由 二蛋 daily-report skill 自动生成*")
    dl.append(f"完整报告:{REPORTS}/{TODAY}.md")
    return "\n".join(rl), "\n".join(dl), total


def main():
    raw = gather()
    report, digest, total = build(parse(raw))
    os.makedirs(REPORTS, exist_ok=True)
    with open(os.path.join(REPORTS, f"{TODAY}.md"), "w") as f:
        f.write(report)
    subprocess.run(["/usr/bin/python3", MATRX], input=json.dumps({"text": digest}).encode(),
                   capture_output=True, timeout=45)
    print(f"日报已生成({total} 个分支有新提交),写入 {REPORTS}/{TODAY}.md 并已发送 Matrx 群。")


if __name__ == "__main__":
    main()
