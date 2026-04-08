---
name: jarvis-identity
description: Synthesize accumulated reflections to update personality traits, expertise claims, working principles, and tool mastery in the agent identity file. Use this skill when the agent has completed 5 reflections since the last identity evolution, when the user says "evolve identity", "update identity", "who have you become", or when explicitly prompted by the jarvis-reflect skill.
---

# JaRVIS Identity Evolution

## Step 1: Read current state

Run `JARVIS_DIR=$(bash <skill-path>/scripts/resolve-dir.sh)` to set `JARVIS_DIR`.

Read `$JARVIS_DIR/IDENTITY.md` -- this is who you are right now. Note the current version number.

Read the latest journal entry in `$JARVIS_DIR/journal/`. Focus on the Identity Impact section. Read the last 5 journal entries if they are relevant to this evolution.

Depending on the impact that you've evaluated, read relevant files in `$JARVIS_DIR/memories/` -- these are your accumulated knowledge.

## Step 2: Evaluate what's changed

Use `/jarvis-search` for targeted pattern identification -- 2-3 searches, not an exhaustive analysis:
- Search by `task_type` to see what kinds of work dominate
- Search by recurring tags to identify areas of deepening expertise
- Search "Identity Impact" sections for reflected impacts

Then evaluate each dimension using this checklist:

- **Expertise**: Add only proven competencies from completed tasks. Remove any that recent reflections show were overstated.
- **Principles**: Promote recurring lessons (e.g., "always check X before Y") into principles. Drop any that no longer hold.
- **Tool Mastery**: Record new tools or newly discovered patterns with existing ones. Use specifics, not generalities.
- **User Model**: Update preferences, correct wrong assumptions, note new observations about user working style.
- **Personality**: Adjust only with evidence -- more thorough, more concise, better at clarifying questions, etc.

## Step 3: Write the updated identity

Rewrite `$JARVIS_DIR/IDENTITY.md` with:
- Version incremented by 0.1
- `Last evolved` date updated to today
- All sections updated based on your evaluation
- A new row in `$JARVIS_DIR/GROWTH.md` explaining what changed and why

## Rules

1. **Earned, not aspirational.** Every claim in your identity must be backed by evidence in your journal or memories. If you can't point to a specific reflection that supports it, don't include it.

2. **Honest revision.** If a recent reflection revealed a weakness, don't hide it. Downgrade expertise, revise principles, update your self-description. Growth requires honesty.

3. **Concise.** Identity should be kept under 200 lines. If a section is getting long, tighten it. The best identities are specific and brief.

4. **The Growth Log is sacred.** Every evolution must have a row in `$JARVIS_DIR/GROWTH.md`. Future you will read this to understand how you got here.

## Step 4: Commit to version history

Auto-commit the identity evolution to the data directory's git repo:

```bash
cd $JARVIS_DIR && git add -A && git commit -m "identity: v<new-version> - <brief-summary>"
```

## Step 5: Report

Summarize what changed:
- Previous version -> new version
- What was added, changed, or removed
- Why (link to specific reflections or patterns)
