# Dev-agents

A multi-agent development framework built on top of the [Claude Code CLI](https://claude.ai/claude-code). Orchestrates specialised AI agents that collaborate to plan, build, test, and review software — each running as an autonomous background process on your local machine.

---

## What this is

This repo contains the **agent framework only** — the scripts, prompts, and coordination logic. It contains no project code, no API keys, no operational data, and no personal information.

Project-specific data (task manifests, build outputs, review decisions, cost logs) lives separately in your local project workspace and is never committed here.

---

## Architecture

```
Planner ──► Orchestrator ──► Builder agents ──► Tester ──► Reviewer ──► Architect
   ▲              │                                                          │
   └──────────────┴──────────────── feedback loop ──────────────────────────┘
```

**13 agents across two types:**

| Type | Agents |
|------|--------|
| Interactive (you start them manually in Claude Code) | Planner, Architect, Researcher, Design Guardian |
| Watcher (background loops, pick up tasks from manifest) | Orchestrator, Builder ×5, Tester, Reviewer, UI Reviewer |

Communication is file-based: watchers drop JSON signal files to `signals/`; the Orchestrator is the sole writer of `manifest.json`.

---

## Getting started

### 1. Prerequisites

- [Claude Code CLI](https://claude.ai/claude-code) installed and authenticated
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

Each agent runs in its own terminal tab:

```bash
./shared/launch-agent.sh orchestrator     my-project
./shared/launch-agent.sh builder-composer my-project
./shared/launch-agent.sh tester           my-project
# ... etc
```

### 4. Monitor progress

```bash
./shared/dashboard.sh my-project
```

---

## Repository structure

```
shared/              # Shared scripts (launch, dashboard, init)
templates/           # Project config and manifest templates
orchestrator/        # Coordination engine
planner/             # Task decomposition (interactive)
architect/           # Quality gate and review (interactive)
researcher/          # Research and ADR generation (interactive)
design-guardian/     # Design constraint extraction (interactive)
builder-composer/    # Feature assembly (watcher)
builder-systems/     # Reusable primitives (watcher)
builder-data/        # Schema and data layer (watcher)
builder-integration/ # External APIs and services (watcher)
builder-generalist/  # Fallback builder (watcher)
tester/              # Test execution (watcher)
reviewer/            # Code and security review (watcher)
ui-reviewer/         # Design system compliance (watcher)
INDEX.md             # Full reference documentation
```

---

## Security

**This framework runs Claude CLI with local file access.** Before using it, understand what it can and cannot do:

- Agents are granted access only to the project root and agent workspace (`--add-dir`) — not your entire filesystem
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
