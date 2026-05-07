#!/usr/bin/env bash
# JaRVIS Finalize Reflection — runs the deterministic tail of /jarvis-reflect
# Usage: finalize-reflection.sh <journal-path>
#
# Pipeline (in order):
#   1. Resolve JARVIS_DIR.
#   2. Self-heal .gitignore (write or append .pending-* if missing).
#   3. Run validate.sh — if it fails, exit non-zero with the validator output.
#   4. Remove pending-reflection marker(s) for this session.
#   5. git add -A && git commit (commit message extracted from journal's
#      Task Summary section, falls back to "reflect: <date> <time>").
#   6. Scan memories/*.md for files > 100 lines; emit consolidation_warn lines.
#   7. Count journal entries; emit evolution_due flag (true when count % 5 == 0).
#
# This script intentionally does *not* call /jarvis-validate as a sub-skill
# — it invokes the validate.sh script directly to avoid agent-side skill
# nesting and the associated system-reminder overhead.

set -euo pipefail

# --- Args ---
if [ $# -lt 1 ]; then
  echo "usage: finalize-reflection.sh <journal-path>" >&2
  exit 2
fi
JOURNAL_PATH="$1"

if [ ! -f "$JOURNAL_PATH" ]; then
  echo "finalize: journal not found: $JOURNAL_PATH" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 1. Resolve JARVIS_DIR ---
# shellcheck source=resolve-dir.sh
source "$SCRIPT_DIR/resolve-dir.sh"

if [ ! -d "$JARVIS_DIR" ]; then
  echo "finalize: JARVIS_DIR does not exist: $JARVIS_DIR" >&2
  echo "         run /jarvis-init first" >&2
  exit 2
fi

# --- 2. Run pending data-dir migrations ---
MIGRATE_SCRIPT="$SCRIPT_DIR/../../jarvis-migrate/scripts/migrate.sh"
if [ -f "$MIGRATE_SCRIPT" ]; then
  if ! mig_out=$(bash "$MIGRATE_SCRIPT" "$JARVIS_DIR" 2>&1); then
    echo "$mig_out"
    echo "" >&2
    echo "finalize: migration failed — fix the issue, then re-run finalize." >&2
    exit 4
  fi
  if [ -n "$mig_out" ]; then
    # Surface migration changelog to the agent so it can pass it on.
    echo "$mig_out"
    echo ""
  fi
fi

# --- 3. Validate ---
VALIDATE_SH="$SCRIPT_DIR/../../jarvis-validate/scripts/validate.sh"
if [ ! -f "$VALIDATE_SH" ]; then
  echo "finalize: validate.sh not found at $VALIDATE_SH" >&2
  exit 2
fi

VALIDATE_OUT=$(bash "$VALIDATE_SH" "$JARVIS_DIR" 2>&1) || VALIDATE_RC=$?
VALIDATE_RC="${VALIDATE_RC:-0}"

if [ "$VALIDATE_RC" -ne 0 ]; then
  echo "$VALIDATE_OUT"
  echo "" >&2
  echo "finalize: validation failed — fix the failures, then re-run finalize." >&2
  exit "$VALIDATE_RC"
fi

# --- 4. Remove pending marker(s) ---
# Prefer cleaning only the current session's marker if the caller passed
# JARVIS_SESSION_ID; otherwise sweep all .pending-* (next SessionStart will
# recreate any concurrent session's marker on its first hook fire).
if [ -n "${JARVIS_SESSION_ID:-}" ]; then
  rm -f "$JARVIS_DIR/.pending-$JARVIS_SESSION_ID"
else
  rm -f "$JARVIS_DIR"/.pending-* 2>/dev/null || true
fi

# --- 5. Commit ---
# Pull commit summary from the journal's "## Task Summary" section.
COMMIT_SUMMARY=$(awk '
  BEGIN { IGNORECASE=1 }
  /^## Task Summary[[:space:]]*$/ { in_sect=1; next }
  in_sect && /^##[[:space:]]/ { exit }
  in_sect && NF { print; exit }
' "$JOURNAL_PATH" | head -c 60 | tr '\n' ' ' | sed 's/[[:space:]]\{1,\}$//')

if [ -z "$COMMIT_SUMMARY" ]; then
  # Fallback: use journal basename (date-time portion) as the summary.
  JOURNAL_BASE=$(basename "$JOURNAL_PATH" .md)
  COMMIT_SUMMARY="$JOURNAL_BASE"
fi

cd "$JARVIS_DIR"
git add -A

# Skip commit if there's nothing to commit (defensive — should rarely happen).
if git diff --cached --quiet; then
  echo "finalize: nothing to commit" >&2
else
  GIT_NAME=$(git config user.name 2>/dev/null || echo "JaRVIS")
  GIT_EMAIL=$(git config user.email 2>/dev/null || echo "jarvis@localhost")
  git -c user.name="$GIT_NAME" -c user.email="$GIT_EMAIL" \
    commit --quiet -m "reflect: $COMMIT_SUMMARY"
fi

# --- 6. Consolidation warnings (informational) ---
CONSOLIDATION_WARNS=()
if [ -d "$JARVIS_DIR/memories" ]; then
  while IFS= read -r -d '' mfile; do
    line_count=$(wc -l < "$mfile")
    if [ "$line_count" -gt 100 ]; then
      CONSOLIDATION_WARNS+=("$(basename "$mfile"):$line_count")
    fi
  done < <(find "$JARVIS_DIR/memories" -maxdepth 1 -type f -name '*.md' -print0)
fi

# --- 7. Journal count + evolution flag ---
JOURNAL_COUNT=0
if [ -d "$JARVIS_DIR/journal" ]; then
  JOURNAL_COUNT=$(find "$JARVIS_DIR/journal" -maxdepth 1 -type f -name '*.md' | wc -l)
fi

if [ "$JOURNAL_COUNT" -gt 0 ] && [ $((JOURNAL_COUNT % 5)) -eq 0 ]; then
  EVOLUTION_DUE="true"
else
  EVOLUTION_DUE="false"
fi

# --- Structured summary ---
echo "FINALIZE_OK"
echo "journal_entries=$JOURNAL_COUNT"
echo "evolution_due=$EVOLUTION_DUE"
echo "commit_summary=$COMMIT_SUMMARY"
for w in "${CONSOLIDATION_WARNS[@]:-}"; do
  [ -n "$w" ] && echo "consolidation_warn=$w"
done
exit 0
