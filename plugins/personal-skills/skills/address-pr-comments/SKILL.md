---
name: address-pr-comments
description: Use when the user wants to address, respond to, or resolve open review comments on a PR. Takes a GitHub PR URL, fetches all unresolved threads, groups related ones by context, applies code fixes, posts rationale replies, and answers or pushes back on comments where a code change isn't needed. Triggers on "address PR comments", "respond to PR comments", "fix PR comments", "resolve review comments", "responder comentários do PR", "resolver comentários".
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Agent
  - AskUserQuestion
---

# address-pr-comments: Address Open PR Review Comments

Act as the PR author responding to a code review. Read the code — not the PR description — to understand what was done and why. Group related comments together, fix what should be fixed, explain what shouldn't change, and ask for clarification when a comment is too ambiguous to act on.

## Non-negotiables

- Never post a reply without having read the actual current file state at the commented location.
- Every code fix must be committed and pushed before its reply is posted (replies reference "applied in <sha>").
- Group comments that touch the same file region or the same conceptual concern — tackle and reply to them together.
- Never apply a fix silently — always post a reply explaining what was done and why.
- Classify every thread; never skip an open thread without taking an action.
- Do not resolve threads on GitHub — let the reviewer mark them resolved after reading the reply.

---

## Step 1 — Parse Input

Extract from the user message:
1. **PR URL** — e.g. `https://github.com/owner/repo/pull/123`
2. **Extra context** — any guidance from the user (e.g. "don't touch the auth module", "we agreed with the reviewer on X")

Derive:
```
OWNER=<owner>
REPO=<repo>
PR_NUMBER=<number>
EXTRA_CONTEXT=<extra context, or "none">
```

---

## Step 2 — Fetch PR Data

Run all of the following **in parallel**:

```bash
# Current user (to distinguish own comments)
gh api user --jq .login

# PR metadata
gh pr view $PR_NUMBER --repo $OWNER/$REPO \
  --json headRefName,baseRefName,headRefOid,title,state,isDraft

# Full diff (SSoT for understanding what changed)
gh pr diff $PR_NUMBER --repo $OWNER/$REPO

# All inline review comments with thread context
gh api repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments \
  --jq '[.[] | {
    id,
    in_reply_to_id,
    path,
    line,
    original_line,
    body,
    author: .user.login,
    created_at,
    diff_hunk
  }]'

# PR-level (non-inline) comments
gh api repos/$OWNER/$REPO/issues/$PR_NUMBER/comments \
  --jq '[.[] | {id, body, author: .user.login, created_at}]'

# Review thread resolution state via GraphQL
gh api graphql -f query='
{
  repository(owner: "'$OWNER'", name: "'$REPO'") {
    pullRequest(number: '$PR_NUMBER') {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          comments(first: 20) {
            nodes {
              databaseId
              body
              path
              line
              author { login }
              createdAt
            }
          }
        }
      }
    }
  }
}'
```

Store:
- `CURRENT_USER` — login from `gh api user`
- `HEAD_SHA` — the `headRefOid` from PR metadata
- `HEAD_BRANCH` — the `headRefName`
- `INLINE_COMMENTS[]` — all inline comments
- `GENERAL_COMMENTS[]` — all PR-level comments
- `THREADS[]` — from GraphQL: `{id, isResolved, isOutdated, comments[]}`

---

## Step 3 — Filter and Build Thread Map

From `THREADS[]`, discard threads where `isResolved == true`.

For each remaining open thread:
- Identify the **root comment** (the one that started the thread, not a reply)
- Collect all **replies** in chronological order, preserving author and body for each

Do **not** filter threads based on who posted last. Authorship alone is an unreliable signal — when `review-pr` is used, all comments originate from `CURRENT_USER`, making author-based filtering useless. Instead, assess each thread's state from its content.

For each thread, run a content-based state assessment:

> Read the full comment chain (root + all replies) for this thread. Then read the current state of the file at the commented location.
>
> Determine the thread's state as exactly one of:
>
> - **NEEDS_ACTION** — The reviewer's concern is still unaddressed in the code, or their question hasn't been answered. Action is required.
> - **ALREADY_HANDLED** — A reply in the thread already fully resolves the concern (a fix was applied and confirmed, or a complete explanation was given) AND the current code confirms it. No further action needed; do not post a duplicate reply.
> - **WAITING_ON_REVIEWER** — The last substantive message explicitly directed a question or request for clarification *at the reviewer*, and the reviewer has not responded. Skip until they reply.
>
> Lean toward **NEEDS_ACTION** when in doubt — a redundant reply is less harmful than silently skipping an open concern.

