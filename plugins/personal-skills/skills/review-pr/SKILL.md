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

# PR status and author
gh pr view $PR_NUMBER --repo $OWNER/$REPO --json state,isDraft,title,number,author

# Current authenticated user (needed to distinguish own comments from others')
gh api user --jq .login

# Existing inline review comments — include id, author, path, line, and body
gh api repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments \
  --jq '[.[] | {id,path,line,body,author: .user.login}]'

# Existing PR-level (non-inline) comments
gh api repos/$OWNER/$REPO/issues/$PR_NUMBER/comments \
  --jq '[.[] | {id,body,author: .user.login}]'
```

In parallel with the above, invoke `personal-skills:fetch-pr-threads` via Agent, passing the PR URL. Store the returned list as `REVIEW_THREADS[]`.

Store:
- `CURRENT_USER` — the login returned by `gh api user`
- `PR_AUTHOR` — the `author.login` from the PR view JSON
- `EXISTING_INLINE[]` — list of `{id, path, line, body, author}`
- `EXISTING_GENERAL[]` — list of `{id, body, author}`
- `REVIEW_THREADS[]` — list of `{id, isResolved, isOutdated, comments[{id, databaseId, body, path, line, originalLine, author, createdAt}], diffContext}` from `fetch-pr-threads`

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

## Step 2.5 — Assess Open Thread States

`REVIEW_THREADS[]` already contains only unresolved threads (filtered by `fetch-pr-threads`).

If `REVIEW_THREADS[]` is empty, skip to Step 3.

For each open thread, build a context entry using the data already returned by `fetch-pr-threads`:

1. **Full conversation** — all comments in chronological order with author and body.
2. **Relevant diff context** — use the `diffContext` field from `REVIEW_THREADS[]` (already fetched per-file by `fetch-pr-threads`).

**Do not filter by authorship.** Author identity is an unreliable signal — when `review-pr` and `address-pr-comments` are used together, replies may be posted by the same GitHub login regardless of which role (reviewer vs. author) originated the response. Classify each thread's state purely from its content.

For each thread, apply a content-based state assessment:

> Read the full comment chain (first comment + all replies). Then look at the diff context for that file and line.
>
> Determine the thread's conversational state as exactly one of:
>
> - **NEEDS_REVIEW** — The most recent substantive message in the thread comes from the PR author side: they notified a fix, pushed back, asked a question, or explained a decision. It is now the reviewer's turn to respond.
> - **WAITING_FOR_AUTHOR** — The reviewer made a request, asked a question, or left a concern that has not yet been meaningfully responded to. Nothing to evaluate here — skip.
> - **SETTLED** — The thread appears fully resolved by content (a fix was confirmed, both sides agreed, or the concern was withdrawn), even though it wasn't marked resolved on GitHub. Skip.
>
> When the state is ambiguous, default to **NEEDS_REVIEW** — a redundant evaluation comment is less harmful than silently ignoring an open concern.

Store as `OPEN_THREADS_FOR_REVIEW[]` — threads classified as `NEEDS_REVIEW`, each with `{thread, fullConversation, relevantDiff}`.

---

## Step 3 — Run Specialist Checks and Evaluate Open Threads

Use the `Agent` tool to run the following **simultaneously**:

**Analysis — `personal-skills:pr-reviewer` agent:**
Pass the full diff and extra rules. Store returned `FINDING...END` blocks as `ALL_FINDINGS[]`.

**Open threads (only if `OPEN_THREADS_FOR_REVIEW` is non-empty) — Agent G:**

### Agent G — Open Thread Response Evaluator

> **Only run this agent if OPEN_THREADS_FOR_REVIEW is non-empty.**
>
> You are a senior engineer evaluating PR author responses to open review comment threads. For each thread, you receive the full conversation and the current diff context at the relevant file/line.
>
> Process each thread independently. Do not use author login as a signal — evaluate from content alone.
>
> ---
>
> **For each thread, follow this two-step process:**
>
> **Step 1 — Identify the nature of the author's latest response** by reading the conversation. Infer from what was said, not who said it. Classify as one of:
>
> - `CODE_FIX` — the response notifies that code was changed (e.g. "done", "fixed", "updated", "applied", or any statement clearly implying a commit was made in response to the concern).
> - `PUSHBACK` — the response argues against the suggestion (e.g. "this is intentional", "I disagree because...", "we decided not to", "actually the reason is...").
> - `QUESTION` — the response asks for clarification or more context from the reviewer.
> - `PARTIAL` — the response addresses some aspects of the concern but explicitly or implicitly leaves others open.
>
> **Step 2 — Evaluate and produce an outcome:**
>
> **If `CODE_FIX`:**
> - Look at the diff context at the thread's `path` near the original `line`.
> - Determine whether the code change actually resolves the original concern — not just whether *something* changed, but whether the *right thing* changed.
> - If fully resolved: outcome = `RESOLVED`. Write a brief one-sentence confirmation.
> - If not fully resolved or the fix is incorrect: outcome = `NEEDS_MORE_WORK`. Specify exactly what is still missing or wrong.
>
> **If `PUSHBACK`:**
> - Evaluate whether the author's argument is technically sound and addresses **all** aspects of the original concern.
> - Consider: Is the argument based on correct assumptions? Does it address the root problem (not just the symptom)? Is there a trade-off the author is making consciously or overlooking?
> - If the argument is valid and the original concern no longer stands: outcome = `ACCEPTED_PUSHBACK`. Write a brief acknowledgment.
> - If the argument is invalid, incomplete, or based on incorrect assumptions: outcome = `INVALID_PUSHBACK`. Write a comprehensive explanation — address each point raised and explain precisely why the original concern persists. Be respectful but direct.
>
> **If `QUESTION`:**
> - Provide a clear, direct answer.
> - If the answer means no code change is needed, say so explicitly. If a code change is still required, reiterate what and where.
> - Outcome = `ANSWERED`.
>
> **If `PARTIAL`:**
> - List what was addressed and what remains.
> - Outcome = `NEEDS_MORE_WORK`. Enumerate only the outstanding items with concrete next steps.
>
> ---
>
> Return one block per thread:
>
> ```
> THREAD_EVAL
> thread_id: <GraphQL thread id, e.g. PRT_...>
> comment_id: <databaseId of the FIRST comment in the thread>
> path: <file path from the thread>
> nature: CODE_FIX | PUSHBACK | QUESTION | PARTIAL
> outcome: RESOLVED | NEEDS_MORE_WORK | ACCEPTED_PUSHBACK | INVALID_PUSHBACK | ANSWERED
> reply: <the reply to post — see reply templates below>
> END
> ```
>
> Reply templates:
> - `RESOLVED`: `✅ **Addressed** — <one sentence confirming the fix resolves the original concern.>`
> - `ACCEPTED_PUSHBACK`: `👍 **Fair point** — <acknowledgment of why the author's argument is valid. Add any nuance if relevant.>`
> - `INVALID_PUSHBACK`: `🔄 **Still outstanding** — <comprehensive explanation of why the original concern persists, addressing each of the author's points directly. Then reiterate the suggested fix, adjusted if needed based on the context the author provided.>`
> - `NEEDS_MORE_WORK`: `🔄 **Partially addressed** — Thanks for the update. Here's what still needs attention:\n\n- <item 1>\n- <item 2>\n\n<Concrete next steps.>`
> - `ANSWERED`: `💬 **Clarification** — <direct answer to the author's question. State explicitly whether a code change is still needed.>`
>
> ---
>
> **OPEN_THREADS_FOR_REVIEW:**
> OPEN_THREADS_PLACEHOLDER
>
> **DIFF:**
> DIFF_PLACEHOLDER

