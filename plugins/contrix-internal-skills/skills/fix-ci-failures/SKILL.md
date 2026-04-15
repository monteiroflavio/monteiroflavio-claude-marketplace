---
name: fix-ci-failures
description: Use when GitHub Actions CI/CD pipelines are failing, when a PR is blocked by red checks, when a branch has broken workflows, or when you need to systematically diagnose and fix CI errors (test failures, build errors, lint issues, type errors, Docker failures, deployment errors).
---

# Fix CI Failures

## Overview

Systematically discover, diagnose, and fix GitHub Actions CI/CD failures using the `gh` CLI. The core principle: **read logs before guessing**. Never modify code based on assumptions — always read the actual failing log lines first.

## When to Use

- A PR has failing checks you need to fix
- CI broke on a branch after a recent commit
- You need to understand what a pipeline does before modifying it
- Multiple jobs are failing and you need to triage order of fixes

## Discovery Phase

```bash
# List recent failed runs on current branch
gh run list --status failure --branch $(git branch --show-current) --limit 10

# List ALL recent runs (any status) with workflow name
gh run list --branch $(git branch --show-current) --json databaseId,workflowName,conclusion,headBranch,createdAt --limit 10

# Check PR checks specifically
gh pr checks  # requires being on a PR branch or passing PR number
```

## Read Failure Logs

```bash
# View summary of a failed run (shows which jobs/steps failed)
gh run view <run-id> --verbose

# Read only failed step logs (most efficient)
gh run view <run-id> --log-failed

# Read full logs for a specific job
gh run view <run-id> --job <job-id> --log

# Open in browser for complex multi-job runs
gh run view <run-id> --web
```

## Understand the Pipeline

```bash
# Find all workflow files
ls .github/workflows/

# Read the failing workflow
cat .github/workflows/<name>.yml
```

Key things to extract from the YAML:
- **Triggers**: `on:` — what events run this workflow
- **Job dependencies**: `needs:` — which jobs must pass first
- **Matrix strategy**: `strategy.matrix` — how many variants run
- **Caching**: `actions/cache` steps — what's being cached and when it invalidates
- **Environment variables and secrets**: what's injected
- **Container / runner**: `runs-on`, `container`

## Systematic Triage Order

Fix failures in this order — later failures are often caused by earlier ones:

1. **Lint / format** — fastest feedback, often blocks everything else
2. **Type check** — TypeScript `tsc --noEmit` errors
3. **Unit tests** — domain logic errors
4. **Build** — compilation, bundle, Docker image build
5. **Integration / e2e tests** — need a build first
6. **Deploy** — only runs after everything above passes

## Common Error Patterns

| Symptom in logs | Likely cause | Fix |
|---|---|---|
| `Cannot find module '...'` | Missing import or package | Check `package.json`, run install |
| `Type error: ... is not assignable` | TypeScript strict mode violation | Fix types; never use `as any` unless forced |
| `ENOENT: no such file or directory` | Path mismatch, missing generated file | Check if codegen step ran first |
| `exit code 1` with no message | Script returned non-zero | Read the lines immediately above |
| `Process completed with exit code 137` | OOM killed | Reduce memory usage or increase runner |
| `Error: Resource not accessible by integration` | Missing GitHub permission | Add `permissions:` block to workflow |
| `Error: Secret ... not found` | Missing repo/env secret | Add secret in GitHub Settings → Secrets |
| Cache miss causing slow run | Cache key changed | Review `hashFiles()` expression |
| `Job was cancelled` | Depends on another failed job | Fix the upstream job first |

## Fix Workflow

```
1. gh run list → find the failed run ID
2. gh run view <id> --log-failed → read exact error message
3. cat .github/workflows/<name>.yml → understand context
4. Identify the error category (table above)
5. Read the relevant source file
6. Apply the minimal fix
7. git push → gh run list → confirm green
```

## Re-triggering Runs

```bash
# Re-run only failed jobs (keeps passed jobs green)
gh run rerun <run-id> --failed

# Re-run entire workflow
gh run rerun <run-id>

# Watch a run in real time
gh run watch <run-id>
```

## Multi-Job Failures: Parallel Diagnosis

When many jobs fail at once, use the Agent tool to read multiple job logs in parallel. Dispatch one subagent per failing job, each reading `gh run view <id> --job <job-id> --log`. Synthesize results before touching any code.

## Common Mistakes

- **Fixing symptoms not causes**: If 5 jobs fail, read all of them before changing code — one root cause often explains all failures.
- **Guessing without reading logs**: Never change code to "try something" without reading the exact error first.
- **Fixing the wrong workflow file**: `gh run view --verbose` shows the workflow name — confirm you're reading the right `.yml` file.
- **Not checking job dependencies**: A failing deploy job may be caused by a failing build job. Fix upstream first.
- **Re-running flaky tests without investigation**: If a test is intermittently failing, root-cause it — don't just keep re-running.
