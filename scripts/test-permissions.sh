#!/usr/bin/env bash
# Fixture-driven tests for skills/jarvis-init/scripts/jarvis-permissions.sh.
#
# Each fixture builds a temp project dir (optionally with a pre-existing
# .claude/settings.local.json), runs the script, and asserts on the resulting
# permissions.allow array, the printed status word, and the exit code.
#
# The canonical rule set the script must produce (plugin install):
#   Read(~/.jarvis/projects/<slug>/**)
#   Edit(~/.jarvis/projects/<slug>/**)
#   Bash(git -C <abs-jarvis-dir> *)
#   Bash(bash <dirname(plugin-root)>/*)

set -u

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$REPO/skills/jarvis-init/scripts/jarvis-permissions.sh"
command -v jq >/dev/null || { echo "FATAL: jq required" >&2; exit 2; }

WORK=$(mktemp -d -t jarvis-perms-test.XXXXXX)
trap 'rm -rf "$WORK"' EXIT
FAIL=0
TOTAL=0

# Fake install layout: a plugin cache with a version dir, and a copied-skills dir.
PLUGIN_ROOT="$WORK/plugins/cache/jarvis-marketplace/jarvis/0.1.6"
PLUGIN_BASE="$WORK/plugins/cache/jarvis-marketplace/jarvis"
SKILLS_DIR="$WORK/copied/.claude/skills"
mkdir -p "$PLUGIN_ROOT/skills" "$SKILLS_DIR"

SLUG="data-user-projects-demo"
JDIR="$WORK/home/.jarvis/projects/$SLUG"
mkdir -p "$JDIR"

# Expected canonical rules (plugin mode)
EXP_READ="Read(~/.jarvis/projects/$SLUG/**)"
EXP_EDIT="Edit(~/.jarvis/projects/$SLUG/**)"
EXP_GIT="Bash(git -C $JDIR *)"
EXP_BASH_PLUGIN="Bash(bash $PLUGIN_BASE/*)"
EXP_BASH_SKILLS="Bash(bash $SKILLS_DIR/jarvis-*)"

# mk_project <n> [settings-json]
# Creates $WORK/proj-<n>; if json is given, writes it to .claude/settings.local.json.
mk_project() {
  local n=$1 json=${2:-}
  local dir="$WORK/proj-$n"
  mkdir -p "$dir"
  if [[ -n "$json" ]]; then
    mkdir -p "$dir/.claude"
    printf '%s\n' "$json" > "$dir/.claude/settings.local.json"
  fi
  echo "$dir"
}

# Old-style settings as produced by the pre-fix template (plus unrelated rules + hooks).
OLD_SETTINGS=$(cat <<EOF
{
  "permissions": {
    "allow": [
      "WebSearch",
      "Read(~/.jarvis/projects/$SLUG/**)",
      "Edit(~/.jarvis/projects/$SLUG/**)",
      "Write(~/.jarvis/projects/$SLUG/**)",
      "Bash(cd ~/.jarvis/projects/$SLUG && git *)",
      "Bash(bash $PLUGIN_BASE/0.1.3/skills/jarvis-validate/scripts/validate.sh *)",
      "Bash(bash $PLUGIN_BASE/0.1.3/skills/jarvis-search/scripts/search.sh *)",
      "Bash(bash $PLUGIN_BASE/0.1.3/skills/jarvis-init/scripts/jarvis-init.sh *)",
      "Bash(find:*)",
      "Bash(bash /dev/src/JaRVIS/skills/jarvis-validate/references/validate.sh .jarvis)"
    ]
  },
  "hooks": {
    "Stop": [ { "matcher": "", "hooks": [ { "type": "command", "command": "echo hi" } ] } ]
  }
}
EOF
)

CANON_SETTINGS=$(jq -n \
  --arg r "$EXP_READ" --arg e "$EXP_EDIT" --arg g "$EXP_GIT" --arg b "$EXP_BASH_PLUGIN" \
  '{permissions:{allow:["WebSearch",$r,$e,$g,$b]}}')

# run_script <project-dir> [extra args...]
# Default args: plugin mode. Captures stdout/stderr/rc into $WORK/last.*
run_script() {
  local proj=$1; shift
  HOME="$WORK/home" bash "$SCRIPT" --project-dir "$proj" --jarvis-dir "$JDIR" "$@" \
    >"$WORK/last.out" 2>"$WORK/last.err"
  echo $? > "$WORK/last.rc"
}

