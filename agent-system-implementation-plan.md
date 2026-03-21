# Agent System Implementation Plan v4
> Prompt this file directly in Claude Code to build the system step by step.
> Updated: Planner/Orchestrator split, signals-based manifest ownership, Orchestrator as background coordinator, sharpened Architect role (technical design upstream + quality gate downstream).

---

## Context

Build a multi-agent orchestration system inside Claude Code. Agents live globally in `ClaudeCodeRepo` and are launched against specific projects via a config file. Some agents run interactively (thinking agents), others run autonomously via a shell watcher (execution agents).

**Base path**: `~/Library/CloudStorage/Dropbox/ClaudeFolder/` (referred to as `$CF` below)

---

## Agent Roster

This is the definitive agent list. Do not create agents outside this list without explicit instruction.

| Agent | Type | Gate output | Notes |
|-------|------|-------------|-------|
| Planner | Interactive | — | PRD → task graph → manifest. Product-minded PO role |
| Orchestrator | Background watcher | — | Signal processing, manifest updates, file locks, git/PRs |
| Architect | Interactive | Approves task cycles | Technical design upstream + quality gate downstream |
| Researcher | Interactive | — | Explicit trigger only |
| Design Guardian | Interactive | Approves UI task specs | Runs before any UI task |
| Builder — Composer | Watcher | signal: `done` | Wires existing parts into features. Highest volume |
| Builder — Systems | Watcher | signal: `done` | Creates primitives: components, services, utilities |
| Builder — Data | Watcher | signal: `done` | Schema, migrations, queries. Strictest file protection |
| Builder — Integration | Watcher | signal: `done` | External APIs, webhooks, third-party services |
| Builder — Generalist | Watcher | signal: `done` | Fallback for tasks that don't fit a specialisation |
| Tester | Watcher | signal: `done` / `failed` | Functional + visual regression |
| Reviewer | Watcher | signal: `reviewed` | Code quality + security combined |
| UI Reviewer | Watcher | signal: `reviewed` | Design system compliance |

**Key design decisions:**
- **Planner owns the what** — product thinking, PRD, task decomposition, replanning
- **Orchestrator owns coordination** — runs continuously in background, sole writer of manifest.json, manages signals, file locks, git/PRs
- **Architect owns the how** — technical design before builders start, quality gate after they finish
- **Watchers never write to manifest** — they drop signal files only; Orchestrator processes signals and updates manifest
- Builders specialised by **cognitive mode**, not file location
- Generalist builder kept as explicit fallback
- Autonomy decreases as consequence increases: builders fully autonomous, merge always requires user

---

## Agent Flow

```
You → Planner (interactive)
  → writes PRD + task graph → initial manifest.json

Architect (interactive, before builders start)
  → reads PRD + task list
  → writes ADR (Architecture Decision Record)
  → defines interface contracts between agents
  → flags risks back to Planner if needed

Orchestrator (background watcher, always running)
  → reads manifest, marks tasks pending when deps met + files free
  → processes signals/ as agents complete work
  → updates manifest statuses + releases file locks
  → notifies Planner + you when cycle done or task fails
  → triggers git/PR workflow when Architect approves a cycle

Builders / Tester / Reviewers (watchers)
  → poll manifest for pending tasks (read-only)
  → do the work
  → write output to their output/ folder
  → drop a signal file to signals/ — never touch manifest

Architect (interactive, after cycle completes)
  → reviews builder output against ADR
  → approves cycle → Orchestrator triggers git/PR
  → rejects cycle → structured feedback to Planner

Planner (interactive, on Architect approval)
  → decides next chunk of work
  → writes next tasks to manifest

You → review PR → merge → GitHub Actions deploys
```

---

## Phase 1 — Global Folder Structure

Create the following folder structure in `$CF/ClaudeCodeRepo/agents/`:

```
$CF/ClaudeCodeRepo/agents/
  planner/
    CLAUDE.md
  orchestrator/
    CLAUDE.md
    watch.sh
  architect/
    CLAUDE.md
  researcher/
    CLAUDE.md
  design-guardian/
    CLAUDE.md
  builder-composer/
    CLAUDE.md
    watch.sh
  builder-systems/
    CLAUDE.md
    watch.sh
  builder-data/
    CLAUDE.md
    watch.sh
  builder-integration/
    CLAUDE.md
    watch.sh
  builder-generalist/
    CLAUDE.md
    watch.sh
  tester/
    CLAUDE.md
    watch.sh
  reviewer/
    CLAUDE.md
    watch.sh
  ui-reviewer/
    CLAUDE.md
    watch.sh
  shared/
    costs.json
    launch-agent.sh
    cost-report.sh
    init-project.sh
    start-project.sh
  INDEX.md
```

Also update the global `~/.claude/CLAUDE.md` to add one line under a new `## Agents` section:
```
Agent index: ~/Library/CloudStorage/Dropbox/ClaudeFolder/ClaudeCodeRepo/agents/INDEX.md
```

---

## Phase 2 — Shared Config Files

