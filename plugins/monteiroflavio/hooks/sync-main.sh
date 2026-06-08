#!/usr/bin/env bash
# UserPromptSubmit hook: syncs current branch with origin/main once per session.
# Outputs a systemMessage JSON so Claude surfaces the result in its first response.
# Silent (outputs {}) when already up to date.

set -uo pipefail

# Consume stdin to avoid broken pipe
cat /dev/stdin > /dev/null 2>&1 || true

# Run only once per session
SESSION_ID="${CLAUDE_SESSION_ID:-}"
if [ -n "$SESSION_ID" ]; then
  SESSION_FLAG="/tmp/sync-main-session-${SESSION_ID}"
  if [ -f "$SESSION_FLAG" ]; then
    echo "{}"
    exit 0
  fi
  touch "$SESSION_FLAG"
fi

# Must be inside a git repo
if ! git rev-parse --git-dir &>/dev/null 2>&1; then
  echo "{}"
  exit 0
fi

# Skip if working tree is dirty
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo "{\"systemMessage\": \"[sync-main] Working tree is dirty — skipped auto-sync with origin/main. Remind the user to run /monteiroflavio:sync-main when ready.\"}"
  exit 0
fi

# Fetch without noise
git fetch origin --quiet 2>/dev/null || {
  echo "{}"
  exit 0
}

# Check if behind
incoming=$(git log HEAD..origin/main --oneline 2>/dev/null)
if [ -z "$incoming" ]; then
  echo "{}"
  exit 0
fi

count=$(echo "$incoming" | wc -l | tr -d ' ')

if git merge origin/main --no-edit --quiet 2>/dev/null; then
  echo "{\"systemMessage\": \"[sync-main] Merged $count commit(s) from origin/main at session start.\"}"
else
  git merge --abort 2>/dev/null || true
  echo "{\"systemMessage\": \"[sync-main] Merge conflicts with origin/main — auto-sync aborted. Remind the user to run /monteiroflavio:sync-main to resolve.\"}"
fi
