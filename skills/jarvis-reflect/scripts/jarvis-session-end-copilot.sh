#!/usr/bin/env bash
# JaRVIS SessionEnd Hook — Copilot
# Handles Copilot's sessionEnd event for cleanup.
# Does NOT call the base jarvis-stop.sh — Copilot hooks are observational
# (cannot block the agent), so the blocking logic is irrelevant.
# Instead, this script resolves JARVIS_DIR and cleans up pending markers
# for this Copilot session.

set -euo pipefail

if [[ "${JARVIS_DISABLE:-false}" == "true" ]]; then
  echo '{}'
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Resolve JARVIS_DIR ---
if [ -f "$SCRIPT_DIR/resolve-dir.sh" ]; then
  # shellcheck source=/dev/null
  source "$SCRIPT_DIR/resolve-dir.sh"
elif [ -z "${JARVIS_DIR:-}" ]; then
  # Inline fallback mirrors resolve-dir.sh: git toplevel + canonicalize + legacy fallback.
  _jstart="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  _jtop=$(git -C "$_jstart" rev-parse --show-toplevel 2>/dev/null || true)
  _jresolved="${_jtop:-$_jstart}"
  _jcanon=$(cd "$_jresolved" 2>/dev/null && pwd -P || echo "$_jresolved")
  _jslug=$(echo "$_jcanon" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
  JARVIS_DIR="$HOME/.jarvis/projects/$_jslug"
  if [ ! -d "$JARVIS_DIR" ]; then
    _jlegacy=$(echo "$_jstart" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
    if [ "$_jlegacy" != "$_jslug" ] && [ -d "$HOME/.jarvis/projects/$_jlegacy" ]; then
      JARVIS_DIR="$HOME/.jarvis/projects/$_jlegacy"
    fi
    unset _jlegacy
  fi
  unset _jstart _jtop _jresolved _jcanon _jslug
fi

# --- If JaRVIS isn't set up, stay silent ---
if [[ ! -d "$JARVIS_DIR" ]]; then
  echo '{}'
  exit 0
fi

# Check for disable toggle (persistent marker file)
if [[ -f "$JARVIS_DIR/.jarvis-disabled" ]]; then
  echo '{}'
  exit 0
fi

# --- Read Copilot's hook input from stdin ---
COPILOT_INPUT=$(cat 2>/dev/null || true)

# Extract timestamp to match the session ID synthesized at start
if command -v jq &>/dev/null; then
  TIMESTAMP=$(echo "$COPILOT_INPUT" | jq -r '.timestamp // empty' 2>/dev/null)
else
  TIMESTAMP=$(echo "$COPILOT_INPUT" | grep -o '"timestamp"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//')
fi

# Clean up pending markers for Copilot sessions
# Since the sessionEnd timestamp may differ from sessionStart, clean all copilot markers
find "$JARVIS_DIR" -maxdepth 1 -name '.pending-copilot-*' -delete 2>/dev/null || true

# Output empty JSON (observational hook)
echo '{}'
