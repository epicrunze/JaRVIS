---
name: jarvis-init
description: Initialize the .jarvis/ directory structure in a project. Use this skill when setting up jarvis for the first time, when the user says "init jarvis", "set up jarvis", "initialize jarvis", or when /jarvis-start detects no .jarvis/ directory exists.
---

# JaRVIS Init

Scaffold the `.jarvis/` directory so the agent has a place to store its identity, memories, and journal.

## Step 1: Check if already initialized

Look for `.jarvis/` in the project root. If it already exists, inform the user that jarvis is already set up and suggest running `/jarvis-start` to begin a session.

## Step 2: Create the directory structure

Create the full `.jarvis/` scaffold:

```
.jarvis/
├── IDENTITY.md
├── GROWTH.md
├── memories/
│   ├── preferences.md
│   └── decisions.md
└── journal/
```

Use the scaffolding templates in `references/scaffolding.md` for initial file contents.

## Step 3: Update .gitignore if needed

Check if the project has a `.gitignore`. If it does, ask the user if they would like `.jarvis/` to not be ignored — these files are meant to be version-controlled.

## Step 4: Report

Confirm the setup is complete and suggest next steps:

> "jarvis is initialized. Your agent identity and memory files are in `.jarvis/`. Run `/jarvis-start` to begin your first session, then `/jarvis-reflect` after completing tasks to start building your identity."
