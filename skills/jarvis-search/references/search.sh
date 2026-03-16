#!/usr/bin/env bash
# JaRVIS Search — search across JaRVIS artifacts
# Usage: search.sh [OPTIONS] [--query KEYWORD]
#   --type journal|memory|identity|growth   (default: all)
#   --from YYYY-MM-DD                       date range start
#   --to YYYY-MM-DD                         date range end
#   --tag TAG                               frontmatter tag filter
#   --task-type TYPE                        frontmatter task_type filter
#   --section "Section Name"                search within specific section
#   --query KEYWORD                         keyword/phrase search

set -euo pipefail

# --- Defaults ---
if [ -n "${JARVIS_DIR:-}" ]; then
  : # env var already set
else
  _project_dir="${CLAUDE_PROJECT_DIR:-$(pwd)}"
  _slug=$(echo "$_project_dir" | sed 's|^/||' | tr ' /' '--' | tr '[:upper:]' '[:lower:]')
  JARVIS_DIR="$HOME/.jarvis/projects/$_slug"
fi
SEARCH_TYPE="all"
DATE_FROM=""
DATE_TO=""
TAG_FILTER=""
TASK_TYPE_FILTER=""
SECTION_FILTER=""
QUERY=""

# --- Color support ---
if [[ -t 1 ]]; then
  CYAN='\033[0;36m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BOLD='\033[1m'
  RESET='\033[0m'
else
  CYAN=''
  GREEN=''
  YELLOW=''
  BOLD=''
  RESET=''
fi

# --- Argument parsing ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    --type)
      SEARCH_TYPE="$2"
      shift 2
      ;;
    --from)
      DATE_FROM="$2"
      shift 2
      ;;
    --to)
      DATE_TO="$2"
      shift 2
      ;;
    --tag)
      TAG_FILTER="$2"
      shift 2
      ;;
    --task-type)
      TASK_TYPE_FILTER="$2"
      shift 2
      ;;
    --section)
      SECTION_FILTER="$2"
      shift 2
      ;;
    --query)
      QUERY="$2"
      shift 2
      ;;
    --jarvis-dir)
      JARVIS_DIR="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: search.sh [OPTIONS] [--query KEYWORD]"
      echo ""
      echo "Options:"
      echo "  --type journal|memory|identity|growth  Filter by artifact type (default: all)"
      echo "  --from YYYY-MM-DD                      Date range start"
      echo "  --to YYYY-MM-DD                        Date range end"
      echo "  --tag TAG                              Filter by frontmatter tag"
      echo "  --task-type TYPE                       Filter by frontmatter task_type"
      echo "  --section \"Section Name\"               Search within specific section"
      echo "  --query KEYWORD                        Keyword/phrase search"
      echo "  --jarvis-dir PATH                      Path to JaRVIS data dir (default: ~/.jarvis/projects/<slug>)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 1
      ;;
  esac
done

# --- Validate JaRVIS data dir ---
if [[ ! -d "$JARVIS_DIR" ]]; then
  echo "Error: JaRVIS data directory not found at $JARVIS_DIR" >&2
  exit 1
fi

MATCH_COUNT=0

# --- Helper: extract frontmatter field ---
get_frontmatter_field() {
  local file="$1"
  local field="$2"
  local first_line
  first_line=$(head -1 "$file")
  if [[ "$first_line" != "---" ]]; then
    echo ""
    return
  fi
  awk -v field="$field" '
    NR==1 && /^---$/ { found=1; next }
    found && /^---$/ { exit }
    found && $0 ~ "^"field":" {
      sub("^"field":[ ]*", "")
      print
    }
  ' "$file"
}

# --- Helper: check if file has frontmatter tag ---
has_tag() {
  local file="$1"
  local tag="$2"
  local tags_line
  tags_line=$(get_frontmatter_field "$file" "tags")
  if [[ -z "$tags_line" ]]; then
    return 1
  fi
  # Case-insensitive match within the tags list
  echo "$tags_line" | grep -qi "$tag"
}

# --- Helper: check if file has task_type ---
has_task_type() {
  local file="$1"
  local task_type="$2"
  local type_line
  type_line=$(get_frontmatter_field "$file" "task_type")
  if [[ -z "$type_line" ]]; then
    return 1
  fi
  echo "$type_line" | grep -qi "^${task_type}$"
}

# --- Helper: extract section content ---
extract_section() {
  local file="$1"
  local section="$2"
  awk -v sect="$section" '
    BEGIN { IGNORECASE=1 }
    $0 ~ "^## "sect { found=1; next }
    /^## / { found=0 }
    found { print }
  ' "$file"
}

# --- Helper: extract date from journal filename ---
filename_date() {
  local basename_file
  basename_file=$(basename "$1" .md)
  # Extract YYYY-MM-DD from YYYY-MM-DD-HH-MM
  echo "$basename_file" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || echo ""
}

# --- Helper: print a match ---
print_match() {
  local file="$1"
  local snippet="$2"
  local metadata="$3"

  MATCH_COUNT=$((MATCH_COUNT + 1))
  echo ""
  echo "${BOLD}--- $(basename "$file") ---${RESET}"
  if [[ -n "$metadata" ]]; then
    echo "${CYAN}${metadata}${RESET}"
  fi
  if [[ -n "$snippet" ]]; then
    echo "$snippet"
  fi
}