pass() { TOTAL=$((TOTAL+1)); printf 'PASS  %s\n' "$1"; }
fail() {
  TOTAL=$((TOTAL+1)); FAIL=$((FAIL+1))
  printf 'FAIL  %s\n  %s\n  rc=%s stdout=%s\n  stderr=%s\n' \
    "$1" "$2" "$(cat "$WORK/last.rc")" "$(head -c 200 "$WORK/last.out")" "$(head -c 300 "$WORK/last.err")" >&2
}

# expect_rc <label> <want_rc>
expect_rc() {
  local rc; rc=$(cat "$WORK/last.rc")
  [[ "$rc" == "$2" ]] && pass "$1" || fail "$1" "exit=$rc (want $2)"
}
# expect_stdout <label> <exact-line>
expect_stdout() {
  local out; out=$(cat "$WORK/last.out")
  [[ "$out" == "$2" ]] && pass "$1" || fail "$1" "stdout=$(printf '%q' "$out") (want $(printf '%q' "$2"))"
}
# expect_allow <label> <settings-file> <expected-json-array>
expect_allow() {
  local got
  got=$(jq -c '.permissions.allow' "$2" 2>/dev/null)
  if [[ "$got" == "$3" ]]; then pass "$1"; else fail "$1" "allow=$got
  want=$3"; fi
}

# ────────────────────────── fixtures ──────────────────────────

# fx1: no settings file → created with exactly the 4 canonical rules.
P=$(mk_project 1)
run_script "$P" --plugin-root "$PLUGIN_ROOT"
expect_rc "fx1 no settings: exit 0" 0
expect_stdout "fx1 no settings: prints UPDATED" "UPDATED"
expect_allow "fx1 no settings: 4 canonical rules" "$P/.claude/settings.local.json" \
  "$(jq -cn --arg r "$EXP_READ" --arg e "$EXP_EDIT" --arg g "$EXP_GIT" --arg b "$EXP_BASH_PLUGIN" '[$r,$e,$g,$b]')"

# fx2: old rule set → stale JaRVIS rules removed, canonical appended,
# unrelated rules kept in order, hooks untouched.
P=$(mk_project 2 "$OLD_SETTINGS")
run_script "$P" --plugin-root "$PLUGIN_ROOT"
expect_rc "fx2 old rules: exit 0" 0
expect_stdout "fx2 old rules: prints UPDATED" "UPDATED"
expect_allow "fx2 old rules: replaced, unrelated kept in order" "$P/.claude/settings.local.json" \
  "$(jq -cn --arg r "$EXP_READ" --arg e "$EXP_EDIT" --arg g "$EXP_GIT" --arg b "$EXP_BASH_PLUGIN" \
     '["WebSearch","Bash(find:*)","Bash(bash /dev/src/JaRVIS/skills/jarvis-validate/references/validate.sh .jarvis)",$r,$e,$g,$b]')"
TOTAL=$((TOTAL+1))
if [[ "$(jq -c '.hooks' "$P/.claude/settings.local.json")" == "$(printf '%s' "$OLD_SETTINGS" | jq -c '.hooks')" ]]; then
  printf 'PASS  %s\n' "fx2 old rules: hooks block preserved"
else
  FAIL=$((FAIL+1)); printf 'FAIL  fx2 old rules: hooks block changed\n' >&2
fi

# fx3: already canonical → UNCHANGED and file byte-identical.
P=$(mk_project 3 "$CANON_SETTINGS")
before=$(cat "$P/.claude/settings.local.json")
run_script "$P" --plugin-root "$PLUGIN_ROOT"
expect_rc "fx3 canonical: exit 0" 0
expect_stdout "fx3 canonical: prints UNCHANGED" "UNCHANGED"
TOTAL=$((TOTAL+1))
if [[ "$(cat "$P/.claude/settings.local.json")" == "$before" ]]; then
  printf 'PASS  %s\n' "fx3 canonical: file byte-identical"
else
  FAIL=$((FAIL+1)); printf 'FAIL  fx3 canonical: file was rewritten\n' >&2
fi

# fx4: --check mode never writes; STALE(1) on old rules, OK(0) on canonical.
P=$(mk_project 4 "$OLD_SETTINGS")
before=$(cat "$P/.claude/settings.local.json")
run_script "$P" --plugin-root "$PLUGIN_ROOT" --check
expect_rc "fx4 check stale: exit 1" 1
expect_stdout "fx4 check stale: prints STALE" "STALE"
TOTAL=$((TOTAL+1))
if [[ "$(cat "$P/.claude/settings.local.json")" == "$before" ]]; then
  printf 'PASS  %s\n' "fx4 check stale: file untouched"
else
  FAIL=$((FAIL+1)); printf 'FAIL  fx4 check stale: file was modified\n' >&2
