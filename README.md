# JaRVIS

**Journaling As Recurrent Versioned Identity Sculpting**

A set of agent skills for Claude Code, Cursor, GitHub Copilot, and Antigravity that give your agent persistent memory, post-task reflection, and a self-evolving identity — stored as flat markdown files in your home directory.

## What it does

JaRVIS adds six skills to your AI coding agent:

- **`/jarvis-init`** — Scaffold the JaRVIS data directory (run once)
- **`/jarvis-reload`** — Reload your agent's identity and memories (automatic on session start for platforms with hooks, manual otherwise)
- **`/jarvis-reflect`** — Structured post-task reflection that captures lessons, updates memories, and logs what happened
- **`/jarvis-identity`** — Evolve the agent's identity document based on accumulated experience
- **`/jarvis-validate`** — Check JaRVIS artifacts for format correctness
- **`/jarvis-search`** — Search past entries by keyword, tag, date range, or section

Everything lives in `~/.jarvis/projects/<slug>/` under your home directory (where `<slug>` is derived from your project path):

```
~/.jarvis/projects/<slug>/
├── IDENTITY.md              # Who the agent is (version-controlled, self-authored)
├── GROWTH.md                # Tracks reflection count and evolution history
├── memories/
│   ├── preferences.md       # Observed user preferences
│   ├── decisions.md         # Key decisions with rationale
│   └── ...                  # Additional files created through reflection
└── journal/
    ├── 2026-03-10-14-30.md  # Reflection entries
    └── ...
```

The `<slug>` is your project path with the leading `/` stripped, `/` and spaces replaced with `-`, and lowercased. For example, `/home/user/Projects/MyApp` becomes `home-user-projects-myapp`. Override with the `JARVIS_DIR` environment variable.

All files are markdown. Each data directory has its own git repo, initialized automatically by `/jarvis-init`. Your agent's growth is visible in its own commit history.

## Install

### Option A: Plugin (Claude Code only)

Install JaRVIS as a Claude Code plugin:

```bash
/plugin marketplace add epicrunze/JaRVIS
/plugin install jarvis@jarvis-marketplace
```

### Option B: One-prompt install

Paste this prompt into your AI coding agent to install or update JaRVIS:

```
Install or update JaRVIS (https://github.com/epicrunze/JaRVIS) in this project. Follow these steps exactly:

1. Download and extract the JaRVIS repo:
   curl -sL https://github.com/epicrunze/JaRVIS/archive/refs/heads/main.tar.gz | tar xz

2. Detect the platform and set SKILLS_DIR:
   - If .claude/ exists → SKILLS_DIR=".claude/skills"
   - If .cursor/ exists → SKILLS_DIR=".cursor/skills"
   - If .github/ exists → SKILLS_DIR=".github/skills"
   - If .agent/ exists or AGENTS.md exists → SKILLS_DIR=".agent/skills"
   - If none match, ask me which platform I'm using.

3. Create the skills directory if needed: mkdir -p "$SKILLS_DIR"

4. Copy the skill folders:
   cp -r JaRVIS-main/skills/* "$SKILLS_DIR/"

5. Clean up: rm -rf JaRVIS-main

6. If JaRVIS hasn't been set up for this project yet, run /jarvis-init to complete setup. If JaRVIS is already set up, skip this step — the update is complete.
```

Works with Claude Code, Cursor, GitHub Copilot, and Antigravity. See [`install/PROMPT.md`](install/PROMPT.md) for details.

### Option C: Manual install

Copy the skill folders into your platform's skills directory:

#### Claude Code

```bash
cp -r skills/* .claude/skills/
```

Global install (all projects): copy to `~/.claude/skills/` instead.

#### Cursor

```bash
cp -r skills/* .cursor/skills/
```

#### GitHub Copilot

```bash
cp -r skills/* .github/skills/
```

#### Antigravity

```bash
cp -r skills/* .agent/skills/
```

### Add to your instruction file

Add the JaRVIS section to your platform's instruction file. See the example files for what to add:

| Platform | Instruction File | Example |
|----------|-----------------|---------|
| Claude Code | `CLAUDE.md` | `skills/jarvis-init/references/CLAUDE.md.example` |
| Cursor | `.cursorrules` | `skills/jarvis-init/references/cursorrules.example` |
| GitHub Copilot | `.github/copilot-instructions.md` | `skills/jarvis-init/references/copilot-instructions.example` |
| Antigravity | `AGENTS.md` | `skills/jarvis-init/references/AGENTS.md.example` |

Then run `/jarvis-init` to scaffold the JaRVIS data directory. The init skill will detect your platform and configure things automatically.

## Hooks

JaRVIS includes hook scripts that automate context loading and reflection reminders. `/jarvis-init` configures these automatically during setup.

- **SessionStart** (`jarvis-session-start.sh` / `jarvis-session-start-cursor.sh`) — Automatically loads your agent's identity, consolidated memories, and recent journal entries at the start of each session.
- **Stop** (`jarvis-stop.sh` / `jarvis-stop-cursor.sh`) — Reminds the agent to run `/jarvis-reflect` before ending its turn if no reflection was captured during the session.

Hook scripts live inside the skill directories (`jarvis-reload/hooks/` and `jarvis-reflect/hooks/`) and are referenced by your platform's hook configuration.

> **Note:** Not all platforms support hooks. On platforms without hook support, use `/jarvis-reload` manually at session start.

## Usage

### First session

1. Start your AI coding agent in your project
2. Type `/jarvis-init` — this scaffolds the JaRVIS data directory and configures your platform
3. Do your work
4. Type `/jarvis-reflect` — writes your first reflection

### Ongoing sessions

1. Identity + memories load at session start (automatically via hook on Claude Code; run `/jarvis-reload` manually on other platforms)
2. Work normally
3. `/jarvis-reflect` after completing tasks
4. Every 5 reflections, `/jarvis-identity` evolves the identity document
5. Use `/jarvis-validate` to check artifact formatting and `/jarvis-search` to find past entries

### The loop

```
[load context] → work → /jarvis-reflect → work → /jarvis-reflect → ... → /jarvis-identity
```

> **Note:** On platforms without session-start hooks, run `/jarvis-reload` at the start of each session to load your identity and memories.

## Philosophy

Most agent memory systems are passive stores. JaRVIS is different — it treats the agent as a journaler who pauses after work, reflects on what happened, and gradually sculpts a coherent identity.

The key ideas:

- **Reflection over logging.** Not "what happened" but "what did I learn and what should I do differently."
- **Earned identity.** The agent only claims expertise it has demonstrated. Principles come from experience, not aspiration.
- **Memory consolidation.** Memories are periodically sculpted — deduplicated, tightened, and shaped. You're not just adding clay, you're sculpting it.
- **Transparency.** Everything is human-readable markdown in `~/.jarvis/`. No databases, no vector stores, no black boxes.

## License

MIT
