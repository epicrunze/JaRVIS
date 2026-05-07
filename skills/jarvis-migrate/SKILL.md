---
name: jarvis-migrate
description: Apply pending JaRVIS data-dir schema migrations. Use when the user reports JaRVIS is not seeing recent data, after upgrading the plugin, or when the SessionStart hook reports a migration failure.
---

# JaRVIS Migrate

Bring the JaRVIS data directory's schema up to date with the current plugin version.

This skill is normally invoked automatically by the SessionStart hook, by `/jarvis-reflect` (via `finalize-reflection.sh`), and by `/jarvis-reload`. You only invoke it manually when those automatic paths are unavailable or have failed.

## Step 1: Resolve the data directory

```bash
JARVIS_DIR=$(bash <skill-path>/scripts/resolve-dir.sh)
```

If the resolved directory doesn't exist, tell the user to run `/jarvis-init` first, then stop.

## Step 2: Run the migration runner

```bash
bash <skill-path>/scripts/migrate.sh "$JARVIS_DIR"
```

Behavior:
- Silent exit 0 = data dir already at latest schema (no work).
- Output beginning with `JaRVIS data dir migrated v<old> → v<new>` and a bullet list = migrations applied. Surface this to the user.
- Non-zero exit = surface the stderr to the user; do not retry blindly.

## Step 3: Report

Briefly tell the user what the runner did. If migrations ran, summarize each bullet. If it was a no-op, say "data dir already current."
