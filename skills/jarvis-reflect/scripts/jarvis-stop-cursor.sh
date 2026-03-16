#!/usr/bin/env bash
# JaRVIS Stop Hook — Cursor JSON Wrapper
# Cursor hooks require JSON I/O ({ "agent_message": "..." }).
# This wrapper reads Cursor's stdin (which has conversation_id, not session_id),
# maps conversation_id → session_id, pipes it to the base script, and wraps output.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read Cursor's hook input from stdin
CURSOR_INPUT=$(cat 2>/dev/null || true)

# Map conversation_id → session_id for the base script.
# Cursor's stop hook doesn't have stop_hook_active, so omit it (defaults to false).
if command -v jq &>/dev/null; then
  BASE_INPUT=$(echo "$CURSOR_INPUT" | jq '{session_id: .conversation_id}' 2>/dev/null || echo '{}')
else
  CONV_ID=$(echo "$CURSOR_INPUT" | grep -o '"conversation_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
  if [[ -n "$CONV_ID" ]]; then
    BASE_INPUT="{\"session_id\":\"$CONV_ID\"}"
  else
    BASE_INPUT='{}'
  fi
fi

JSON_OUTPUT=$(echo "$BASE_INPUT" | "$SCRIPT_DIR/jarvis-stop.sh" 2>/dev/null || true)

if [[ -z "$JSON_OUTPUT" ]]; then
  echo '{"agent_message":""}'
  exit 0
fi

# Extract the reason field from the blocking JSON and wrap for Cursor
if command -v jq &>/dev/null; then
  REASON=$(echo "$JSON_OUTPUT" | jq -r '.reason // empty' 2>/dev/null)
  if [[ -n "$REASON" ]]; then
    echo "$REASON" | jq -Rs '{ agent_message: . }'
  else
    echo '{"agent_message":""}'
  fi
else
  # Fallback: extract reason with sed, wrap in Cursor format
  REASON=$(echo "$JSON_OUTPUT" | sed -n 's/.*"reason"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')
  if [[ -n "$REASON" ]]; then
    printf '{"agent_message":"%s"}\n' "$REASON"
  else
    echo '{"agent_message":""}'
  fi
fi
