# Dev-agents

A multi-agent development framework built on top of the [Claude Code CLI](https://claude.ai/claude-code). Orchestrates specialised AI agents that collaborate to plan, build, test, and review software — each running as an autonomous background process on your local machine.

---

## What this is

This repo contains the **agent framework only** — the scripts, prompts, and coordination logic. It contains no project code, no API keys, no operational data, and no personal information.

Project-specific data (task manifests, build outputs, review decisions, cost logs) lives separately in your local project workspace and is never committed here.

---

## Architecture

```
Planner + Architect ──► Orchestrator ──► Builder agents ──► Composer task ──► Tester (E2E)  ──► Architect
        ▲                    │                │                     │         ──► UI Reviewer ──►    │
        │                    │           unit tests                 └──────── ──► Reviewer    ──►    │
        └────────────────────┴──────────────────────────────── feedback loop ───────────────────────┘
```

**Planning phase:** Planner produces the PRD and task graph; Architect produces the phase-scoped ADR and interface contracts. Both run before any builder task starts.

**Build phase:** Orchestrator activates tasks as dependencies clear. Builders write and run their own unit tests in the same invocation — a failing unit test signals `failed` immediately without waiting for a downstream tester. Once a composer task wires a feature together, the Tester (E2E), Reviewer, and UI Reviewer run in parallel. Architect acts as quality gate at the end of each cycle — approving or rejecting with structured feedback that feeds back to Planner.

**13 agents across two types:**

| Type | Agents |
|------|--------|
| Interactive (you start them manually in Claude Code) | Planner, Architect, Researcher, Design Guardian |
| Watcher (background loops, pick up tasks from manifest) | Orchestrator, Builder ×5, Tester, Reviewer, UI Reviewer |

Communication is file-based: watchers drop JSON signal files to `signals/`; the Orchestrator is the sole writer of `manifest.json`.

---

## Context efficiency

Each watcher agent runs as a fresh Claude invocation per task. Token cost is therefore per-task, not per-session. The framework is designed to keep each invocation lean:

**Builder tasks** receive only what they need. Every builder task input must end with a `Files needed:` list — the exact files the builder will read. Builders are instructed to signal `BLOCKED` rather than explore the codebase if a needed file was not listed. This keeps per-task context to ~10–20k tokens regardless of project size.

```
Files needed:
- app/components/UserCard.tsx   (modify to add avatar prop)
- app/lib/types.ts              (read User type definition)
```

**For edits to short snippets**, include the current code inline in the task input — the builder uses `Edit` directly without reading the file at all, and you can omit it from `Files needed:`.

**Reviewer, tester, and ui-reviewer tasks** use a two-hop approach: their task input lists the builder output files to read; they extract the `Files Modified` list from those outputs and read only those project files. The Planner cannot predict which lines will change, but the builder output always records them.

```
Builder outputs:
- agent-workspace/builder-composer/output/task-004.md

Read the `Files Modified` section from the output above, then review only those files.
```

**Tester** receives explicit E2E test commands in its task input — it does not discover or run unit tests (builders handle those). This keeps tester invocations short and focused on integration behaviour.

**Progress signals:** reviewer, ui-reviewer, and tester work through named parts (e.g. code quality → security for reviewer) and write a progress update to their status file after each part. This keeps the dashboard live during long-running review tasks without requiring orchestrator changes.

The project directory is never injected wholesale into any agent — there is no equivalent of "load the whole codebase". All context is explicit and task-scoped.

---

## Getting started

### 1. Prerequisites

Two runner options — use whichever fits your setup:

**Claude Code runner** (default)
- [Claude Code CLI](https://claude.ai/claude-code) installed and authenticated
- `gh` CLI for git/PR automation
- Python 3.9+

**Anthropic API runner** (no Claude Code CLI required)
- `pip install anthropic`
- `export ANTHROPIC_API_KEY=sk-ant-...`
- `gh` CLI for git/PR automation
- Python 3.9+

### 2. Set up a project

```bash
# For a new project
./shared/init-project.sh my-project

# For an existing project (adds agent-workspace only)
./shared/add-workspace.sh my-project
```

Then fill in the three required files in your project folder:
- `.agent-config.json` — stack, git repo, budget, paths
- `CONVENTIONS.md` — coding conventions for builders
- `DESIGN_SYSTEM.md` — design tokens and component rules (required for UI tasks)

### 3. Launch agents

Each agent runs in its own terminal tab. Use the launcher that matches your runner — the same command works for all watcher agents:

```bash
# Claude Code runner
./shared/launch-agent.sh orchestrator      my-project
./shared/launch-agent.sh builder-composer  my-project
./shared/launch-agent.sh builder-systems   my-project
# ... same pattern for builder-data, builder-integration, builder-generalist, tester, reviewer, ui-reviewer

# Anthropic API runner (same agents, different launcher)
./shared/launch-api-agent.sh orchestrator     my-project
./shared/launch-api-agent.sh builder-composer my-project
./shared/launch-api-agent.sh builder-systems  my-project
# ... same pattern for all remaining watcher agents
```

To get all launch commands for a project at once:
```bash
./shared/start-project.sh my-project
```

### 4. Monitor progress

```bash
./shared/dashboard.sh my-project
```

---

## Repository structure

```
shared/
  launch-agent.sh       # Launch a watcher agent (Claude Code CLI runner)
  launch-api-agent.sh   # Launch a watcher agent (Anthropic API runner)
  claude-api-runner.py  # API drop-in replacement for claude --print
  init-project.sh       # Initialise a new project workspace
  add-workspace.sh      # Add agent workspace to an existing project
  start-project.sh      # Print all launch commands for a project
  dashboard.sh          # Live agent status dashboard
  cost-report.sh        # Per-agent token and cost summary
  costs.json            # Model pricing table

templates/
  project-config-template.json  # .agent-config.json starter
  manifest-template.json        # manifest.json starter with example tasks
  design-system-template.md     # DESIGN_SYSTEM.md starter
  signal-schema.json            # Signal file schema reference
  ci.yml                        # GitHub Actions CI starter

orchestrator/        # Coordination engine — sole writer of manifest.json (watcher)
planner/             # PRD and task graph (interactive)
architect/           # Technical design + quality gate (interactive)
researcher/          # External knowledge tasks (interactive)
design-guardian/     # Design constraints before UI tasks (interactive)
builder-composer/    # Wires existing parts into features (watcher)
builder-systems/     # Creates reusable components, services, utilities (watcher)
builder-data/        # Schema, migrations, queries (watcher)
builder-integration/ # External APIs, webhooks, third-party services (watcher)
builder-generalist/  # Fallback for tasks that span specialisations (watcher)
tester/              # E2E tests, runs once per composer task (watcher)
reviewer/            # Code quality + security review (watcher)
ui-reviewer/         # Design system compliance + visual regression (watcher)
INDEX.md             # Full reference documentation
```

---

## Security

**This framework runs Claude CLI with local file access.** Before using it, understand what it can and cannot do:

- Agents access only the files explicitly listed in their task input (`Files needed:`) — the project directory is not injected automatically
- Builder agents can run shell commands (`--allowedTools Bash,...`). Review agents (reviewer, ui-reviewer) cannot
- Task inputs are wrapped in XML delimiters before being passed to Claude to mitigate prompt injection from task content
- Signal files are JSON written by agents and read by the Orchestrator — validate them if your task inputs come from untrusted sources
- **Never put secrets in `.agent-config.json`** — it is read by background processes and its path pattern is gitignored, but treat it as a config file, not a vault
- The framework does not make network requests beyond the Claude API (via the CLI) and GitHub API (via `gh`)
- All file changes made by agents are visible via `git diff` before any PR is merged — the Architect review step and Lauri approval gate exist specifically to catch unwanted changes

**Reporting issues:** open an issue at [github.com/saviranta/Dev-agents](https://github.com/saviranta/Dev-agents/issues)

---

## Full documentation

See [INDEX.md](INDEX.md) for the complete reference: agent roles, manifest schema, signal lifecycle, budget tracking, and the full coordination loop.
