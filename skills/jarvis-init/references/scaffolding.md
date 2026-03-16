# JaRVIS Scaffolding Templates

Use these templates when creating the JaRVIS data directory (`~/.jarvis/projects/<slug>/`) for the first time.

## IDENTITY.md

```markdown
# Agent Identity

## Core
- **Name**: (unnamed — awaiting first session)
- **Version**: 0.0
- **Last evolved**: never

## Personality
Not yet established. Identity emerges through work and reflection.

## Expertise
No demonstrated expertise yet. This section grows only through completed tasks.

## Principles
No principles established. These emerge from real experience, not aspiration.

## Tool Mastery
No tools mastered yet. Tracks effective patterns and pitfalls discovered through use.

## User Model
No observations yet. Preferences noted during collaboration appear here.
```

## GROWTH.md

```markdown
# Growth Log

| Date | Version | What changed | Why |
|------|---------|-------------|-----|
```

## Version control

After scaffolding, run `git init` inside the data directory and create an initial commit. This gives the agent's growth its own version history, independent of any project repo.

## Journal entry format note

Journal entries created by `/jarvis-reflect` include YAML frontmatter with `date`, `time`, `tags`, `task_type`, and optionally `files_touched`. This frontmatter enables structured search via `/jarvis-search` and validation via `/jarvis-validate`.

## memories/preferences.md

```markdown
# User Preferences

## Consolidated
No consolidated preferences yet.

## Recent
```

## memories/decisions.md

```markdown
# Key Decisions

## Consolidated
No consolidated decisions yet.

## Recent
```