Discard threads classified as `ALREADY_HANDLED` or `WAITING_ON_REVIEWER`.

Result: `OPEN_THREADS[]` — the set of threads classified as `NEEDS_ACTION`.

If `OPEN_THREADS[]` is empty, report "No open threads to address" and stop.

---

## Step 4 — Group Threads by Context

Group `OPEN_THREADS[]` into clusters. A cluster contains threads that share the same conceptual context and should be addressed together.

**Grouping rules (apply in order; first match wins):**

| Rule | Group together when... |
|---|---|
| Same file + adjacent lines | Threads on the same `path` whose `line` values are within 15 lines of each other |
| Same file + same function/class | Threads on the same `path` that fall within the same function or class block (infer from the `diff_hunk`) |
| Same cross-cutting concern | Threads on different files but the `body` text references the same concept (e.g. "error handling", "naming", "missing test", "import") — use semantic similarity, not exact match |
| Standalone | Everything else: each thread forms its own single-thread cluster |

Label each cluster with a short descriptor (e.g. `auth-service:validateToken`, `missing-tests`, `naming-in-dto`). This label is used in the summary reply header.

Result: `CLUSTERS[]` — each with `{label, threads[], files[]}`.

---

## Step 5 — Dispatch Analysis Agents in Parallel

For each cluster, spawn one Agent with the following prompt. Pass all thread bodies, the relevant file paths, and the full diff section for those files.

> **Task:** Analyze this cluster of PR review comments and determine the best response strategy.
>
> **Cluster label:** CLUSTER_LABEL
>
> **Threads in this cluster:**
> THREADS_PLACEHOLDER (each thread: path, line, reviewer comments in order, any existing replies)
>
> **Relevant diff section:**
> DIFF_SECTION_PLACEHOLDER
>
> **Extra context from PR author:** EXTRA_CONTEXT_PLACEHOLDER
>
> **Read the current state of the mentioned files** using the Read tool before drawing conclusions. The diff shows what changed; the file shows what it looks like now.
>
> **Classify the cluster** as exactly one of:
>
> ```
> CLASSIFICATION: ALREADY_APPLIED | NEEDS_FIX | DISAGREE | NEEDS_CLARIFICATION | ACKNOWLEDGE
> ```
>
> Definitions:
> - **ALREADY_APPLIED**: The code change requested in these comments has already been made in a commit after the comment was posted. The file's current state satisfies the reviewer's ask.
> - **NEEDS_FIX**: The reviewer's request is valid, clear, and actionable. Apply the change.
> - **DISAGREE**: The reviewer's request is not the right call. The current implementation is intentional or the suggestion would introduce a problem. Explain why without being defensive.
> - **NEEDS_CLARIFICATION**: The comment is too ambiguous to act on. A focused question to the reviewer is the right move.
> - **ACKNOWLEDGE**: The reviewer made a statement or observation that doesn't require a code change (e.g. "nice catch", question that's already answered by docs, curiosity comment). A brief thank-you or explanation is all that's needed.
>
> Then return a structured response in this exact format:
>
> ```
> CLASSIFICATION: <one of the above>
> RATIONALE: <1-3 sentences explaining the classification>
>
> [If NEEDS_FIX:]
> FILES_TO_CHANGE:
> - file: <path>
>   change: <precise description of what to change — specific enough to implement without re-reading the thread>
>   location: <function name, line range, or other anchor>
>
> [If DISAGREE:]
> PUSHBACK_REPLY:
> <The reply to post. Should: acknowledge the reviewer's concern, explain the intentional design decision or tradeoff, cite specific code or patterns if helpful. Tone: collegial, not dismissive.>
>
> [If NEEDS_CLARIFICATION:]
> CLARIFICATION_QUESTION:
> <The question to post. One focused question. Include what you've already understood to show you read the comment.>
>
> [If ALREADY_APPLIED or ACKNOWLEDGE:]
> REPLY_BODY:
> <The reply to post.>
> ```

Collect all agent responses. Result: `ANALYSIS[]` — one entry per cluster.

---

## Step 6 — Apply Code Fixes