### `shared/costs.json`
Pricing table per model (USD per token). Include:
- `claude-opus-4-5`: input 0.000015, output 0.000075
- `claude-sonnet-4-5`: input 0.000003, output 0.000015
- `claude-haiku-4-5`: input 0.00000025, output 0.00000125
- `gpt-4o`: input 0.000005, output 0.000015
- `gemini-1.5-pro`: input 0.00000125, output 0.000005

### `shared/launch-agent.sh`
Script that takes two arguments: `AGENT` and `PROJECT`.
- Reads `$CF/ClaudeProjects/$PROJECT/.agent-config.json`
- Exports `PROJECT_CONFIG` and `AGENT_NAME` as environment variables
- `cd`s into the agent's folder and runs `watch.sh`
- Errors clearly if the config file doesn't exist
- Supports launching multiple instances of the same agent — each polls independently, Orchestrator handles file lock conflicts

### `shared/cost-report.sh`
Script that takes `PROJECT` as argument.
- Reads `$CF/ClaudeProjects/$PROJECT/agent-workspace/run-log.jsonl`
- Outputs a formatted table: Agent | Tasks | Tokens In | Tokens Out | Cost USD
- Includes a TOTAL row at the bottom

### `shared/start-project.sh`
Prints exact terminal commands to launch all agents for a project. One command per Cursor tab.

```bash
#!/bin/bash
# start-project.sh — prints launch commands for all agents
# Usage: ./shared/start-project.sh PROJECT_NAME

PROJECT=$1
CF="$HOME/Library/CloudStorage/Dropbox/ClaudeFolder"
SHARED="$CF/ClaudeCodeRepo/agents/shared"

if [ -z "$PROJECT" ]; then
  echo "❌ Usage: ./start-project.sh PROJECT_NAME"
  exit 1
fi

if [ ! -f "$CF/ClaudeProjects/$PROJECT/.agent-config.json" ]; then
  echo "❌ No .agent-config.json found for: $PROJECT"
  echo "   Run init-project.sh first"
  exit 1
fi

echo ""
echo "🤖 Agent launch commands for: $PROJECT"
echo "   Open a new Cursor terminal tab for each line"
echo "   Rename each tab to the agent name for easy tracking"
echo ""
echo "── BACKGROUND WATCHER (launch first) ───────────────────"
echo "$SHARED/launch-agent.sh orchestrator        $PROJECT"
echo ""
echo "── WATCHER AGENTS ───────────────────────────────────────"
echo "$SHARED/launch-agent.sh builder-composer    $PROJECT"
echo "$SHARED/launch-agent.sh builder-systems     $PROJECT"
echo "$SHARED/launch-agent.sh builder-data        $PROJECT"
echo "$SHARED/launch-agent.sh builder-integration $PROJECT"
echo "$SHARED/launch-agent.sh tester              $PROJECT"
echo "$SHARED/launch-agent.sh reviewer            $PROJECT"
echo "$SHARED/launch-agent.sh ui-reviewer         $PROJECT"
echo ""
echo "── INTERACTIVE AGENTS (open Cursor in these folders) ────"
echo "$CF/ClaudeCodeRepo/agents/planner/          → run: claude"
echo "$CF/ClaudeCodeRepo/agents/architect/        → run: claude"
echo "$CF/ClaudeCodeRepo/agents/design-guardian/  → run: claude (UI tasks only)"
echo "$CF/ClaudeCodeRepo/agents/researcher/       → run: claude (when needed)"
echo ""
echo "── STARTUP ORDER ────────────────────────────────────────"
echo "1. Launch Orchestrator tab (background watcher)"
echo "2. Run Planner to write PRD + manifest.json"
echo "3. Run Architect to write ADR + interface contracts"
echo "4. Launch remaining watcher tabs — they pick up tasks immediately"
echo ""
echo "── OPTIONAL: PARALLEL BUILDERS ─────────────────────────"
echo "Run the same builder twice for faster parallel execution:"
echo "$SHARED/launch-agent.sh builder-composer $PROJECT  # tab A"
echo "$SHARED/launch-agent.sh builder-composer $PROJECT  # tab B"
echo ""
```

---

## Phase 3 — Per-Project Config Template

Create a template file at `$CF/ClaudeCodeRepo/agents/project-config-template.json`:

