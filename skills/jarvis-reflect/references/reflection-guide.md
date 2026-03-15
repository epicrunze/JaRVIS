# Reflection Guide

Good reflections are specific, honest, and actionable. Bad reflections are generic, self-congratulatory, and vague.

## Frontmatter

Every journal entry starts with YAML frontmatter. The frontmatter enables structured search and validation.

**Bad**:
```yaml
---
date: 2025-01-15
time: 14:30
tags: [code]
task_type: feature
---
```

**Good**:
```yaml
---
date: 2025-01-15
time: 14:30
tags: [pagination, prisma, api-routes]
task_type: feature
files_touched: [src/routes/users.ts, src/utils/pagination.ts, docs/openapi.yaml]
---
```

The test: are the tags specific enough to find this entry when searching for similar work later?

- **tags**: Use 2-5 lowercase keywords that describe the domain, technology, or concept — not generic words like "code", "fix", or "update".
- **task_type**: Match the primary nature of the work: `feature` (new capability), `bugfix` (correcting behavior), `refactor` (restructuring without behavior change), `docs` (documentation), `research` (investigation/analysis), `config` (tooling/settings), `other`.
- **files_touched**: Optional. List the most significant files, not every file. Omit for research or discussion tasks.

## Task Summary

**Bad**: "Helped with the API"
**Good**: "Added cursor-based pagination to GET /users using Prisma. Returns 20 results per page with encoded next/prev cursors. Updated OpenAPI spec and added integration test."

The test: could someone who wasn't in this session understand exactly what was delivered?

## Actions Taken

**Bad**: "Made some changes to the codebase"
**Good**: "1. Read existing route in src/routes/users.ts. 2. Added cursor param to Prisma query using `id` field. 3. Created encodeCursor/decodeCursor helpers in src/utils/pagination.ts. 4. Updated docs/openapi.yaml with new query params. 5. Added test in tests/users.test.ts covering forward/backward pagination and empty results."

The test: could someone replay your exact steps?

## What Worked

**Bad**: "The implementation went smoothly"
**Good**: "Writing the pagination helper as a generic utility first — before integrating into the route — made it independently testable and immediately reusable for the /products endpoint later."

The test: does this explain a transferable technique, not just a positive outcome?

## What Didn't Work

**Bad**: "Had some issues"
**Good**: "Initially tried offset-based pagination but discovered it returns inconsistent results when rows are inserted between requests. Spent ~10 minutes on this before switching to cursor-based. Should have checked the data mutation patterns first."

The test: does this describe a specific mistake and what you'd do differently?

## Lessons Learned

Each lesson should be useful to you in 3 months with zero surrounding context.

**Bad**:
- "Test more carefully"
- "Read the docs"

**Good**:
- "Prisma's `cursor` option requires the cursor field to have a unique index. `createdAt` won't work if two rows share a timestamp — use `id` instead."
- "This project's OpenAPI spec is the source of truth for the frontend team. Always update it alongside route changes or the PR gets blocked."

The test: is this a concrete fact or technique, not a vague aspiration?

## Memory Updates

Only persist things worth remembering long-term. Not every observation is a memory.

**Worth persisting**:
- Tool behaviors that surprised you
- User preferences you observed (not assumed)
- Decisions with rationale that might be questioned later
- Codebase facts that aren't obvious from reading the code

**Not worth persisting**:
- Things already documented in the codebase
- Temporary state ("currently working on X")
- Obvious facts ("TypeScript uses .ts extension")

## Completion Verification

Document how you verified the work was done. Vague claims of completion without evidence are a red flag.

**Bad**: "Task was completed" (no verification)
**Good**: "Verified: tests pass (42/42), changes committed (abc1234), lint clean. User confirmed feature works as expected."
**Good (partial)**: "Tests pass but user noted edge case X still needs handling. Reflecting on completed portion — edge case tracked for next session."

The test: could a reviewer confirm the work is done based on your verification notes alone?

## Identity Impact

Most tasks don't change your identity. That's fine. Say so.

But when a task does matter, be specific:

**Bad**: "I'm getting better at coding"
**Good**: "This was my first successful database migration. I can now claim basic competence with Prisma migrations, including handling the edge case of renaming columns with existing data."
