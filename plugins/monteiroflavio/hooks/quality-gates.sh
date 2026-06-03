#!/usr/bin/env bash
# Quality Gates Runner — reads .claude/quality-gates from the project root and
# runs each line as a shell command. Blank lines and # comments are skipped.
# Exit 1 if any gate fails; Claude will feed the output back and continue fixing.
#
# Snapshot strategy: computes a content hash of every file reported by
# `git status --porcelain` (both tracked modifications and untracked files).
# Gates only run when that hash differs from the previous Stop — avoiding
# redundant runs when nothing actually changed. The snapshot is saved only
# on full pass, so failing gates keep re-running until they're fixed.

set -uo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
CONFIG="$PROJECT_ROOT/.claude/quality-gates"

[ -f "$CONFIG" ] || exit 0

# Returns a single checksum representing the content of every file currently
# shown by git status. Immune to mtime-only changes; includes untracked files.
compute_snapshot() {
  local status_output
  status_output=$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null) || true
  [ -z "$status_output" ] && echo "empty" && return

  echo "$status_output" | while IFS= read -r entry; do
    file="${entry:3}"
    # Renames are shown as "old -> new" — use the new path
    [[ "$file" == *" -> "* ]] && file="${file##* -> }"
    filepath="$PROJECT_ROOT/$file"
    if [ -f "$filepath" ]; then
      cksum "$filepath"
    else
      echo "gone $file"
    fi
  done | sort | cksum | awk '{print $1}'
}

SNAPSHOT_KEY=$(printf '%s' "$PROJECT_ROOT" | cksum | awk '{print $1}')
SNAPSHOT_FILE="/tmp/.quality-gates-$SNAPSHOT_KEY"

pre_snapshot=$(compute_snapshot)

# Nothing modified or untracked — nothing to check
[ "$pre_snapshot" = "empty" ] && exit 0

# Content identical to last passing run — skip
if [ -f "$SNAPSHOT_FILE" ] && [ "$(cat "$SNAPSHOT_FILE")" = "$pre_snapshot" ]; then
  exit 0
fi

# Run the gates
failed=0
total=0
output_lines=()

while IFS= read -r line || [ -n "$line" ]; do
  [[ "$line" =~ ^[[:space:]]*$ ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue

  total=$((total + 1))
  cmd_output=$(cd "$PROJECT_ROOT" && eval "$line" 2>&1)
  status=$?

  if [ $status -eq 0 ]; then
    output_lines+=("  ✓  $line")
  else
    output_lines+=("  ✗  $line")
    while IFS= read -r out_line; do
      output_lines+=("       $out_line")
    done <<< "$cmd_output"
    failed=$((failed + 1))
  fi
done < "$CONFIG"

echo ""
echo "[quality-gates] $total gate(s) checked"
for l in "${output_lines[@]}"; do echo "$l"; done
echo ""

if [ "$failed" -gt 0 ]; then
  echo "[quality-gates] $failed gate(s) failed — fix the issues above before finishing."
  # No snapshot save: failed gates re-run on every Stop until fixed
  exit 1
fi

# All passed: save post-gate snapshot so gate-generated file updates
# (e.g. auto-lowered baselines) are captured and don't re-trigger next Stop
printf '%s' "$(compute_snapshot)" > "$SNAPSHOT_FILE"

echo "[quality-gates] All gates passed."
exit 0
