#!/usr/bin/env bash
# JaRVIS End-to-End Tests
# Runs a full JaRVIS lifecycle using a live Claude Code instance.
# Requires: claude CLI, API access
# Uses: claude -p (non-interactive print mode), each call is a fresh session.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
VALIDATE="$SCRIPT_DIR/skills/jarvis-validate/scripts/validate.sh"
SEARCH="$SCRIPT_DIR/skills/jarvis-search/scripts/search.sh"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf "  ${GREEN}PASS${RESET} %s\n" "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf "  ${RED}FAIL${RESET} %s\n" "$1"
  if [[ -n "${2:-}" ]]; then
    printf "       %s\n" "$2"
  fi
}

skip() {
  SKIP_COUNT=$((SKIP_COUNT + 1))
  printf "  ${YELLOW}SKIP${RESET} %s\n" "$1"
}

# --- Prerequisites ---
if ! command -v claude &>/dev/null; then
  echo "claude CLI not found — skipping e2e tests."
  exit 0
fi

echo ""
printf "${BOLD}JaRVIS End-to-End Tests${RESET}\n"
printf "${YELLOW}WARNING: This will make live API calls to Claude.${RESET}\n"
if [[ -t 0 ]]; then
  echo "Press Enter to continue or Ctrl-C to abort..."
  read -r
fi

# --- Setup temp project ---
TEMP_PROJECT=$(mktemp -d)
mkdir -p "$TEMP_PROJECT/.claude/skills"
cp -r "$SCRIPT_DIR/skills/"* "$TEMP_PROJECT/.claude/skills/"

