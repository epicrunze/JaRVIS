#!/usr/bin/env bash
# JaRVIS Permissions Check
# Verifies that documented permissions in platform-claude-code.md cover all JaRVIS operations.
#
# Usage:
#   bash test/permissions-check.sh          # Static analysis only
#   bash test/permissions-check.sh --e2e    # Static analysis + live e2e test

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLATFORM_DOC="$SCRIPT_DIR/skills/jarvis-init/references/platform-claude-code.md"
SKILLS_DIR="$SCRIPT_DIR/skills"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

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

warn() {
  WARN_COUNT=$((WARN_COUNT + 1))
  printf "  ${YELLOW}WARN${RESET} %s\n" "$1"
}

# ============================================================
# Part 1: Verify platform-claude-code.md exists and has permissions
# ============================================================
echo ""
printf "${BOLD}=== Part 1: Documented permissions ===${RESET}\n"

if [[ ! -f "$PLATFORM_DOC" ]]; then
  fail "platform-claude-code.md not found at $PLATFORM_DOC"
  exit 1
fi

# Extract permission patterns from the doc
# They're in the JSON code block under ## Permissions
declared_perms=$(sed -n '/^```json/,/^```/p' "$PLATFORM_DOC" | grep -o '"[A-Za-z]*([^"]*)"' | tr -d '"' | sort)

if [[ -z "$declared_perms" ]]; then
  fail "No permissions found in platform-claude-code.md"
  exit 1
fi

pass "platform-claude-code.md has permissions section"
echo "  Declared permissions:"
echo "$declared_perms" | while read -r perm; do
  echo "    - $perm"
done

# ============================================================
# Part 2: Scan SKILL.md files for tool invocations
# ============================================================
echo ""
printf "${BOLD}=== Part 2: Scan skills for tool invocations ===${RESET}\n"

# Categories of operations we expect permissions for:
# 1. Read/Write/Edit on JARVIS_DIR paths
# 2. Bash(cd $JARVIS_DIR && git ...)
# 3. Bash(bash .../validate.sh ...)
# 4. Bash(bash .../search.sh ...)
# 5. Bash(bash .../jarvis-init.sh ...)

found_read=false
found_write=false
found_edit=false
found_git=false
found_validate=false
found_search=false
found_init=false

for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
  [[ -f "$skill_file" ]] || continue
  skill_name=$(basename "$(dirname "$skill_file")")
  content=$(cat "$skill_file")

  # Check for Read operations on JARVIS_DIR
  if echo "$content" | grep -qiE 'Read.*\$JARVIS_DIR|Read.*IDENTITY\.md|Read.*GROWTH\.md|Read.*journal|Read.*memories'; then
    found_read=true
  fi

  # Check for Write operations on JARVIS_DIR
  if echo "$content" | grep -qiE 'Write.*\$JARVIS_DIR|Write.*IDENTITY\.md|Write.*GROWTH\.md|Rewrite.*\$JARVIS_DIR|write.*journal|write.*memories'; then
    found_write=true
  fi

  # Check for Edit operations on JARVIS_DIR
  if echo "$content" | grep -qiE 'Edit.*\$JARVIS_DIR|Edit.*IDENTITY\.md|Edit.*GROWTH\.md|edit.*journal|edit.*memories'; then
    found_edit=true
  fi

  # Check for git operations
  if echo "$content" | grep -qiE 'cd \$JARVIS_DIR && git|cd \$JARVIS_DIR.*git commit|git add.*git commit'; then
    found_git=true
  fi

  # Check for validate.sh
  if echo "$content" | grep -qiE 'validate\.sh|jarvis-validate'; then
    found_validate=true
  fi

  # Check for search.sh
  if echo "$content" | grep -qiE 'search\.sh|jarvis-search'; then
    found_search=true
  fi

  # Check for jarvis-init.sh
  if echo "$content" | grep -qiE 'jarvis-init\.sh'; then
    found_init=true
  fi
done

# Verify each operation type has a matching permission
check_perm() {
  local op_name="$1" found="$2" perm_pattern="$3"
  if [[ "$found" == "true" ]]; then
    if echo "$declared_perms" | grep -q "$perm_pattern"; then
      pass "$op_name operations covered by permission ($perm_pattern)"
    else
      fail "$op_name operations found in skills but NO matching permission" "Missing: $perm_pattern"
    fi
  else
    if echo "$declared_perms" | grep -q "$perm_pattern"; then
      warn "$op_name permission declared but no operations found in SKILL.md files"
    fi
  fi
}

check_perm "Read" "$found_read" "Read("
check_perm "Write" "$found_write" "Write("
check_perm "Edit" "$found_edit" "Edit("
check_perm "Git" "$found_git" "Bash(cd"
check_perm "validate.sh" "$found_validate" "validate.sh"
check_perm "search.sh" "$found_search" "search.sh"
check_perm "jarvis-init.sh" "$found_init" "jarvis-init.sh"

# ============================================================
# Part 3: Check for undocumented operations
# ============================================================
echo ""
printf "${BOLD}=== Part 3: Check for undocumented operations ===${RESET}\n"

