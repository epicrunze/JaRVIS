#!/usr/bin/env bash
# JaRVIS Stop Hook
# Fires when the agent is about to end its turn.
# Checks if a journal entry was created during this session.
# If not, blocks the agent with a reminder to reflect before ending.
#
# Claude Code Stop hooks receive JSON on stdin with a stop_hook_active flag.
# When stop_hook_active is true, we already blocked once — exit silently to prevent loops.
# Output format: {"decision": "block", "reason": "..."} to block the agent.
#
# Installation: Add to your platform's hook configuration (e.g., .claude/settings.local.json for Claude Code)
# See skills/jarvis-init/references/CLAUDE.md.example for configuration details.

set -euo pipefail

# Check for disable toggle (env var)
if [[ "${JARVIS_DISABLE:-false}" == "true" ]]; then
  exit 0
fi

# --- Read hook input from stdin ---
INPUT=$(cat 2>/dev/null || true)

# --- Check stop_hook_active to prevent infinite loop ---
if command -v jq &>/dev/null; then
  STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)
else
  # Fallback: grep for the flag in raw JSON
  if echo "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
    STOP_HOOK_ACTIVE="true"
  else
    STOP_HOOK_ACTIVE="false"
  fi
fi

if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

# --- Resolve JARVIS_DIR ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  exit 0
fi

# Check for disable toggle (persistent marker file)
if [[ -f "$JARVIS_DIR/.jarvis-disabled" ]]; then
  exit 0
fi

# --- Read session_id, transcript_path, and last_assistant_message from stdin ---
# last_assistant_message is a Claude Code field — the agent's final text
# verbatim. The gate uses it for Rule 1 (pause-signal check) to sidestep the
# transcript-flush race entirely. Absent on non-Claude-Code platforms; gate
# falls back to transcript walk-back in that case.
if command -v jq &>/dev/null; then
  SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
  TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null)
  JARVIS_LAST_ASSISTANT_MESSAGE=$(echo "$INPUT" | jq -r '.last_assistant_message // empty' 2>/dev/null)
else
  SESSION_ID=$(echo "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
  TRANSCRIPT_PATH=$(echo "$INPUT" | grep -o '"transcript_path"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
  JARVIS_LAST_ASSISTANT_MESSAGE=""
fi

# --- Bail if no session-pending marker ---
MARKER="$JARVIS_DIR/.pending-$SESSION_ID"
if [[ -z "$SESSION_ID" || ! -f "$MARKER" ]]; then
  exit 0
fi

# --- Heuristic gate: decide whether the reminder is warranted ---
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"
export TRANSCRIPT_PATH MARKER PROJECT_DIR JARVIS_LAST_ASSISTANT_MESSAGE
# shellcheck source=stop-gate.sh
source "$SCRIPT_DIR/stop-gate.sh"
verdict=$(gate_verdict)
if [[ "$verdict" != "BLOCK" ]]; then
  exit 0
fi

# --- Emit the blocking reminder ---
REASON="Reminder to reflect if needed. Run /jarvis-reflect to reflect on your session. (session_id: $SESSION_ID)"
if command -v jq &>/dev/null; then
  jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
else
  printf '{"decision":"block","reason":"Reminder to reflect if needed. Run /jarvis-reflect to reflect on your session. (session_id: %s)"}\n' "$SESSION_ID"
fi
