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
  _project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  _slug=$(echo "$_project_dir" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
  JARVIS_DIR="$HOME/.jarvis/projects/$_slug"
  unset _project_dir _slug
fi

# --- If JaRVIS isn't set up, stay silent ---
if [[ ! -d "$JARVIS_DIR" ]]; then
  exit 0
fi

# --- Read session_id from stdin ---
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null)
# fallback without jq
if [[ -z "$SESSION_ID" ]]; then
  SESSION_ID=$(echo "$INPUT" | grep -o '"session_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
fi

# --- Check for this session's pending marker ---
if [[ -n "$SESSION_ID" && -f "$JARVIS_DIR/.pending-$SESSION_ID" ]]; then
  # This session hasn't reflected yet → block
  REASON="You haven't reflected on this session yet. Run /jarvis-reflect if needed before ending."
  if command -v jq &>/dev/null; then
    jq -n --arg reason "$REASON" '{decision: "block", reason: $reason}'
  else
    echo '{"decision":"block","reason":"You haven'\''t reflected on this session yet. Run /jarvis-reflect if needed before ending."}'
  fi
fi
