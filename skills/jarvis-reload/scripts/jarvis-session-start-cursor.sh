#!/usr/bin/env bash
# JaRVIS SessionStart Hook — Cursor JSON Wrapper
# Cursor hooks require JSON I/O ({ "agent_message": "..." }).
# This wrapper reads Cursor's stdin (which has conversation_id, not session_id),
# maps conversation_id → session_id, pipes it to the base script, and wraps output.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read Cursor's hook input from stdin
CURSOR_INPUT=$(cat 2>/dev/null || true)

# Map conversation_id → session_id for the base script
if command -v jq &>/dev/null; then
  BASE_INPUT=$(echo "$CURSOR_INPUT" | jq '{session_id: .conversation_id, source: "startup"}' 2>/dev/null || echo '{}')
else
  CONV_ID=$(echo "$CURSOR_INPUT" | grep -o '"conversation_id"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"\([^"]*\)"$/\1/')
  if [[ -n "$CONV_ID" ]]; then
    BASE_INPUT="{\"session_id\":\"$CONV_ID\",\"source\":\"startup\"}"
  else
    BASE_INPUT='{}'
  fi
fi

PLAIN_OUTPUT=$(echo "$BASE_INPUT" | "$SCRIPT_DIR/jarvis-session-start.sh" 2>/dev/null || true)

if [[ -z "$PLAIN_OUTPUT" ]]; then
  echo '{"agent_message":""}'
  exit 0
fi

# Use jq if available, otherwise fall back to manual JSON encoding
if command -v jq &>/dev/null; then
  echo "$PLAIN_OUTPUT" | jq -Rs '{ agent_message: . }'
else
  # Escape backslashes, double quotes, and newlines for JSON
  ESCAPED=$(printf '%s' "$PLAIN_OUTPUT" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g')
  printf '{"agent_message":"%s"}\n' "$ESCAPED"
fi
