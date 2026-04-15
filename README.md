# Contrix Plugins Marketplace

Internal Claude Code marketplace for Contrix team.

## Install

```
/plugin marketplace add <org>/contrix-plugins-marketplace
/plugin install contrix-internal-skills@contrix-marketplace
```

## Plugins

- **contrix-internal-skills** — bundles the `sync-main` and `fix-ci-failures` skills.

## Adding a skill to an existing plugin

1. Drop the skill folder into `plugins/<plugin>/skills/<skill-name>/` (must contain `SKILL.md`).
2. Bump `version` in `plugins/<plugin>/.claude-plugin/plugin.json` and in the matching entry of `.claude-plugin/marketplace.json`.
3. Commit and push. Teammates pick it up on next `/plugin` refresh.
