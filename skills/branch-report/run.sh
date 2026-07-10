#!/bin/bash
# 分支报告采集(自包含)。参数从 stdin 收 JSON(当前无需参数)。
# 数据(repos.txt / cache / state)放在本 skill 的 data/,不依赖 ~/.claude。
DIR="$(cd "$(dirname "$0")" && pwd)"
export BRANCH_REPORT_HOME="$DIR/data"
cat >/dev/null 2>&1   # 吞掉 stdin 参数
bash "$DIR/gather.sh"
