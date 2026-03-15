#!/usr/bin/env bash
# JaRVIS Stop Hook — Cursor JSON Wrapper
# Cursor hooks require JSON I/O ({ "agent_message": "..." }).
# This wrapper calls the plain-text jarvis-stop.sh and wraps its output.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAIN_OUTPUT=$("$SCRIPT_DIR/jarvis-stop.sh" 2>/dev/null || true)

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
