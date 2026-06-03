---
name: fetch-pr-threads
description: Fetches open review threads from a GitHub PR and enriches each with per-file diff context.
allowed-tools:
  - Bash
---

# fetch-pr-threads: Fetch Open PR Review Threads

Fetch all review threads for a GitHub PR, filter to unresolved ones, and enrich each with the diff context for its file.

## Step 1 — Parse Input

Extract from the input:
1. **PR URL** — e.g. `https://github.com/owner/repo/pull/123`

Derive:
```
OWNER=<owner>
REPO=<repo>
PR_NUMBER=<number>
```

## Step 2 — Fetch Threads via GraphQL

```bash
gh api graphql -f query='
query($owner: String!, $repo: String!, $number: Int!) {
  repository(owner: $owner, name: $repo) {
    pullRequest(number: $number) {
      reviewThreads(first: 100) {
        nodes {
          id
          isResolved
          isOutdated
          comments(first: 20) {
            nodes {
              id
              databaseId
              body
              path
              line
              originalLine
              author { login }
              createdAt
            }
          }
        }
      }
    }
  }
}' -f owner="$OWNER" -f repo="$REPO" -F number=$PR_NUMBER
```

Discard threads where `isResolved == true`.

## Step 3 — Enrich with Diff Context

Fetch the full PR diff once, then extract per-file sections:

```bash
gh pr diff $PR_NUMBER --repo $OWNER/$REPO > /tmp/pr_full_diff.txt
```

```bash
python3 - <<'PYEOF'
import json

with open('/tmp/pr_full_diff.txt') as f:
    content = f.read()

sections = {}
current_file = None
current_lines = []

for line in content.splitlines(keepends=True):
    if line.startswith('diff --git '):
        if current_file:
            sections[current_file] = ''.join(current_lines)
        parts = line.split(' ')
        current_file = parts[2][2:] if len(parts) >= 3 else None  # strip "a/"
        current_lines = [line]
    elif current_file is not None:
        current_lines.append(line)

if current_file:
    sections[current_file] = ''.join(current_lines)

print(json.dumps(sections))
PYEOF
```

Store the result as `FILE_DIFFS` (dict keyed by file path). For each thread, set `diffContext = FILE_DIFFS[thread.path]`. If a path is missing from `FILE_DIFFS`, set `diffContext: null` and note the missing path.

## Output

Return `THREADS[]` — one entry per unresolved thread:

```
{
  id: <GraphQL thread id, e.g. PRT_...>,
  isOutdated: <boolean>,
  comments: [
    {
      id: <REST API comment id>,
      databaseId: <integer>,
      body: <comment text>,
      path: <file path>,
      line: <line number or null>,
      originalLine: <original line number>,
      author: <login string>,
      createdAt: <ISO timestamp>
    }
  ],
  diffContext: <raw diff output for this thread's file>
}
```

**Do not classify thread state here.** The calling skill applies its own perspective-specific classification. Do not filter by authorship — author identity is an unreliable signal when `review-pr` and `address-pr-comments` are used together, since replies may be posted under the same GitHub login regardless of which role originated the response.

## Error Handling

| Situation | Action |
|---|---|
| GraphQL returns empty `reviewThreads` (old PR or API limit) | Return an empty `THREADS[]` and note it |
| `gh` not authenticated | Run `gh auth status`; surface the error and stop |
| Per-file diff fetch fails for a thread | Include the thread with `diffContext: null`; note which paths failed |
