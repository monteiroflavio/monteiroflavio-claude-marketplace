#!/usr/bin/env bash
# Quality Gates Runner — reads .claude/quality-gates from the project root and
# runs each line as a shell command. Blank lines and # comments are skipped.
# Exit 1 if any gate fails; Claude will feed the output back and continue fixing.

set -uo pipefail

PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")
CONFIG="$PROJECT_ROOT/.claude/quality-gates"

[ -f "$CONFIG" ] || exit 0

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
  exit 1
fi

echo "[quality-gates] All gates passed."
exit 0
