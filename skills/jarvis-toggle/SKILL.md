---
name: jarvis-toggle
description: Enable or disable JaRVIS for the current project. Use when you want to turn jarvis on or off, pause jarvis, disable jarvis hooks, or stop jarvis from loading.
---

# JaRVIS Toggle

Enable or disable JaRVIS for the current project. This toggles both the hook system
and the JaRVIS instructions in your project's agent configuration file.

## Step 1: Resolve JaRVIS data directory

Run `JARVIS_DIR=$(bash <skill-path>/scripts/resolve-dir.sh)` to set `JARVIS_DIR`.

If the resolved directory doesn't exist, inform the user they need to run `/jarvis-init` first, then stop.

## Step 2: Detect platform and instruction file

Look for the project's agent instruction file. Check in order:

| File | Platform |
|------|----------|
| `CLAUDE.md` | Claude Code |
| `.cursorrules` | Cursor |
| `.github/copilot-instructions.md` | GitHub Copilot |
| `AGENTS.md` | Antigravity |

Use the first one found. If multiple exist, operate on all of them.

## Step 3: Toggle state

Check if `$JARVIS_DIR/.jarvis-disabled` exists:

### Disabling (marker does NOT exist → create it)

1. For each detected instruction file, find the `## JaRVIS` section (from the heading
   to the next `## ` heading or end of file).
2. Store the removed content in `$JARVIS_DIR/.jarvis-disabled` as a JSON object:
   ```json
   {
     "files": {
       "CLAUDE.md": "## JaRVIS\n\nUse `/jarvis-reload`...",
       ".cursorrules": "## JaRVIS\n\nIdentity and memories..."
     }
   }
   ```
3. Remove the `## JaRVIS` section from each instruction file.

### Enabling (marker EXISTS → remove it)

1. Read `$JARVIS_DIR/.jarvis-disabled` to get the backed-up sections.
2. For each file in the backup, append the stored JaRVIS section back to the file.
3. Delete `$JARVIS_DIR/.jarvis-disabled`.

If the backup file is missing or corrupted, fall back to the example snippets from
`skills/jarvis-init/references/` (CLAUDE.md.example, cursorrules.example, etc.)
to regenerate the section.

## Step 4: Report status

Tell the user the new state:

- If now **enabled**: "JaRVIS is now enabled for this project. The `## JaRVIS` section
  has been restored to `<files>`. Hooks will run on next session start."
- If now **disabled**: "JaRVIS is now disabled for this project. The `## JaRVIS` section
  has been removed from `<files>`. Hooks will be skipped until you run `/jarvis-toggle` again."

Also note: "You can also set `JARVIS_DISABLE=true` in your environment to temporarily
disable JaRVIS for a single session without changing the persistent setting."
