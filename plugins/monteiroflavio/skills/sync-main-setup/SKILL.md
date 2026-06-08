---
name: sync-main-setup
description: Use when the user wants to install or re-install the sync-main UserPromptSubmit hook globally. Triggers on "setup sync-main", "install sync-main hook", "auto-sync with main on session start".
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
---

# sync-main-setup

Installs the sync-main hook globally so that every Claude Code session automatically syncs the current branch with `origin/main` on the first user prompt. The hook outputs a `systemMessage` JSON so Claude surfaces the result inline — fully visible in the conversation, not lost in terminal flush.

---

## Step 1 — Locate the shipped script

The hook script ships with the plugin. Find it:

```bash
ls ~/.claude/plugins/cache/monteiroflavio-marketplace/monteiroflavio/*/hooks/sync-main.sh 2>/dev/null | tail -1
```

If the glob returns nothing, the plugin cache is missing or stale — tell the user to re-sync the plugin and stop.

---

## Step 2 — Install (or upgrade) the script

Always copy — this doubles as an upgrade path when the plugin updates:

```bash
mkdir -p ~/.claude/hooks
cp "<path-from-step-1>" ~/.claude/hooks/sync-main.sh
chmod +x ~/.claude/hooks/sync-main.sh
```

---

## Step 3 — Wire the UserPromptSubmit hook in settings.json

Read `~/.claude/settings.json`. Add the following entry to the `hooks.UserPromptSubmit` array **only if it is not already present** (check for `sync-main.sh` in any existing UserPromptSubmit command). Also remove any `sync-main.sh` entry from `hooks.SessionStart` if present — the two must not coexist.

```json
{
  "hooks": [
    {
      "type": "command",
      "command": "~/.claude/hooks/sync-main.sh"
    }
  ]
}
```

Write the updated settings back. Do not disturb any other hook entries.

---

## Step 4 — Confirm

Tell the user whether this was a fresh install or an upgrade, then:
> Hook ready. On your first message each session, Claude will automatically sync with `origin/main` and mention the result if anything changed. If the tree is dirty or conflicts arise, Claude will prompt you to run `/monteiroflavio:sync-main` to finish. Re-run `/sync-main-setup` after plugin updates to pull in the latest script.

---

## Edge cases

- **`~/.claude/hooks/` does not exist** — create it in Step 2.
- **UserPromptSubmit hook already wired** — skip Step 3 (don't add a duplicate entry); Step 2 still runs to upgrade the script.
- **SessionStart still has sync-main.sh** — remove that entry in Step 3 to avoid double-running.
- **Plugin cache has multiple versions** — use `tail -1` to pick the latest.
- **User wants to uninstall** — remove `~/.claude/hooks/sync-main.sh` and the matching entry from `hooks.UserPromptSubmit` in `~/.claude/settings.json`.
