---
name: jarvis-validate
description: Validate the format and health of your .jarvis/ directory. Use when you want to check jarvis health, validate jarvis entries, verify journal format, or ensure memories and identity are well-formed.
---

# JaRVIS Validate

Check that your `.jarvis/` artifacts are well-formed and complete.

## Step 1: Locate your jarvis directory

Check if `.jarvis/` exists in the project root. If it doesn't, inform the user they need to run `/jarvis-init` first to set up the directory structure, then stop.

## Step 2: Run validation

Run the validation script against the `.jarvis/` directory:

```bash
bash <skill-path>/references/validate.sh .jarvis
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

If everything passes, confirm the `.jarvis/` directory is healthy.
