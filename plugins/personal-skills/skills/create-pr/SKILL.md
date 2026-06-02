---
name: create-pr
description: Use when the user wants to open a pull request, finish a feature branch, ship the current work, or wrap up a session with a PR. Stages the changed files, commits (letting husky run lint-staged, baseline, type-check, and tests), pushes, and opens a PR with a body that summarises what changed and what the session accomplished. Links the matching Speckit spec at `specs/<branch>/` when present. Triggers on phrases like "create a PR", "open a PR", "ship this", "finish this branch", "abrir PR", "subir PR".
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Grep
  - Glob
  - AskUserQuestion
---

# create-pr: Ship the current branch as a PR

Take a working branch from "code written" to "PR open". Quality gates (lint, baseline, type-check, tests) are enforced by the husky `pre-commit` hooks in `rhdp-back/.husky/` and `rhdp-front/.husky/` — **don't duplicate them**. Just try to commit; if husky blocks, fix the root cause and try again.

**Non-negotiables**
- Never use `--no-verify`, `--no-gpg-sign`, or `git add -A` / `git add .`.
- Never force-push.
- Never commit `.env`, credentials, or unrelated files.
- If husky fails, **fix the root cause**. Do not bypass the hook. Do not delete or `.skip` failing tests.

---

## Step 1 — Orient

Run these **in parallel**:

```bash
git status --porcelain
git branch --show-current
git log --oneline origin/main..HEAD 2>/dev/null || git log --oneline -10
git diff --stat origin/main...HEAD 2>/dev/null || git diff --stat HEAD
gh pr list --head "$(git branch --show-current)" --json number,url,state 2>/dev/null
```

From the output, determine:

- **Current branch** — if it is `main` / `master`, see **"On main" flow** below before continuing.
- **Existing PR?** — if `gh pr list` shows an `OPEN` PR, default to updating it (push more commits). Ask only if the user's intent is unclear.
- **Workspaces touched** — which of `rhdp-back/`, `rhdp-front/`, `specs/`, root configs. This informs the PR body, nothing else.
- **Spec link** — if `specs/<current-branch>/spec.md` exists, read it. Capture title + primary goal for the PR body.

Report a one-line summary to the user: branch, workspaces touched, spec detected (yes/no), PR exists (yes/no).

### On main flow

When the current branch is `main` or `master`:

1. Derive a candidate branch name from the staged/unstaged diff — use `git diff --stat HEAD` and `git log --oneline -5` to infer a short, kebab-case name (e.g. `feat/add-user-auth`).
2. Ask the user to confirm or override the name:
   ```
   You're on main. I'll create branch "<candidate>" and continue — OK, or type a different name?
   ```
3. On confirmation (or custom name), run:
   ```bash
   git checkout -b "<branch-name>"
   ```
4. Continue from Step 2 with the new branch as the current branch.

---

## Step 2 — Stage

List the files to stage explicitly (never `git add -A`):

```bash
git add <path1> <path2> ...
```

Include files the user modified or created in this session.

**Exclude**:
- `.env`, `*.local`, credential files
- Unrelated changes that belong to a different task
- Lockfiles, unless the change genuinely involves dependencies

Run `git diff --cached --stat` and show what's about to be committed. If anything looks off, ask before continuing.

---

## Step 3 — Commit (let husky run the gates)

Draft the message from the staged diff + session work. Match the repo's existing style (`git log --oneline -20`).

- **Title**: ≤70 chars, imperative mood, user-visible outcome.
- **Body**: 2–5 bullets on what and why. Reference the spec by name if relevant.

```bash
git commit -m "$(cat <<'EOF'
<title>

- <bullet 1>
- <bullet 2>

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

### If husky blocks the commit

Husky hooks run **in the changed workspace(s)**:
- `rhdp-back/.husky/pre-commit` → lint-staged + eslint baseline + `type-check` + `jest`
- `rhdp-front/.husky/pre-commit` → lint-staged + eslint baseline + `type-check` + `vitest run` + legacy-API check

Failure modes and responses:

| Failure | Response |
|---|---|
| `lint-staged` rewrote files (prettier/eslint --fix) | The hook already staged the fixes — just re-run the commit. If it rewrote files but then failed on unfixable errors, read the output and fix in code. |
| ESLint baseline ratchet blocks | Read which files newly crossed the baseline. Fix them at the source. Do not update the baseline to paper over new issues — the ratchet only **lowers** baselines, never raises. |
| `type-check` fails | Fix the type errors. No `any`, no `@ts-ignore` unless the user explicitly asks. |
| `jest` / `vitest` fails | Invoke the `superpowers:systematic-debugging` skill if the cause isn't obvious. Fix the code or the test — don't delete or skip. |
| Legacy-API check blocks (frontend, new file imports from `lib/api/modules/`) | Rewrite the new file to use the generated Orval client instead. |

After fixing, run `git status` — lint-staged may have produced new unstaged edits inside already-staged files. Re-stage those files explicitly and retry the commit. **Never** `--amend` a commit that never landed; create a new commit each attempt.

---

## Step 4 — Push

```bash
git push -u origin "$(git branch --show-current)"
```

Never `--force` / `--force-with-lease` unless the user explicitly asks.

---

## Step 5 — Open (or update) the PR

### PR already exists
The push refreshed it. Fetch the URL:
```bash
gh pr view --json url -q .url
```
Only add a comment if the user asks.

### No PR yet
Draft the body from:
1. The commits in `git log origin/main..HEAD` and the full diff stat.
2. The session's context — the *why* and any trade-offs the user called out.
3. The Speckit spec, if `specs/<branch>/spec.md` exists.

```bash
gh pr create --title "<title ≤70 chars>" --body "$(cat <<'EOF'
## Summary
- <what shipped, user-visible>
- <notable implementation choice>
- <known gaps or follow-ups, if any>

## Spec
<include only if specs/<branch>/ exists>
Implements `specs/<branch>/spec.md` — <one-line goal quoted from the spec>.
Relevant tasks: <list any completed task IDs from tasks.md, or omit>.

## Session notes
<1–3 bullets about how the work was approached — useful context the diff alone doesn't show. Omit this section if the diff speaks for itself.>

## Test plan
- [ ] <manual check 1 tied to user-visible behaviour>
- [ ] <manual check 2>
- [ ] <regression check on an adjacent feature>

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

Return the PR URL.

---

## Step 6 — Report

One or two sentences. Example:

> Opened PR #341 — *simplify auth flow*. Husky gates passed (lint, baseline, type-check, jest). Spec `001-simplify-auth-flow` linked.

Stop.

---

## Edge cases

- **Nothing modified and nothing staged** — tell the user there's nothing to ship.
- **Only lockfile changed** — ask whether it's intentional before committing.
- **User is on `main`** — derive a branch name from the diff, confirm with the user, `git checkout -b <name>`, then continue.
- **`gh` not authenticated** — `gh auth status`; surface the error and stop.
- **Working tree has files unrelated to this task** — list them and ask which belong in this PR before staging.
- **Husky hook not installed** (`.husky/_/` missing) — run `npm install` in the affected workspace once, then retry. Do not bypass the hook.
