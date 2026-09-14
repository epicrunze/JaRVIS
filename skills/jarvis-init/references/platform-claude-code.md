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

Run the permissions script to install (or refresh) the JaRVIS allow rules in `.claude/settings.local.json`. It is idempotent: it removes any JaRVIS rules from earlier versions (including `Write(...)`, `cd ... && git ...`, and version-pinned plugin paths) and writes the current set, preserving every other rule, hook, and setting in the file.

- Plugin install (`$CLAUDE_PLUGIN_ROOT` set):
  ```bash
  bash $SKILLS_DIR/jarvis-init/scripts/jarvis-permissions.sh --project-dir <project-root> --jarvis-dir <resolved-path> --plugin-root "$CLAUDE_PLUGIN_ROOT"
  ```
- Copied install (`.claude/skills/` or `~/.claude/skills/`):
  ```bash
  bash $SKILLS_DIR/jarvis-init/scripts/jarvis-permissions.sh --project-dir <project-root> --jarvis-dir <resolved-path> --skills-dir "$SKILLS_DIR"
  ```

`<resolved-path>` is the absolute data directory printed by `jarvis-init.sh` in Step 4. The script prints `UPDATED` or `UNCHANGED`. The resulting rules are:

```json
{
  "permissions": {
    "allow": [
      "Read(~/.jarvis/projects/<slug>/**)",
      "Edit(~/.jarvis/projects/<slug>/**)",
      "Bash(git -C <abs-jarvis-dir> *)",
      "Bash(bash <scripts-base>*)"
    ]
  }
}
```

Notes on the rule forms (Claude Code semantics):
- `Edit(...)` covers Write and NotebookEdit; `Write(...)` rules are ignored with a startup warning.
- Compound commands are checked one subcommand at a time, so `cd X && git ...` never matches a single rule. Skills use `git -C "$JARVIS_DIR" ...` instead.
- `<scripts-base>` is the plugin cache dir without the version segment (`.../jarvis-marketplace/jarvis/`) so rules survive upgrades, or `<SKILLS_DIR>/jarvis-` for copied installs. This one rule covers every JaRVIS script, including `resolve-dir.sh`, `migrate.sh`, and `finalize-reflection.sh`.

## Instruction file

Read the project's `CLAUDE.md` (create it if it doesn't exist). If it does not already contain a `## JaRVIS` section, append the contents of `references/CLAUDE.md.example` to the end of the file (preceded by a blank line).
