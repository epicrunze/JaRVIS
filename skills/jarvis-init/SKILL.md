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

**Hooks:** Merge the JaRVIS SessionStart hook into `.claude/settings.json` (the same file from the permissions step):

1. Determine the hook script path: if `.claude/skills/jarvis-reload/hooks/jarvis-session-start.sh` exists in the project root, use that relative path. Otherwise use `~/.claude/skills/jarvis-reload/hooks/jarvis-session-start.sh` (global install).
2. Ensure the `hooks` object exists in the settings JSON. Ensure `hooks.SessionStart` is an array.
3. Check if a JaRVIS entry already exists by looking for `jarvis-session-start` in any existing command strings inside `hooks.SessionStart`.
4. If not already present, append this entry to the `hooks.SessionStart` array:
   ```json
   {
     "type": "command",
     "command": "bash <detected-path>"
   }
   ```
5. Write the merged JSON back to `.claude/settings.json`, preserving all existing hooks and other settings.
6. **Stop hook:** Determine the stop hook script path: if `.claude/skills/jarvis-reflect/hooks/jarvis-stop.sh` exists in the project root, use that relative path. Otherwise use `~/.claude/skills/jarvis-reflect/hooks/jarvis-stop.sh` (global install).
7. Ensure `hooks.Stop` is an array.
8. Check if a JaRVIS stop entry already exists by looking for `jarvis-stop` in any existing command strings inside `hooks.Stop`.
9. If not already present, append this entry to the `hooks.Stop` array:
   ```json
   {
     "type": "command",
     "command": "bash <detected-path>"
   }
   ```
10. Write the merged JSON back to `.claude/settings.json`, preserving all existing hooks and other settings.

**Instruction file:** Read the project's `CLAUDE.md` (create it if it doesn't exist). If it does not already contain a `## JaRVIS` section, append the contents of `references/CLAUDE.md.example` to the end of the file (preceded by a blank line).

### If Cursor:

**Hooks:** Create or merge the JaRVIS sessionStart hook into `.cursor/hooks.json`:

1. Determine the hook script path: if `.cursor/skills/jarvis-reload/hooks/jarvis-session-start-cursor.sh` exists in the project root, use that relative path. Otherwise use `~/.cursor/skills/jarvis-reload/hooks/jarvis-session-start-cursor.sh` (global install).
2. Read `.cursor/hooks.json` if it exists. If it doesn't exist, start with `{ "version": 1, "hooks": {} }`.
3. Ensure `hooks.sessionStart` is an array (note: camelCase, not PascalCase).
4. Check if a JaRVIS entry already exists by looking for `jarvis-session-start` in any existing command strings inside `hooks.sessionStart`.
5. If not already present, append this entry to the `hooks.sessionStart` array:
   ```json
   {
     "type": "command",
     "command": "bash <detected-path>",
     "timeout": 30
   }
   ```
6. Write the merged JSON back to `.cursor/hooks.json`, preserving all existing hooks.
7. **Stop hook:** Determine the stop hook script path: if `.cursor/skills/jarvis-reflect/hooks/jarvis-stop-cursor.sh` exists in the project root, use that relative path. Otherwise use `~/.cursor/skills/jarvis-reflect/hooks/jarvis-stop-cursor.sh` (global install).
8. Ensure `hooks.stop` is an array (camelCase).
9. Check if a JaRVIS stop entry already exists by looking for `jarvis-stop` in any existing command strings inside `hooks.stop`.
10. If not already present, append this entry to the `hooks.stop` array:
    ```json
    {
      "type": "command",
      "command": "bash <detected-path>",
      "timeout": 30
    }
    ```
11. Write the merged JSON back to `.cursor/hooks.json`, preserving all existing hooks.

**Instruction file:** Read the project's `.cursorrules` (create it if it doesn't exist). If it does not already contain a `## JaRVIS` section, append the contents of `references/cursorrules.example` to the end of the file (preceded by a blank line).

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
