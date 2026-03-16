---
name: jarvis-validate
description: Validate the format and health of your JaRVIS data directory. Use when you want to check jarvis health, validate jarvis entries, verify journal format, or ensure memories and identity are well-formed.
---

# JaRVIS Validate

Check that your JaRVIS artifacts are well-formed and complete.

## Step 1: Resolve JaRVIS data directory

Run `source ~/.jarvis/bin/resolve-dir.sh` to set `JARVIS_DIR`. If the script doesn't exist, set it manually: use the `JARVIS_DIR` env var if set, or slugify the project path (strip leading `/`, replace `/` and spaces with `-`, lowercase) under `~/.jarvis/projects/`.

If the resolved directory doesn't exist, inform the user they need to run `/jarvis-init` first, then stop.

## Step 2: Run validation

Run the validation script against the JaRVIS data directory:

```bash
bash <skill-path>/references/validate.sh <data-dir>
```

The script checks:
- **Journals**: filename format, YAML frontmatter (warn if missing), required sections, non-empty content
- **Memories**: filename format, required sections (`## Consolidated`, `## Recent`)
- **Identity** (`IDENTITY.md`): required sections (Core, Personality, Expertise, Principles, Tool Mastery, User Model), version format
- **Growth log** (`GROWTH.md`): table structure, valid data rows

## Step 3: Report results

Present the validation results to the user. For any failures or warnings:
- Explain what's wrong and where
- Suggest how to fix it (e.g., "run `/jarvis-reflect` to create a properly formatted entry" or "add the missing `## Consolidated` section to memories/preferences.md")

If everything passes, confirm the JaRVIS data directory is healthy.
