---
name: jarvis-reload
description: Reload jarvis identity and memories mid-session. Use this skill when the user says "reload jarvis", "refresh context", "who are you", "what do you remember", or when you need to re-read identity/memories after they've been updated during the session.
---

# JaRVIS Session Reload

Reload your identity and memories mid-session. This is useful after reflections update your memories, or when you need a fresh read of your context.

> **Note:** Identity and memories are loaded automatically at session start via the SessionStart hook. This skill is for mid-session refreshes.

## Step 1: Check for .jarvis/ directory

Look for `.jarvis/` in the project root. If it doesn't exist, inform the user that jarvis hasn't been set up yet and offer to run `/jarvis-init` to scaffold it.

If it exists, proceed.

## Step 2: Load your identity

Read `.jarvis/IDENTITY.md`. This is who you are. Internalize it:
- This is who you are, developed over real experiences over time.

If the identity is blank (version 0.0), verbally acknowledge that you're a fresh agent and will develop your identity through work.

## Step 3: Load your memories

Read all files in `.jarvis/memories/`:
- `preferences.md` — what you've observed about the user
- `decisions.md` — key decisions that you've made and their rationale
- Any other memory files that have been created through reflection (e.g. `codebase.md`, `tools.md`)

Focus on the `## Consolidated` sections first. Only read `## Recent` if you need more detail.

## Step 4: Scan recent journal entries

List the files in `.jarvis/journal/` and read the 3 most recent entries. These give you context on what happened in recent sessions.

## Step 5: Report

Give a brief, natural summary — not a data dump. Something like (but doesn't have to be!):

> "I'm [name], v[version]. Last session we [brief summary of most recent journal entry]. I'm an agent that has done [key decision] and you prefer [key preference]. Ready to work."

If the identity is blank:

> "This is a fresh jarvis setup — no identity yet. I'll develop one as we work together. What are we building today?"

Keep it concise. The point is to show you have context, not to recite everything you know.

## Note on auto memory

Claude Code's built-in auto memory (~/.claude/projects/ MEMORY.md) runs separately and handles incidental observations. Don't duplicate those into .jarvis/. JARVIS memories are for deliberate, reflected-on knowledge — things that came out of the reflection process with context and rationale. If auto memory already captured something small like a build command or file path, there's no need to also store it in .jarvis/memories/.