# Look for any Bash commands in SKILL.md files that touch JARVIS_DIR
# but aren't covered by the known permission patterns
undocumented=0
for skill_file in "$SKILLS_DIR"/*/SKILL.md; do
  [[ -f "$skill_file" ]] || continue
  skill_name=$(basename "$(dirname "$skill_file")")

  # Look for Bash commands with JARVIS_DIR that aren't git, validate, search, or init
  while IFS= read -r line; do
    # Skip known patterns
    if echo "$line" | grep -qiE 'git (add|commit|log|diff|status)|validate\.sh|search\.sh|jarvis-init\.sh|resolve-dir\.sh|source'; then
      continue
    fi
    # Flag potential undocumented Bash operations
    if echo "$line" | grep -qiE 'bash.*\$JARVIS_DIR|bash.*jarvis'; then
      warn "Potentially undocumented Bash operation in $skill_name: $(echo "$line" | head -c 100)"
      undocumented=$((undocumented + 1))
    fi
  done < "$skill_file"
done

if [[ "$undocumented" -eq 0 ]]; then
  pass "No undocumented Bash operations found"
fi

# ============================================================
# Part 4: E2E validation (optional, requires --e2e flag and claude CLI)
# ============================================================
if [[ "${1:-}" == "--e2e" ]]; then
  echo ""
  printf "${BOLD}=== Part 4: E2E permissions validation ===${RESET}\n"

  if ! command -v claude &>/dev/null; then
    echo "claude CLI not found — skipping e2e permissions test."
  else
    printf "${YELLOW}WARNING: This will make live API calls to Claude.${RESET}\n"
    if [[ -t 0 ]]; then
      echo "Press Enter to continue or Ctrl-C to abort..."
      read -r
    fi

    # Setup temp project
    TEMP_PROJECT=$(mktemp -d)
    mkdir -p "$TEMP_PROJECT/.claude/skills"
    cp -r "$SKILLS_DIR/"* "$TEMP_PROJECT/.claude/skills/"

    SLUG=$(echo "$TEMP_PROJECT" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
    E2E_DATA_DIR="$HOME/.jarvis/projects/$SLUG"

    if [[ -d "$E2E_DATA_DIR" ]]; then
      echo "ERROR: Data dir already exists at $E2E_DATA_DIR — aborting."
      rm -rf "$TEMP_PROJECT"
      exit 1
    fi

    e2e_cleanup() {
      rm -rf "$TEMP_PROJECT"
      rm -rf "$E2E_DATA_DIR"
    }
    trap e2e_cleanup EXIT

    SKILLS_PATH="$TEMP_PROJECT/.claude/skills"

    # Build the exact --allowedTools list from documented permissions
    # Replace <slug> with actual slug, $SKILLS_DIR with actual path
    run_with_perms() {
      local prompt="$1"
      (cd "$TEMP_PROJECT" && timeout 120 claude -p \
        --allowedTools \
        "Read($HOME/.jarvis/projects/$SLUG/**)" \
        "Edit($HOME/.jarvis/projects/$SLUG/**)" \
        "Write($HOME/.jarvis/projects/$SLUG/**)" \
        "Bash(cd $HOME/.jarvis/projects/$SLUG && git *)" \
        "Bash(bash $SKILLS_PATH/jarvis-validate/scripts/validate.sh *)" \
        "Bash(bash $SKILLS_PATH/jarvis-search/scripts/search.sh *)" \
        "Bash(bash $SKILLS_PATH/jarvis-init/scripts/jarvis-init.sh *)" \
        -- "$prompt" 2>&1)
    }

    # Test 1: Init (needs broader perms for setup, so use wildcard for init only)
    set +e
    init_output=$( (cd "$TEMP_PROJECT" && timeout 120 claude -p \
      --allowedTools 'Bash(*)' 'Read(*)' 'Write(*)' 'Edit(*)' 'Glob(*)' 'Grep(*)' \
      -- "/jarvis-init" 2>&1) )
    init_rc=$?
    set -e

    if [[ $init_rc -eq 0 ]] && [[ -d "$E2E_DATA_DIR" ]]; then
      pass "E2E: Init succeeded"
    else
      fail "E2E: Init failed" "rc=$init_rc"
    fi

    # Test 2: Validate with restricted perms
    set +e
    val_output=$(run_with_perms "Run the validate script on my JaRVIS data directory using: bash $SKILLS_PATH/jarvis-validate/scripts/validate.sh $E2E_DATA_DIR")
    val_rc=$?
    set -e

    if [[ $val_rc -eq 0 ]]; then
      pass "E2E: Validate with documented permissions succeeded"
    else
      fail "E2E: Validate with documented permissions failed" "rc=$val_rc"
    fi

    # Test 3: Search with restricted perms
    set +e
    search_output=$(run_with_perms "Run the search script: bash $SKILLS_PATH/jarvis-search/scripts/search.sh --jarvis-dir $E2E_DATA_DIR --query test")
    search_rc=$?
    set -e

    if [[ $search_rc -eq 0 ]]; then
      pass "E2E: Search with documented permissions succeeded"
    else
      fail "E2E: Search with documented permissions failed" "rc=$search_rc"
    fi

    echo ""
    printf "${YELLOW}Note: Full workflow e2e (reflect → identity) requires broader permissions for the agent's own tool use.${RESET}\n"
    printf "${YELLOW}The static analysis above covers all SKILL.md-documented operations.${RESET}\n"
  fi
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "========================================"
TOTAL=$((PASS_COUNT + FAIL_COUNT))
printf "${BOLD}Results:${RESET} ${GREEN}%d passed${RESET}, ${RED}%d failed${RESET}, ${YELLOW}%d warnings${RESET} (%d total)\n" \
  "$PASS_COUNT" "$FAIL_COUNT" "$WARN_COUNT" "$TOTAL"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
else
  exit 0
fi