```json
{
  "project": "PROJECT_NAME",
  "project_root": "$CF/ClaudeProjects/PROJECT_NAME/",
  "stack": "describe tech stack here",
  "workspace": "$CF/ClaudeProjects/PROJECT_NAME/agent-workspace/",
  "manifest": "$CF/ClaudeProjects/PROJECT_NAME/agent-workspace/manifest.json",
  "signals": "$CF/ClaudeProjects/PROJECT_NAME/agent-workspace/signals/",
  "design_system": "$CF/ClaudeProjects/PROJECT_NAME/DESIGN_SYSTEM.md",
  "adr": "$CF/ClaudeProjects/PROJECT_NAME/ADR.md",
  "agents_enabled": [
    "planner", "orchestrator", "architect", "design-guardian",
    "builder-composer", "builder-systems", "builder-data",
    "builder-integration", "builder-generalist",
    "tester", "reviewer", "ui-reviewer"
  ],
  "git_repo": "saviranta/PROJECT_NAME",
  "conventions": "See PROJECT_NAME/CONVENTIONS.md",
  "budget_usd": 10.00,
  "budget_alert_at": 8.00,
  "agents": {
    "planner":             { "model": "claude-opus-4-5" },
    "orchestrator":        { "model": "claude-sonnet-4-5" },
    "architect":           { "model": "claude-opus-4-5" },
    "researcher":          { "model": "claude-opus-4-5" },
    "design-guardian":     { "model": "claude-opus-4-5" },
    "builder-composer":    { "model": "claude-sonnet-4-5" },
    "builder-systems":     { "model": "claude-sonnet-4-5" },
    "builder-data":        { "model": "claude-sonnet-4-5" },
    "builder-integration": { "model": "claude-sonnet-4-5" },
    "builder-generalist":  { "model": "claude-sonnet-4-5" },
    "tester":              { "model": "claude-sonnet-4-5" },
    "reviewer":            { "model": "claude-sonnet-4-5" },
    "ui-reviewer":         { "model": "claude-sonnet-4-5" }
  },
  "review_gate": {
    "reviewer":    "architect",
    "ui-reviewer": "architect",
    "security":    "lauri"
  },
  "git": {
    "main_branch": "main",
    "branch_prefix": "agent/",
    "auto_pr": true,
    "require_approval_before_merge": true,
    "protected_files": [
      "schema.prisma",
      ".env.example",
      "package.json",
      "package-lock.json"
    ]
  },
  "ci": {
    "provider": "github_actions",
    "deploy_on_merge_to": "main",
    "notify": "lauri"
  },
  "regression_scope": {
    "shared_components": [],
    "always_test_pages": ["/", "/dashboard"]
  }
}
```

Note: Orchestrator uses Sonnet not Opus — its job is mechanical coordination, not deep reasoning.

---

## Phase 4 — Design System Document Template

Create `$CF/ClaudeCodeRepo/agents/design-system-template.md`.

Copy into each new project as `DESIGN_SYSTEM.md` and fill before any UI work begins. Both Design Guardian and UI Reviewer reference it explicitly.

```markdown
# Design System — PROJECT_NAME

## Brand Tokens
- Primary colour: #XXXXXX
- Secondary colour: #XXXXXX
- Surface / background: #XXXXXX
- Text primary: #XXXXXX
- Text secondary: #XXXXXX
- Border radius: Xpx (cards), Xpx (inputs), Xpx (pills)
- Spacing base unit: 4px — all spacing must be multiples of 4
- Shadow: define elevation levels here

## Typography
- Headings: [font] [weight]
- Body: [font] [weight], [size]/[line-height]
- Monospace: [font] (code blocks only)
- Type scale: define h1–h4 sizes here

## Component Rules
- Buttons: always use <Button> component, never raw <button>
- Forms: always use <FormField> wrapper
- Lists: never use bare <ul>, always <DataList> or <MenuList>
- Icons: [icon library name] only, no mixing libraries
- Add new component rules here as the system grows

## What Builders Must Never Do
- Inline styles (except truly dynamic values)
- Custom colours outside the token system
- New components without Design Guardian approval
- Mixing icon libraries
- Hardcoded spacing values (use spacing scale)

## Approved Patterns
List recurring UI patterns here: card layout, form layout, navigation structure, modal behaviour, etc.

## Change Log
Date | Change | Approved by
```

---

## Phase 5 — Manifest Schema

Create `$CF/ClaudeCodeRepo/agents/manifest-template.json`.

**Critical rule: only Orchestrator writes to manifest.json. All other agents read it or drop signal files. Never write directly to manifest from a watcher.**

