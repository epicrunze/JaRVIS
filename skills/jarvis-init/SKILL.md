---
name: jarvis-init
description: Initialize the ~/.jarvis/ directory structure for a project. Use this skill when setting up jarvis for the first time, when the user says "init jarvis", "set up jarvis", "initialize jarvis", or when /jarvis-reload detects no JaRVIS data directory exists.
---

# JaRVIS Init

Scaffold the JaRVIS data directory so the agent has a place to store its identity, memories, and journal.

## Step 1: Migration check

If `.jarvis/` exists in the project root, this project used the old per-project storage layout. Offer to migrate:

1. Tell the user: "Found existing `.jarvis/` in the project root. Would you like to migrate it to the new home-directory location?"
2. If the user agrees, note `--migrate` for the next step.
3. If the user declines, proceed without `--migrate` (the old directory is left untouched).

If no `.jarvis/` exists in the project root, skip this step.

## Step 2: Detect platform

Determine which AI coding agent platform is running. Check for these signals in order:

| Signal | Platform |
|--------|----------|
| `CLAUDE_PROJECT_DIR` env var or `.claude/` directory exists | **Claude Code** |
| `.cursor/` directory exists | **Cursor** |
| `.github/` directory with copilot config exists | **GitHub Copilot** |
| `opencode.json` or `.opencode/` directory exists | **OpenCode** |
| `.agent/` directory or `AGENTS.md` exists | **Antigravity** |

If multiple signals are detected, ask the user which platform they're using (include "Other" as an option).

If no signals are detected, ask the user to choose from: Claude Code, Cursor, GitHub Copilot, Antigravity, or Other.

## Step 3: Configure platform

First, determine the skills base directory (`SKILLS_DIR`) for the detected platform:

| Platform | Local (project) | Global (user home) | Plugin |
|----------|------------------|--------------------|--------|
| Claude Code | `.claude/skills` | `~/.claude/skills` | `$CLAUDE_PLUGIN_ROOT/skills` (if installed as plugin) |
| Cursor | `.cursor/skills` | `~/.cursor/skills` | — |
| GitHub Copilot | `.github/skills` | `~/.github/skills` | — |
| OpenCode | `.opencode/skills` | `~/.config/opencode/skills` | — |
| Antigravity | `.agent/skills` | `~/.agent/skills` | — |

For Claude Code: if `$CLAUDE_PLUGIN_ROOT` is set and `$CLAUDE_PLUGIN_ROOT/skills/jarvis-reload/` exists, JaRVIS is installed as a plugin — use `$CLAUDE_PLUGIN_ROOT/skills`. Otherwise check local then global.
For other platforms: check if the local path contains JaRVIS skills (e.g., `<local-path>/jarvis-reload/` exists). If so, use the local path. Otherwise use the global path.
Call the result `SKILLS_DIR`.

## Step 4: Scaffold data directory

Run the init script to resolve the path, scaffold the directory, and create a git repo:

```bash
bash $SKILLS_DIR/scripts/jarvis-init.sh [--migrate] [--project-dir <path>]
```

- Pass `--migrate` if the user agreed to migrate in Step 1.
- Pass `--project-dir <path>` if the project root differs from `CLAUDE_PROJECT_DIR` / `pwd`.

The script prints `ALREADY_EXISTS` followed by the path if already initialized — inform the user and suggest `/jarvis-reload`.
Otherwise it prints `MIGRATED` (if migration happened) followed by the resolved path.
After successful migration, suggest the user remove the old `.jarvis/` directory at their convenience.

Then read and follow the corresponding setup guide:

| Platform | Reference |
|----------|-----------|
| Claude Code | `references/platform-claude-code.md` |
| Cursor | `references/platform-cursor.md` |
| GitHub Copilot | `references/platform-copilot.md` |
| OpenCode | `references/platform-opencode.md` |
| Antigravity | `references/platform-antigravity.md` |
| Other | `references/platform-other.md` |

Read the reference document for the detected platform and execute all steps within it.
Use `<slug>` from Step 2 and `SKILLS_DIR` wherever the guide references them.

## Step 5: Report

Confirm the setup is complete:

> "JaRVIS is initialized. Your agent data is stored at `<resolved-path>` with its own git history. Run `/jarvis-reload` to begin your first session, then `/jarvis-reflect` after completing tasks to start building your identity."
