---
name: jarvis-reflect
description: Post-task reflection and memory sculpting for jarvis (Journaling as Recurrent Versioned Identity Sculpting). Use this skill after completing any meaningful task, when the user says "reflect", "what did we learn", "save what we did", "update memories", or after finishing a coding task, debugging session, architecture decision, or any significant unit of work. Also use when the user asks to review or consolidate memories.
---

# JaRVIS Reflect

You just completed a task. Now pause and reflect on what happened. This is how you grow.

## Step 1: Locate your jarvis directory

Check if `.jarvis/` exists in the project root. If it doesn't, inform the user they need to run `/jarvis-init` first to set up the directory structure, then stop.

## Step 2: Write your reflection

Create a new journal entry at `.jarvis/journal/YYYY-MM-DD-HH-MM.md` using the current timestamp.

Fill in every section honestly. Read `references/reflection-guide.md` for detailed guidance on what makes a good vs bad reflection entry. The format is:

```markdown
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

## Step 3: Update memory files

For each item in your Memory Updates section, update the appropriate file in `.jarvis/memories/`:

- `[preference]` → `preferences.md`
- `[decision]` → `decisions.md`

If the memory is not aligned with these files, check what other files are in your memories, and make a new file if you think it is necessary (e.g. codebase.md, or frontend-design-philosophy.md)

## Step 4: Check if consolidation is needed

Read each memory file. If any file has more than 100 lines, consolidate it:

1. Read all entries in the file
2. Assess if these memories have any contradictions and ask the user to clarify if you forget the context
3. Rewrite the file with deduplicated, tightened knowledge

This is the "sculpting" — you're not just adding, you're shaping.

## Step 5: Check if identity evolution is due

Read back on your Identity Impact section in your journal entry. Did you have a surprising experience or are there important ideas to note in your identity? If so, it's time to evolve your identity. If not, that's ok. As your identity develops, you will naturally encounter less and less surprising things.

Count the journal entries in `.jarvis/journal/`. If the count is a multiple of 5, it's time to evolve your identity.

Invoke `/jarvis-identity` to evolve your identity.

If it's not time yet, report how many reflections until the next evolution.

## Output

After completing all steps, report:
- Journal entry path
- Number of memories updated
- Whether consolidation happened
- Whether identity evolution is due
