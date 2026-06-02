---
name: check-test-coverage
description: Use when code needs to be reviewed for test coverage gaps. Triggers on "check test coverage", "test coverage review", "missing tests", or when spawned as a sub-agent.
allowed-tools:
  - Read
  - Bash
---

# check-test-coverage: Test Coverage Review

Analyze code for test coverage gaps.

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

- Every new function, method, or class containing business logic MUST have at least one test. Missing test = blocking.
- Deleted tests or tests changed to `.skip`/`.todo`/`xtest`/`xit` are blocking unless the tested code was also deleted.
- Significant logic change with no corresponding test update = blocking (regression risk).
- Tests with trivially-passing or vacuous assertions (e.g. `expect(true).toBe(true)`, empty test body) = blocking.
- Missing edge case coverage for security-sensitive paths (auth, permissions, input validation) = blocking.
- Missing test for a pure utility function with no side effects = suggestion.
- Test file naming or organization inconsistency with the rest of the project = suggestion.

**Extra rules:** EXTRA_RULES_PLACEHOLDER

**INPUT:**
INPUT_PLACEHOLDER
