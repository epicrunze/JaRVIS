# Cross-Platform Session Hooks: Implementation Research

Research compiled March 2026. Covers session start and session end hooks across Claude Code, Cursor, GitHub Copilot, and OpenCode — the four platforms with mature, practical support for these lifecycle events.

---

## Executive Summary

All four platforms support session start and session end hooks. Three of them (Claude Code, Cursor, Copilot) use the same fundamental mechanism: a shell script receives JSON on stdin and can return JSON on stdout. OpenCode uses in-process JavaScript/TypeScript plugins instead. A cross-platform plugin can share core logic by writing it as a Node.js module that is either called directly (OpenCode) or wrapped in a thin stdin/stdout CLI shim (the other three).

---

## Claude Code

### Config Locations

- `~/.claude/settings.json` — user-global
- `.claude/settings.json` — project-level
- `hooks/hooks.json` — inside a plugin directory (wrap with `{"hooks": {...}}`)

Settings from all locations are merged. Enterprise admins can use `allowManagedHooksOnly` to block user/project/plugin hooks.

### Hook Events

`SessionStart` and `SessionEnd`.

### Config Format

```json
{
  "SessionStart": [
    {
      "matcher": "*",
      "hooks": [
        {
          "type": "command",
          "command": "./scripts/on-session-start.sh"
        }
      ]
    }
  ],
  "SessionEnd": [
    {
      "matcher": "*",
      "hooks": [
        {
          "type": "command",
          "command": "./scripts/on-session-end.sh"
        }
      ]
    }
  ]
}
```

For plugin `hooks/hooks.json`, wrap the above in `{"hooks": {...}}`. For `settings.json`, use the direct format shown above.

The `matcher` field is a regex. For SessionStart, it matches on how the session was initiated. Use `"*"` or omit to match everything.

### SessionStart Stdin Payload

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.txt",
  "cwd": "/current/working/dir",
  "permission_mode": "ask",
  "hook_event_name": "SessionStart",
  "source": "startup",
  "model": "claude-sonnet-4-20250514",
  "agent_type": "optional-agent-name"
}
```

- `source`: `"startup"` (new session), `"resume"` (resumed), `"clear"` (after `/clear`), `"compact"` (after compaction)
- `model`: the model identifier string
- `agent_type`: present only when launched with `claude --agent <name>`

### SessionEnd Stdin Payload

```json
{
  "session_id": "abc123",
  "cwd": "/current/working/dir",
  "hook_event_name": "SessionEnd"
}
```

### Stdout Contract

**SessionStart**: stdout is injected as context for Claude. Return JSON:

```json
{
  "additionalContext": "Current branch: main, last commit: abc1234"
}
```

**SessionEnd**: stdout is not used for context injection. Fire-and-forget.

Both can return the structured `hookSpecificOutput` envelope:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "extra info for Claude"
  },
  "systemMessage": "Explanation for Claude"
}
```

### Environment Variables

Available in all command hooks:

- `$CLAUDE_PROJECT_DIR` — project root path
- `$CLAUDE_PLUGIN_ROOT` — plugin directory (use for portable script paths)
- `$CLAUDE_ENV_FILE` — **SessionStart only**. Append `export KEY=value` lines to persist env vars for the entire session.
- `$CLAUDE_CODE_REMOTE` — set if running in a remote context

### Exit Codes

- `0` — success; stdout JSON is parsed
- `2` — blocking error; stderr is fed back to Claude
- Other — non-blocking error; stderr shown in verbose mode, execution continues

### Constraints

- Only `type: "command"` hooks are supported for SessionStart — `prompt` and `agent` types are not available for this event.
- SessionStart hooks should be fast since they run on every session.
- Multiple hooks matching the same event run in parallel.
- Identical commands are automatically deduplicated.
- Hooks have a 60-second default timeout, configurable per hook.

### Source References

- Official docs: https://code.claude.com/docs/en/hooks
- Hook development skill: https://github.com/anthropics/claude-code/blob/main/plugins/plugin-dev/skills/hook-development/SKILL.md
- Blog post: https://claude.com/blog/how-to-configure-hooks