```json
{
  "project": "PROJECT_NAME",
  "created": "ISO_TIMESTAMP",
  "goal": "High level goal description",
  "prd": "PROJECT_NAME/PRD.md",
  "adr": "PROJECT_NAME/ADR.md",
  "locked_files": {},
  "tasks": [
    {
      "id": "task-001",
      "assigned_to": "design-guardian",
      "status": "pending",
      "input": "Review this UI task and add design constraints before it goes to builder: [task description]. Reference DESIGN_SYSTEM.md.",
      "depends_on": [],
      "branch": null,
      "output_file": null,
      "review_gate": null,
      "pr_url": null
    },
    {
      "id": "task-002",
      "assigned_to": "builder-systems",
      "status": "waiting",
      "input": "Create [component/service]. Interface spec: [inputs, outputs, behaviour]. Reference ADR.md for technical approach. Design constraints from task-001 output apply.",
      "depends_on": ["task-001"],
      "branch": "agent/task-002-component-name",
      "output_file": null,
      "review_gate": "architect",
      "pr_url": null
    },
    {
      "id": "task-003",
      "assigned_to": "builder-data",
      "status": "pending",
      "input": "Add [table/migration/query]. Schema spec: [fields, types, constraints, indexes]. Reference ADR.md. schema.prisma may only be modified with explicit the user approval in this spec.",
      "depends_on": [],
      "branch": "agent/task-003-data-layer",
      "output_file": null,
      "review_gate": "architect",
      "pr_url": null
    },
    {
      "id": "task-004",
      "assigned_to": "builder-composer",
      "status": "waiting",
      "input": "Wire [feature] using components from task-002. Do not create new primitives. Design constraints from task-001 apply. Reference ADR.md.",
      "depends_on": ["task-002", "task-003"],
      "branch": "agent/task-004-feature-name",
      "output_file": null,
      "review_gate": null,
      "pr_url": null
    },
    {
      "id": "task-005",
      "assigned_to": "tester",
      "status": "waiting",
      "input": "Test task-004 output. Functional tests for [feature]. Check regression_scope pages.",
      "depends_on": ["task-004"],
      "branch": "agent/task-004-feature-name",
      "output_file": null,
      "review_gate": null,
      "pr_url": null
    },
    {
      "id": "task-006",
      "assigned_to": "ui-reviewer",
      "status": "waiting",
      "input": "Review task-004 output against DESIGN_SYSTEM.md. Report PASS / DRIFT / BROKEN.",
      "depends_on": ["task-004"],
      "branch": "agent/task-004-feature-name",
      "output_file": null,
      "review_gate": "architect",
      "pr_url": null
    },
    {
      "id": "task-007",
      "assigned_to": "reviewer",
      "status": "waiting",
      "input": "Review code from tasks 002–004 for quality and security. Flag CRITICAL/HIGH security findings for the user.",
      "depends_on": ["task-004"],
      "branch": "agent/task-004-feature-name",
      "output_file": null,
      "review_gate": "architect",
      "pr_url": null
    }
  ]
}
```

**Status flow**: `waiting` → `pending` → `in_progress` → `done` | `reviewed` | `failed`

Orchestrator sets status. Watchers never set status — they signal via `signals/` folder only.

**Builder assignment decision tree — Planner uses this when writing tasks:**
1. Touches schema, migrations, or queries? → `builder-data`
2. Calls an external API or third-party service? → `builder-integration`
3. Creates a new reusable component, service, or utility? → `builder-systems`
4. Wires existing parts into a feature? → `builder-composer`
5. None of the above, or spans multiple categories? → `builder-generalist`

If more than 20% of tasks land on `builder-generalist`, task specs are too broad — split them.

---

## Phase 6 — Signal File Schema

Create `$CF/ClaudeCodeRepo/agents/signal-schema.json` as reference. Watchers write these to `agent-workspace/signals/` — Orchestrator reads and deletes them.

```json
{
  "task_id": "task-004",
  "agent": "builder-composer",
  "status": "done",
  "tokens_in": 2840,
  "tokens_out": 1200,
  "cost_usd": 0.0043,
  "started": "2024-01-15T14:23:00Z",
  "completed": "2024-01-15T14:24:12Z",
  "duration_seconds": 72,
  "output_file": "builder-composer/output/task-004.md",
  "flags": ""
}
```

Signal filename: `[task-id].[status].json` e.g. `task-004.done.json`, `task-005.failed.json`

Orchestrator processes signals in the order they arrive. After processing, it deletes the signal file and appends an entry to `run-log.jsonl`.

---

## Phase 7 — Orchestrator watch.sh (Background Coordinator)

Create `orchestrator/watch.sh`. This is the coordination engine — the only process that writes to `manifest.json`.

The script runs a loop every 15 seconds:

```
1. PROCESS SIGNALS
   - Scan signals/ for any *.json files
   - For each signal:
     a. Read task_id, status, tokens, cost
     b. Update manifest task status
     c. Release file locks for that task from locked_files
     d. Append entry to run-log.jsonl
     e. Delete signal file
     f. Print: ✅ task-004 done | builder-composer | 2,840 tokens | $0.0043

2. CHECK BUDGET
   - Sum cost_usd in run-log.jsonl
   - If total >= budget_alert_at: print warning and stop launching new tasks
   - If total >= budget_usd: stop all task activation, notify the user

3. CHECK FOR FAILURES
   - If any task status is 'failed': print alert with task_id and agent
   - Do not auto-retry — wait for Planner to replan

4. UNLOCK DEPENDENT TASKS
   - Find tasks with status 'waiting'
   - For each: check all depends_on tasks are 'done' or 'reviewed' (with gate approved)
   - If deps met: check locked_files — if files needed are free, mark task 'pending' and register file locks
   - If files locked: skip this cycle, retry next

5. CHECK FOR CYCLE COMPLETION
   - If all tasks are done/reviewed/failed and no tasks are pending/in_progress:
     a. Print cycle summary with cost totals
     b. Notify: "Cycle complete — Architect review needed before PR"
     c. Wait for Architect approval signal before triggering git/PR

6. GIT / PR WORKFLOW (triggered by Architect approval signal)
   - Verify task branches are clean against main
   - If conflicts: alert the user, do not proceed
   - For clean branches: gh pr create with task context + reviewer findings
   - Update manifest pr_url fields
   - Print PR URLs

7. SLEEP 15s, REPEAT
```

Orchestrator never invokes Claude for planning or judgment. It is pure coordination logic — shell script and Python only, no LLM calls in the coordination loop.

