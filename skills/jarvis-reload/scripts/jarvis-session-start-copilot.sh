#!/usr/bin/env bash
# JaRVIS SessionStart Hook — Copilot JSON Wrapper
# Copilot hooks receive JSON on stdin with timestamp, cwd, source fields.
# Copilot has no session_id in its payload, so we synthesize one from the timestamp.
# Copilot hooks are observational — they cannot inject context into the agent.
# This wrapper runs the base script for side effects (pending marker creation,
# stale cleanup) and discards the structured output.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read Copilot's hook input from stdin
COPILOT_INPUT=$(cat 2>/dev/null || true)

# Extract timestamp to synthesize a session ID (Copilot has no session_id)
if command -v jq &>/dev/null; then
  TIMESTAMP=$(echo "$COPILOT_INPUT" | jq -r '.timestamp // empty' 2>/dev/null)
else
  TIMESTAMP=$(echo "$COPILOT_INPUT" | grep -o '"timestamp"[[:space:]]*:[[:space:]]*[0-9]*' | sed 's/.*:[[:space:]]*//')
fi

if [[ -n "$TIMESTAMP" ]]; then
  SESSION_ID="copilot-$TIMESTAMP"
else
  SESSION_ID="copilot-$(date +%s)"
fi

# Build input for the base script
if command -v jq &>/dev/null; then
  BASE_INPUT=$(jq -n --arg sid "$SESSION_ID" '{session_id: $sid, source: "startup"}')
else
  BASE_INPUT="{\"session_id\":\"$SESSION_ID\",\"source\":\"startup\"}"
fi

# Run the base script for side effects (pending marker, stale cleanup)
# Discard output — Copilot cannot inject context
echo "$BASE_INPUT" | "$SCRIPT_DIR/jarvis-session-start.sh" >/dev/null 2>&1 || true

# Output empty JSON to satisfy Copilot's expectation
echo '{}'
