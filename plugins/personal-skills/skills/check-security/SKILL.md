---
name: check-security
description: Use when code needs to be reviewed for security vulnerabilities. Triggers on "check security", "security review", "security check", or when spawned as a sub-agent.
allowed-tools:
  - Read
  - Bash
---

# check-security: Security Review

Analyze code for security vulnerabilities.

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

- Injection vulnerabilities: SQL/NoSQL/command injection via string interpolation (blocking)
- XSS: unsanitized user input rendered as HTML (blocking)
- IDOR: endpoints that don't verify resource ownership before returning data (blocking)
- Missing or incorrect authentication/authorization guards on new endpoints (blocking)
- Sensitive data (tokens, passwords, PII) returned in response bodies or logged (blocking)
- Hardcoded credentials or secrets in code or config files (blocking)
- Unvalidated/unsanitized input accepted from external sources (blocking)
- Insecure HTTP methods (GET with side effects, state-changing operations without idempotency) (suggestion)
- Missing rate limiting on new public endpoints (suggestion)
- CORS, CSP, or security header regressions (blocking if header removed, suggestion if merely not added)

**Extra rules:** EXTRA_RULES_PLACEHOLDER

**INPUT:**
INPUT_PLACEHOLDER
