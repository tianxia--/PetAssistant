#!/usr/bin/env bash
# Gather raw data about remote branches that gained new commits since the last
# run, across ALL GitLab repos listed in repos.txt. Output is plain text on
# stdout for Claude to summarize into a report.
#
# Lightweight: does a SHALLOW fetch (recent commits only) into a small bare repo
# per project — it never clones full history, never touches your working copies,
# and never checks out a branch. Add a project by pasting its URL into repos.txt.
#
# Usage: gather.sh [days_fallback] [depth]
#   days_fallback: for a branch seen for the first time (new branch on an already
#                  tracked repo), how many days back to include commits (default 1).
#   depth:         shallow-fetch depth per branch (default 100).
#
# It fetches with --filter=blob:none (partial clone: commits + trees only, no
# file contents), so even binary-heavy repos stay small. File changes are shown
# by name (--name-status), which needs no blob download.
set -uo pipefail
export GIT_TERMINAL_PROMPT=0   # fail fast instead of hanging on auth prompts

HOME_DIR="${BRANCH_REPORT_HOME:-$(cd "$(dirname "$0")" && pwd)/data}"   # 自包含:默认用本 skill 的 data/
REPOS_FILE="$HOME_DIR/repos.txt"
CACHE="$HOME_DIR/cache"
STATE="$HOME_DIR/state"
DAYS_FALLBACK="${1:-1}"
DEPTH="${2:-100}"
MODE="${BRANCH_REPORT_MODE:-incremental}"   # incremental=只报新提交并推进 state;recent=报最近 N 天全部,不动 state
RECENT_DAYS="${BRANCH_REPORT_DAYS:-7}"
mkdir -p "$CACHE" "$STATE"

if [ ! -f "$REPOS_FILE" ]; then
  echo "### ERROR: no config at $REPOS_FILE"
  exit 0
fi

trim() { echo "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'; }

TOTAL_CHANGED=0

while IFS= read -r raw || [ -n "$raw" ]; do
  line="$(echo "$raw" | sed 's/#.*//')"
  line="$(trim "$line")"
  [ -z "$line" ] && continue

  if [[ "$line" == *"="* ]]; then
    name="$(trim "${line%%=*}")"
    url="$(trim "${line#*=}")"
  else
    url="$line"
    name="${url##*/}"; name="${name%.git}"
  fi

  bare="$CACHE/$name.git"
  state_file="$STATE/$name.txt"
  first_run=0
  [ ! -f "$state_file" ] && first_run=1

  echo "### REPO $name"
  echo "  url: $url"

  [ ! -d "$bare" ] && git init --bare -q "$bare"

  # Shallow + blobless fetch of all branches — commits & trees only, no file
  # contents. Small even for binary-heavy repos.
  if ! git -C "$bare" fetch --depth="$DEPTH" --filter=blob:none --prune --no-tags --force \
        "$url" "+refs/heads/*:refs/heads/*" 2>/tmp/br_fetch_err; then
    echo "  FETCH FAILED (auth/network?): $(tail -1 /tmp/br_fetch_err 2>/dev/null)"
    echo
    continue
  fi
  [ "$MODE" = "incremental" ] && [ "$first_run" = "1" ] && echo "  first-time fetch (seeding baseline, no report this run)"

  new_state="$(mktemp)"
  git -C "$bare" for-each-ref --format='%(objectname) %(refname:short)' refs/heads > "$new_state"

  repo_changed=0
  while read -r sha branch; do
    [ -z "$branch" ] && continue

    if [ "$MODE" = "recent" ]; then
      range="--since=${RECENT_DAYS}.days ${sha}"; diffbase=""        # 最近 N 天全部,不看 state
    else
      if [ "$first_run" = "1" ]; then continue; fi   # baseline only
      prev="$(grep " ${branch}$" "$state_file" 2>/dev/null | awk '{print $1}' | head -1)"
      if [ -n "$prev" ]; then
        [ "$prev" = "$sha" ] && continue
        if git -C "$bare" cat-file -e "$prev" 2>/dev/null; then
          range="${prev}..${sha}"; diffbase="$prev"
        else
          range="--since=${DAYS_FALLBACK}.days ${sha}"; diffbase=""   # beyond shallow depth
        fi
      else
        range="--since=${DAYS_FALLBACK}.days ${sha}"; diffbase=""      # new branch
      fi
    fi

    count=$(git -C "$bare" log --oneline $range 2>/dev/null | wc -l | tr -d ' ')
    [ "${count:-0}" = "0" ] && continue

    repo_changed=$((repo_changed + 1))
    TOTAL_CHANGED=$((TOTAL_CHANGED + 1))
    echo
    echo "  ## BRANCH ${branch}  (+${count} new commits)"
    git -C "$bare" log --date=format:'%Y-%m-%d %H:%M' \
        --pretty=format:'  - %h %ad %an: %s' $range 2>/dev/null
    echo
    echo "  ### FILE CHANGES ${branch}"
    if [ -n "$diffbase" ]; then
      git -C "$bare" diff --name-status "$diffbase" "$sha" 2>/dev/null | tail -60 | sed 's/^/  /'
    else
      git -C "$bare" show --name-status --oneline "$sha" 2>/dev/null | tail -60 | sed 's/^/  /'
    fi
    echo
  done < "$new_state"

  if [ "$MODE" = "recent" ]; then
    rm -f "$new_state"                                             # recent 模式不推进 state
    [ "$repo_changed" = "0" ] && echo "  (最近 ${RECENT_DAYS} 天无提交)"
  else
    mv "$new_state" "$state_file"
    [ "$repo_changed" = "0" ] && [ "$first_run" = "0" ] && echo "  (no branches with new commits)"
  fi
  echo
done < "$REPOS_FILE"

echo "### SUMMARY"
echo "branches_with_new_commits=${TOTAL_CHANGED}"
echo "### DONE"