---

## Phase 8 — Watcher watch.sh (Execution Agents)

Create `watch.sh` inside all builder folders, `tester/`, `reviewer/`, and `ui-reviewer/`. All use the same template — only the `AGENT` variable at the top differs.

**Critical difference from v3: watchers never write to manifest. They only read it and drop signal files.**

The script must:

1. Read `$PROJECT_CONFIG` env var to get all paths and settings
2. Extract this agent's model from config
3. Every 30 seconds, scan `manifest.json` (read-only) for tasks where:
   - `assigned_to` matches this agent
   - `status` is `pending`
4. If a task is found:
   a. Record `START_TIME`
   b. Invoke Claude: `echo "$TASK_INPUT" | claude --model $MODEL --print --output-format json > /tmp/task-response.json`
   c. Extract `tokens_in`, `tokens_out`, `result` from JSON response
   d. Calculate cost using `shared/costs.json`
   e. Write output to `agent-workspace/[agent]/output/[task-id].md`
   f. Write signal file to `agent-workspace/signals/[task-id].[status].json`
      - Status: `done` for builders and tester (pass), `failed` for tester (fail), `reviewed` for reviewer and ui-reviewer
   g. Print: `📤 Signal dropped: task-004.done.json | 2,840 tokens | $0.0043`
5. If no pending task found, sleep 30s and repeat
6. Never write to manifest.json under any circumstances

Handle failures: Claude exits non-zero → write `[task-id].failed.json` signal, include error summary in output file.

Note: No flock or file lock logic in watchers — Orchestrator owns all locking. Watchers only need to write to their own output folder and the signals folder, which are segregated by task_id and never conflict.

---

## Phase 9 — Agent CLAUDE.md Files

### All agents — common header
Every CLAUDE.md must start with:
```markdown
## Runtime Context
At session start, read the `$PROJECT_CONFIG` environment variable to load:
- project_root, workspace, manifest path, signals path
- design_system path, adr path
- Stack and conventions

Never hardcode project paths. All file operations use paths from config.
```

---

### `planner/CLAUDE.md`

Role: Product-minded planning. Owns the PRD and task graph. Thinks in outcomes and user value, not implementation.

**PRD format — always produce this before writing tasks:**
```markdown
## PRD — [Feature Name]
Problem: what user problem does this solve
Users: who is affected
Success criteria: how we know it's done (measurable where possible)
Scope: what is included
Out of scope: what is explicitly excluded
Constraints: technical, time, or resource constraints
Open questions: things that need answers before or during build
```

**Task writing rules:**
- Each task must be fully self-contained — a fresh Claude session with no prior context must be able to complete it from the task input alone
- Include: what to build, relevant file paths, interface contracts, design constraints, ADR reference
- Size tasks for a single agent session — not too granular (one function), not too broad (entire feature)
- Maximise parallelism — minimise depends_on chains; tasks that don't share files should run simultaneously
- Always insert a Design Guardian task before any builder task that touches UI
- Always insert a UI Reviewer task and Tester task after any builder task
- Always insert a Reviewer task covering the full cycle before Architect reviews

**Builder assignment decision tree:**
1. Touches schema, migrations, or queries? → `builder-data`
2. Calls external API or third-party service? → `builder-integration`
3. Creates new reusable component, service, or utility? → `builder-systems`
4. Wires existing parts into a feature? → `builder-composer`
5. None of the above or spans categories? → `builder-generalist`

If more than 20% of tasks go to `builder-generalist`, specs are too broad — split them.

**When replanning:**
- Read Architect's rejection note carefully — understand the root cause before replanning
- Fix the spec, not just the symptom
- Do not add tasks to patch bad output — fix the original task spec and requeue

End every session with a `<trace>` block.

---

### `orchestrator/CLAUDE.md`

Role: Pure coordination engine. Runs continuously as a background watcher. Never plans, never judges, never invokes Claude for reasoning.

- Sole writer of manifest.json — no other agent modifies this file
- Processes signal files from signals/ folder and updates manifest accordingly
- Manages file locks in locked_files — assigns on task activation, releases on signal receipt
- Monitors budget — alerts when threshold exceeded, halts task activation when budget hit
- Triggers git/PR workflow only when Architect approval signal received
- Alerts Planner and the user when tasks fail — does not replan itself
- Never touches protected files directly — only manages the git/PR commands

This agent has no interactive mode. It runs watch.sh continuously and does not need a CLAUDE.md for interactive sessions. Its coordination logic lives entirely in watch.sh.

---

### `architect/CLAUDE.md`

Role: Technical strategy. Appears at two points in the flow — before builders start (design) and after they finish (quality gate).

**Mode 1 — Technical Design (before builders start)**

Triggered after Planner writes manifest, before Orchestrator activates builder tasks.

Produce an ADR (Architecture Decision Record) saved to `ADR.md` in project root:
```markdown
## ADR — [Feature Name]
Date: ISO date
Status: proposed

### Technical Approach
How the feature will be built at a structural level

### Key Decisions
Decision | Rationale | Alternatives considered

### Interface Contracts
For each builder-systems output that builder-composer will consume:
  - Component/service name
  - Inputs (types)
  - Outputs (types)
  - Behaviour

### Data Shape
Any new data structures, API response shapes, state shapes

### Risks
Technical risks and mitigations

### What Builders Must Not Do
Constraints and anti-patterns specific to this feature
```

