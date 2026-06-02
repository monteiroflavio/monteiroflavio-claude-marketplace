---
name: sync-main
description: Use when the user wants to update their current branch with the latest changes from origin/main, sync with main, pull in main changes, merge main into branch, or resolve merge conflicts from origin/main. Triggers on phrases like "sync with main", "update from main", "bring in main changes", "merge main", "pull main".
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - AskUserQuestion
---

# sync-main: Update Branch from origin/main

Fetches the latest origin/main and merges it into the current branch. When conflicts arise, resolves them intelligently — preserving meaningful changes from **both** sides wherever possible.

---

## Step 1 — Safety Check

Run `git status --porcelain` and `git diff --stat HEAD`. If there are any uncommitted changes (modified, untracked files that matter, or staged changes), **stop immediately** and tell the user:

> Your working tree has uncommitted changes. Please commit or stash them before syncing:
> - `git stash` to temporarily set them aside
> - `git add . && git commit -m "wip"` to commit them

Do NOT proceed if the working tree is dirty.

---

## Step 2 — Sync Current Branch with Remote

Before merging origin/main, ensure the local branch is up-to-date with its own remote tracking branch.

```bash
git rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null
```

- If the command **fails** (no upstream set), skip to Step 3 — there is nothing to sync.
- If the command **succeeds**, check for incoming commits from the remote tracking branch:

```bash
git log HEAD..@{u} --oneline
```

- If there are no incoming commits, the branch is already in sync — proceed to Step 3.
- If there are incoming commits, pull them with fast-forward only:

```bash
git pull --ff-only
```

  - If `--ff-only` **succeeds**, report the number of commits pulled and continue.
  - If `--ff-only` **fails** (local and remote have diverged), **stop immediately** and tell the user:

    > The local branch has diverged from its remote (`<upstream>`). Fast-forward is not possible.
    > Please resolve the divergence manually before syncing with main:
    > - `git pull --rebase` to rebase local commits on top of the remote
    > - Or inspect with `git log --oneline --graph HEAD...@{u}` to understand the divergence

    Do NOT proceed with the sync until the branch is in a fast-forward state with its remote.

---

## Step 3 — Fetch and Preview

```bash
git fetch origin
git log HEAD..origin/main --oneline
```

Show the user how many commits are incoming. If `origin/main` is already merged (no output), report "Branch is already up to date with origin/main" and stop.

---

## Step 4 — Attempt the Merge

```bash
git merge origin/main --no-edit
```

- If the merge succeeds with no conflicts → report success and the number of commits merged.
- If the merge produces conflicts → proceed to Step 5.

---

## Step 5 — Conflict Resolution Loop

### 5a. Identify conflicted files

```bash
git diff --name-only --diff-filter=U
```

### 5b. For each conflicted file

1. **Read the entire file** using the Read tool.
2. **Parse all conflict hunks** — each hunk is delimited by:
   ```
   <<<<<<< HEAD
   [ours — current branch changes]
   =======
   [theirs — origin/main changes]
   >>>>>>> origin/main
   ```
3. **Resolve each hunk** using the rules below.
4. **Write the resolved content** back using the Edit or Write tool (no conflict markers in the output).
5. **Stage the file**: `git add <filepath>`

### Conflict Resolution Rules (in priority order)

| Situation | Resolution |
|---|---|
| **Additive on both sides** (new imports, new functions, new fields that don't overlap) | Keep **both** — concatenate or merge the additions logically |
| **Same line edited differently** | Read the surrounding context. Prefer the version that is semantically more complete, more recent, or aligns with the feature being implemented |
| **One side deleted, the other edited** | **Escalate** — ask the user before dropping either version |
| **Only one side changed** (the other is identical to the common ancestor) | Keep the changed side |
| **Generated / lock files** (`package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`, `*.lock`) | Keep **theirs** (origin/main) — the lock file will be regenerated correctly after merge |
| **`package.json` dependency lists** | Merge both sets of dependencies; for version conflicts on the same package, keep the **higher** version |
| **Configuration files** (`.env.example`, `docker-compose`, `tsconfig`) | Merge both sides additively; if a key conflicts, prefer theirs and note the override to the user |
| **Genuinely ambiguous** (can't determine intent from context) | Use `AskUserQuestion` to show both versions and ask the user which to keep |

### 5c. When to Escalate (AskUserQuestion)

Always ask the user when:
- A deletion on one side conflicts with a meaningful edit on the other
- A conflict involves business logic where the intent of both changes is unclear
- More than 3 consecutive lines differ in a complex way and context doesn't clarify intent

Show both versions clearly when asking:
```
Conflict in `src/example.ts` — I need your guidance:

**Ours (current branch):**
[paste ours block]

**Theirs (origin/main):**
[paste theirs block]

Which should we keep, or should I combine them?
```

---

## Step 6 — Complete the Merge

After all files are resolved and staged:

```bash
git merge --continue
```

If `--continue` fails because there's nothing to commit (all conflicts were already staged), run:

```bash
git commit --no-edit
```

---

## Step 7 — Report

Summarize what happened:
- How many commits were merged
- How many files had conflicts, and how each was resolved
- Any decisions that were made automatically (and why)
- Any files the user should double-check

---

## Step 8 — Offer to Push

After reporting, ask the user via `AskUserQuestion` whether they want to push the updated branch to the remote.

- If the branch has no upstream set, push with `git push -u origin <current-branch>`.
- Otherwise, run `git push`.
- Determine the current branch with `git rev-parse --abbrev-ref HEAD` and check upstream with `git rev-parse --abbrev-ref --symbolic-full-name @{u}` (failure means no upstream).
- Never force-push. If the push is rejected (non-fast-forward), stop and report the error to the user — do not pass `--force` or `--force-with-lease` unless the user explicitly asks.
- If the user declines, skip the push and end the flow.

Report the push result (success or error output) back to the user.

---

## Common Pitfalls

- **Never use `git checkout --ours` or `--theirs` blindly** — always inspect the content first
- **Never remove conflict markers without reading both sides** — silent data loss is worse than a failed merge
- **Do not run `git merge --abort`** unless the user explicitly asks to abandon the sync
- **Do not commit until ALL conflicts are resolved** — `git diff --check` can help verify no markers remain
