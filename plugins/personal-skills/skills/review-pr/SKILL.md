---
name: review-pr
description: Use when the user wants to review a PR as a human engineer, evaluate code quality, provide constructive feedback, or act as a technical reviewer. Takes a GitHub PR URL and optional extra rules. Spawns specialist subagents to analyze different aspects in parallel, then posts inline comments and a final review decision to GitHub. Triggers on "review PR", "review this PR", "revisar PR", "avaliar PR", or when given a GitHub PR URL with a review intent.
allowed-tools:
  - Bash
  - Read
  - Agent
  - AskUserQuestion
---

# review-pr: Human-Grade Pull Request Review

Act as a senior engineer doing a thorough, opinionated PR review. The PR description is **never** the source of truth — the code diff is the only SSoT. Derive intent from what the code actually does.

## Non-negotiables

- Never trust the PR description. Read the code.
- Every finding must reference the exact file and line number.
- Every comment must be constructive: state the problem, explain why it matters, and show how to fix it.
- Classify every finding: **BLOCKING** (must fix before merge) or **NAIL-POLISH** (suggestion, won't block).
- Never post a silent approval — always include a human-readable summary of what was reviewed.
- The review is complete only when all comments and the final verdict are posted to GitHub.

---

## Step 1 — Parse Input

Extract from the user message:
1. **PR URL** — e.g. `https://github.com/owner/repo/pull/123`
2. **Extra rules** — any additional requirements stated after the URL (added on top of the built-in checklist, not instead of it)

Derive:
```
OWNER=<owner>
REPO=<repo>
PR_NUMBER=<number>
EXTRA_RULES=<extra rules, or "none">
```

---

## Step 2 — Fetch PR Data

Run all of the following **in parallel**:

```bash
# Full diff — SSoT for all analysis
gh pr diff $PR_NUMBER --repo $OWNER/$REPO

# File list and PR metadata
gh pr view $PR_NUMBER --repo $OWNER/$REPO --json files,headRefName,baseRefName,additions,deletions,changedFiles

# PR status
gh pr view $PR_NUMBER --repo $OWNER/$REPO --json state,isDraft,title,number

# Current authenticated user (needed to distinguish own comments from others')
gh api user --jq .login

# Existing inline review comments — include id, author, path, line, and body
gh api repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments \
  --jq '[.[] | {id,path,line,body,author: .user.login}]'

# Existing PR-level (non-inline) comments
gh api repos/$OWNER/$REPO/issues/$PR_NUMBER/comments \
  --jq '[.[] | {id,body,author: .user.login}]'
```

Store:
- `CURRENT_USER` — the login returned by `gh api user`
- `EXISTING_INLINE[]` — list of `{id, path, line, body, author}`
- `EXISTING_GENERAL[]` — list of `{id, body, author}`

From the diff, determine:
- **Languages and tech stack** in use (TypeScript, Python, Go, etc.)
- **Project structure** — where tests live, naming conventions, how layers are separated
- **Primary intent** — what the code is actually trying to accomplish (from code patterns, not description)
- **Layers or modules touched** — e.g. controllers, services, repositories, domain objects, DTOs, entities, UI components, generated files, tests, migrations, config, etc.
- **Whether a backend layering pattern is in use** — infer from directory/file naming (e.g. `controllers/`, `services/`, `repositories/`, `entities/`, `dto/`, `domain/`)
- **Whether an API client generation tool is in use** — infer from generated files, `orval.config`, `openapi-generator`, `swagger-codegen`, etc.

If the PR is already **merged**, note it and proceed — comments are still useful historical record.
If the PR is a **draft**, note it in the final review body but still review fully.
If the diff is empty or the PR cannot be fetched, stop and report the error.

---

## Step 3 — Dispatch Specialist Review Agents in Parallel

Use the `Agent` tool to run all applicable agents **simultaneously**. Pass each agent the full diff text and extra rules. Each agent must return findings in the structured format below.

### Universal finding format (all agents must follow this exactly)

```
FINDING
severity: BLOCKING | NAIL-POLISH
file: path/to/file.ts
line: <line number in the new version of the file, or 0 if file-level>
category: Code Quality | Security | Architecture | Test Coverage | API Schema | Regression
problem: <what is wrong and why it matters — be specific, reference variable/function names>
fix: <concrete suggestion; include a short code snippet when the fix is non-obvious>
END
```

Return multiple FINDING...END blocks, one per issue. If nothing is found in your area, return: `NO_FINDINGS`.

---

### Agent A — Code Quality & Completeness

> You are a senior engineer reviewing a PR diff for code quality and completeness. Analyze the diff and return findings in the FINDING...END format.
>
> **Check for:**
> - Dead code or accidentally committed commented-out code
> - Magic numbers/strings that should be named constants
> - Functions violating Single Responsibility (doing too many things)
> - Naming that doesn't convey intent (misleading names are BLOCKING; vague names are NAIL-POLISH)
> - Incomplete implementations: `TODO`/`FIXME` without a ticket reference (BLOCKING if in an active code path, NAIL-POLISH otherwise)
> - Missing null/undefined guards that will cause runtime errors (BLOCKING)
> - Duplicate logic that already exists elsewhere in the same diff
> - Partial renames — changed in one place but not all occurrences in the diff
> - Console.log / debug print statements committed (NAIL-POLISH unless they expose sensitive data)
>
> **Extra rules:** EXTRA_RULES_PLACEHOLDER
>
> **DIFF:**
> DIFF_PLACEHOLDER

---

### Agent B — Security

> You are a security engineer reviewing a PR diff. Return findings in the FINDING...END format.
>
> **Check for:**
> - Injection vulnerabilities: SQL/NoSQL/command injection via string interpolation (BLOCKING)
> - XSS: unsanitized user input rendered as HTML (BLOCKING)
> - IDOR: endpoints that don't verify resource ownership before returning data (BLOCKING)
> - Missing or incorrect authentication/authorization guards on new endpoints (BLOCKING)
> - Sensitive data (tokens, passwords, PII) returned in response bodies or logged (BLOCKING)
> - Hardcoded credentials or secrets in code or config files (BLOCKING)
> - Unvalidated/unsanitized input accepted from external sources (BLOCKING)
> - Insecure HTTP methods (GET with side effects, state-changing operations without idempotency) (NAIL-POLISH)
> - Missing rate limiting on new public endpoints (NAIL-POLISH)
> - CORS, CSP, or security header regressions (BLOCKING if header removed, NAIL-POLISH if merely not added)
>
> **Extra rules:** EXTRA_RULES_PLACEHOLDER
>
> **DIFF:**
> DIFF_PLACEHOLDER

---

### Agent C — Backend Architecture (Layering)

> You are a backend architect reviewing a PR for architecture and layering compliance. Return findings in the FINDING...END format.
>
> **First, infer the architecture from the diff:**
> - Look at directory names, file names, decorators, imports, and class names to understand what layering pattern the project follows (e.g. Controller → Service → Repository, MVC, Clean Architecture, Hexagonal, etc.)
> - If no clear layering pattern exists, skip architecture findings and focus only on obvious cross-cutting concerns (e.g. HTTP logic in a persistence file).
>
> **If a layered backend architecture is detected, enforce it:**
>
> Expected call flow (adapt to the project's actual naming):
> ```
> HTTP Request → DTO/Request Schema → Controller → Service → Domain/Business Object → Repository → DB Model/Entity
>                                                                                     ← DB Model/Entity
>                                              ← Domain/Business Object ← Repository
>                              ← DTO/Response Schema ← Service
>         HTTP Response ← Controller
> ```
>
> **Rules (all violations are BLOCKING):**
> - HTTP/framework-specific code (request parsing, response serialization) belongs only in the outermost layer (controller/handler/route).
> - Business logic belongs only in the service/use-case layer — not in controllers, repositories, or DB models.
> - Persistence logic belongs only in the repository/data-access layer — controllers and services must not directly query the DB.
> - DB models/entities must not be returned from services — map them to domain objects or response schemas first.
> - DTOs/request-response schemas belong only at the HTTP boundary — they must not leak into inner layers.
> - Even if pre-existing code in the same file violated these rules, **new lines added in this diff** must comply.
>
> **Extra rules:** EXTRA_RULES_PLACEHOLDER
>
> **DIFF:**
> DIFF_PLACEHOLDER

---

### Agent D — API Schema Generation Compliance

> You are a frontend/API engineer reviewing a PR for API schema compliance. Return findings in the FINDING...END format.
>
> **First, detect whether the project uses an API client generation tool:**
> - Look for config files like `orval.config.ts`, `openapi-generator-config.json`, `swagger-codegen.json`, or similar.
> - Look for generated files (typically in directories named `generated/`, `api/generated/`, `__generated__/`, or similar).
> - If no code generation tooling is detected, return `NO_FINDINGS`.
>
> **If API code generation is in use, enforce it:**
> - Types that represent API request/response shapes MUST come from the generated files, not be written manually.
> - Signs of a manual schema violation: interfaces/types named like `CreateXxxDto`, `XxxResponse`, `ApiPayload` defined outside the generated directory; `fetch`/`axios`/`http` calls with manually-typed response shapes; types that look copy-pasted from API documentation.
> - The generated client (hooks, query functions, API methods) MUST be used to call API endpoints — raw HTTP calls that bypass the generated layer are BLOCKING.
> - If new API routes are consumed but the generated client has no corresponding function, flag it as BLOCKING (regeneration needed, not a manual workaround).
> - Modifying generated files by hand is BLOCKING — they will be overwritten on next generation.
>
> **Extra rules:** EXTRA_RULES_PLACEHOLDER
>
> **DIFF:**
> DIFF_PLACEHOLDER

---

### Agent E — Test Coverage

> You are a QA engineer reviewing a PR for test coverage. Return findings in the FINDING...END format.
>
> **Rules:**
> - Every new function, method, or class containing business logic MUST have at least one test in the same PR. Missing test = BLOCKING.
> - Deleted tests or tests changed to `.skip`/`.todo`/`xtest`/`xit` are BLOCKING unless the tested code was also deleted.
> - Significant logic change with no corresponding test update = BLOCKING (regression risk).
> - Tests with trivially-passing or vacuous assertions (e.g. `expect(true).toBe(true)`, empty test body) = BLOCKING.
> - Missing edge case coverage for security-sensitive paths (auth, permissions, input validation) = BLOCKING.
> - Missing test for a pure utility function with no side effects = NAIL-POLISH.
> - Test file naming or organization inconsistency with the rest of the project = NAIL-POLISH.
>
> **Extra rules:** EXTRA_RULES_PLACEHOLDER
>
> **DIFF:**
> DIFF_PLACEHOLDER

---

### Agent F — Regression & Completeness

> You are a senior engineer reviewing a PR for regressions and completeness gaps. Return findings in the FINDING...END format.
>
> **Check for:**
> - Import changed/removed but the consuming code in the diff was not updated (BLOCKING)
> - Function signature changed but not all call sites visible in the diff were updated (BLOCKING)
> - API contract changed (endpoint path, method, request/response shape) without updating known consumers (BLOCKING)
> - Environment variable added but missing from `.env.example` or equivalent documentation file (NAIL-POLISH)
> - Database migration added without a corresponding rollback/down migration (BLOCKING if the project uses reversible migrations)
> - Feature flag introduced without a cleanup ticket reference in a comment (NAIL-POLISH)
> - Config keys renamed/removed without updating all config files in the diff (BLOCKING)
> - Exported symbol removed without a deprecation path or replacement (BLOCKING)
> - Breaking change to a shared interface/type used by modules not visible in this diff (BLOCKING)
>
> **Extra rules:** EXTRA_RULES_PLACEHOLDER
>
> **DIFF:**
> DIFF_PLACEHOLDER

---

## Step 4 — Aggregate and Verify Findings

Collect all FINDING...END blocks from every agent.

1. **De-duplicate across agents**: if two agents flagged the same file+line for related reasons, merge into one finding combining both perspectives.
2. **Verify each BLOCKING finding**: confirm the flagged code is actually present in the diff. If a BLOCKING finding is unverifiable or is a false positive, downgrade to NAIL-POLISH or discard — do not post unverified blockers.
3. **Apply extra rules**: evaluate the user's extra rules against the diff. Classify extra-rule findings using the same BLOCKING / NAIL-POLISH judgment.
4. **Cross-reference against existing comments**: for each finding, search `EXISTING_INLINE[]` and `EXISTING_GENERAL[]` for a comment that already covers the same problem on the same file/line (semantic match — exact wording doesn't need to match). Classify each finding into one of three actions:

   | Situation | Action |
   |---|---|
   | No existing comment covers this finding | **NEW** — post a fresh comment |
   | An existing comment covers it and `author != CURRENT_USER` | **REINFORCE** — reply to that comment thread to support the point |
   | An existing comment covers it and `author == CURRENT_USER` | **EDIT** — update the existing comment with improved wording or added context |

5. Separate into:
   - `BLOCKING_FINDINGS[]` — each tagged with action: NEW / REINFORCE / EDIT
   - `POLISH_FINDINGS[]` — each tagged with action: NEW / REINFORCE / EDIT

---

## Step 5 — Post Inline Comments to GitHub

Run sequentially (GitHub API rate limits apply). For each finding, choose the right action:

### Action: NEW — post a fresh inline comment

```bash
cat > /tmp/review_comment.txt << 'COMMENT'
<formatted_comment_body>
COMMENT
gh api repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments \
  --method POST \
  --field commit_id="<head_commit_sha>" \
  --field path="<file_path>" \
  --field position=<diff_position> \
  --field body="$(cat /tmp/review_comment.txt)"

# IMPORTANT: Always write the body to a temp file first (cat > /tmp/review_comment.txt << 'COMMENT' ... COMMENT)
# and pass it via $(cat /tmp/review_comment.txt). Never inline the body with escaped backticks —
# they double-escape inside $() and break code block rendering on GitHub.
#
# `position` is the 1-based line offset in the unified diff for that file.
# Count from the @@ hunk header (position 1) through every context, added, and removed line.
# Each @@ header of subsequent hunks also counts as one position.
# Fetch the file diff to count: gh pr diff $PR_NUMBER --repo $OWNER/$REPO -- <file_path>
```

If `line` is 0 (file-level finding) or the line cannot be resolved (deleted file, binary, generated file), post as a PR-level comment instead:
```bash
gh pr comment $PR_NUMBER --repo $OWNER/$REPO --body "<formatted_comment_body>"
```

### Action: REINFORCE — reply to an existing comment thread

Use the existing comment's `id` as the `in_reply_to` parameter. This keeps the discussion threaded.

```bash
gh api repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments \
  --method POST \
  --field commit_id="<head_commit_sha>" \
  --field in_reply_to=<existing_comment_id> \
  --field body="<reinforcement_body>"
```

For PR-level comments (from `EXISTING_GENERAL[]`), reply as a new comment quoting the original:
```bash
gh pr comment $PR_NUMBER --repo $OWNER/$REPO \
  --body "> <first line of existing comment>\n\n<reinforcement_body>"
```

Reinforcement tone: briefly agree and add any extra context or impact that the original comment didn't mention. Don't just restate what was said — add value ("Agreed — also worth noting that this could affect X if Y happens").

### Action: EDIT — update own existing comment

```bash
gh api repos/$OWNER/$REPO/pulls/comments/<existing_comment_id> \
  --method PATCH \
  --field body="<updated_comment_body>"
```

For PR-level own comments, use:
```bash
gh api repos/$OWNER/$REPO/issues/comments/<existing_comment_id> \
  --method PATCH \
  --field body="<updated_comment_body>"
```

When editing, preserve the original content and append or refine — don't discard what was already written. Add a separator and a note that the comment was updated: `---\n*Updated: <one-line reason for the edit>.*`

**BLOCKING comment template:**
```
🚫 **[BLOCKING] <Category>**

<Problem — specific, referencing variable/function/method names. Explain why it matters.>

**How to fix:**
<Concrete suggestion. Include a short code example when the fix is non-obvious.>
```

**NAIL-POLISH comment template:**
```
💅 **[Suggestion] <Category>**

<Observation — what caught your eye and why it could be nicer. Keep the tone light; this is purely optional.>

If you feel like it:
<Concrete suggestion. If the change touches multiple files, use one labeled code block per file:>

`path/to/first/file.ts`
```ts
// suggested change
```

`path/to/second/file.ts`
```ts
// suggested change
```
```

Rules for NAIL-POLISH comments:
- Tone must be genuinely optional — phrases like "you might consider", "one idea", "totally up to you". Never use "should", "must", or "need to".
- If the suggestion touches more than one file, include a separate labeled code block for each file with its exact path. Never bundle multi-file suggestions into a single block.
- Never repeat a suggestion as a blocker — if it's NAIL-POLISH, it stays NAIL-POLISH regardless of how many files it spans.

Post all BLOCKING comments first, then NAIL-POLISH.

---

## Step 6 — Post Final Review Decision

After all inline comments are posted, submit the final review with one of the three verdicts below.

### Verdict: BLOCKING findings exist → REQUEST_CHANGES

```bash
gh pr review $PR_NUMBER --repo $OWNER/$REPO --request-changes --body "$(cat <<'EOF'
## Review: Changes Requested

Reviewed the actual code changes. Found **<N> blocking issue(s)** that must be resolved before merge.

### Blocking issues
<one bullet per BLOCKING finding — file:line and one-sentence summary>

### What looks good
<genuine positives; always include at least one if anything is well done>

### Non-blocking suggestions
<N nail-polish findings left inline — optional improvements>

---
*Review based on code diff only — PR description was not used as source of truth.*
EOF
)"
```

### Verdict: Only NAIL-POLISH findings (or none) → APPROVE with notes

```bash
gh pr review $PR_NUMBER --repo $OWNER/$REPO --approve --body "$(cat <<'EOF'
## Review: Approved ✓

The implementation looks solid. Left <N> optional suggestion(s) inline — act on them or not, they won't block merge.

### What I reviewed
- Code quality & completeness
- Security
- Backend architecture / layering (if applicable)
- API schema generation compliance (if applicable)
- Test coverage
- Regression risk

### Highlights
<2–3 genuine positives about the implementation — be specific>

---
*Review based on code diff only — PR description was not used as source of truth.*
EOF
)"
```

### Verdict: Zero findings → APPROVE cleanly

```bash
gh pr review $PR_NUMBER --repo $OWNER/$REPO --approve --body "$(cat <<'EOF'
## Review: Approved ✓

Clean implementation across all checked dimensions: code quality, security, architecture, test coverage, and regression risk.

<One sentence describing what the change actually does, derived from reading the code.>

---
*Review based on code diff only — PR description was not used as source of truth.*
EOF
)"
```

---

## Step 7 — Report to User

One or two sentences. Example:

> Posted review on PR #123: requested changes on 4 blocking issues (2 architecture, 1 security, 1 test coverage) with 3 nail-polish suggestions.

---

## Edge Cases

| Situation | Action |
|---|---|
| `gh` not authenticated | Run `gh auth status`; surface the error and stop |
| PR not found / private repo with no access | Report the error with the exact `gh` output |
| PR is already merged | Note it clearly; post comments anyway (historical record) |
| PR is a draft | Note "draft PR" in review body; still review fully |
| Diff is very large (>500 files) | Ask the user if they want to narrow the scope first |
| All agents return `NO_FINDINGS` | Still post an APPROVE with the "what I reviewed" summary — never silently skip |
| GitHub API rejects inline comment (line not in diff) | Fall back to PR-level comment, noting the file and line |
| Duplicate findings from multiple agents | Merge into one comment before posting |
| User-provided extra rules conflict with built-in rules | Apply the stricter rule; note the conflict in the comment |
