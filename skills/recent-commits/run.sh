#!/bin/bash
# 看各仓库最近 N 天的全部提交(不推进增量 state)。stdin 收 {"days": N}。
# 复用 branch-report 的 gather.sh + 数据,只切换到 recent 模式。
BR="$(cd "$(dirname "$0")/../branch-report" && pwd)"
ARGS="$(cat)"
DAYS="$(printf '%s' "$ARGS" | python3 -c 'import sys,json
try: print(int(json.load(sys.stdin).get("days",7)))
except Exception: print(7)' 2>/dev/null)"
[ -z "$DAYS" ] && DAYS=7
export BRANCH_REPORT_HOME="$BR/data"
export BRANCH_REPORT_MODE=recent
export BRANCH_REPORT_DAYS="$DAYS"
bash "$BR/gather.sh"