---

## Cursor

### Config Locations

- `.cursor/hooks.json` — project-level
- `~/.cursor/hooks.json` — user-global

All hooks from all locations are merged and run.

### Hook Events

`sessionStart` and `sessionEnd` (plus `stop`, which is distinct — it fires when the agent task completes and can loop).

The full list of Cursor hook types as of v2.5:

```
sessionStart, sessionEnd, preToolUse, postToolUse,
subagentStart, subagentStop, beforeShellExecution,
afterShellExecution, afterMCPExecution, afterFileEdit,
preCompact, stop, beforeTabFileRead, afterTabFileEdit
```

### Config Format

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      { "command": "./hooks/on-session-start.sh" }
    ],
    "sessionEnd": [
      { "command": "./hooks/on-session-end.sh" }
    ]
  }
}
```

Hook command paths are relative to the `hooks.json` file location.

### sessionStart Stdin Payload

```json
{
  "conversation_id": "668320d2-2fd8-4888-b33c-2a466fec86e7",
  "generation_id": "490b90b7-a2ce-4c2c-bb76-cb77b125df2f",
  "hook_event_name": "sessionStart",
  "workspace_roots": ["/Users/you/projects/myapp"]
}
```

### sessionEnd Stdin Payload

```json
{
  "conversation_id": "668320d2-2fd8-4888-b33c-2a466fec86e7",
  "generation_id": "490b90b7-a2ce-4c2c-bb76-cb77b125df2f",
  "hook_event_name": "sessionEnd",
  "workspace_roots": ["/Users/you/projects/myapp"]
}
```

### stop Stdin Payload (related but distinct)

```json
{
  "conversation_id": "cdefee2d-2727-4b73-bf77-d9d830f31d2a",
  "generation_id": "26b45fb6-bdea-439c-b2dc-5e97ee00ecea",
  "status": "completed",
  "hook_event_name": "stop",
  "workspace_roots": ["/Users/you/projects/myapp"],
  "loop_count": 0
}
```

- `status`: `"completed"`, `"aborted"`, or `"error"`
- `loop_count`: increments each time the agent loops via `followup_message`

### Stdout Contract

**sessionStart** can return:

```json
{
  "additional_context": "Injected into the agent's context"
}
```

**sessionEnd** is observational — no documented stdout contract.

**stop** can return:

```json
{
  "followup_message": "Continue working on remaining tasks."
}
```

Returning a `followup_message` from `stop` keeps the agent running. The config supports `"loop_limit": N` to cap iterations.

### Known Issues (as of March 2026)

- `sessionStart` was not recognized in Cursor ≤2.3 (bug in validation). It fires as of 2.5+ but `continue: false` does not work as documented. `user_message` output is also broken. These are acknowledged known issues.
- On Windows, sessionStart hooks in plugins may produce no output even when the script runs correctly. Workaround: use `node` or `bun` scripts instead of `.sh`.
- `stop` is the more battle-tested lifecycle hook. If you need reliable end-of-session behavior, prefer `stop` over `sessionEnd` as a fallback.

### Source References

- Official docs: https://cursor.com/docs/hooks
- Plugin reference: https://cursor.com/docs/plugins/building
- GitButler deep dive (definitive early reference): https://blog.gitbutler.com/cursor-hooks-deep-dive
- TypeScript types / JSON schema: https://github.com/johnlindquist/cursor-hooks
- Bug reports: https://forum.cursor.com/t/unknown-hook-type-sessionstart/149566, https://forum.cursor.com/t/sessionstart-hook-ignores-continue-false/150006

---

## GitHub Copilot

### Config Locations

- `.github/hooks/<name>.json` — repository-level (must be on default branch for Copilot coding agent)
- Current working directory — for Copilot CLI

Multiple hook files can coexist in `.github/hooks/`. Each is a standalone JSON file.

### Hook Events

`sessionStart` and `sessionEnd` (plus `userPromptSubmitted`, `preToolUse`, `postToolUse`, `errorOccurred`).

### Config Format

```json
{
  "version": 1,
  "hooks": {
    "sessionStart": [
      {
        "type": "command",
        "bash": "./scripts/on-session-start.sh",
        "powershell": "./scripts/on-session-start.ps1",
        "cwd": ".",
        "env": {
          "LOG_LEVEL": "INFO"
        },
        "timeoutSec": 10
      }
    ],
    "sessionEnd": [
      {
        "type": "command",
        "bash": "./scripts/on-session-end.sh",
        "powershell": "./scripts/on-session-end.ps1",
        "cwd": "scripts",
        "timeoutSec": 10
      }
    ]
  }
}
```

Key differences from Cursor/Claude Code:

- Separate `bash` and `powershell` fields (not a single `command`)
- Explicit `cwd` (resolved relative to repo root)
- `env` for injecting environment variables
- `timeoutSec` (default 30s)

### sessionStart Stdin Payload

```json
{
  "timestamp": 1704614400000,
  "cwd": "/path/to/project",
  "source": "new",
  "initialPrompt": "Create a new feature"
}
```

- `source`: `"new"` for new sessions
- `initialPrompt`: the user's first prompt text

### sessionEnd Stdin Payload

```json
{
  "timestamp": 1704614400000,
  "cwd": "/path/to/project"
}
```

### Stdout Contract

sessionStart and sessionEnd are primarily observational. No documented context injection mechanism for these events (unlike `preToolUse` which can block/modify tool calls).

Scripts should output valid JSON if they output anything. Use `jq -c` in bash or `ConvertTo-Json -Compress` in PowerShell for compact single-line output.

### Exit Codes

Hooks are intentionally non-blocking. Even if a hook fails, the Copilot agent session continues. Non-zero exit codes may skip subsequent hooks for the same event.

### Known Issues

- In Copilot CLI interactive mode, `sessionStart` and `sessionEnd` hooks may fire per-prompt instead of per-session. This is a known bug reported January 2026 (github/copilot-cli#991).

### Copilot CLI Extensions (advanced alternative)

Copilot CLI also has a separate "extensions" system — full Node.js processes communicating via JSON-RPC over stdio:

```
.github/extensions/my-ext/
└── extension.mjs
```

Extensions register `onSessionStart` hooks that receive structured input and return structured output — no shell exit codes or stdout parsing needed. This is more powerful than the JSON hooks but less portable.

### Source References

- Official hooks guide: https://docs.github.com/en/copilot/how-tos/use-copilot-agents/coding-agent/use-hooks
- Hooks configuration reference: https://docs.github.com/en/copilot/reference/hooks-configuration
- About hooks (conceptual): https://docs.github.com/en/copilot/concepts/agents/coding-agent/about-hooks
- Awesome Copilot hooks examples: https://awesome-copilot.github.com/learning-hub/automating-with-hooks/
- CLI extensions (advanced): https://dev.to/htekdev/github-copilot-cli-extensions-the-most-powerful-feature-nobodys-talking-about-4f8f

---

## OpenCode

### Config Locations

- `.opencode/plugins/` — project-level (auto-loaded at startup)
- `~/.config/opencode/plugins/` — global
- `opencode.json` `"plugin"` array — npm packages

### Hook Events

- `session.created` — new session created (≈ session start)
- `session.idle` — agent finished responding (≈ session end)
- `session.error` — session errored
- `session.compacted` — after context compaction
- `session.deleted` — session deleted
- `session.updated` — session metadata changed
- `session.diff` — diff generated
- `session.status` — status changed

### Implementation

OpenCode does **not** use shell scripts or stdin JSON. Plugins are JavaScript or TypeScript modules executed in-process by the Bun runtime.

```typescript
// .opencode/plugins/session-hooks.ts
import type { Plugin } from "@opencode-ai/plugin"

