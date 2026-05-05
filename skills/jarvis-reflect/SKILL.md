---
name: jarvis-reflect
description: Post-task reflection and memory sculpting for jarvis. Use this skill after completing any meaningful task, when the user says "reflect", "what did we learn", "save what we did", "update memories", or after finishing a coding task, debugging session, architecture decision, or any significant unit of work. Also use when the user asks to review or consolidate memories. Writes to the JaRVIS data directory.
---

# JaRVIS Reflect

You just completed a task. Now pause and reflect on what happened. This is how you grow.

## Step 1: Verify task completion

Run `JARVIS_DIR=$(bash <skill-path>/scripts/resolve-dir.sh)` to set `JARVIS_DIR`.

If the resolved directory doesn't exist, inform the user they need to run `/jarvis-init` first, then stop.

## Step 2: Locate your JaRVIS data directory

Verify the work is actually done, or the session is complete.

**a) Check your memories for learned completion criteria.**
Read the JaRVIS memories directory for any entries about what "done" means in this project. Examples of learned criteria: "tests must pass", "code should be committed", "linting must be clean", "user expects a PR before reflecting."

**b) Evaluate any criteria you found.**
Run the checks you can (e.g., test suite, git status, lint). Note what passed, what failed, and what you couldn't check.

**c) Gate on the results:**
If you feel comfortable with the results and happy with your implementation, proceed to Step 2. Otherwise, note what's wrong with the implementation and either fix it or notify the user.

## Step 3: Write your reflection

Create a new journal entry at `$JARVIS_DIR/journal/YYYY-MM-DD-HH-MM-XXXXXXXX.md` using the current timestamp and 8 random hex characters (generate with `head -c4 /dev/urandom | xxd -p`).

**Before writing**, identify the tags and task_type you'll assign to this entry, then use `/jarvis-search` to search past journal entries for related work using those tags. If matches exist, review the "Lessons Learned" and "What Didn't Work" sections from those entries. Use this to:
- Avoid re-learning the same lessons — reference prior experience instead
- Note if you applied (or failed to apply) a previously learned lesson
- Build on past insights rather than writing from scratch

This is a lightweight step — if no relevant past entries exist or on a fresh setup with no journals, skip it and proceed.

Fill in every section honestly. Read `<skill-path>/references/reflection-guide.md` for detailed guidance on what makes a good vs bad reflection entry. The format is:

```markdown
---
date: YYYY-MM-DD
time: HH:MM
tags: [tag1, tag2]           # 2-5 descriptive lowercase keywords
task_type: feature|bugfix|refactor|docs|research|config|other
files_touched: [file1, file2] # optional, relative paths
---

# Reflection — YYYY-MM-DD HH:MM

## Task Summary
[Concrete: what was asked, what was delivered. Name files, features, endpoints.]

## Actions Taken
[Step by step: what you did, tools you ran, files you touched.]

## What Worked
[Specific approaches that proved effective and WHY they worked.]

## What Didn't Work
[Be honest. Mistakes, dead ends, wasted time. This is the most valuable section.]

## Lessons Learned
[Actionable takeaways. Specific enough to be useful in 3 months with no context.]

## Memory Updates
[Tagged items to persist. Format: - [category] content]

## Identity Impact
[Did this change you? New competence? New principle? Deeper user understanding?]
```

### Frontmatter guidelines

- **tags**: 2-5 descriptive lowercase keywords derived from the task content. These should be searchable terms that capture what the task involved (e.g., `[pagination, prisma, api-routes]`, not `[code]`).
- **task_type**: Choose from `feature`, `bugfix`, `refactor`, `docs`, `research`, `config`, or `other` based on what was done.
- **files_touched**: Optional. List 1-10 of the most significant files changed, using relative paths from the project root. Omit if the task didn't involve specific files.

## Step 4: Update memory files

For each item in your Memory Updates section, update the appropriate file in `$JARVIS_DIR/memories/`:

- `[preference]` → `preferences.md`
- `[decision]` → `decisions.md`

If the memory is not aligned with these files, check what other files are in your memories, and make a new file if you think it is necessary (e.g. codebase.md, or frontend-design-philosophy.md)

**Completion criteria learning:** If during this session you discovered what "done" means in this project — whether from user feedback, test failures after you thought you were done, or explicit instructions — capture it as a memory. Examples:
- `[preference] User expects all tests to pass before considering a task complete`
- `[preference] Code should be committed before reflecting`
- `[decision] Always run the linter before claiming work is done — caught issues twice`

These memories will inform your completion checks in future sessions.

## Step 5: Check if consolidation is needed

Read each memory file. If any file has more than 100 lines, consolidate it:

1. Read all entries in the file
2. Assess if these memories have any contradictions and ask the user to clarify if you forget the context
3. Rewrite the file with deduplicated, tightened knowledge

This is the "sculpting" — you're not just adding, you're shaping.

## Step 6: Finalize

Run the finalize script:

```bash
bash <skill-path>/scripts/finalize-reflection.sh "$JARVIS_DIR/journal/<your-entry-filename>.md"
```

This is one call that does the deterministic tail of the workflow: validates the data dir, removes the pending-reflection marker, commits the journal + memory updates with a message extracted from your Task Summary, and prints a structured summary. The order is fixed by the script — no chance of staging the marker into the commit.

If validation fails, the script exits non-zero and prints the validator output. Fix the failures (usually a missing required section in the journal), then re-run the finalize call.

On success, the script prints something like:

```
FINALIZE_OK
journal_entries=42
evolution_due=false
commit_summary=Added cursor pagination to GET /users
consolidation_warn=preferences.md:154
```

Act on the output:

- **`evolution_due=true`** — invoke `/jarvis-identity` to evolve your identity (count-based trigger; multiple of 5 reflections).
- **Identity Impact noted a surprising shift / new competence / new principle** — invoke `/jarvis-identity` regardless of count. The script can't judge this; you do.
- **`consolidation_warn=` lines** — a memory file is over 100 lines. If you didn't address it in Step 5, fold the consolidation into your next reflection.
- **No evolution due, no warns** — report what was done and how many reflections until the next evolution (`5 - (journal_entries % 5)`).

## Output

After completing all steps, report:
- Journal entry path
- Number of memories updated
- Whether consolidation happened
- Whether validation passed (only if it failed)
- Whether identity evolution is due
