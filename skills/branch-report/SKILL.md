---
name: run_branch_report
description: 采集所有已配置 GitLab 仓库自上次以来有新提交的分支,返回原始增量文本(提交列表+改动文件)。用户想看/发各仓库最近改动、出分支日报时用。
entry: run.sh
---
# 分支增量采集

采集所有已配置 GitLab 仓库自上次以来的新提交(**增量**,跑完会推进进度)。

- 入口:`run.sh`,从 stdin 收 JSON(当前无需参数)。
- 数据(仓库清单 / 缓存 / 进度)都在本目录 `data/`,不依赖 `~/.claude`。
- 要跟踪哪些仓库,填在 `data/repos.txt`(每行一个 GitLab 仓库地址)。

> 主要给「发日报到群」的流程用。如果只是想看最近提交、且不想推进进度,用 `recent_commits`。