export const SessionHooks: Plugin = async ({ project, client, $, directory, worktree }) => {
  // Plugin initialization — runs once at startup
  console.log(`Plugin loaded for project in ${directory}`)

  return {
    event: async ({ event }) => {
      if (event.type === "session.created") {
        // ── Session Start ──
        // You have direct access to:
        //   project  — current project info
        //   directory — cwd
        //   worktree — git worktree path
        //   client   — OpenCode SDK client
        //   $        — Bun shell API

        // Example: log to file
        await $`echo "Session started at $(date)" >> /tmp/opencode-sessions.log`

        // Example: call an external API
        // await fetch("https://your-api.com/session-start", { method: "POST", body: JSON.stringify({ directory }) })
      }

      if (event.type === "session.idle") {
        // ── Session End ──
        await $`echo "Session ended at $(date)" >> /tmp/opencode-sessions.log`
      }

      if (event.type === "session.error") {
        // ── Session Error ──
        await $`echo "Session error at $(date)" >> /tmp/opencode-errors.log`
      }
    }
  }
}
```

### Context Object

The plugin function receives:

- `project` — current project information
- `directory` — current working directory (string)
- `worktree` — git worktree path (string)
- `client` — OpenCode SDK client for programmatic AI interaction
- `$` — Bun's shell API for executing commands

### Dependencies

To use npm packages in your plugin, add a `package.json` to your config directory:

```json
// .opencode/package.json
{
  "dependencies": {
    "node-fetch": "^3.0.0"
  }
}
```

OpenCode runs `bun install` at startup to install these.

### Compaction Hook (bonus)

```typescript
export const CompactionPlugin: Plugin = async (ctx) => {
  return {
    "experimental.session.compacting": async (input, output) => {
      output.context.push(`
        ## Persisted Context
        - Current task status
        - Important decisions made
      `)
    }
  }
}
```

### Notes

- No stdin/stdout JSON — everything is direct function calls
- Plugin functions are async and can use `await`
- Errors thrown in `tool.execute.before` block operations; errors in event handlers are logged but don't disrupt the session
- TypeScript types available via `@opencode-ai/plugin`
- Plugins are hot-loaded; changes to plugin files may require restart

### Source References

- Official docs: https://opencode.ai/docs/plugins/
- Community plugins: https://github.com/awesome-opencode/awesome-opencode
- OpenCode GitHub: https://github.com/opencode-ai/opencode

---

## Cross-Platform Field Mapping

| Concept | Claude Code | Cursor | Copilot | OpenCode |
|---|---|---|---|---|
| **Session start event** | `SessionStart` | `sessionStart` | `sessionStart` | `session.created` |
| **Session end event** | `SessionEnd` | `sessionEnd` | `sessionEnd` | `session.idle` |
| **Task complete event** | `Stop` | `stop` | — | — |
| **Session ID** | `session_id` | `conversation_id` | (not in payload) | (via event object) |
| **Working directory** | `cwd` | `workspace_roots[0]` | `cwd` | `directory` (context) |
| **Event name field** | `hook_event_name` | `hook_event_name` | (implicit from config) | `event.type` |
| **Session origin** | `source` | — | `source` | — |
| **Model** | `model` | — | — | — |
| **Initial prompt** | — | — | `initialPrompt` | — |
| **Timestamp** | — | — | `timestamp` | — |
| **Inject context** | stdout `additionalContext` | stdout `additional_context` | not supported | programmatic |
| **Persist env vars** | `$CLAUDE_ENV_FILE` | not supported | `env` in config only | programmatic |

---

## Cross-Platform Implementation Strategy

### Architecture

Write hook logic as a **Node.js/TypeScript module** with two exports:

```typescript
interface NormalizedPayload {
  event: "session_start" | "session_end"
  platform: "claude_code" | "cursor" | "copilot" | "opencode"
  session_id: string | null
  cwd: string
  source: string | null      // "startup", "resume", "new", etc.
  status: string | null       // for end events: "completed", "error", etc.
  model: string | null
  initial_prompt: string | null
  raw: Record<string, any>   // original platform payload
}

