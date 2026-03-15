# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

JaRVIS (Journaling As Recurrent Versioned Identity Sculpting) is a set of agent skills for Claude Code, Cursor, GitHub Copilot, and Antigravity that provide persistent memory, post-task reflection, and self-evolving identity. It is a **skill distribution project**, not a traditional application — there is no build system, no runtime code, and no tests. Skills are pure instruction sets written as markdown.

## Repository Structure

- `skills/` — Contains the four JaRVIS skills, each in its own directory with a `SKILL.md`
  - `jarvis-init/` — One-time setup: scaffolds the `.jarvis/` directory structure
  - `jarvis-reload/` — Mid-session reload: re-reads identity and memories from `.jarvis/`
  - `jarvis-reflect/` — Post-task reflection: writes journal entries, updates memories, triggers identity evolution every 5 reflections
  - `jarvis-identity/` — Identity evolution: updates `.jarvis/IDENTITY.md` based on accumulated experience
- `skills/jarvis-init/references/scaffolding.md` — Templates for bootstrapping a new `.jarvis/` directory
- `skills/jarvis-reflect/references/reflection-guide.md` — Quality standards for writing reflections (specific over generic)
- `skills/jarvis-reload/hooks/` — SessionStart hook script for automatic context loading
  - `jarvis-session-start.sh` — Loads identity, memories, and last journal entry at session start
- `skills/jarvis-init/references/CLAUDE.md.example` — Snippet users add to their project's CLAUDE.md after installing JaRVIS (Claude Code)
- `skills/jarvis-init/references/cursorrules.example` — Snippet for `.cursorrules` (Cursor)
- `skills/jarvis-init/references/copilot-instructions.example` — Snippet for `.github/copilot-instructions.md` (GitHub Copilot)
- `skills/jarvis-init/references/AGENTS.md.example` — Snippet for `AGENTS.md` (Antigravity)

## Installation Paths

Skills are installed by copying skill folders into the platform's skills directory:
- **Claude Code:** `.claude/skills/` (project) or `~/.claude/skills/` (global)
- **Cursor:** `.cursor/skills/`
- **GitHub Copilot:** `.github/skills/`
- **Antigravity:** `.agent/skills/`

## Architecture

Setup is a one-time `/jarvis-init` to scaffold the directory. Session context is loaded automatically via the `SessionStart` hook (identity, memories, last journal entry). The ongoing workflow is a loop: work → `/jarvis-reflect` → work → `/jarvis-reflect` → ... → `/jarvis-identity` (every 5 reflections). Use `/jarvis-reload` mid-session to reload context after reflections update memories.

All agent artifacts (identity, memories, journals) are flat markdown files stored in `.jarvis/` at the consuming project's root. There are no databases, vector stores, or external services.

Each SKILL.md uses YAML frontmatter (`name`, `description`, `disable-model-invocation`) and contains step-by-step instructions that the agent's skill system executes directly.

## Design Principles

- **Reflection over logging** — captures "what I learned" not just "what happened"
- **Earned identity** — agent only claims expertise demonstrated through completed tasks
- **Memory consolidation** — memories are periodically sculpted and deduplicated, not just appended
- **Transparency** — everything is human-readable markdown, git-trackable