Process all `NEEDS_FIX` clusters **sequentially** (to avoid conflicting edits on overlapping files).

### 6a — Capture pre-fix baselines

Before touching any file, record the current quality baselines so regressions can be detected later. Run whatever gates exist in the project — infer them from `package.json` scripts, `Makefile`, CI config, or tool config files present in the repo.

```bash
# TypeScript / JavaScript
npx tsc --noEmit 2>&1 > /tmp/baseline_typecheck.txt || true
npx eslint . --format json 2>/dev/null | python3 -c "
import sys,json; d=json.load(sys.stdin)
print(sum(len(f['messages']) for f in d))
" > /tmp/baseline_lint_count.txt 2>/dev/null || true

# Tests + coverage (run only if fast; skip if suite takes >2 min — note that in the report)
npx jest --coverage --coverageReporters=text-summary 2>&1 | tail -5 > /tmp/baseline_coverage.txt || true
# OR for Python:
pytest --tb=no -q 2>&1 | tail -3 > /tmp/baseline_test.txt || true
```

Store each baseline file. If a gate tool is absent from the project, skip it and do not invent a baseline.

### 6b — Apply the changes

For each `NEEDS_FIX` cluster:

1. **Read the current file state** for every file in `FILES_TO_CHANGE`.
2. **Apply the change** using the Edit tool. Be precise — change only what the reviewer asked for (plus any immediately adjacent cleanup that's directly caused by the change). Do not refactor surrounding code.

### 6c — Run quality gates and enforce no baseline drop

After all files in a cluster are edited, re-run every gate that produced a baseline in 6a.

**Type checking:**
```bash
npx tsc --noEmit 2>&1 > /tmp/post_typecheck.txt || true
diff /tmp/baseline_typecheck.txt /tmp/post_typecheck.txt
```
- If new type errors appear that weren't in the baseline → **fix them before committing**. Do not proceed with a broken type-check.

**Linting:**
```bash
npx eslint . --format json 2>/dev/null | python3 -c "
import sys,json; d=json.load(sys.stdin)
print(sum(len(f['messages']) for f in d))
" > /tmp/post_lint_count.txt 2>/dev/null || true
```
- If `post_lint_count > baseline_lint_count` → new lint violations were introduced. Fix them before committing. Auto-fix where possible (`eslint --fix`), manually fix the rest.
- The lint error count must never go up. It may go down (acceptable drop).

**Tests and coverage:**
```bash
npx jest --coverage --coverageReporters=text-summary 2>&1 | tail -5 > /tmp/post_coverage.txt || true
```
- If any test that previously passed now fails → fix the test or fix the code so the test passes. Do not delete or skip tests.
- If overall coverage percentage drops by any amount → add tests to cover the changed code before committing. A fix that removes a code path may legitimately drop coverage; in that case, also remove the now-dead test and confirm the net coverage holds.
- Coverage must never drop. It may rise.

**Baseline drop is a hard stop.** If a gate cannot be brought back to baseline within 2 fix attempts, do NOT commit the cluster's changes. Instead:
- Revert the edits for that cluster (`git checkout -- <changed_files>`)
- Reclassify the cluster as `BLOCKED_BY_GATES`
- Note the gate failure and the attempted fix in the reply (see Step 7)

### 6d — Commit

Once all gates pass (or the project has no gates to run):

```bash
git add <changed_files>
git commit -m "$(cat <<'EOF'
address review: CLUSTER_LABEL

- <one bullet per change applied>

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

Record the commit SHA for use in the reply.

### 6e — Push

After all fix clusters are committed:

```bash
git push origin $HEAD_BRANCH
```

---

## Step 7 — Compose and Post Replies

For every cluster, post a single summary reply to the **root comment** of each thread in the cluster.

### Reply format by classification

**NEEDS_FIX** — post as reply to each thread's root comment:
```
Applied in <short_sha>. <1-2 sentences explaining what was changed and why the reviewer's concern was valid.>

<If the cluster grouped multiple threads:>
This commit also addresses the related comments in [list other thread locations in this cluster].
```

**BLOCKED_BY_GATES** — post as reply to each thread's root comment:
```
I attempted this change but it caused a quality gate regression (type-check / lint / coverage) that I couldn't resolve without broader refactoring. Leaving this for manual attention.

Gate that failed: <gate name>
What was tried: <1-2 sentences describing the attempted fix and why it hit the gate>
```

**ALREADY_APPLIED** — post as reply to each thread's root comment:
```
This was already addressed in <short_sha> — <one sentence describing the existing fix and where it lives>.
```

**DISAGREE** — post the `PUSHBACK_REPLY` from the analysis agent as a reply to each thread's root comment.

**NEEDS_CLARIFICATION** — post the `CLARIFICATION_QUESTION` from the analysis agent as a reply to the root comment of the most relevant thread in the cluster. If the cluster has multiple threads, reference the others in the question.

**ACKNOWLEDGE** — post the `REPLY_BODY` from the analysis agent as a reply to the root comment.

### Posting inline replies

```bash
# Reply to an existing inline comment thread
cat > /tmp/reply_body.txt << 'REPLY'
<reply content>
REPLY

gh api repos/$OWNER/$REPO/pulls/$PR_NUMBER/comments \
  --method POST \
  --field commit_id="$HEAD_SHA" \
  --field in_reply_to=<root_comment_id> \
  --field body="$(cat /tmp/reply_body.txt)"
```

### Posting PR-level replies (for non-inline threads)

```bash
gh pr comment $PR_NUMBER --repo $OWNER/$REPO \
  --body "$(cat /tmp/reply_body.txt)"
```

Post replies for all clusters. Run `NEEDS_CLARIFICATION` replies last — reviewers may answer them while other replies are being posted.

---

## Step 8 — Post Cluster Summary (when a cluster has 2+ threads)

For any cluster that grouped 2 or more threads, post a **single PR-level comment** as a summary. This gives the reviewer a consolidated view of everything addressed in that cluster.

```bash
gh pr comment $PR_NUMBER --repo $OWNER/$REPO --body "$(cat <<'EOF'
### Addressed: CLUSTER_LABEL

<1 paragraph summary of the group of comments and how they were resolved together. Include the rationale for any design decisions made.>

**Threads covered:**
- `path/to/file.ts:LINE` — <one sentence on what changed or was explained>
- `path/to/file.ts:LINE` — <one sentence>

<If NEEDS_FIX:>
**Commit:** `<short_sha>`
EOF
)"
```

---

## Step 9 — Report to User

Summarize what was done:

```
Addressed N threads across M clusters on PR #<number>:

