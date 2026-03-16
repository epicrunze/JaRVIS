# Platform Setup: Other / Generic

## Skills directory

Ask the user for their platform's skills directory path (default: `.agent/skills/`).

## Hooks

Ask the user if hooks are available in their platform, and do some research on the docs for their platform. Try to work with the user to set up hooks, but if it's not supported, inform the user they should run `/jarvis-reload` manually at the start of each session.

## Instruction file

Ask the user for their platform's instruction file path (default: `AGENTS.md`). Read the file (create it if it doesn't exist). If it does not already contain a `## JaRVIS` section, append the contents of `references/AGENTS.md.example` to the end of the file (preceded by a blank line).
