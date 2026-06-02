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

For each remaining thread, fetch the diff for that file:

```bash
gh pr diff $PR_NUMBER --repo $OWNER/$REPO -- <path>
```

Run these in parallel where possible — one call per unique `path`; re-use the result for multiple threads on the same file.

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
