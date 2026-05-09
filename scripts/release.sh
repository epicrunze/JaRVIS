#!/usr/bin/env bash
# Bumps the JaRVIS plugin version in both .claude-plugin/plugin.json and
# .claude-plugin/marketplace.json, commits the change, and creates a vX.Y.Z tag.
# Does NOT push — review with `git show` then `git push origin main --tags`.
#
# Usage:
#   scripts/release.sh patch         # 0.1.0 -> 0.1.1
#   scripts/release.sh minor         # 0.1.0 -> 0.2.0
#   scripts/release.sh major         # 0.1.0 -> 1.0.0
#   scripts/release.sh 0.3.5         # explicit version

set -euo pipefail

if ! command -v jq >/dev/null 2>&1; then
  echo "release.sh requires jq" >&2
  exit 1
fi

ROOT=$(git rev-parse --show-toplevel)
PLUGIN_JSON="$ROOT/.claude-plugin/plugin.json"
MARKET_JSON="$ROOT/.claude-plugin/marketplace.json"

if [[ ! -f "$PLUGIN_JSON" || ! -f "$MARKET_JSON" ]]; then
  echo "Could not find plugin.json or marketplace.json under $ROOT/.claude-plugin/" >&2
  exit 1
fi

usage() {
  sed -n '2,11p' "$0"
  exit 1
}

arg="${1:-}"
[[ -z "$arg" ]] && usage

current=$(jq -r '.version' "$PLUGIN_JSON")
m_current=$(jq -r '.plugins[0].version' "$MARKET_JSON")
if [[ "$current" != "$m_current" ]]; then
  echo "Refusing to bump: plugin.json=$current marketplace.json=$m_current — fix the drift first." >&2
  exit 1
fi

semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'
case "$arg" in
  patch|minor|major)
    if [[ ! "$current" =~ $semver_re ]]; then
      echo "Current version '$current' is not X.Y.Z; bump $arg requires semver." >&2
      exit 1
    fi
    IFS='.' read -r maj min pat <<< "$current"
    case "$arg" in
      patch) new="${maj}.${min}.$((pat+1))" ;;
      minor) new="${maj}.$((min+1)).0" ;;
      major) new="$((maj+1)).0.0" ;;
    esac
    ;;
  -h|--help) usage ;;
  *)
    if [[ ! "$arg" =~ $semver_re ]]; then
      echo "Invalid version '$arg' — expected X.Y.Z or patch|minor|major." >&2
      exit 1
    fi
    new="$arg"
    ;;
esac

if [[ "$new" == "$current" ]]; then
  echo "New version equals current ($current). Nothing to do." >&2
  exit 1
fi

if ! git diff --quiet -- "$PLUGIN_JSON" "$MARKET_JSON"; then
  echo "Refusing to bump: $PLUGIN_JSON or $MARKET_JSON has uncommitted changes." >&2
  exit 1
fi

if git rev-parse "v$new" >/dev/null 2>&1; then
  echo "Tag v$new already exists." >&2
  exit 1
fi

echo "Bumping $current -> $new"

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
jq --arg v "$new" '.version = $v' "$PLUGIN_JSON" > "$tmp" && mv "$tmp" "$PLUGIN_JSON"
tmp=$(mktemp)
jq --arg v "$new" '.plugins[0].version = $v' "$MARKET_JSON" > "$tmp" && mv "$tmp" "$MARKET_JSON"

p_after=$(jq -r '.version' "$PLUGIN_JSON")
m_after=$(jq -r '.plugins[0].version' "$MARKET_JSON")
if [[ "$p_after" != "$new" || "$m_after" != "$new" ]]; then
  echo "Post-write check failed: plugin.json=$p_after marketplace.json=$m_after" >&2
  exit 1
fi

git add "$PLUGIN_JSON" "$MARKET_JSON"
git commit -m "release: v$new"
git tag "v$new"

echo
echo "Tagged v$new locally. To publish:"
echo "  git push origin main --tags"
