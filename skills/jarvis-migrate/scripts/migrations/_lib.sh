#!/usr/bin/env bash
# Shared helpers for JaRVIS migrations. Source from each migration script:
#   . "$(dirname "$0")/_lib.sh"
#
# --- Migration script conventions ---
#
# Every migration MUST start with:
#   #!/usr/bin/env bash
#   set -euo pipefail
#   . "$(dirname "$0")/_lib.sh"
#   JDIR="$1"
#
# `set -euo pipefail` matters: without -e a forgotten error check can let the
# script exit 0 with the migration only partly applied. The runner advances
# the stamp on exit 0, so silent partial success would mark the data dir as
# migrated when it isn't. Don't skip set -e.
#
# Migrations MUST be idempotent. The runner calls each migration at most once
# in a single run (gated by the stamp), but if a later migration in the same
# run fails, the stamp is left at its pre-run value and the entire range
# re-runs on the next attempt. A non-idempotent migration would double-apply.
# Pattern: check the desired post-state first; act only if it isn't already
# there. Migration 001 is a good template.
#
# --- Platform note: Copilot fail-loud limitation ---
#
# The Copilot SessionStart wrapper (jarvis-session-start-copilot.sh) discards
# stdout/stderr and exit codes from the base hook (`>/dev/null 2>&1 || true`)
# because Copilot hooks cannot inject context. Migration *failures* on Copilot
# therefore surface only at the next /jarvis-reflect (which calls migrate.sh
# directly via finalize-reflection.sh and propagates the exit code). Side-
# effect migrations still run correctly on Copilot — only the failure UI is
# missing. Accept this trade-off rather than working around it.

log_change() {
  # Single-line changelog blurb to stdout. Runner aggregates these.
  printf '%s\n' "$1"
}

log_error() {
  # Diagnostic to stderr. Runner surfaces these on failure.
  printf '%s\n' "$1" >&2
}
