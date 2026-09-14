#!/usr/bin/env bash
# JaRVIS permissions — install or refresh the JaRVIS allow rules in a
# project's .claude/settings.local.json (Claude Code only).
#
# Usage:
#   jarvis-permissions.sh --project-dir <P> --jarvis-dir <J> \
#       (--plugin-root <R> | --skills-dir <S>) [--check]
#
#   --project-dir  Project root containing .claude/ (created if missing).
#   --jarvis-dir   Absolute JaRVIS data dir (output of resolve-dir.sh).
#   --plugin-root  $CLAUDE_PLUGIN_ROOT for plugin installs. The Bash rule
#                  targets its parent dir so it survives version bumps.
#   --skills-dir   Skills base dir for copied installs (.claude/skills etc).
#   --check        Do not write. Print OK (exit 0) if the file already holds
#                  exactly the canonical rules, else STALE (exit 1).
#
# Without --check, prints UPDATED (file rewritten) or UNCHANGED (already
# canonical; file left byte-identical). Every existing JaRVIS-owned rule
# (old Write/`cd && git`/version-pinned forms included) is removed and the
# canonical set appended; all other rules, hooks and keys are preserved.
#
# Canonical rules:
#   Read(<jarvis-dir>/**)              (~/ form when under $HOME, // otherwise)
#   Edit(<jarvis-dir>/**)              (Edit covers Write/NotebookEdit too)
#   Bash(git -C <abs-jarvis-dir> *)    (each && subcommand must match alone)
#   Bash(bash <dirname(plugin-root)>/*)  or  Bash(bash <skills-dir>/jarvis-*)
#
# Exit codes: 0 ok, 1 stale (--check only), 2 usage, 3 settings unreadable.

set -euo pipefail

PROJECT_DIR=""
JARVIS_DIR_ARG=""
PLUGIN_ROOT=""
SKILLS_DIR=""
CHECK=false

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project-dir) PROJECT_DIR="${2:-}"; shift 2 ;;
    --jarvis-dir)  JARVIS_DIR_ARG="${2:-}"; shift 2 ;;
    --plugin-root) PLUGIN_ROOT="${2:-}"; shift 2 ;;
    --skills-dir)  SKILLS_DIR="${2:-}"; shift 2 ;;
    --check)       CHECK=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    *) echo "jarvis-permissions: unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ -z "$PROJECT_DIR" || -z "$JARVIS_DIR_ARG" ]]; then
  echo "jarvis-permissions: --project-dir and --jarvis-dir are required" >&2
  exit 2
fi
if [[ -n "$PLUGIN_ROOT" && -n "$SKILLS_DIR" ]] || [[ -z "$PLUGIN_ROOT" && -z "$SKILLS_DIR" ]]; then
  echo "jarvis-permissions: exactly one of --plugin-root or --skills-dir is required" >&2
  exit 2
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jarvis-permissions: jq is required" >&2
  exit 2
fi

# Normalize: strip trailing slashes.
JARVIS_DIR="${JARVIS_DIR_ARG%/}"
PLUGIN_ROOT="${PLUGIN_ROOT%/}"
SKILLS_DIR="${SKILLS_DIR%/}"
SETTINGS="$PROJECT_DIR/.claude/settings.local.json"

# Path rules: prefer ~/ when the data dir lives under $HOME (matches the
# documented template); otherwise use the // absolute form.
if [[ -n "${HOME:-}" && "$JARVIS_DIR" == "$HOME/"* ]]; then
  PATH_RULE_DIR="~/${JARVIS_DIR#"$HOME"/}"
else
  PATH_RULE_DIR="/$JARVIS_DIR"
fi

if [[ -n "$PLUGIN_ROOT" ]]; then
  BASH_RULE="Bash(bash $(dirname "$PLUGIN_ROOT")/*)"
else
  BASH_RULE="Bash(bash $SKILLS_DIR/jarvis-*)"
fi

CANON=$(jq -cn \
  --arg r "Read($PATH_RULE_DIR/**)" \
  --arg e "Edit($PATH_RULE_DIR/**)" \
  --arg g "Bash(git -C $JARVIS_DIR *)" \
  --arg b "$BASH_RULE" \
  '[$r, $e, $g, $b]')

# A rule is JaRVIS-owned if it mentions the JaRVIS data dir (any slug), the
# plugin cache, a jarvis-* skill script path, or the copied-install prefix
# rule. Dev-only rules such as .../jarvis-validate/references/validate.sh are
# deliberately not matched.
OWNED_RE='\.jarvis/projects/|jarvis-marketplace/jarvis/|/jarvis-[a-z]+/scripts/|/jarvis-\*\)$'

# --- Load current settings (missing file == empty object) ---
if [[ -f "$SETTINGS" ]]; then
  if ! CURRENT=$(jq -c . "$SETTINGS" 2>/dev/null); then
    echo "jarvis-permissions: $SETTINGS is not valid JSON; fix it by hand and re-run" >&2
    exit 3
  fi
else
  CURRENT='{}'
fi

# --- Compute the merged result ---
MERGED=$(printf '%s' "$CURRENT" | jq -c \
  --arg jdir "$JARVIS_DIR" --arg re "$OWNED_RE" --argjson canon "$CANON" '
  def owned: type == "string" and (test($re) or contains($jdir));
  .permissions = ((.permissions // {}) | .allow = ((.allow // []) | if type == "array" then . else [] end))
  | .permissions.allow |= (map(select(owned | not)) + $canon)
')

if [[ "$CHECK" == true ]]; then
  OWNED_NOW=$(printf '%s' "$CURRENT" | jq -c \
    --arg jdir "$JARVIS_DIR" --arg re "$OWNED_RE" '
    def owned: type == "string" and (test($re) or contains($jdir));
    [ (.permissions.allow // [] | if type == "array" then . else [] end)[] | select(owned) ] | sort')
  if [[ "$OWNED_NOW" == "$(printf '%s' "$CANON" | jq -c 'sort')" ]]; then
    echo "OK"; exit 0
  fi
  echo "STALE"; exit 1
fi

if [[ "$(printf '%s' "$CURRENT" | jq -S -c .)" == "$(printf '%s' "$MERGED" | jq -S -c .)" ]]; then
  echo "UNCHANGED"; exit 0
fi

mkdir -p "$(dirname "$SETTINGS")"
printf '%s' "$MERGED" | jq --indent 2 . > "$SETTINGS.tmp"
mv "$SETTINGS.tmp" "$SETTINGS"
echo "UPDATED"
