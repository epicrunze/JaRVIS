#!/usr/bin/env bash
# JaRVIS Init — scaffolds the JaRVIS data directory for a project
# Usage: jarvis-init.sh [--project-dir <path>] [--migrate]
#
# Handles steps 1-4 of /jarvis-init:
#   1. Resolve JARVIS_DIR via resolve-dir.sh
#   2. Check if already initialized (exit 0 if so)
#   3. Optionally migrate from old .jarvis/ layout
#   4. Scaffold directory structure + template files
#   5. git init + initial commit
#   6. Print the resolved JARVIS_DIR path
#
# The agent handles platform detection and configuration (steps 5-6 of SKILL.md).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MIGRATE=false
PROJECT_DIR=""

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir)
      PROJECT_DIR="$2"
      shift 2
      ;;
    --migrate)
      MIGRATE=true
      shift
      ;;
    -h|--help)
      echo "Usage: jarvis-init.sh [--project-dir <path>] [--migrate]"
      echo ""
      echo "Options:"
      echo "  --project-dir PATH  Project directory (default: CLAUDE_PROJECT_DIR or pwd)"
      echo "  --migrate           Migrate existing .jarvis/ from project root to home directory"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# --- Set CLAUDE_PROJECT_DIR if --project-dir was given, so resolve-dir.sh picks it up ---
if [[ -n "$PROJECT_DIR" ]]; then
  export CLAUDE_PROJECT_DIR="$PROJECT_DIR"
fi

# --- Resolve JARVIS_DIR ---
# shellcheck source=resolve-dir.sh
source "$SCRIPT_DIR/resolve-dir.sh"

# --- Check if already initialized ---
if [[ -d "$JARVIS_DIR" ]]; then
  echo "ALREADY_EXISTS"
  echo "$JARVIS_DIR"
  exit 0
fi

# --- Migration ---
if [[ "$MIGRATE" == true ]]; then
  OLD_DIR="${PROJECT_DIR:-.}/.jarvis"
  if [[ -d "$OLD_DIR" ]]; then
    mkdir -p "$JARVIS_DIR"
    cp -r "$OLD_DIR"/* "$JARVIS_DIR"/
    echo "MIGRATED"
  fi
fi

# --- Scaffold directory structure ---
mkdir -p "$JARVIS_DIR/memories" "$JARVIS_DIR/journal"

# --- IDENTITY.md ---
if [[ ! -f "$JARVIS_DIR/IDENTITY.md" ]]; then
  cat > "$JARVIS_DIR/IDENTITY.md" << 'EOF'
# Agent Identity

## Core
- **Name**: (unnamed — awaiting first session)
- **Version**: 0.0
- **Last evolved**: never

## Personality
Not yet established. Identity emerges through work and reflection.

## Expertise
No demonstrated expertise yet. This section grows only through completed tasks.

## Principles
No principles established. These emerge from real experience, not aspiration.

## Tool Mastery
No tools mastered yet. Tracks effective patterns and pitfalls discovered through use.

## User Model
No observations yet. Preferences noted during collaboration appear here.
EOF
fi

# --- GROWTH.md ---
if [[ ! -f "$JARVIS_DIR/GROWTH.md" ]]; then
  cat > "$JARVIS_DIR/GROWTH.md" << 'EOF'
# Growth Log

| Date | Version | What changed | Why |
|------|---------|-------------|-----|
EOF
fi

# --- memories/preferences.md ---
if [[ ! -f "$JARVIS_DIR/memories/preferences.md" ]]; then
  cat > "$JARVIS_DIR/memories/preferences.md" << 'EOF'
# User Preferences

## Consolidated
No consolidated preferences yet.

## Recent
EOF
fi

# --- memories/decisions.md ---
if [[ ! -f "$JARVIS_DIR/memories/decisions.md" ]]; then
  cat > "$JARVIS_DIR/memories/decisions.md" << 'EOF'
# Key Decisions

## Consolidated
No consolidated decisions yet.

## Recent
EOF
fi

# --- Git init + initial commit ---
cd "$JARVIS_DIR"
git init --quiet
git add -A
# Use fallback author if git user is not configured
_jarvis_git_author_name=$(git config user.name 2>/dev/null || echo "JaRVIS")
_jarvis_git_author_email=$(git config user.email 2>/dev/null || echo "jarvis@localhost")
git -c user.name="$_jarvis_git_author_name" -c user.email="$_jarvis_git_author_email" commit --quiet -m "jarvis: initial scaffold"
unset _jarvis_git_author_name _jarvis_git_author_email

# --- Print resolved path ---
echo "$JARVIS_DIR"
