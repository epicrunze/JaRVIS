# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

JaRVIS (Journaling As Recurrent Versioned Identity Sculpting) is a set of agent skills for Claude Code, Cursor, GitHub Copilot, Antigravity, and other AI coding agents that provide persistent memory, post-task reflection, and self-evolving identity. It is a **skill distribution project**, not a traditional application — there is no build system, no runtime code, and no tests. Skills are pure instruction sets written as markdown.

## Repository Structure

- `hooks/hooks.json` — Claude Code plugin hooks (auto-registers SessionStart + Stop when installed as a plugin)
- `skills/` — Contains the six JaRVIS skills, each in its own directory with a `SKILL.md`
  - `jarvis-init/` — One-time setup: scaffolds the `~/.jarvis/projects/<slug>/` data directory
  - `jarvis-reload/` — Mid-session reload: re-reads identity and memories from the JaRVIS data directory
  - `jarvis-reflect/` — Post-task reflection: writes journal entries, updates memories, triggers identity evolution every 5 reflections
  - `jarvis-identity/` — Identity evolution: updates `IDENTITY.md` based on accumulated experience
  - `jarvis-validate/` — Format validation: checks journals, memories, identity, and growth log for correctness
  - `jarvis-search/` — Structured search: keyword, tag, date, and section-based search across all JaRVIS artifacts
- `skills/*/scripts/resolve-dir.sh` — Shared path resolver (sets `JARVIS_DIR`); each skill carries its own copy
- `skills/jarvis-init/scripts/jarvis-init.sh` — Init automation script (scaffold, migrate, git init)
- `skills/jarvis-init/references/scaffolding.md` — Templates for bootstrapping a new JaRVIS data directory
- `skills/jarvis-init/references/platform-*.md` — Per-platform setup guides (Claude Code, Cursor, Copilot, OpenCode, Antigravity, Other)
- `skills/jarvis-init/references/copilot-hooks.json.example` — Template for Copilot hook configuration
- `skills/jarvis-init/references/opencode-plugin.ts.example` — Template for OpenCode session hooks plugin
- `skills/jarvis-init/references/opencode-instructions.example` — Instruction snippet for OpenCode projects
- `skills/jarvis-reflect/references/reflection-guide.md` — Quality standards for writing reflections (specific over generic)
- `skills/jarvis-reload/scripts/jarvis-session-start.sh` — Loads identity, memories, and last journal entry at session start
- `skills/jarvis-reload/scripts/jarvis-session-start-cursor.sh` — Cursor variant of session start hook
- `skills/jarvis-reload/scripts/jarvis-session-start-copilot.sh` — Copilot variant of session start hook (marker tracking only)
- `skills/jarvis-reflect/scripts/jarvis-stop.sh` — Stop hook that reminds to reflect before ending session
- `skills/jarvis-reflect/scripts/jarvis-stop-cursor.sh` — Cursor variant of stop hook
- `skills/jarvis-reflect/scripts/jarvis-session-end-copilot.sh` — Copilot session end hook (marker cleanup)
- `skills/jarvis-init/references/CLAUDE.md.example` — Snippet users add to their project's CLAUDE.md after installing JaRVIS (Claude Code)
- `skills/jarvis-init/references/cursorrules.example` — Snippet for `.cursorrules` (Cursor)
- `skills/jarvis-init/references/copilot-instructions.example` — Snippet for `.github/copilot-instructions.md` (GitHub Copilot)
- `skills/jarvis-init/references/AGENTS.md.example` — Snippet for `AGENTS.md` (Antigravity)
- `skills/jarvis-validate/scripts/validate.sh` — Shell script for format validation of JaRVIS artifacts
- `skills/jarvis-search/scripts/search.sh` — Shell script for structured search across JaRVIS artifacts

## Installation Paths

Skills are installed by copying skill folders into the platform's skills directory:
- **Claude Code:** `.claude/skills/` (project) or `~/.claude/skills/` (global); also installable as a plugin (`claude plugins add`) with auto-registered hooks
- **Cursor:** `.cursor/skills/`
- **GitHub Copilot:** `.github/skills/`
- **OpenCode:** `.opencode/skills/` (project) or `~/.config/opencode/skills/` (global)
- **Antigravity:** `.agent/skills/`
- **Other:** User-specified directory (default: `.agent/skills/`)

## Architecture

Setup is a one-time `/jarvis-init` to scaffold the data directory at `~/.jarvis/projects/<slug>/`. Session context is loaded automatically via the `SessionStart` hook (identity, memories, last journal entry). The ongoing workflow is a loop: work → `/jarvis-reflect` → work → `/jarvis-reflect` → ... → `/jarvis-identity` (every 5 reflections). Use `/jarvis-reload` mid-session to reload context after reflections update memories. Use `/jarvis-validate` to check JaRVIS artifacts for format correctness. Use `/jarvis-search` to find past entries by keyword, tag, date range, or section.

All agent artifacts (identity, memories, journals) are flat markdown files stored in `~/.jarvis/projects/<slug>/` under the user's home directory. The path is derived by slugifying the project directory, or can be overridden with the `JARVIS_DIR` env var. Each data directory has its own git repo for version history.

Each SKILL.md uses YAML frontmatter (`name`, `description`, `disable-model-invocation`) and contains step-by-step instructions that the agent's skill system executes directly.

## Design Principles

- **Reflection over logging** — captures "what I learned" not just "what happened"
- **Earned identity** — agent only claims expertise demonstrated through completed tasks
- **Memory consolidation** — memories are periodically sculpted and deduplicated, not just appended
- **Transparency** — everything is human-readable markdown, git-trackable
