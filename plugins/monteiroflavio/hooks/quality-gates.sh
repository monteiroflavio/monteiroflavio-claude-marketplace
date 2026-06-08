#!/usr/bin/env bash
# Quality Gates Runner — reads .claude/quality-gates from the project root and
# runs each line as a shell command. Blank lines and # comments are skipped.
# Exit 2 if any gate fails; Claude will feed the output back and continue fixing.
#
# Snapshot strategy: computes a content hash of every file reported by
# `git status --porcelain` (both tracked modifications and untracked files).
# Gates only run when that hash differs from the previous Stop — avoiding
# redundant runs when nothing actually changed. The snapshot is saved only
# on full pass, so failing gates keep re-running until they're fixed.
#
# Env vars exported to every gate command:
#   QUALITY_GATE_CHANGED_FILES  — newline-separated list of changed file paths
#                                  (relative to PROJECT_ROOT)
#   QUALITY_GATE_PROJECT_ROOT   — absolute path to the git root
#
# Scope prefix:
#   Lines starting with @<dir> are only run when at least one changed file
#   lives under that directory. Example:
#     @rhdp-back node scripts/check-eslint-baseline.js backend
#   Skipped commands are shown with ⊘ and do not count toward totals.

set -u

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
CONFIG="$PROJECT_ROOT/.claude/quality-gates"

[ -f "$CONFIG" ] || exit 0

# Returns one relative file path per line for every file currently shown by
# git status (tracked modifications and untracked files). Handles renames.
list_changed_files() {
  local status_output
  status_output=$(git -C "$PROJECT_ROOT" status --porcelain 2>/dev/null) || true
  [ -z "$status_output" ] && return 0
  while IFS= read -r entry; do
    local file="${entry:3}"
    # Renames are shown as "old -> new" — use the new path
    [[ "$file" == *" -> "* ]] && file="${file##* -> }"
    printf '%s\n' "$file"
  done <<< "$status_output"
}

# Returns a single checksum representing the content of every file in the
# provided list (one path per line). Always exits 0 — individual file failures
# are recorded as a sentinel string so a temporarily unreadable file doesn't
# silently kill the hook.
compute_snapshot_from_files() {
  local files="$1"
  [ -z "$files" ] && echo "empty" && return 0
  while IFS= read -r file; do
    local filepath="$PROJECT_ROOT/$file"
    if [ -f "$filepath" ]; then
      cksum "$filepath" 2>/dev/null || echo "unreadable:$file"
    else
      echo "gone:$file"
    fi
  done <<< "$files" | sort | cksum | awk '{print $1}'
  return 0
}

SNAPSHOT_KEY=$(printf '%s' "$PROJECT_ROOT" | cksum | awk '{print $1}')
SNAPSHOT_FILE="/tmp/.quality-gates-$SNAPSHOT_KEY"

# Collect changed files once — reused for snapshot, env vars, and scope checks
CHANGED_FILES=$(list_changed_files)

# Nothing modified or untracked — nothing to check
[ -z "$CHANGED_FILES" ] && exit 0

pre_snapshot=$(compute_snapshot_from_files "$CHANGED_FILES")

# Content identical to last passing run — skip
if [ -f "$SNAPSHOT_FILE" ] && [ "$(cat "$SNAPSHOT_FILE")" = "$pre_snapshot" ]; then
  exit 0
fi

# Export changed files for gate scripts to use
export QUALITY_GATE_CHANGED_FILES="$CHANGED_FILES"
export QUALITY_GATE_PROJECT_ROOT="$PROJECT_ROOT"

# Run the gates
failed=0
total=0
output_lines=()

while IFS= read -r line || [ -n "$line" ]; do
  [[ "$line" =~ ^[[:space:]]*$ ]] && continue
  [[ "$line" =~ ^[[:space:]]*# ]] && continue

  # Check for scope prefix: @<dir> <command>
  scope=""
  cmd="$line"
  if [[ "$line" =~ ^@([^[:space:]]+)[[:space:]]+(.+)$ ]]; then
    scope="${BASH_REMATCH[1]}"
    cmd="${BASH_REMATCH[2]}"
  fi

  # Skip command if its scope directory has no changed files
  if [ -n "$scope" ]; then
    scope_has_changes=false
    while IFS= read -r f; do
      if [[ "$f" == "$scope/"* || "$f" == "$scope" ]]; then
        scope_has_changes=true
        break
      fi
    done <<< "$CHANGED_FILES"
    if ! $scope_has_changes; then
      output_lines+=("  ⊘  $cmd  (skipped — no changes in $scope/)")
      continue
    fi
  fi

  total=$((total + 1))
  cmd_output=$(cd "$PROJECT_ROOT" && eval "$cmd" 2>&1)
  status=$?

  if [ $status -eq 0 ]; then
    output_lines+=("  ✓  $cmd")
  else
    output_lines+=("  ✗  $cmd")
    while IFS= read -r out_line; do
      output_lines+=("       $out_line")
    done <<< "$cmd_output"
    failed=$((failed + 1))
  fi
done < "$CONFIG"

if [ "$failed" -gt 0 ]; then
  {
    echo ""
    echo "[quality-gates] $total gate(s) checked"
    for l in "${output_lines[@]}"; do echo "$l"; done
    echo ""
    echo "[quality-gates] $failed gate(s) failed — fix the issues above before finishing."
  } >&2
  # No snapshot save: failed gates re-run on every Stop until fixed
  exit 2
fi

echo ""
echo "[quality-gates] $total gate(s) checked"
for l in "${output_lines[@]}"; do echo "$l"; done
echo ""

# All passed: save post-gate snapshot so gate-generated file updates
# (e.g. auto-lowered baselines) are captured and don't re-trigger next Stop
printf '%s' "$(compute_snapshot_from_files "$(list_changed_files)")" > "$SNAPSHOT_FILE"

echo "[quality-gates] All gates passed."
exit 0
