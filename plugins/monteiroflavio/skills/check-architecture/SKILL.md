---
name: check-architecture
description: Use when code needs to be reviewed for backend architecture and layering compliance. Triggers on "check architecture", "architecture review", "layering check", or when spawned as a sub-agent.
allowed-tools:
  - Read
  - Bash
---

# check-architecture: Backend Architecture & Layering Review

Analyze code for architecture and layering compliance.

## Input Handling

Check the **INPUT** section at the bottom of these instructions.

- If it still reads `INPUT_PLACEHOLDER`: ask the user what to analyze. Accepted inputs:
  - **Diff text** — pasted unified diff
  - **File or directory path** — read the file(s) with the `Read` tool; for a directory, read relevant source files within it
  - **GitHub PR URL** — run `gh pr diff <PR_NUMBER> --repo <OWNER>/<REPO>` to fetch the diff
- If it contains actual content: proceed directly with analysis.

Same for **EXTRA_RULES** — if it still reads `EXTRA_RULES_PLACEHOLDER`, treat it as "none".

When analyzing files directly (not a diff), check all code in the provided scope. When analyzing a diff, focus only on added/changed lines.

When run standalone, return a clear list of issues, noting severity (blocking vs. suggestion) for each. When spawned as a sub-agent, follow the output format specified by the caller.

## Review Checklist

**First, infer the architecture from the code:**
- Look at directory names, file names, decorators, imports, and class names to understand what layering pattern the project follows (e.g. Controller → Service → Repository, MVC, Clean Architecture, Hexagonal, etc.)
- If no clear layering pattern exists, skip architecture findings and focus only on obvious cross-cutting concerns (e.g. HTTP logic in a persistence file).

**If a layered backend architecture is detected, enforce it:**

Expected call flow (adapt to the project's actual naming):
```
HTTP Request → DTO/Request Schema → Controller → Service → Domain/Business Object → Repository → DB Model/Entity
                                                                                    ← DB Model/Entity
                                             ← Domain/Business Object ← Repository
                             ← DTO/Response Schema ← Service
        HTTP Response ← Controller
```

**Layer boundary rules (all violations are blocking):**
- HTTP/framework-specific code belongs only in the outermost layer (controller/handler/route).
- Business logic belongs only in the service/use-case layer — not in controllers, repositories, or DB models.
- Persistence logic belongs only in the repository/data-access layer — controllers and services must not directly query the DB.
- DB models/entities must not be returned from services — map them to domain objects or response schemas first.
- DTOs/request-response schemas belong only at the HTTP boundary — they must not leak into inner layers.

**Adapter/mapper rules (all violations are blocking):**
- **DTO → Domain object**: conversion must go through a dedicated mapper/adapter (e.g. `toDomain()`, `fromDto()`). Inline spread or manual property assignment without a mapper is a violation.
- **Domain object → Repository entity**: conversion to the persistence model must go through a mapper (e.g. `toEntity()`, `toPersistence()`). Services must not construct DB entities directly.
- **Repository entity → Domain object**: the repository must map its result back to a domain object before returning — raw DB entities must not escape the repository layer.
- **Domain object → DTO/Response**: conversion must use a mapper (e.g. `toDto()`, `toResponse()`). Inline object construction without a dedicated mapper is a violation.
- If a mapper exists for a given conversion, it must be used consistently — bypassing it in some call sites while using it in others is a violation.

**Extra rules:** EXTRA_RULES_PLACEHOLDER

**INPUT:**
INPUT_PLACEHOLDER