- NEEDS_FIX (K clusters, J threads): committed fixes in <sha1>, <sha2>
- BLOCKED_BY_GATES (K clusters): fix attempted but reverted — gate regressions (list gate + cluster)
- ALREADY_APPLIED (K clusters): replied with pointers to existing commits
- DISAGREE (K clusters): posted rationale replies
- NEEDS_CLARIFICATION (K clusters): posted clarification questions
- ACKNOWLEDGE (K clusters): posted brief acknowledgements
```

Call out any `BLOCKED_BY_GATES` clusters explicitly — the user needs to decide how to handle those manually.

---

## Edge Cases

| Situation | Action |
|---|---|
| `gh` not authenticated | Run `gh auth status`; surface the error and stop |
| PR not found / no access | Report the exact `gh` error and stop |
| `OPEN_THREADS[]` is empty | Report "No open threads to address" and stop |
| Thread is outdated (`isOutdated == true`) | Include it in analysis but note in the reply that the code has since changed; describe current state |
| Two threads in the same cluster disagree with each other | Flag to the user via `AskUserQuestion` before proceeding |
| Quality gate drops after applying a fix | Fix the regression (up to 2 attempts); if still failing, revert the cluster's edits and mark it BLOCKED_BY_GATES — never commit a baseline drop |
| Test suite is too slow to run (>2 min) | Note it in the report; run type-check and lint only; skip coverage gate for this session |
| A `NEEDS_FIX` edit conflicts with a prior fix in the same session | Read the already-edited file before applying the next change |
| Reviewer has multiple threads open on the same line | Merge them into one cluster entry; post a single reply covering all points |
| Extra context from user contradicts a NEEDS_FIX classification | Reclassify as DISAGREE and use the user's context as the rationale |
| PR is already merged | Note it; still post replies (useful historical record) — skip the commit/push step |
| Push is rejected (non-fast-forward) | Stop; tell the user to sync first (see `personal-skills:sync-main`) |
| Git working tree is dirty before committing | Stop; ask user to commit or stash before running this skill |
