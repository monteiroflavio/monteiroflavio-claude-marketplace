---
name: check-api-schema
description: Use when code needs to be reviewed for API schema generation compliance. Triggers on "check API schema", "API schema review", "generated client compliance", or when spawned as a sub-agent.
allowed-tools:
  - Read
  - Bash
---

# check-api-schema: API Schema Generation Compliance Review

Analyze code for API schema generation compliance.

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

**First, detect whether the project uses an API client generation tool:**
- Look for config files like `orval.config.ts`, `openapi-generator-config.json`, `swagger-codegen.json`, or similar.
- Look for generated files (typically in directories named `generated/`, `api/generated/`, `__generated__/`, or similar).
- If no code generation tooling is detected, return no findings.

**If API code generation is in use, enforce it:**
- Types that represent API request/response shapes MUST come from the generated files, not be written manually.
- Signs of a manual schema violation: interfaces/types named like `CreateXxxDto`, `XxxResponse`, `ApiPayload` defined outside the generated directory; `fetch`/`axios`/`http` calls with manually-typed response shapes; types that look copy-pasted from API documentation.
- The generated client (hooks, query functions, API methods) MUST be used to call API endpoints — raw HTTP calls that bypass the generated layer are blocking.
- If new API routes are consumed but the generated client has no corresponding function, flag it as blocking (regeneration needed, not a manual workaround).
- Modifying generated files by hand is blocking — they will be overwritten on next generation.

**Extra rules:** EXTRA_RULES_PLACEHOLDER

**INPUT:**
INPUT_PLACEHOLDER
