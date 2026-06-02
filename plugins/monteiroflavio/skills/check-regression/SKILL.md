---
name: check-regression
description: Use when code needs to be reviewed for regressions and completeness gaps. Triggers on "check regression", "regression review", "completeness check", or when spawned as a sub-agent.
allowed-tools:
  - Read
  - Bash
---

# check-regression: Regression & Completeness Review

Analyze code for regressions and completeness gaps.

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

- Import changed/removed but the consuming code in the scope was not updated (blocking)
- Function signature changed but not all call sites visible in the scope were updated (blocking)
- API contract changed (endpoint path, method, request/response shape) without updating known consumers (blocking)
- Environment variable added but missing from `.env.example` or equivalent documentation file (suggestion)
- Database migration added without a corresponding rollback/down migration (blocking if the project uses reversible migrations)
- Feature flag introduced without a cleanup ticket reference in a comment (suggestion)
- Config keys renamed/removed without updating all config files in the scope (blocking)
- Exported symbol removed without a deprecation path or replacement (blocking)
- Breaking change to a shared interface/type used by modules not visible in this scope (blocking)

**Extra rules:** EXTRA_RULES_PLACEHOLDER

**INPUT:**
INPUT_PLACEHOLDER