fi
P=$(mk_project 5 "$CANON_SETTINGS")
run_script "$P" --plugin-root "$PLUGIN_ROOT" --check
expect_rc "fx4 check canonical: exit 0" 0
expect_stdout "fx4 check canonical: prints OK" "OK"
# --check with no settings file at all is also STALE (nothing granted yet).
P=$(mk_project 6)
run_script "$P" --plugin-root "$PLUGIN_ROOT" --check
expect_rc "fx4 check no file: exit 1" 1
expect_stdout "fx4 check no file: prints STALE" "STALE"

# fx5: copied-install mode (--skills-dir) → Bash(bash <SKILLS_DIR>/jarvis-*).
P=$(mk_project 7)
run_script "$P" --skills-dir "$SKILLS_DIR"
expect_rc "fx5 skills-dir: exit 0" 0
expect_allow "fx5 skills-dir: rule uses jarvis- prefix" "$P/.claude/settings.local.json" \
  "$(jq -cn --arg r "$EXP_READ" --arg e "$EXP_EDIT" --arg g "$EXP_GIT" --arg b "$EXP_BASH_SKILLS" '[$r,$e,$g,$b]')"

# fx6: invalid JSON → non-zero exit, file untouched, message on stderr.
P=$(mk_project 8 '{ "permissions": { "allow": [ ')
before=$(cat "$P/.claude/settings.local.json")
run_script "$P" --plugin-root "$PLUGIN_ROOT"
TOTAL=$((TOTAL+1))
rc=$(cat "$WORK/last.rc")
if [[ "$rc" != "0" ]] && [[ -s "$WORK/last.err" ]] && [[ "$(cat "$P/.claude/settings.local.json")" == "$before" ]]; then
  printf 'PASS  %s\n' "fx6 invalid JSON: non-zero, stderr message, file untouched"
else
  FAIL=$((FAIL+1)); printf 'FAIL  fx6 invalid JSON: rc=%s stderr=%s\n' "$rc" "$(head -c 200 "$WORK/last.err")" >&2
fi

# fx7: missing mode flag (neither --plugin-root nor --skills-dir) → usage error, no write.
P=$(mk_project 9)
run_script "$P"
TOTAL=$((TOTAL+1))
if [[ "$(cat "$WORK/last.rc")" != "0" ]] && [[ ! -e "$P/.claude/settings.local.json" ]]; then
  printf 'PASS  %s\n' "fx7 missing mode flag: usage error, nothing written"
else
  FAIL=$((FAIL+1)); printf 'FAIL  fx7 missing mode flag: rc=%s\n' "$(cat "$WORK/last.rc")" >&2
fi

# fx8: data dir outside $HOME (JARVIS_DIR override) → // absolute-path rules.
P=$(mk_project 10)
OUT_JDIR="$WORK/srv/jarvis-data"
mkdir -p "$OUT_JDIR"
HOME="$WORK/home" bash "$SCRIPT" --project-dir "$P" --jarvis-dir "$OUT_JDIR" --plugin-root "$PLUGIN_ROOT" \
  >"$WORK/last.out" 2>"$WORK/last.err"; echo $? > "$WORK/last.rc"
expect_rc "fx8 outside-home: exit 0" 0
expect_allow "fx8 outside-home: // path rules" "$P/.claude/settings.local.json" \
  "$(jq -cn --arg r "Read(/$OUT_JDIR/**)" --arg e "Edit(/$OUT_JDIR/**)" --arg g "Bash(git -C $OUT_JDIR *)" --arg b "$EXP_BASH_PLUGIN" '[$r,$e,$g,$b]')"
# Re-running on the same file must be UNCHANGED (no duplicate accumulation).
HOME="$WORK/home" bash "$SCRIPT" --project-dir "$P" --jarvis-dir "$OUT_JDIR" --plugin-root "$PLUGIN_ROOT" \
  >"$WORK/last.out" 2>"$WORK/last.err"; echo $? > "$WORK/last.rc"
expect_stdout "fx8 outside-home: rerun is UNCHANGED" "UNCHANGED"

# fx9: copied-install rerun must not duplicate the jarvis-* prefix rule.
P=$(mk_project 11)
run_script "$P" --skills-dir "$SKILLS_DIR"
run_script "$P" --skills-dir "$SKILLS_DIR"
expect_stdout "fx9 skills-dir rerun: UNCHANGED" "UNCHANGED"
expect_allow "fx9 skills-dir rerun: no duplicates" "$P/.claude/settings.local.json" \
  "$(jq -cn --arg r "$EXP_READ" --arg e "$EXP_EDIT" --arg g "$EXP_GIT" --arg b "$EXP_BASH_SKILLS" '[$r,$e,$g,$b]')"

echo
echo "──── $((TOTAL-FAIL))/$TOTAL passed ────"
exit "$FAIL"
