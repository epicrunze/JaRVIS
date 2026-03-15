# One-Prompt Install / Update

Copy the prompt below and paste it into your AI coding agent (Cursor, GitHub Copilot, Antigravity, or Claude Code) to install or update JaRVIS in one step.

## How to use

1. Open your AI coding agent in the project where you want JaRVIS
2. Paste the entire prompt below
3. Let the agent run — it will download and install (or update) JaRVIS

## The prompt

```
Install or update JaRVIS (https://github.com/epicrunze/JaRVIS) in this project. Follow these steps exactly:

1. Download and extract the JaRVIS repo:
   curl -sL https://github.com/epicrunze/JaRVIS/archive/refs/heads/main.tar.gz | tar xz

2. Detect the platform and set SKILLS_DIR:
   - If .claude/ exists → SKILLS_DIR=".claude/skills"
   - If .cursor/ exists → SKILLS_DIR=".cursor/skills"
   - If .github/ exists → SKILLS_DIR=".github/skills"
   - If .agent/ exists or AGENTS.md exists → SKILLS_DIR=".agent/skills"
   - If none match, ask me which platform I'm using.

3. Create the skills directory if needed: mkdir -p "$SKILLS_DIR"

4. Copy the four skill folders:
   cp -r JaRVIS-main/skills/jarvis-init "$SKILLS_DIR/"
   cp -r JaRVIS-main/skills/jarvis-reload "$SKILLS_DIR/"
   cp -r JaRVIS-main/skills/jarvis-reflect "$SKILLS_DIR/"
   cp -r JaRVIS-main/skills/jarvis-identity "$SKILLS_DIR/"

5. Clean up: rm -rf JaRVIS-main

6. If the .jarvis/ directory does NOT already exist, run /jarvis-init to complete setup. If .jarvis/ already exists, skip this step — the update is complete.
```

> **Global install (Claude Code only):** To install JaRVIS for all projects, tell the agent to use `SKILLS_DIR="$HOME/.claude/skills"` instead of detecting the platform.
