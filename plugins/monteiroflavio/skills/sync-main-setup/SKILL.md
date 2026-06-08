---
name: sync-main-setup
description: Use when the user wants to install or re-install the sync-main UserPromptSubmit hook globally. Triggers on "setup sync-main", "install sync-main hook", "auto-sync with main on session start".
allowed-tools:
  - Bash
  - Read
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

Use `jq` to modify `~/.claude/settings.json` — never manually edit JSON, as it will produce missing commas or unclosed brackets.

**Check if already wired and add if missing:**
```bash
if jq -e '.hooks.UserPromptSubmit // [] | .[].hooks // [] | .[] | select(.command | test("sync-main.sh"))' ~/.claude/settings.json > /dev/null 2>&1; then
  echo "already-wired"
else
  jq '.hooks.UserPromptSubmit += [{"hooks": [{"type": "command", "command": "~/.claude/hooks/sync-main.sh"}]}]' \
    ~/.claude/settings.json > ~/.claude/settings.json.tmp && \
    mv ~/.claude/settings.json.tmp ~/.claude/settings.json
  echo "added"
fi
```

**Remove from SessionStart if present (the two must not coexist):**
```bash
jq 'if .hooks.SessionStart then .hooks.SessionStart |= map(select((.hooks // []) | map(.command) | any(test("sync-main.sh")) | not)) else . end' \
  ~/.claude/settings.json > ~/.claude/settings.json.tmp && \
  mv ~/.claude/settings.json.tmp ~/.claude/settings.json
```

---

## Step 4 — Confirm

Tell the user whether this was a fresh install or an upgrade, then:
> Hook ready. On your first message each session, Claude will automatically sync with `origin/main` and mention the result if anything changed. If the tree is dirty or conflicts arise, Claude will prompt you to run `/monteiroflavio:sync-main` to finish. Re-run `/sync-main-setup` after plugin updates to pull in the latest script.

---

## Edge cases

- **`~/.claude/hooks/` does not exist** — create it in Step 2.
- **UserPromptSubmit hook already wired** — the `jq` check in Step 3 will output `already-wired` and skip adding a duplicate; Step 2 still runs to upgrade the script.
- **SessionStart still has sync-main.sh** — remove that entry in Step 3 to avoid double-running.
- **Plugin cache has multiple versions** — use `tail -1` to pick the latest.
- **User wants to uninstall** — remove `~/.claude/hooks/sync-main.sh` and the matching entry from `hooks.UserPromptSubmit` in `~/.claude/settings.json`.
