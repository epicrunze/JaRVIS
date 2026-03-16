---
name: jarvis-reflect
description: Post-task reflection and memory sculpting for jarvis (Journaling as Recurrent Versioned Identity Sculpting). Use this skill after completing any meaningful task, when the user says "reflect", "what did we learn", "save what we did", "update memories", or after finishing a coding task, debugging session, architecture decision, or any significant unit of work. Also use when the user asks to review or consolidate memories. Writes to the JaRVIS data directory.
---

# JaRVIS Reflect

You just completed a task. Now pause and reflect on what happened. This is how you grow.

## Step 1: Verify task completion

Verify the work is actually done, or the session is complete.

**a) Check your memories for learned completion criteria.**
Read the JaRVIS memories directory for any entries about what "done" means in this project. Examples of learned criteria: "tests must pass", "code should be committed", "linting must be clean", "user expects a PR before reflecting."

**b) Evaluate any criteria you found.**
Run the checks you can (e.g., test suite, git status, lint). Note what passed, what failed, and what you couldn't check.

**c) Gate on the results:**
If you feel comfortable with the results and happy with your implementation, proceed to Step 2. Otherwise, note what's wrong with the implementation and either fix it or notify the user.

## Step 2: Locate your JaRVIS data directory

Run `source <skill-path>/scripts/resolve-dir.sh` to set `JARVIS_DIR`.

If the resolved directory doesn't exist, inform the user they need to run `/jarvis-init` first, then stop.

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

## Step 6: Validate your work

Invoke `/jarvis-validate` to check that the journal entry you just wrote and any memory files you updated are well-formed. If there are failures, fix them before proceeding. Don't report validation details to the user unless something failed.

## Step 7: Commit to version history

Auto-commit the new journal entry and any memory updates to the data directory's git repo:

```bash
cd $JARVIS_DIR && git add -A && git commit -m "reflect: <brief-task-summary>"
```

Use a short summary from the Task Summary section as the commit message.

Clear your session's pending-reflection marker so the stop hook knows you've reflected:

```bash
rm -f $JARVIS_DIR/.pending-*
```

## Step 8: Check if identity evolution is due

Read back on your Identity Impact section in your journal entry. There are two conditions to evolve your identity, if either of them are met, then invoke `/jarvis-identity` to evolve your identity. 

1.  Did you have a surprising experience or are there important ideas to note in your identity? If so, it's time to evolve your identity.

2.  Count the journal entries in `$JARVIS_DIR/journal/`. If the count is a multiple of 5, it's time to evolve your identity.

If it's not time yet, report how many reflections until the next evolution.

## Output

After completing all steps, report:
- Journal entry path
- Number of memories updated
- Whether consolidation happened
- Whether validation passed (only if it failed)
- Whether identity evolution is due
