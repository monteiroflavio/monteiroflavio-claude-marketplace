---
name: quality-gate-setup
description: Use when the user wants to install or re-install the quality-gates Stop hook globally, or add a .claude/quality-gates config file to the current project. Triggers on "setup quality gates", "install quality gates", "quality gate config", or "add quality gates to this project".
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
---

# quality-gate-setup

Two modes. Detect which one the user wants from context:

- **Global install** (default when no project context) — copy the hook script to `~/.claude/hooks/` and wire the `Stop` hook in `~/.claude/settings.json`.
- **Project init** — create `.claude/quality-gates` in the current project so quality gates run here.

Run both if the user says "set up quality gates for this project" with no global hook already installed.

---

## Mode 1 — Global install

### Step 1 — Locate the shipped script

The hook runner ships with the plugin. Find it:

```bash
ls ~/.claude/plugins/cache/monteiroflavio-marketplace/monteiroflavio/*/hooks/quality-gates.sh 2>/dev/null | tail -1
```

If the glob returns nothing, the plugin cache is missing or stale — tell the user to re-sync the plugin and stop.

### Step 2 — Install (or upgrade) the runner

Always copy — this doubles as an upgrade path when the plugin updates:

```bash
mkdir -p ~/.claude/hooks
cp "<path-from-step-1>" ~/.claude/hooks/quality-gates.sh
chmod +x ~/.claude/hooks/quality-gates.sh
```

### Step 3 — Wire the Stop hook in settings.json

Read `~/.claude/settings.json`. Add the following entry to the `hooks.Stop` array **only if it is not already present** (check for `quality-gates.sh` in any existing Stop command):

```json
{
  "hooks": [
    {
      "type": "command",
      "command": "~/.claude/hooks/quality-gates.sh"
    }
  ]
}
```

Write the updated settings back. Do not disturb any other hook entries.

### Step 4 — Confirm

Tell the user whether this was a fresh install or an upgrade, then:
> Hook ready. Claude will run `.claude/quality-gates` at the end of every turn where that file exists. Re-run `/quality-gate-setup` after plugin updates to pull in the latest runner. Run it inside any project to create the config file.

---

## Mode 2 — Project init

### Step 1 — Check for existing config

```bash
cat "$(git rev-parse --show-toplevel 2>/dev/null || echo .)/.claude/quality-gates" 2>/dev/null
```

If the file already exists, show its contents and ask whether the user wants to overwrite or append.

### Step 2 — Collect gates

Ask the user which scripts to run as quality gates, or infer them from context (e.g. if scripts like `check-eslint-baseline.js`, `check-typecheck-baseline.js`, or `check-coverage-baseline.js` exist in the project, suggest them).

### Step 3 — Write the config

Write `.claude/quality-gates` at the git root. Format:

```
# Quality gates — one shell command per line. Blank lines and # comments are ignored.
# Each command runs from the project root. Non-zero exit fails the gate.

<command 1>
<command 2>
```

Every gate command receives two environment variables:

- **`QUALITY_GATE_CHANGED_FILES`** — newline-separated list of changed file paths, relative to the git root. Use this to limit checks to only the files that changed.
- **`QUALITY_GATE_PROJECT_ROOT`** — absolute path to the git root, so scripts can build file paths reliably.

For **monolithic repos** (multiple apps in one repo), prefix any command with `@<dir>` to scope it to a directory. The hook auto-skips the command when no changed file lives under that directory — no script changes required:

```
# Only runs when rhdp-back/ has changes
@rhdp-back node scripts/check-eslint-baseline.js backend
@rhdp-front node scripts/check-eslint-baseline.js frontend

# Type checking
@rhdp-back node scripts/check-typecheck-baseline.js backend
@rhdp-front node scripts/check-typecheck-baseline.js frontend

# API usage
node scripts/validate-api-usage.js --changed
```

Skipped commands are shown with `⊘` in the output and do not count toward the gate total. Commands without a `@<dir>` prefix always run (backwards-compatible with existing configs).

### Step 4 — Confirm

Tell the user the gates that were configured and remind them that the global hook must also be installed (`/quality-gate-setup` with no project context) if not done already.

---

## Edge cases

- **`~/.claude/hooks/` does not exist** — create it in Step 2.
- **Stop hook already wired** — skip Step 3 of Mode 1 (don't add a duplicate entry); Step 2 still runs to upgrade the script.
- **Plugin cache has multiple versions** — use `tail -1` to pick the latest (lexicographic order is sufficient for version directories).
- **Not in a git repo** — the hook gracefully exits 0 at runtime; warn the user that `$PWD` will be used as the project root instead of git root.
- **User wants to uninstall** — remove `~/.claude/hooks/quality-gates.sh` and the matching entry from `hooks.Stop` in `~/.claude/settings.json`.
