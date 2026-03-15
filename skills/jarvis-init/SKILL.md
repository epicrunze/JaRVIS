---
name: jarvis-init
description: Initialize the .jarvis/ directory structure in a project. Use this skill when setting up jarvis for the first time, when the user says "init jarvis", "set up jarvis", "initialize jarvis", or when /jarvis-reload detects no .jarvis/ directory exists.
---

# JaRVIS Init

Scaffold the `.jarvis/` directory so the agent has a place to store its identity, memories, and journal.

## Step 1: Check if already initialized

Look for `.jarvis/` in the project root. If it already exists, inform the user that jarvis is already set up and suggest running `/jarvis-reload` to begin a session.

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

## Step 3: Detect platform

Determine which AI coding agent platform is running. Check for these signals in order:

| Signal | Platform |
|--------|----------|
| `CLAUDE_PROJECT_DIR` env var or `.claude/` directory exists | **Claude Code** |
| `.cursor/` directory exists | **Cursor** |
| `.github/` directory with copilot config exists | **GitHub Copilot** |
| `.agent/` directory or `AGENTS.md` exists | **Antigravity** |

If multiple signals are detected, ask the user which platform they're using.

If no signals are detected, ask the user to choose from: Claude Code, Cursor, GitHub Copilot, or Antigravity.

## Step 4: Configure platform

Based on the detected platform, perform the platform-specific setup:

### If Claude Code:

**Permissions:** Read `.claude/settings.json` in the project root (create it if it doesn't exist). Merge the following into the `permissions.allow` array, preserving any existing rules:

```json
{
  "permissions": {
    "allow": [
      "Read(.jarvis/**)",
      "Read(~/.claude/plugins/cache/**)"
    ]
  }
}
```

**Instruction file:** Read the project's `CLAUDE.md` (create it if it doesn't exist). If it does not already contain a `## JaRVIS` section, append the following to the end of the file:

```markdown

## JaRVIS

Identity and memories are loaded automatically at session start via the SessionStart hook.
Use `/jarvis-reload` to reload context mid-session if needed.
After completing any meaningful task, run `/jarvis-reflect` to capture what you learned.

### Hook Installation

Add the following to your project's `.claude/settings.json`:

\```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "bash .claude/skills/jarvis-reload/hooks/jarvis-session-start.sh"
      }
    ]
  }
}
\```

If you installed JaRVIS globally (`~/.claude/skills/`), use the global path instead:

\```json
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "bash ~/.claude/skills/jarvis-reload/hooks/jarvis-session-start.sh"
      }
    ]
  }
}
\```
```

### If Cursor:

**Instruction file:** Read the project's `.cursorrules` (create it if it doesn't exist). If it does not already contain a `## JaRVIS` section, append the following:

```markdown

## JaRVIS

Run `/jarvis-reload` at the start of each session to load your identity and memories.
Use `/jarvis-reload` to reload context mid-session if needed.
After completing any meaningful task, run `/jarvis-reflect` to capture what you learned.
```

### If GitHub Copilot:

**Instruction file:** Read the project's `.github/copilot-instructions.md` (create the `.github/` directory and file if they don't exist). If it does not already contain a `## JaRVIS` section, append the following:

```markdown

## JaRVIS

Run `/jarvis-reload` at the start of each session to load your identity and memories.
Use `/jarvis-reload` to reload context mid-session if needed.
After completing any meaningful task, run `/jarvis-reflect` to capture what you learned.
```

### If Antigravity:

**Instruction file:** Read the project's `AGENTS.md` (create it if it doesn't exist). If it does not already contain a `## JaRVIS` section, append the following:

```markdown

## JaRVIS

Run `/jarvis-reload` at the start of each session to load your identity and memories.
Use `/jarvis-reload` to reload context mid-session if needed.
After completing any meaningful task, run `/jarvis-reflect` to capture what you learned.
```

If the JaRVIS section already exists in the instruction file, skip this step.

## Step 5: Update .gitignore if needed

Check if the project has a `.gitignore`. If it does, ask the user if they would like `.jarvis/` to not be ignored — these files are meant to be version-controlled.

## Step 6: Report

Confirm the setup is complete and suggest next steps:

> "jarvis is initialized. Your agent identity and memory files are in `.jarvis/`. Run `/jarvis-reload` to begin your first session, then `/jarvis-reflect` after completing tasks to start building your identity."
