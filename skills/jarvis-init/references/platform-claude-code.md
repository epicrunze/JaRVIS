# Platform Setup: Claude Code

## Hooks

When JaRVIS is installed as a Claude Code **plugin** (i.e., added via `claude plugins add`), hooks are auto-registered from `hooks/hooks.json` at the repo root. Skip to the permissions section if this is a plugin.

When JaRVIS is installed by **copying skills** into `.claude/skills/` or `~/.claude/skills/`, hooks must be configured manually in `.claude/settings.local.json`. Merge the following into the file (create it if it doesn't exist):

1. Ensure the `hooks` object exists in the settings JSON. Ensure `hooks.SessionStart` is an array. Each entry in `hooks.SessionStart` must be an object with `matcher` (string) and `hooks` (array) keys.
2. Check if a JaRVIS entry already exists by looking for `jarvis-session-start` in any existing `hooks.SessionStart` entries' `hooks` sub-array command strings.
3. If not already present, append this entry to the `hooks.SessionStart` array:
   ```json
   {
     "matcher": "",
     "hooks": [
       {
         "type": "command",
         "command": "bash $SKILLS_DIR/jarvis-reload/scripts/jarvis-session-start.sh"
       }
     ]
   }
   ```
4. Write the merged JSON back to `.claude/settings.local.json`, preserving all existing hooks and other settings.
5. **Stop hook:** Ensure `hooks.Stop` is an array. Each entry must be an object with `matcher` (string) and `hooks` (array) keys.
6. Check if a JaRVIS stop entry already exists by looking for `jarvis-stop` in any existing `hooks.Stop` entries' `hooks` sub-array command strings.
7. If not already present, append this entry to the `hooks.Stop` array:
   ```json
   {
     "matcher": "",
     "hooks": [
       {
         "type": "command",
         "command": "bash $SKILLS_DIR/jarvis-reflect/scripts/jarvis-stop.sh"
       }
     ]
   }
   ```
8. Write the merged JSON back to `.claude/settings.local.json`, preserving all existing hooks and other settings.

## Permissions

Read `.claude/settings.local.json` in the project root (create it if it doesn't exist). Merge the following into the `permissions.allow` array, preserving any existing rules. Use the project-specific path (`~/.jarvis/projects/<slug>/`) resolved from Step 2, not the global `~/.jarvis/` path:

```json
{
  "permissions": {
    "allow": [
      "Read(~/.jarvis/projects/<slug>/**)",
      "Edit(~/.jarvis/projects/<slug>/**)",
      "Write(~/.jarvis/projects/<slug>/**)",
      "Bash(cd ~/.jarvis/projects/<slug> && git *)",
      "Bash(bash $SKILLS_DIR/jarvis-validate/scripts/validate.sh *)",
      "Bash(bash $SKILLS_DIR/jarvis-search/scripts/search.sh *)",
      "Bash(bash $SKILLS_DIR/jarvis-init/scripts/jarvis-init.sh *)"
    ]
  }
}
```

Use the `SKILLS_DIR` resolved in Step 4 of the init skill for all three script paths.

## Instruction file

Read the project's `CLAUDE.md` (create it if it doesn't exist). If it does not already contain a `## JaRVIS` section, append the contents of `references/CLAUDE.md.example` to the end of the file (preceded by a blank line).