Flag any risks or constraints back to Planner before builders start — it is cheaper to fix the plan than fix the code.

**Mode 2 — Quality Gate (after cycle completes)**

Triggered when Orchestrator signals cycle complete.

- Read builder output files from their output/ folders
- Read Reviewer and UI Reviewer reports
- Check against ADR: does the implementation match the intended architecture?
- Check structural decisions, not code style (Reviewer owns that)
- If approving: write an approval signal file to signals/ → Orchestrator triggers git/PR
- If rejecting: write a structured rejection note to Planner — specific, actionable, root-cause focused
- Never fix issues directly — always route back through Planner

End every session with a `<trace>` block.

---

### `researcher/CLAUDE.md`

Role: Open-ended research and synthesis. Triggered explicitly by Planner, not on a schedule.

- Trigger criteria: task requires external knowledge not in codebase or project docs — library evaluation, API investigation, competitive analysis, technology selection
- Output structured findings: summary, sources, assumptions, confidence (high/medium/low)
- Keep output focused — Planner decides what to do with findings
- End every session with a `<trace>` block

---

### `design-guardian/CLAUDE.md`

Role: Design system owner. Runs before any builder task that touches UI. Adds design constraints to task specs so builders never invent.

- Read `DESIGN_SYSTEM.md` at the start of every session
- Review incoming UI task description
- Output design-annotated task spec: which components, which tokens, spacing, typography, applicable patterns
- If task requires a new component or pattern not in design system: flag it, propose addition, stop until the user confirms
- If `DESIGN_SYSTEM.md` does not exist: stop and tell the user — do not invent a design system
- End every session with a `<trace>` block

---

### `builder-composer/CLAUDE.md`

Role: Wire existing parts into features. Highest-volume builder. Never invents primitives.

- Assembles features from existing components, services, and APIs only
- Read `ADR.md` at session start — follow interface contracts exactly
- If something needed does not exist: write `BLOCKED` note with specific missing primitive — do not create it
- Never modify files outside task scope
- Work on branch specified in task
- Follow design constraints exactly as specified in task input
- Run lint and build after changes
- Write output to `output/[task-id].md` then drop signal file
- Output summary: what was wired + any flags

---

### `builder-systems/CLAUDE.md`

Role: Create reusable primitives — components, services, utilities — that composer tasks depend on.

- Read `ADR.md` at session start — build to the interface contracts defined there
- Single responsibility — one thing, done well, named clearly
- No side effects outside the component/service boundary
- Design for reuse: clean API surface, no assumptions about callers
- Never modify files outside task scope
- Work on branch specified in task
- Follow design constraints exactly as specified in task input
- Run lint and build after changes
- Write output to `output/[task-id].md` then drop signal file
- Output includes interface documentation: what it does, how to call it, what it returns

---

### `builder-data/CLAUDE.md`

Role: Schema, migrations, queries, data access layer. Highest-risk builder — smallest scope, strictest rules.

- Read `ADR.md` at session start — follow data shape decisions exactly
- `schema.prisma` is a protected file — only modify if task spec contains explicit `SCHEMA_CHANGE_APPROVED_BY_USER` flag
- Migrations must be safe: never destructive without explicit `DESTRUCTIVE_APPROVED` flag in task input
- Never raw SQL unless explicitly required — use data access layer
- Always consider query performance: no N+1 patterns, add indexes for fields used in WHERE or ORDER BY
- Validate data integrity: foreign keys, unique constraints, required fields
- Work on branch specified in task
- Write output to `output/[task-id].md` then drop signal file
- Output includes: data model changes, migration notes, performance considerations

---

### `builder-integration/CLAUDE.md`

Role: Third-party services, external APIs, webhooks, OAuth flows, payment providers.

- Read `ADR.md` at session start
- Assume the external service will behave unexpectedly — always handle errors defensively
- Never trust external response shapes without validating (use Zod or equivalent)
- Wrap all external calls with retry logic and timeout handling
- Never expose raw external service errors to users — translate to internal error types
- Log all external interactions with enough context to debug failures
- Never hardcode API keys or secrets — read from environment variables only
- Work on branch specified in task
- Run lint and build after changes
- Write output to `output/[task-id].md` then drop signal file
- Output includes: external service behaviour, error cases handled, rate limit/quota notes

---

### `builder-generalist/CLAUDE.md`

Role: Fallback for tasks that don't fit a specialisation or span multiple categories.

- Apply combined discipline of all builders: clean interfaces, defensive error handling, no design system violations, no unsafe data operations
- Read `ADR.md` at session start if it exists
- If task clearly belongs to a specialist in hindsight: note this in output so Planner can improve future task splitting
- Never modify files outside task scope
- Work on branch specified in task
- Run lint and build after changes
- Write output to `output/[task-id].md` then drop signal file

---

### `tester/CLAUDE.md`