# Derive expected slug
SLUG=$(echo "$TEMP_PROJECT" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
DATA_DIR="$HOME/.jarvis/projects/$SLUG"

# Safety check
if [[ -d "$DATA_DIR" ]]; then
  echo "ERROR: Data dir already exists at $DATA_DIR — aborting for safety."
  rm -rf "$TEMP_PROJECT"
  exit 1
fi

cleanup() {
  rm -rf "$TEMP_PROJECT"
  rm -rf "$DATA_DIR"
}
trap cleanup EXIT

run_claude() {
  local prompt="$1"
  (cd "$TEMP_PROJECT" && timeout 120 claude -p \
    --allowedTools 'Bash(*)' 'Read(*)' 'Write(*)' 'Edit(*)' 'Glob(*)' 'Grep(*)' \
    -- "$prompt" 2>&1)
}

# ============================================================
# Step 1: /jarvis-init
# ============================================================
echo ""
printf "${BOLD}=== Step 1: /jarvis-init ===${RESET}\n"

set +e
output=$(run_claude "/jarvis-init")
init_rc=$?
set -e

if [[ $init_rc -ne 0 ]]; then
  fail "jarvis-init exited with code $init_rc"
  echo "Output:"
  echo "$output" | tail -20
  echo ""
  echo "Init failed — skipping remaining tests."
  echo ""
  printf "${BOLD}Results:${RESET} ${GREEN}%d passed${RESET}, ${RED}%d failed${RESET}, ${YELLOW}%d skipped${RESET}\n" \
    "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT"
  exit 1
fi

if [[ -d "$DATA_DIR" ]]; then
  pass "Data directory created"
else
  fail "Data directory not created at $DATA_DIR"
  echo "Init did not create expected directory — skipping remaining tests."
  exit 1
fi

if [[ -f "$DATA_DIR/IDENTITY.md" ]]; then
  pass "IDENTITY.md exists"
  if grep -q 'version: 0\.0\|Version.*0\.0' "$DATA_DIR/IDENTITY.md"; then
    pass "IDENTITY.md has version 0.0"
  else
    fail "IDENTITY.md does not have version 0.0"
  fi
else
  fail "IDENTITY.md not found"
fi

if [[ -f "$DATA_DIR/GROWTH.md" ]]; then
  pass "GROWTH.md exists"
else
  fail "GROWTH.md not found"
fi

if [[ -d "$DATA_DIR/memories" ]]; then
  pass "memories/ directory exists"
else
  fail "memories/ directory not found"
fi

if [[ -d "$DATA_DIR/journal" ]]; then
  pass "journal/ directory exists"
else
  fail "journal/ directory not found"
fi

# Check hook setup
if [[ -f "$TEMP_PROJECT/.claude/settings.local.json" ]]; then
  if grep -q "jarvis-session-start" "$TEMP_PROJECT/.claude/settings.local.json"; then
    pass "settings.local.json has SessionStart hook entry"
  else
    fail "settings.local.json missing SessionStart hook entry"
  fi
  if grep -q "jarvis-stop" "$TEMP_PROJECT/.claude/settings.local.json"; then
    pass "settings.local.json has Stop hook entry"
  else
    fail "settings.local.json missing Stop hook entry"
  fi
else
  fail "settings.local.json not found"
fi

# ============================================================
# Step 2: /jarvis-reload
# ============================================================
echo ""
printf "${BOLD}=== Step 2: /jarvis-reload ===${RESET}\n"

set +e
output=$(run_claude "/jarvis-reload")
reload_rc=$?
set -e

if [[ $reload_rc -eq 0 ]]; then
  pass "jarvis-reload completed without error"
else
  fail "jarvis-reload exited with code $reload_rc"
fi

# ============================================================
# Step 3: Create file + /jarvis-reflect
# ============================================================
echo ""
printf "${BOLD}=== Step 3: Create file + /jarvis-reflect ===${RESET}\n"

# First create a file
set +e
output=$(run_claude "Create a file called hello.txt with the content 'Hello from JaRVIS e2e test'")
set -e

if [[ -f "$TEMP_PROJECT/hello.txt" ]]; then
  pass "hello.txt created"
else
  fail "hello.txt not created"
fi

# Now reflect
set +e
output=$(run_claude "Run /jarvis-reflect. Reflect on creating hello.txt. The task is complete. Use tags [testing, e2e]. task_type: feature. This was a simple file creation task for end-to-end testing.")
reflect_rc=$?
set -e

if [[ $reflect_rc -eq 0 ]]; then
  pass "jarvis-reflect completed without error"
else
  fail "jarvis-reflect exited with code $reflect_rc" "Output: $(echo "$output" | tail -5)"
fi

# Check journal entry was created
journal_count=$(ls -1 "$DATA_DIR/journal/"*.md 2>/dev/null | wc -l)
if [[ "$journal_count" -ge 1 ]]; then
  pass "Journal entry created ($journal_count file(s))"

  newest_journal=$(ls -1t "$DATA_DIR/journal/"*.md 2>/dev/null | head -1)
  if grep -q '## Task Summary' "$newest_journal"; then
    pass "Journal has ## Task Summary section"
  else
    fail "Journal missing ## Task Summary"
  fi

  if head -1 "$newest_journal" | grep -q '^---$'; then
    pass "Journal has YAML frontmatter"
  else
    fail "Journal missing YAML frontmatter"
  fi
else
  fail "No journal entry created"
fi

# ============================================================
# Step 4: /jarvis-validate
# ============================================================
echo ""
printf "${BOLD}=== Step 4: /jarvis-validate ===${RESET}\n"

set +e
output=$(bash "$VALIDATE" "$DATA_DIR" 2>&1)
validate_rc=$?
set -e

if [[ $validate_rc -eq 0 ]]; then
  pass "validate.sh passes on data dir"
else
  fail "validate.sh failed" "Output: $(echo "$output" | tail -10)"
fi

# ============================================================
# Step 5: Re-init idempotency
# ============================================================
echo ""
printf "${BOLD}=== Step 5: Re-init idempotency ===${RESET}\n"

# Capture state before re-init
identity_before=$(cat "$DATA_DIR/IDENTITY.md")
journal_count_before=$(ls -1 "$DATA_DIR/journal/"*.md 2>/dev/null | wc -l)

set +e
output=$(run_claude "/jarvis-init")
reinit_rc=$?
set -e

if [[ $reinit_rc -eq 0 ]]; then
  pass "Re-init completed without error"
else
  fail "Re-init exited with code $reinit_rc"
fi

# Verify data was not destroyed
if [[ -f "$DATA_DIR/IDENTITY.md" ]]; then
  pass "IDENTITY.md still exists after re-init"
else
  fail "IDENTITY.md was deleted by re-init"
fi

journal_count_after=$(ls -1 "$DATA_DIR/journal/"*.md 2>/dev/null | wc -l)
if [[ "$journal_count_after" -ge "$journal_count_before" ]]; then
  pass "Journal entries preserved after re-init ($journal_count_after >= $journal_count_before)"
else
  fail "Journal entries lost after re-init ($journal_count_after < $journal_count_before)"
fi

# ============================================================
# Step 6: /jarvis-toggle (disable + re-enable)
# ============================================================
echo ""
printf "${BOLD}=== Step 6: /jarvis-toggle (disable) ===${RESET}\n"

# First, ensure CLAUDE.md has a ## JaRVIS section (init should have created it)
if grep -q '## JaRVIS' "$TEMP_PROJECT/CLAUDE.md" 2>/dev/null; then
  pass "CLAUDE.md has ## JaRVIS section before toggle"
else
  skip "CLAUDE.md has no ## JaRVIS section — toggle test may be incomplete"
fi

# Toggle OFF
set +e
output=$(run_claude "/jarvis-toggle")
toggle_off_rc=$?
set -e

if [[ $toggle_off_rc -eq 0 ]]; then
  pass "jarvis-toggle (disable) completed without error"
else
  fail "jarvis-toggle (disable) exited with code $toggle_off_rc"
fi

if [[ -f "$DATA_DIR/.jarvis-disabled" ]]; then
  pass ".jarvis-disabled marker created"
else
  fail ".jarvis-disabled marker not created"
fi

if grep -q '## JaRVIS' "$TEMP_PROJECT/CLAUDE.md" 2>/dev/null; then
  fail "## JaRVIS section still in CLAUDE.md after disable"
else
  pass "## JaRVIS section removed from CLAUDE.md"
fi

# Verify session-start hook produces no identity when disabled
set +e
hook_output=$(echo '{"session_id": "toggle-test"}' | JARVIS_DIR="$DATA_DIR" bash "$SCRIPT_DIR/skills/jarvis-reload/scripts/jarvis-session-start.sh" 2>&1)
set -e
if echo "$hook_output" | grep -qi "TestBot\|identity"; then
  fail "Session-start hook still loads identity when disabled"
else
  pass "Session-start hook skips identity when disabled"
fi

# Toggle ON
echo ""
printf "${BOLD}=== Step 6b: /jarvis-toggle (re-enable) ===${RESET}\n"

set +e
output=$(run_claude "/jarvis-toggle")
toggle_on_rc=$?
set -e

if [[ $toggle_on_rc -eq 0 ]]; then
  pass "jarvis-toggle (re-enable) completed without error"
else
  fail "jarvis-toggle (re-enable) exited with code $toggle_on_rc"
fi

if [[ -f "$DATA_DIR/.jarvis-disabled" ]]; then
  fail ".jarvis-disabled marker still exists after re-enable"
else
  pass ".jarvis-disabled marker removed"
fi

if grep -q '## JaRVIS' "$TEMP_PROJECT/CLAUDE.md" 2>/dev/null; then
  pass "## JaRVIS section restored in CLAUDE.md"
else
  fail "## JaRVIS section not restored in CLAUDE.md"
fi

# ============================================================
# Step 7: /jarvis-identity
# ============================================================
echo ""
printf "${BOLD}=== Step 7: /jarvis-identity ===${RESET}\n"

# Capture version before
version_before=$(grep -o 'Version.*[0-9]\+\.[0-9]\+' "$DATA_DIR/IDENTITY.md" 2>/dev/null || echo "0.0")

set +e
output=$(run_claude "/jarvis-identity")
identity_rc=$?
set -e

if [[ $identity_rc -eq 0 ]]; then
  pass "jarvis-identity completed without error"
else
  fail "jarvis-identity exited with code $identity_rc" "Output: $(echo "$output" | tail -5)"
fi

# Verify IDENTITY.md version incremented
if grep -q 'Version.*0\.1\|version.*0\.1' "$DATA_DIR/IDENTITY.md" 2>/dev/null; then
  pass "IDENTITY.md version incremented to 0.1"
else
  current_version=$(grep -o 'Version.*[0-9]\+\.[0-9]\+' "$DATA_DIR/IDENTITY.md" 2>/dev/null || echo "unknown")
  fail "IDENTITY.md version not 0.1" "Current: $current_version"
fi

# Verify GROWTH.md has a new row
today=$(date +%Y-%m-%d)
growth_rows=$(tail -n +5 "$DATA_DIR/GROWTH.md" 2>/dev/null | grep -c '^|' || true)
if [[ "$growth_rows" -ge 1 ]]; then
  pass "GROWTH.md has new row(s) ($growth_rows data row(s))"
else
  fail "GROWTH.md has no data rows"
fi

# Verify git log shows identity commit
set +e
git_log=$(cd "$DATA_DIR" && git log --oneline -5 2>&1)
set -e
if echo "$git_log" | grep -qi "identity"; then
  pass "Git log shows identity commit"
else
  fail "Git log missing identity commit" "Log: $git_log"
fi

# ============================================================
# Step 8: /jarvis-search
# ============================================================
echo ""
printf "${BOLD}=== Step 8: /jarvis-search ===${RESET}\n"

set +e
output=$(bash "$SEARCH" --jarvis-dir "$DATA_DIR" --query "hello" 2>&1)
search_rc=$?
set -e

if echo "$output" | grep -qi "match"; then
  if echo "$output" | grep -qi "No matches"; then
    fail "search --query hello found no matches"
  else
    pass "search --query hello found matches"
  fi
else
  fail "search output unexpected" "Output: $output"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "========================================"
TOTAL=$((PASS_COUNT + FAIL_COUNT + SKIP_COUNT))
printf "${BOLD}Results:${RESET} ${GREEN}%d passed${RESET}, ${RED}%d failed${RESET}, ${YELLOW}%d skipped${RESET} (%d total)\n" \
  "$PASS_COUNT" "$FAIL_COUNT" "$SKIP_COUNT" "$TOTAL"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
