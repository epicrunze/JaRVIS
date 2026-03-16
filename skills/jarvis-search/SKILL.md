---
name: jarvis-search
description: Search across your JaRVIS data — journals, memories, identity, and growth log. Use when you want to search jarvis, find in journal, search memories, look up past reflections, find entries by tag or date, or recall what you learned about a topic.
---

# JaRVIS Search

Search across all JaRVIS artifacts — journals, memories, identity, and growth log.

## Step 1: Resolve JaRVIS data directory

Run `source ~/.jarvis/bin/resolve-dir.sh` to set `JARVIS_DIR`. If the script doesn't exist, set it manually: use the `JARVIS_DIR` env var if set, or slugify the project path (strip leading `/`, replace `/` and spaces with `-`, lowercase) under `~/.jarvis/projects/`.

If the resolved directory doesn't exist, inform the user they need to run `/jarvis-init` first, then stop.

## Step 2: Translate the user's request to search flags

Map the user's natural language request to `search.sh` flags:

| User says | Flags |
|-----------|-------|
| "search for pagination" | `--query pagination` |
| "find journal entries about auth" | `--type journal --query auth` |
| "what did I learn last week" | `--type journal --from YYYY-MM-DD --to YYYY-MM-DD` |
| "entries tagged with prisma" | `--tag prisma` |
| "bugfix entries" | `--task-type bugfix` |
| "what worked with caching" | `--section "What Worked" --query caching` |
| "search memories for testing" | `--type memory --query testing` |

Multiple flags can be combined for precise queries.

## Step 3: Run search

Run the search script:

```bash
bash <skill-path>/references/search.sh --jarvis-dir <data-dir> [OPTIONS] --query KEYWORD
```

Full interface:
```
search.sh [OPTIONS] [--query KEYWORD]
  --type journal|memory|identity|growth   (default: all)
  --from YYYY-MM-DD                       date range start
  --to YYYY-MM-DD                         date range end
  --tag TAG                               frontmatter tag filter
  --task-type TYPE                        frontmatter task_type filter
  --section "Section Name"                search within specific section
  --query KEYWORD                         keyword/phrase search
```

## Step 4: Present results

Format the search results for the user:
- Show matching entries with their metadata (date, tags, task type)
- Include relevant snippets with enough context to be useful
- If no results found, suggest broadening the search (e.g., different keywords, removing date filters)