Role: Validate builder output works correctly and hasn't broken anything.

- Run functional tests relevant to task scope
- Check `regression_scope` in project config — if builder touched a shared component, test all `always_test_pages`
- Use Playwright for visual regression where configured: screenshot before/after, diff, flag visual changes outside task scope
- Output structured report: PASS / PARTIAL / FAIL + itemised findings with severity
- Write output to `output/[task-id].md`
- Drop `[task-id].done.json` signal if tests pass, `[task-id].failed.json` if critical tests fail
- Do not fix issues — report them clearly

---

### `reviewer/CLAUDE.md`

Role: Combined code quality and security review. Output gates via Architect.

**Code quality checks:**
- Conventions match stack and `CONVENTIONS.md`
- No unnecessary complexity, dead code, or hardcoded values
- Error handling present and appropriate
- No new dependencies introduced without flagging

**Security checks:**
- Injection vulnerabilities (SQL, XSS, command)
- Auth and authorisation issues
- Secrets or credentials in code
- Insecure dependencies
- Data exposure risks

**Output format:** Two-section report (Code Quality, Security). Each finding: severity (CRITICAL / HIGH / MEDIUM / LOW), location, description, suggested fix. Overall verdict: PASS / NEEDS_CHANGES / FAIL.

CRITICAL or HIGH security findings flagged explicitly for the user regardless of overall verdict.

Write output to `output/[task-id].md` then drop `[task-id].reviewed.json` signal.

---

### `ui-reviewer/CLAUDE.md`

Role: Design system compliance check. Output gates via Architect.

- Read `DESIGN_SYSTEM.md` at session start
- Compare builder output against design system: token usage, component usage, spacing, typography
- Output structured report: PASS / DRIFT / BROKEN
  - PASS: fully compliant
  - DRIFT: minor inconsistency, Architect decides
  - BROKEN: major violation or broken layout, must return to builder
- List each finding: location, expected, found
- Write output to `output/[task-id].md` then drop `[task-id].reviewed.json` signal

---

## Phase 10 — Trace Format (Thinking Agents)

Add to Planner, Architect, Researcher, and Design Guardian CLAUDE.md files:

```markdown
## Output Format — Trace Block
Always end your response with:

<trace>
  decision: what you chose to do and why
  alternatives_considered: other approaches you ruled out
  assumptions: things you assumed that aren't explicit in the input
  confidence: high / medium / low
  flags: anything downstream agents or the user should know
</trace>
```

Orchestrator saves trace content to `agent-workspace/decisions/[task-id]-trace.md` when processing signals from thinking agents.

---

## Phase 11 — Logging Infrastructure

Create these files in each new project workspace (not globally):

### `agent-workspace/run-log.jsonl`
Written by Orchestrator only. Append-only. One JSON line per processed signal.
Schema: `{ task_id, agent, model, started, completed, duration_seconds, status, tokens_in, tokens_out, cost_usd, project }`

### `agent-workspace/quality-log.json`
Human-maintained. Updated by the user or Architect after reviewing output.
Schema per entry: `{ task_id, agent, model, score, issue, root_cause, fix_applied }`
Score: 1 = needs redo, 2 = acceptable, 3 = good. Patterns drive future CLAUDE.md improvements.

### `agent-workspace/signals/`
Live signal files dropped by watchers, processed and deleted by Orchestrator. Should be empty between task completions.

### `agent-workspace/decisions/`
Trace files from thinking agents. Filename: `[task-id]-trace.md`.

---

## Phase 12 — GitHub Actions (CI/CD)

Create `.github/workflows/ci.yml` in each project repo. Agents feed into this pipeline — they do not replace it.

```yaml
name: CI

on:
  pull_request:
    branches: [main]
  push:
    branches: [main]

jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - run: npm ci
      - run: npm run lint
      - run: npm run build
      - run: npm test

  deploy:
    needs: ci
    if: github.ref == 'refs/heads/main' && github.event_name == 'push'
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Deploy
        run: echo "Add deploy command here"
```

Orchestrator opens PRs. GitHub Actions runs CI on PR. the user reviews CI + reviewer reports + PR description, then merges. Deployment triggers on merge to main.

Agents never merge. Agents never deploy. These are always human-triggered.

---

## Phase 13 — Workspace Init Script

Create `$CF/ClaudeCodeRepo/agents/shared/init-project.sh`:

Takes `PROJECT` as argument. Creates full workspace structure:

```
$CF/ClaudeProjects/$PROJECT/
  .agent-config.json              (copied from template, PROJECT substituted)
  DESIGN_SYSTEM.md                (copied from design-system-template.md)
  CONVENTIONS.md                  (empty — fill before first build task)
  ADR.md                          (empty — Architect fills this)
  PRD.md                          (empty — Planner fills this)
  .github/
    workflows/
      ci.yml                      (copied from CI template)
  agent-workspace/
    manifest.json                 (empty template)
    run-log.jsonl                 (empty)
    quality-log.json              (empty {})
    signals/                      (empty — Orchestrator watches this)
    decisions/                    (empty)
    planner/
      output/
    architect/
      output/
    builder-composer/
      output/
    builder-systems/
      output/
    builder-data/
      output/
    builder-integration/
      output/
    builder-generalist/
      output/
    tester/
      output/
    reviewer/
      output/
    ui-reviewer/
      output/
    design-guardian/
      output/
```

