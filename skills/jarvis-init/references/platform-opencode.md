# Platform Setup: OpenCode

## Plugin

OpenCode uses in-process TypeScript plugins instead of shell-based hooks. JaRVIS provides a plugin template that handles session lifecycle events.

1. Create the `.opencode/plugins/` directory if it doesn't exist.
2. Check if a JaRVIS plugin already exists by looking for files containing `jarvis` in `.opencode/plugins/`.
3. If not already present, copy `references/opencode-plugin.ts.example` to `.opencode/plugins/jarvis-hooks.ts`.
4. The plugin needs to know where JaRVIS skills are installed. It uses `JARVIS_SKILLS_DIR` env var if set, otherwise defaults to looking in `.opencode/skills/` and `~/.config/opencode/skills/`. Update the path in the copied plugin if the skills are installed elsewhere.

## Instruction file

Read the project's `opencode.md` or `.opencode/instructions.md` (check which convention the project uses; create if neither exists, preferring `opencode.md`). If it does not already contain a `## JaRVIS` section, append the contents of `references/opencode-instructions.example` to the end of the file (preceded by a blank line).