---

## Step 4 — Aggregate and Verify Findings

Collect all FINDING...END blocks from Agents A–F.

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

Collect all THREAD_EVAL blocks from Agent G (if it ran) into `THREAD_EVALUATIONS[]`. Each entry carries `{thread_id, comment_id, path, nature, outcome, reply}`.

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

## Step 5.5 — Handle Open Thread Evaluations

Skip this step if `THREAD_EVALUATIONS[]` is empty.

For each entry in `THREAD_EVALUATIONS[]`, run sequentially:

### 1. Post a reply to the thread

```bash
cat > /tmp/thread_reply.txt << 'REPLY'
<reply from THREAD_EVAL>
REPLY

gh api repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments \
  --method POST \
  --field commit_id="<head_commit_sha>" \
  --field in_reply_to=<comment_id from THREAD_EVAL> \
  --field body="$(cat /tmp/thread_reply.txt)"
```

### 2. Resolve the thread if the outcome warrants it

Resolve the thread (via GraphQL) **only** when `outcome` is `RESOLVED` or `ACCEPTED_PUSHBACK`:

```bash
gh api graphql -f query='
mutation($threadId: ID!) {
  resolveReviewThread(input: {threadId: $threadId}) {
    thread { id isResolved }
  }
}' -f threadId="<thread_id from THREAD_EVAL>"
```

Leave the thread **open** (do not resolve) when `outcome` is `NEEDS_MORE_WORK`, `INVALID_PUSHBACK`, or `ANSWERED` — the thread should stay visible until the author acts.

---

## Step 6 — Post Final Review Decision

After all inline comments and thread replies are posted, submit the final review with one of the three verdicts below.

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

### Open threads
<if THREAD_EVALUATIONS is non-empty: one bullet per thread — path:line, outcome, one-sentence summary. Skip this section if empty.>

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

### Open threads
<if THREAD_EVALUATIONS is non-empty: one bullet per thread — outcome and one-sentence summary. Skip this section if empty.>

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

One or two sentences covering both new findings and thread outcomes. Example:

> Posted review on PR #123: requested changes on 4 blocking issues (2 architecture, 1 security, 1 test coverage) with 3 nail-polish suggestions. Handled 3 open threads: resolved 2 (code fixes verified), pushed back on 1 invalid argument.

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
| GraphQL `reviewThreads` returns empty (old PR or API limit) | Skip Step 2.5 and Agent G; proceed with code review only |
| Thread `resolveReviewThread` mutation fails | Log the error, leave the thread open, and note it in the user report |
| Thread state is ambiguous (can't tell if it's NEEDS_REVIEW or WAITING_FOR_AUTHOR) | Default to `NEEDS_REVIEW` — a redundant evaluation reply is less harmful than silently skipping an open concern |
| Author's response nature is ambiguous (can't classify as CODE_FIX, PUSHBACK, etc.) | Default to `PUSHBACK` evaluation — treat it as a textual argument and evaluate its validity |
| Thread has many back-and-forth replies | Focus on the latest unresolved exchange to avoid re-litigating settled points; reference earlier context only if directly relevant |
