#!/usr/bin/env bash
# JaRVIS SessionStart Hook — Cursor JSON Wrapper
# Cursor hooks require JSON I/O ({ "agent_message": "..." }).
# This wrapper reads Cursor's stdin (which has conversation_id, not session_id),
# maps conversation_id → session_id, pipes it to the base script, and wraps output.
# The base script now outputs structured JSON; this wrapper extracts the
# additionalContext field and rewraps it for Cursor.

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

JSON_OUTPUT=$(echo "$BASE_INPUT" | "$SCRIPT_DIR/jarvis-session-start.sh" 2>/dev/null || true)

if [[ -z "$JSON_OUTPUT" ]]; then
  echo '{"agent_message":""}'
  exit 0
fi

# Extract additionalContext from the base script's JSON output and wrap for Cursor
if command -v jq &>/dev/null; then
  CONTEXT=$(echo "$JSON_OUTPUT" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)
  if [[ -z "$CONTEXT" ]]; then
    # Fallback: treat entire output as context (in case base script format changes)
    CONTEXT="$JSON_OUTPUT"
  fi
  echo "$CONTEXT" | jq -Rs '{ agent_message: . }'
else
  # Without jq, try to extract additionalContext with grep/sed
  # The additionalContext value is a JSON string, so extract between the quotes
  CONTEXT=$(printf '%s' "$JSON_OUTPUT" | grep -o '"additionalContext"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/^"additionalContext"[[:space:]]*:[[:space:]]*"//;s/"$//')
  if [[ -z "$CONTEXT" ]]; then
    # Fallback: use the raw JSON output
    ESCAPED=$(printf '%s' "$JSON_OUTPUT" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a' -e 'N' -e '$!ba' -e 's/\n/\\n/g')
    printf '{"agent_message":"%s"}\n' "$ESCAPED"
  else
    # Context is already JSON-escaped from the base script output, wrap it directly
    printf '{"agent_message":"%s"}\n' "$CONTEXT"
  fi
fi
