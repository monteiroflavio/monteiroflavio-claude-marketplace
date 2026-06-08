#!/usr/bin/env bash
# Sync current branch with origin/main at session start.
# Aborts cleanly if the tree is dirty or conflicts arise — prints a clear
# message so the user knows to run /monteiroflavio:sync-main to finish.

set -uo pipefail

# Must be inside a git repo
if ! git rev-parse --git-dir &>/dev/null; then
  exit 0
fi

# Skip if working tree is dirty
if [ -n "$(git status --porcelain 2>/dev/null)" ]; then
  echo ""
  echo "[sync-main] Working tree is dirty — skipping auto-sync with origin/main."
  echo "[sync-main] Run /monteiroflavio:sync-main when ready."
  echo ""
  exit 0
fi

# Fetch without printing noise
git fetch origin --quiet 2>/dev/null || {
  echo ""
  echo "[sync-main] Could not reach origin — skipping sync."
  echo ""
  exit 0
}

# Check if there's anything to merge
incoming=$(git log HEAD..origin/main --oneline 2>/dev/null)
if [ -z "$incoming" ]; then
  exit 0
fi

count=$(echo "$incoming" | wc -l | tr -d ' ')
echo ""
echo "[sync-main] Merging $count commit(s) from origin/main..."

if git merge origin/main --no-edit --quiet 2>/dev/null; then
  echo "[sync-main] Done."
  echo ""
else
  git merge --abort 2>/dev/null || true
  echo ""
  echo "[sync-main] Merge produced conflicts — auto-sync aborted."
  echo "[sync-main] Run /monteiroflavio:sync-main to resolve and complete the sync."
  echo ""
fi
