---
name: daily_report
description: 生成今天的分支日报:采集所有仓库分支增量 → 写报告到桌面 BranchReports → 把精简摘要发到 Matrx 群。用户说'出个日报/发日报'或每天定时触发时用。
entry: run.py
---
# 每日分支日报

一键出今天的分支日报,确定性、无需模型:

1. 调 `branch-report` 采集原始增量;
2. 整理成报告,写到桌面 `BranchReports/日期.md`;
3. 调 `matrx-send` 把精简摘要发到群。

- 入口:`run.py`,输出一句执行结果。
- App 内置定时器每天按 `pet-config.json` 的 `dailyReportTime`(默认 09:03)自动触发。