Prints next steps after creating:
```
✅ Project workspace created for: PROJECT_NAME

Before starting:
1. Edit .agent-config.json — set stack, git_repo, budget, regression_scope
2. Fill DESIGN_SYSTEM.md — required before any UI tasks
3. Fill CONVENTIONS.md — required before any builder tasks
4. Set up GitHub Actions secrets if deploying

To get all launch commands:
  ./shared/start-project.sh PROJECT_NAME

Startup order:
  1. Launch Orchestrator tab first (background coordinator)
  2. Run Planner → PRD + manifest.json
  3. Run Architect → ADR.md + interface contracts
  4. Launch remaining watcher tabs
```

---

## Phase 14 — INDEX.md

Create `$CF/ClaudeCodeRepo/agents/INDEX.md` documenting:

- Full agent roster table
- Planner vs Orchestrator distinction — what each owns
- Architect two-mode explanation (design upstream, quality gate downstream)
- Full task flow diagram:
  `Planner → manifest → Architect (ADR) → Orchestrator activates tasks → Design Guardian → builder-systems + builder-data (parallel) → builder-integration → builder-composer → Tester + UI Reviewer (parallel) → Reviewer → Architect gate → Orchestrator PR → the user merges → GitHub Actions deploys`
- Signal file schema and lifecycle (written by watcher, processed+deleted by Orchestrator)
- Manifest ownership rule: Orchestrator only
- Builder specialisation decision tree
- Generalist usage rule (fallback only, flag if over 20%)
- Gate logic: who approves what
- Researcher trigger criteria
- Design Guardian trigger criteria
- How to initialise a new project
- How to launch agents (start-project.sh)
- How to run parallel builder instances
- How to check costs
- Protected files policy
- Manifest status flow
- ADR.md format and when Architect writes it

---

## Verification Checklist

After implementation, verify:

- [ ] `init-project.sh flat_value` creates correct workspace including signals/, ADR.md, PRD.md
- [ ] `start-project.sh flat_value` prints Orchestrator first, then watchers, then interactive agents
- [ ] Orchestrator watch.sh starts and polls signals/ every 15s with no errors
- [ ] Planner writes a valid manifest.json with correct task schema
- [ ] Architect writes ADR.md before builder tasks are activated
- [ ] Orchestrator marks a `waiting` task `pending` when all deps are `done` and files are free
- [ ] Watcher (builder-composer) picks up `pending` task and invokes Claude
- [ ] Watcher drops signal file to signals/ — does NOT write to manifest
- [ ] Orchestrator processes signal: updates manifest status, releases file locks, appends run-log.jsonl, deletes signal
- [ ] Two builder-composer instances pick up different tasks without conflict (no flock needed — Orchestrator serialises activation)
- [ ] builder-data refuses to touch schema.prisma without SCHEMA_CHANGE_APPROVED_BY_USER flag
- [ ] Budget alert triggers when threshold exceeded — Orchestrator stops activating new tasks
- [ ] Failed task alert printed by Orchestrator — no auto-retry
- [ ] Reviewer and UI Reviewer drop `reviewed` signals, not `done`
- [ ] Orchestrator waits for Architect approval signal before triggering git/PR workflow
- [ ] Orchestrator opens PR via `gh pr create` with correct body
- [ ] `cost-report.sh flat_value` outputs correct totals by agent
- [ ] Trace blocks saved to decisions/ folder
- [ ] GitHub Actions CI runs on PR open
- [ ] Deployment does not trigger until the user merges

---

## Notes for Review Before Running

- **Launch Orchestrator first** — it must be running before any watcher drops a signal, or signals pile up unprocessed
- **Fill DESIGN_SYSTEM.md before any UI work** — Design Guardian and UI Reviewer are useless without it
- **Architect must write ADR.md before builders start** — builders reference it; without it they'll invent
- **Fill CONVENTIONS.md before first builder task** — builders reference it for code style
- **Planner CLAUDE.md is the quality ceiling** — vague PRDs produce vague tasks, which produce bad output at every stage downstream
- **builder-data is the highest-risk agent** — double-check protected file flags before first run
- **builder-generalist is a fallback** — if it's getting most tasks, Planner's specs are too broad
- **Orchestrator uses Sonnet not Opus** — its job is mechanical, not reasoning; Sonnet is faster and cheaper here
- **signals/ should be empty between task completions** — if signals accumulate, Orchestrator has stopped or crashed
- **Budget caps** — set conservatively on first project ($5 suggested), increase once pipeline is trusted
- **regression_scope** — fill shared_components and always_test_pages before first Tester run
- **GitHub Actions** — add deploy step and secrets before first merge to main
- **quality-log.json** — score outputs from day one; patterns here drive agent CLAUDE.md improvements over time
- **Multiple builder instances** — safe to run; Orchestrator serialises task activation so two instances never get the same task
