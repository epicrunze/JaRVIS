# Platform Setup: GitHub Copilot

## Hooks

GitHub Copilot supports `sessionStart` and `sessionEnd` hooks via JSON config files in `.github/hooks/`.

> **Note:** Copilot hooks are observational — they cannot inject context into the agent. The agent still needs manual `/jarvis-reload` at session start. Hooks are used for pending-reflection marker tracking and cleanup.

Create or merge JaRVIS hooks into `.github/hooks/jarvis.json`:

1. Create the `.github/hooks/` directory if it doesn't exist.
2. Read `.github/hooks/jarvis.json` if it exists. If it doesn't exist, start with `{ "version": 1, "hooks": {} }`.
3. Check if JaRVIS entries already exist by looking for `jarvis-session-start` or `jarvis-session-end` in the hook commands.
4. If not already present, write the hooks config. Use `references/copilot-hooks.json.example` as a template, replacing `$SKILLS_DIR` with the resolved skills directory path.
5. Write the merged JSON back to `.github/hooks/jarvis.json`, preserving any existing hooks.

## Instruction file

Read the project's `.github/copilot-instructions.md` (create the `.github/` directory and file if they don't exist). If it does not already contain a `## JaRVIS` section, append the contents of `references/copilot-instructions.example` to the end of the file (preceded by a blank line).
