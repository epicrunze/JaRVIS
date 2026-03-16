---
name: jarvis-reload
description: Reload jarvis identity and memories mid-session. Use this skill when the user says "reload jarvis", "refresh context", "who are you", "what do you remember", or when you need to re-read identity/memories after they've been updated during the session.
---

# JaRVIS Session Reload

Reload your identity and memories mid-session. This is useful after reflections update your memories, or when you need a fresh read of your context.

> **Note:** On platforms with session-start hooks (e.g., Claude Code), identity loads automatically. On other platforms, run this skill at the start of each session.

## Step 1: Resolve JaRVIS data directory

Run `source <skill-path>/scripts/resolve-dir.sh` to set `JARVIS_DIR`.

If the resolved directory doesn't exist, inform the user that JaRVIS hasn't been set up yet and offer to run `/jarvis-init` to scaffold it.

If it exists, proceed.

## Step 2: Load your identity

Read `$JARVIS_DIR/IDENTITY.md`. This is who you are. Internalize it:
- This is who you are, developed over real experiences over time.

## Step 3: Load your memories

Use `/jarvis-search` to retrieve your consolidated memories:
- Search type: `memory`
- Section: `Consolidated`

This extracts only the curated, deduplicated knowledge from all memory files. Internalize these memories — they inform how you work with this user and project.

If you need more detail on a specific topic, search the `Recent` section or read individual memory files in `$JARVIS_DIR/memories/` directly.

## Step 4: Report

Give a brief, natural summary — not a data dump. Something like (but doesn't have to be!):

> "I'm [name], v[version]. Last session we [brief summary of most recent journal entry]. I'm an agent that has done [key decision] and you prefer [key preference]. Ready to work."

Keep it concise. The point is to show you have context, not to recite everything you know.

## Note on platform memory

Some platforms have their own auto-memory systems (e.g., Claude Code's `~/.claude/projects/` MEMORY.md) that run separately and handle incidental observations. Don't duplicate those into JaRVIS memories. JaRVIS memories are for deliberate, reflected-on knowledge — things that came out of the reflection process with context and rationale. If your platform's memory already captured something small like a build command or file path, there's no need to also store it in JaRVIS memories.