export async function onSessionStart(payload: NormalizedPayload): Promise<void> {
  // Your logic here
}

export async function onSessionEnd(payload: NormalizedPayload): Promise<void> {
  // Your logic here
}
```

### Shell adapter (for Claude Code, Cursor, Copilot)

A thin `router.sh` reads stdin, detects the platform from the payload shape, normalizes it, and calls your logic:

```bash
#!/usr/bin/env bash
set -euo pipefail
INPUT=$(cat)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Detect platform from payload fields
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // empty')
HAS_SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
HAS_TIMESTAMP=$(echo "$INPUT" | jq -r '.timestamp // empty')

if [ -n "$HAS_SESSION_ID" ]; then
  PLATFORM="claude_code"
elif [ -n "$HAS_TIMESTAMP" ]; then
  PLATFORM="copilot"
else
  PLATFORM="cursor"
fi

# Normalize event name
case "$EVENT" in
  SessionStart|sessionStart)  NORMALIZED_EVENT="session_start" ;;
  SessionEnd|sessionEnd)      NORMALIZED_EVENT="session_end" ;;
  stop)                       NORMALIZED_EVENT="session_end" ;;
  *)                          NORMALIZED_EVENT="unknown" ;;
esac

# Build normalized payload
NORMALIZED=$(jq -nc \
  --arg event "$NORMALIZED_EVENT" \
  --arg platform "$PLATFORM" \
  --argjson raw "$INPUT" \
  '{event: $event, platform: $platform, raw: $raw}')

