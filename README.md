# JaRVIS

**Journaling As Recurrent Versioned Identity Sculpting**

A set of Claude Code skills that give your agent persistent memory, post-task reflection, and a self-evolving identity — stored as flat markdown files in your repo.

## What it does

JaRVIS adds four skills to Claude Code:

- **`/jarvis-init`** — Scaffold the `.jarvis/` directory in your project (run once)
- **`/jarvis-start`** — Load your agent's identity and memories at session start
- **`/jarvis-reflect`** — Structured post-task reflection that captures lessons, updates memories, and logs what happened
- **`/jarvis-identity`** — Evolve the agent's identity document based on accumulated experience

Everything lives in a `.jarvis/` directory in your project:

```
.jarvis/
├── IDENTITY.md              # Who the agent is (version-controlled, self-authored)
├── memories/
│   ├── tools.md             # Tool usage patterns and discoveries
│   ├── preferences.md       # Observed user preferences
│   ├── decisions.md         # Key decisions with rationale
│   └── codebase.md          # Structural codebase knowledge
└── journal/
    ├── 2026-03-10-14-30.md  # Reflection entries
    └── ...
```

All files are markdown. All files are git-trackable. Your agent's growth is visible in your commit history.

## Install

### Option A: Plugin (recommended)

Install JaRVIS as a Claude Code plugin:

```bash
/plugin marketplace add epicrunze/JaRVIS
/plugin install jarvis@jarvis-marketplace
```

### Option B: Manual (project-level)

Copy the skill folders into your project:

```bash
cp -r skills/jarvis-init .claude/skills/jarvis-init
cp -r skills/jarvis-start .claude/skills/jarvis-start
cp -r skills/jarvis-reflect .claude/skills/jarvis-reflect
cp -r skills/jarvis-identity .claude/skills/jarvis-identity
```

### Option C: Manual (global, all projects)

```bash
cp -r skills/jarvis-init ~/.claude/skills/jarvis-init
cp -r skills/jarvis-start ~/.claude/skills/jarvis-start
cp -r skills/jarvis-reflect ~/.claude/skills/jarvis-reflect
cp -r skills/jarvis-identity ~/.claude/skills/jarvis-identity
```

### Add to CLAUDE.md

Add these lines to your project's `CLAUDE.md`:

```markdown
## JaRVIS

At the start of each session, run `/jarvis-start` to load your identity and memories.
After completing any meaningful task, run `/jarvis-reflect` to capture what you learned.
```

Then run `/jarvis-init` to scaffold the `.jarvis/` directory.

## Usage

### First session

1. Start Claude Code in your project
2. Type `/jarvis-init` — this scaffolds the `.jarvis/` directory
3. Type `/jarvis-start` — loads your (blank) identity and memories
4. Do your work
5. Type `/jarvis-reflect` — writes your first reflection

### Ongoing sessions

1. `/jarvis-start` loads identity + memories (or happens automatically via CLAUDE.md)
2. Work normally
3. `/jarvis-reflect` after completing tasks
4. Every 5 reflections, `/jarvis-identity` evolves the identity document

### The loop

```
/jarvis-start → work → /jarvis-reflect → work → /jarvis-reflect → ... → /jarvis-identity
```

## Philosophy

Most agent memory systems are passive stores. JaRVIS is different — it treats the agent as a journaler who pauses after work, reflects on what happened, and gradually sculpts a coherent identity.

The key ideas:

- **Reflection over logging.** Not "what happened" but "what did I learn and what should I do differently."
- **Earned identity.** The agent only claims expertise it has demonstrated. Principles come from experience, not aspiration.
- **Memory consolidation.** Memories are periodically sculpted — deduplicated, tightened, and shaped. You're not just adding clay, you're sculpting it.
- **Transparency.** Everything is human-readable markdown in your repo. No databases, no vector stores, no black boxes.

## License

MIT