# --- Build file list ---
build_file_list() {
  local files=""

  case "$SEARCH_TYPE" in
    journal)
      files=$(ls -1 "$JARVIS_DIR/journal/"*.md 2>/dev/null || true)
      ;;
    memory)
      files=$(ls -1 "$JARVIS_DIR/memories/"*.md 2>/dev/null || true)
      ;;
    identity)
      if [[ -f "$JARVIS_DIR/IDENTITY.md" ]]; then
        files="$JARVIS_DIR/IDENTITY.md"
      fi
      ;;
    growth)
      if [[ -f "$JARVIS_DIR/GROWTH.md" ]]; then
        files="$JARVIS_DIR/GROWTH.md"
      fi
      ;;
    all)
      files=$(ls -1 "$JARVIS_DIR/journal/"*.md 2>/dev/null || true)
      files="${files}"$'\n'$(ls -1 "$JARVIS_DIR/memories/"*.md 2>/dev/null || true)
      if [[ -f "$JARVIS_DIR/IDENTITY.md" ]]; then
        files="${files}"$'\n'"$JARVIS_DIR/IDENTITY.md"
      fi
      if [[ -f "$JARVIS_DIR/GROWTH.md" ]]; then
        files="${files}"$'\n'"$JARVIS_DIR/GROWTH.md"
      fi
      ;;
    *)
      echo "Error: unknown type '$SEARCH_TYPE' (expected: journal, memory, identity, growth)" >&2
      exit 1
      ;;
  esac

  # Remove empty lines
  echo "$files" | sed '/^$/d'
}

# --- Main search pipeline ---
file_list=$(build_file_list)

if [[ -z "$file_list" ]]; then
  echo "No files found for type: $SEARCH_TYPE"
  exit 0
fi

while IFS= read -r file; do
  [[ -f "$file" ]] || continue

  # --- Date range filter (journals only, based on filename) ---
  if [[ -n "$DATE_FROM" || -n "$DATE_TO" ]]; then
    file_date=$(filename_date "$file")
    if [[ -z "$file_date" ]]; then
      # Non-journal files skip date filtering
      if [[ -n "$DATE_FROM" || -n "$DATE_TO" ]]; then
        # If date filter is active and file has no date, skip it
        # unless it's not a journal file (memories/identity/growth pass through)
        if echo "$file" | grep -q '/journal/'; then
          continue
        fi
      fi
    else
      if [[ -n "$DATE_FROM" && "$file_date" < "$DATE_FROM" ]]; then
        continue
      fi
      if [[ -n "$DATE_TO" && "$file_date" > "$DATE_TO" ]]; then
        continue
      fi
    fi
  fi

  # --- Tag filter (journals with frontmatter only) ---
  if [[ -n "$TAG_FILTER" ]]; then
    if ! has_tag "$file" "$TAG_FILTER"; then
      continue
    fi
  fi

  # --- Task type filter (journals with frontmatter only) ---
  if [[ -n "$TASK_TYPE_FILTER" ]]; then
    if ! has_task_type "$file" "$TASK_TYPE_FILTER"; then
      continue
    fi
  fi

  # --- Build searchable content ---
  if [[ -n "$SECTION_FILTER" ]]; then
    content=$(extract_section "$file" "$SECTION_FILTER")
    if [[ -z "$content" ]]; then
      continue
    fi
  else
    content=$(cat "$file")
  fi

  # --- Keyword search ---
  if [[ -n "$QUERY" ]]; then
    matches=$(echo "$content" | grep -in "$QUERY" || true)
    if [[ -z "$matches" ]]; then
      continue
    fi

    # Build metadata summary
    metadata=""
    tags_val=$(get_frontmatter_field "$file" "tags")
    type_val=$(get_frontmatter_field "$file" "task_type")
    date_val=$(get_frontmatter_field "$file" "date")
    if [[ -n "$date_val" || -n "$tags_val" || -n "$type_val" ]]; then
      metadata=""
      [[ -n "$date_val" ]] && metadata="date: $date_val"
      [[ -n "$type_val" ]] && metadata="${metadata:+$metadata | }type: $type_val"
      [[ -n "$tags_val" ]] && metadata="${metadata:+$metadata | }tags: $tags_val"
    fi

    # Show matching lines with context
    snippet=$(echo "$content" | grep -in -C 2 "$QUERY" | head -20 || true)
    print_match "$file" "$snippet" "$metadata"
  else
    # No keyword — show metadata and summary
    metadata=""
    tags_val=$(get_frontmatter_field "$file" "tags")
    type_val=$(get_frontmatter_field "$file" "task_type")
    date_val=$(get_frontmatter_field "$file" "date")
    if [[ -n "$date_val" || -n "$tags_val" || -n "$type_val" ]]; then
      [[ -n "$date_val" ]] && metadata="date: $date_val"
      [[ -n "$type_val" ]] && metadata="${metadata:+$metadata | }type: $type_val"
      [[ -n "$tags_val" ]] && metadata="${metadata:+$metadata | }tags: $tags_val"
    fi

    # Show first heading and task summary for journals
    heading=$(grep -m1 '^# ' "$file" 2>/dev/null || true)
    snippet=""
    if [[ -n "$SECTION_FILTER" ]]; then
      snippet=$(echo "$content" | head -10)
    elif [[ -n "$heading" ]]; then
      snippet="$heading"
    fi

    print_match "$file" "$snippet" "$metadata"
  fi
done <<< "$file_list"

# --- Summary ---
echo ""
if [[ "$MATCH_COUNT" -eq 0 ]]; then
  printf "${YELLOW}No matches found.${RESET}\n"
  echo "Try broadening your search: remove date filters, use different keywords, or search all types."
else
  printf "${GREEN}%d match(es) found.${RESET}\n" "$MATCH_COUNT"
fi
