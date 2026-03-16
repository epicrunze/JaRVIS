# Platform Setup: Cursor

## Hooks

Create or merge the JaRVIS sessionStart hook into `.cursor/hooks.json`:

1. Read `.cursor/hooks.json` if it exists. If it doesn't exist, start with `{ "version": 1, "hooks": {} }`.
2. Ensure `hooks.sessionStart` is an array (note: camelCase, not PascalCase).
3. Check if a JaRVIS entry already exists by looking for `jarvis-session-start` in any existing command strings inside `hooks.sessionStart`.
4. If not already present, append this entry to the `hooks.sessionStart` array:
   ```json
   {
     "type": "command",
     "command": "bash $SKILLS_DIR/jarvis-reload/scripts/jarvis-session-start-cursor.sh",
     "timeout": 30
   }
   ```
5. Write the merged JSON back to `.cursor/hooks.json`, preserving all existing hooks.
6. **Stop hook:** Ensure `hooks.stop` is an array (camelCase).
7. Check if a JaRVIS stop entry already exists by looking for `jarvis-stop` in any existing command strings inside `hooks.stop`.
8. If not already present, append this entry to the `hooks.stop` array:
   ```json
   {
     "type": "command",
     "command": "bash $SKILLS_DIR/jarvis-reflect/scripts/jarvis-stop-cursor.sh",
     "timeout": 30
   }
   ```
9. Write the merged JSON back to `.cursor/hooks.json`, preserving all existing hooks.

## Instruction file

Read the project's `.cursorrules` (create it if it doesn't exist). If it does not already contain a `## JaRVIS` section, append the contents of `references/cursorrules.example` to the end of the file (preceded by a blank line).
