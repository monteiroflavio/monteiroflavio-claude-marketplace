---
name: git-worktree
description: Use when the user wants to create, list, or remove a git worktree — to parallelize work, spin up a scratch branch, or tear down a finished one. Triggers on phrases like "create a worktree", "new worktree", "spin off a worktree", "worktree for this branch", "remove worktree", "delete worktree", "clean up worktree", "list worktrees". Works in any git repository.
allowed-tools:
  - Bash
  - AskUserQuestion
---

# git-worktree: Manage git worktrees for parallel work

Create a sibling worktree so a second session can work in parallel, or remove one cleanly when done. Repo-agnostic — no assumptions about project layout.

---

## Step 0 — Detect intent

Decide from the user's phrasing:

- **Create** — "create / new / spin off / add a worktree", "work on X in parallel"
- **Remove** — "remove / delete / drop / clean up worktree"
- **List** — "list worktrees", "what worktrees do I have"

If ambiguous, `AskUserQuestion` with the three options above.

Always start with a sanity check. Capture the **main repo root** once — every worktree command later runs with `git -C <main_repo_root>` so the skill never operates from a directory that might get removed:

```bash
git rev-parse --show-toplevel            # must succeed, else "not a git repo"
git worktree list --porcelain            # used to discover the main worktree
```

The **main worktree** is the first entry in `git worktree list --porcelain` (the one without a `linked` marker). Store its path as `<main_repo_root>` for the rest of the flow.

---

## Create flow

### C1 — Pick the new branch name

If the user supplied a name, use it. Otherwise ask via `AskUserQuestion`.

Validate:
```bash
git show-ref --verify --quiet "refs/heads/<name>"
```
If it already exists, ask whether to **check it out** into the new worktree (no `-b`) or **pick a different name**.

### C2 — Pick the base ref

`AskUserQuestion` with two options:
- **Current HEAD** — `git rev-parse --abbrev-ref HEAD` (derive from whatever the user is on; default)
- **origin/main** — fetch first (`git fetch origin main`), then branch off `origin/main`

Record the chosen base as `<base>`.

### C3 — Pick the worktree path

Default: sibling directory next to the main repo.

```bash
repo_name=$(basename "<main_repo_root>")
slug=$(echo "<new-branch>" | tr '/' '-' | tr '[:upper:]' '[:lower:]')
default_path="$(dirname "<main_repo_root>")/${repo_name}-${slug}"
```

Show the default to the user and let them override. If the path already exists and is non-empty, stop and ask — do not clobber.

### C4 — Create the worktree

New branch:
```bash
git -C <main_repo_root> worktree add -b <new-branch> <path> <base>
```

Existing branch (if C1 found one and the user chose to reuse it):
```bash
git -C <main_repo_root> worktree add <path> <new-branch>
```

If the command fails because the branch is already checked out in another worktree, report which one (`git worktree list`) and stop.

### C5 — Report and hand off

Print a short summary:
- Worktree path (absolute)
- Branch name and the base it was created from

Then present a ready-to-paste `cd` command the user can run in a **new terminal tab**. Put it on its own line in a fenced block so it's easy to copy, and use the **absolute path** (the new tab may start in a different directory):

```bash
cd <absolute-path-to-new-worktree>
```

Do **not** `cd` from the current session yourself — the original session stays in the original repo.

---

## Remove flow

### R1 — Pick the target

Parse `git worktree list --porcelain`. Exclude the main worktree (`<main_repo_root>`) — it cannot be removed.

- If the user named a path or branch, match it against the list.
- Otherwise `AskUserQuestion` with one option per removable worktree (label: `<branch> — <path>`).

Let `<target_path>` be the absolute path and `<target_branch>` the branch of the selection.

### R1a — Detect "removing from inside"

Compare the current working directory to `<target_path>`:

```bash
case "$(pwd -P)" in
  <target_path>|<target_path>/*) inside_target=1 ;;
  *) inside_target=0 ;;
esac
```

If `inside_target=1`, that is **fine** — the skill always runs git with `-C <main_repo_root>`, so removal works even when the user's shell is sitting inside the doomed worktree. Just remember to tell the user in R5 that their current shell will be left in a now-deleted directory.

### R2 — Check for uncommitted work

```bash
git -C <target_path> status --porcelain
git -C <target_path> log @{u}..HEAD --oneline 2>/dev/null   # unpushed commits, if upstream set
```

If either is non-empty, show the user what's there and `AskUserQuestion`:
- **Cancel** (default) — stop, do nothing
- **Force remove** — proceed with `--force`; warn that uncommitted changes will be lost

### R3 — Remove the worktree

Clean case:
```bash
git -C <main_repo_root> worktree remove <target_path>
```

Force case (only if user explicitly confirmed in R2):
```bash
git -C <main_repo_root> worktree remove --force <target_path>
```

Then prune stale admin entries:
```bash
git -C <main_repo_root> worktree prune
```

### R4 — Delete the branch

Always attempt to delete the branch after the worktree is gone:

```bash
git -C <main_repo_root> branch -d <target_branch>
```

- If `-d` fails because the branch isn't merged into its upstream/HEAD, **ask** the user whether to force with `git -C <main_repo_root> branch -D <target_branch>`. Never force-delete without confirmation.
- If the branch has a remote counterpart (`git -C <main_repo_root> ls-remote --exit-code origin <target_branch>` succeeds), ask whether to delete the remote branch too (`git -C <main_repo_root> push origin --delete <target_branch>`). Default: no.

### R5 — Report

One or two lines: which worktree + branch were removed, whether a force was used, whether the remote branch was also deleted.

If `inside_target` was set in R1a, **also** tell the user their current terminal is now in a deleted directory, and give them a ready-to-paste escape command:

```bash
cd <main_repo_root>
```

---

## List flow

```bash
git -C <main_repo_root> worktree list
```

Format the output as a short table (path, branch, HEAD). Mark the main worktree. Stop.

---

## Guardrails

- **Never** remove the main worktree — exclude it in R1 before offering choices.
- **Never** force anything (`--force`, `-D`, `push --delete`) without an explicit confirmation in the same turn.
- **Always** run worktree-mutating git commands with `git -C <main_repo_root> ...` — never rely on the shell's current directory, since the user may be inside the worktree being removed.
- **Never** `cd` permanently or mutate the user's current shell — the skill runs from the original repo; new worktrees are used by starting a fresh session in another tab.
- **Never** `rm -rf` a worktree directory manually — always go through `git worktree remove` so git's admin files stay consistent.
- If `git worktree list --porcelain` marks a worktree as `prunable` (path no longer exists on disk), offer `git worktree prune` instead of trying to remove it.