# Dispatch
if [ "$NORMALIZED_EVENT" = "session_start" ]; then
  echo "$NORMALIZED" | "$SCRIPT_DIR/on-session-start.sh"
elif [ "$NORMALIZED_EVENT" = "session_end" ]; then
  echo "$NORMALIZED" | "$SCRIPT_DIR/on-session-end.sh"
fi
```

### OpenCode adapter

An OpenCode plugin that calls the same logic:

```typescript
// .opencode/plugins/session-hooks.ts
import type { Plugin } from "@opencode-ai/plugin"
// import { onSessionStart, onSessionEnd } from "./your-shared-logic"

export const SessionHooks: Plugin = async ({ directory, worktree }) => {
  return {
    event: async ({ event }) => {
      const base = {
        platform: "opencode" as const,
        session_id: null,
        cwd: directory,
        source: null,
        status: null,
        model: null,
        initial_prompt: null,
        raw: event
      }

      if (event.type === "session.created") {
        // await onSessionStart({ ...base, event: "session_start" })
      }
      if (event.type === "session.idle") {
        // await onSessionEnd({ ...base, event: "session_end" })
      }
    }
  }
}
```

---

## Platforms Evaluated and Dropped

### Kiro (AWS)

Kiro has hooks but **no session start or session end event**. Its trigger types are: Prompt Submit, Agent Stop, Pre Tool Use, Post Tool Use, File Create, File Save, File Delete, Pre Task Execution, Post Task Execution, and Manual Trigger. The closest approximation would be Prompt Submit (first prompt ≈ start) and Agent Stop (≈ end), but these are semantically different and would require state tracking to simulate session lifecycle. Hooks are also configured via a UI form rather than JSON files, making automated plugin installation harder.

Source: https://kiro.dev/docs/hooks/types

### Google Antigravity

Antigravity does not support hooks at all as of March 2026. It focuses on its Manager/Editor paradigm with artifacts and feedback loops. An InfoWorld review explicitly noted: "Antigravity doesn't have Kiro's more development-workflow-centric features, like the hooks that can be defined to trigger agent behaviors at certain points."

Source: https://www.infoworld.com/article/4096113/a-first-look-at-googles-new-antigravity-ide.html

### Cline

Cline has a hooks system in `.clinerules/hooks/` with a `HookDiscoveryCache`, and supports multi-platform deployment (VS Code, CLI, JetBrains). However, documentation on specific session lifecycle events is sparse and the system is still evolving rapidly. Worth revisiting once the hook API stabilizes.

Source: https://deepwiki.com/cline/cline/2.1-extension-activation