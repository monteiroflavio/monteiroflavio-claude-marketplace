---
name: check-code-quality
description: Use when code needs to be reviewed for quality and completeness issues. Triggers on "check code quality", "review code quality", "code quality check", or when spawned as a sub-agent.
allowed-tools:
  - Read
  - Bash
---

# check-code-quality: Code Quality & Completeness Review

Analyze code for quality and completeness issues.

## Input Handling

Check the **INPUT** section at the bottom of these instructions.

- If it still reads `INPUT_PLACEHOLDER`: ask the user what to analyze. Accepted inputs:
  - **Diff text** — pasted unified diff
  - **File or directory path** — read the file(s) with the `Read` tool; for a directory, read relevant source files within it
  - **GitHub PR URL** — run `gh pr diff <PR_NUMBER> --repo <OWNER>/<REPO>` to fetch the diff
- If it contains actual content: proceed directly with analysis.

Same for **EXTRA_RULES** — if it still reads `EXTRA_RULES_PLACEHOLDER`, treat it as "none".

When analyzing files directly (not a diff), check all code in the provided scope. When analyzing a diff, focus only on added/changed lines.

When run standalone, return a clear list of issues, noting severity (blocking vs. suggestion) for each. When spawned as a sub-agent, follow the output format specified by the caller.

## Review Checklist

- Dead code or accidentally committed commented-out code
- Magic numbers/strings that should be named constants
- Functions violating Single Responsibility (doing too many things)
- Naming that doesn't convey intent (misleading names are blocking; vague names are suggestions)
- Incomplete implementations: `TODO`/`FIXME` without a ticket reference (blocking if in an active code path, suggestion otherwise)
- Missing null/undefined guards that will cause runtime errors (blocking)
- Duplicate logic that already exists elsewhere in the analyzed scope
- Partial renames — changed in one place but not all occurrences visible in the scope
- Console.log / debug print statements (suggestion unless they expose sensitive data)

**Extra rules:** EXTRA_RULES_PLACEHOLDER

**INPUT:**
INPUT_PLACEHOLDER
