# monteiroflavio Claude Marketplace

Personal Claude Code marketplace with reusable skills and plugins.

## Install

```
/plugin marketplace add monteiroflavio/monteiroflavio-claude-marketplace
/plugin install personal-skills@monteiroflavio-marketplace
```

## Plugins

- **personal-skills** — bundles the `sync-main`, `fix-ci-failures`, `create-pr`, and `git-worktree` skills.

## Adding a skill to an existing plugin

1. Drop the skill folder into `plugins/<plugin>/skills/<skill-name>/` (must contain `SKILL.md`).
2. Bump `version` in `plugins/<plugin>/.claude-plugin/plugin.json` and in the matching entry of `.claude-plugin/marketplace.json`.
3. Commit and push. Pick it up on next `/plugin` refresh.

## Refreshing an installed plugin

```
/plugin refresh <plugin-name>
```
