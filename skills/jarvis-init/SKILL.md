---
name: jarvis-init
description: Initialize the ~/.jarvis/ directory structure for a project. Use this skill when setting up jarvis for the first time, when the user says "init jarvis", "set up jarvis", "initialize jarvis", or when /jarvis-reload detects no JaRVIS data directory exists.
---

# JaRVIS Init

Scaffold the JaRVIS data directory so the agent has a place to store its identity, memories, and journal.

## Step 1: Resolve data directory

Derive the JaRVIS data path:

1. If `JARVIS_DIR` env var is set, use it.
2. Otherwise, slugify the current project path: strip leading `/`, replace `/` and spaces with `-`, lowercase. The data dir is `~/.jarvis/projects/<slug>/`.

If the resolved directory already exists, inform the user that JaRVIS is already set up and suggest running `/jarvis-reload` to begin a session.

## Step 2: Migration check

If `.jarvis/` exists in the project root, this project used the old per-project storage layout. Offer to migrate:

1. Tell the user: "Found existing `.jarvis/` in the project root. Would you like to migrate it to the new home-directory location (`<resolved-path>`)?"
2. If the user agrees, copy the contents: `cp -r .jarvis/* <resolved-path>/`
3. After successful copy, suggest the user remove the old `.jarvis/` directory at their convenience.
4. If the user declines, proceed with a fresh scaffold (the old directory is left untouched).

If no `.jarvis/` exists in the project root, skip this step.

## Step 3: Create the directory structure

Create the full scaffold at the resolved data directory:

```
~/.jarvis/projects/<slug>/
├── IDENTITY.md
├── GROWTH.md
├── memories/
│   ├── preferences.md
│   └── decisions.md
└── journal/
```

Use `mkdir -p` to create the directory tree. Use the scaffolding templates in `references/scaffolding.md` for initial file contents.

## Step 4: Initialize version control

Run `git init` inside the data directory and create an initial commit:

```bash
cd <data-dir> && git init && git add -A && git commit -m "jarvis: initial scaffold"
```

This gives the agent's growth its own version history, independent of the project repo.

## Step 5: Detect platform

Determine which AI coding agent platform is running. Check for these signals in order:

| Signal | Platform |
|--------|----------|
| `CLAUDE_PROJECT_DIR` env var or `.claude/` directory exists | **Claude Code** |
| `.cursor/` directory exists | **Cursor** |
| `.github/` directory with copilot config exists | **GitHub Copilot** |
| `.agent/` directory or `AGENTS.md` exists | **Antigravity** |

If multiple signals are detected, ask the user which platform they're using.

If no signals are detected, ask the user to choose from: Claude Code, Cursor, GitHub Copilot, or Antigravity.

## Step 6: Configure platform

Based on the detected platform, perform the platform-specific setup:

### If Claude Code:

**Permissions:** Read `.claude/settings.json` in the project root (create it if it doesn't exist). Merge the following into the `permissions.allow` array, preserving any existing rules:

```json
{
  "permissions": {
    "allow": [
      "Read(~/.jarvis/**)"
    ]
  }
}
```

**Hooks:** Merge the JaRVIS SessionStart hook into `.claude/settings.json` (the same file from the permissions step):

1. Determine the hook script path: if `.claude/skills/jarvis-reload/hooks/jarvis-session-start.sh` exists in the project root, use that relative path. Otherwise use `~/.claude/skills/jarvis-reload/hooks/jarvis-session-start.sh` (global install).
2. Ensure the `hooks` object exists in the settings JSON. Ensure `hooks.SessionStart` is an array. Each entry in `hooks.SessionStart` must be an object with `matcher` (string) and `hooks` (array) keys.
3. Check if a JaRVIS entry already exists by looking for `jarvis-session-start` in any existing `hooks.SessionStart` entries' `hooks` sub-array command strings.
4. If not already present, append this entry to the `hooks.SessionStart` array:
   ```json
   {
     "matcher": "",
     "hooks": [
       {
         "type": "command",
         "command": "bash <detected-path>"
       }
     ]
   }
   ```
5. Write the merged JSON back to `.claude/settings.json`, preserving all existing hooks and other settings.
6. **Stop hook:** Determine the stop hook script path: if `.claude/skills/jarvis-reflect/hooks/jarvis-stop.sh` exists in the project root, use that relative path. Otherwise use `~/.claude/skills/jarvis-reflect/hooks/jarvis-stop.sh` (global install).
7. Ensure `hooks.Stop` is an array. Each entry must be an object with `matcher` (string) and `hooks` (array) keys.
8. Check if a JaRVIS stop entry already exists by looking for `jarvis-stop` in any existing `hooks.Stop` entries' `hooks` sub-array command strings.
9. If not already present, append this entry to the `hooks.Stop` array:
   ```json
   {
     "matcher": "",
     "hooks": [
       {
         "type": "command",
         "command": "bash <detected-path>"
       }
     ]
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

## Step 7: Report

Confirm the setup is complete:

> "JaRVIS is initialized. Your agent data is stored at `<resolved-path>` with its own git history. Run `/jarvis-reload` to begin your first session, then `/jarvis-reflect` after completing tasks to start building your identity."
