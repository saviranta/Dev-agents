# Dev-Agents — Index

Multi-agent development orchestration system for Claude Code.
Agents live globally here. Each project supplies its own `.agent-config.json` and `agent-workspace/`.

---

## Agent Roster

| Agent | Type | Signal output | Role |
|-------|------|---------------|------|
| Planner | Interactive | — | PRD → task graph → manifest. Product-minded PO. |
| Validator | Interactive | `manifest.validated.json` | Checks manifest for structural + content issues before Orchestrator activates tasks. |
| Orchestrator | Background watcher | — | Signal processing, manifest writes, file locks, git/PRs |
| Architect | Interactive | `cycle.approved.json` | Technical design upstream + quality gate downstream |
| Researcher | Interactive | — | Explicit trigger only — external knowledge tasks |
| Design Guardian | Interactive | — | Design constraints before any UI builder task |
| Builder — Composer | Watcher | `done` | Wires existing parts into features. Highest volume. |
| Builder — Systems | Watcher | `done` | Creates primitives: components, services, utilities |
| Builder — Data | Watcher | `done` | Schema, migrations, queries. Strictest rules. |
| Builder — Integration | Watcher | `done` | External APIs, webhooks, third-party services |
| Builder — Generalist | Watcher | `done` | Fallback for tasks that don't fit a specialisation |
| Tester | Watcher | `done` / `failed` | Functional + visual regression |
| Reviewer | Watcher | `reviewed` | Code quality + security combined |
| UI Reviewer | Watcher | `reviewed` | Design system compliance |

---

## Key Design Rules

**Planner owns the what** — product thinking, PRD, task decomposition, replanning.
**Orchestrator owns coordination** — runs continuously, sole writer of `manifest.json`, manages signals and file locks.
**Architect owns the how** — technical design before builders start, quality gate after they finish.
**Watchers never write to manifest** — they drop signal files only; Orchestrator processes signals and updates manifest.
Builders are specialised by **cognitive mode**, not file location.
**Generalist is a fallback** — if it's getting >20% of tasks, Planner's specs are too broad.
**Autonomy decreases as consequence increases** — builders fully autonomous, merge always requires Lauri.

---

## Task Flow

```
Planner
  → writes PRD.md + task graph → manifest.json

Architect (Mode 1 — Design)
  → reads PRD + task list
  → writes ADR.md + interface contracts
  → flags risks to Planner if needed

Orchestrator (background, always running)
  → activates waiting tasks when deps met + files free
  → processes signals/ → updates manifest → run-log.jsonl

[Parallel where deps allow]
Design Guardian  → annotates UI tasks with design constraints
Builder — Data   → schema, migrations, queries
Builder — Systems → creates primitives per ADR interface contracts

Builder — Integration → external service wiring
Builder — Composer  → wires everything into features

[Parallel]
Tester           → functional + regression tests
UI Reviewer      → design system compliance
Reviewer         → code quality + security

Architect (Mode 2 — Quality Gate)
  → reads builder outputs + reviewer reports
  → APPROVE → drops signals/cycle.approved.json
  → REJECT  → structured feedback to Planner → replan cycle

Orchestrator
  → receives cycle.approved.json
  → opens PRs via gh pr create

Lauri
  → reviews CI + PR + reviewer reports
  → merges → GitHub Actions deploys
```

---

## Signal File Lifecycle

1. Watcher completes task → drops `signals/[task-id].[status].json`
2. Orchestrator reads signal → updates manifest status → releases file locks → appends `run-log.jsonl` → deletes signal
3. Orchestrator checks for newly unblocked tasks → sets `waiting` → `pending`

Signal statuses:
- `done` — builders, tester (pass)
- `reviewed` — reviewer, ui-reviewer
- `failed` — any agent on error
- `manifest.validated.json` — Validator approval (gates Orchestrator task activation)
- `cycle.approved.json` — Architect approval (special file)

Signals folder should be empty between task completions. Accumulation means Orchestrator stopped.

---

## Manifest Status Flow

```
waiting → pending → in_progress → done
                               → reviewed
                               → failed
```

Only Orchestrator writes status changes. Watchers read manifest (read-only) and drop signals.

---

## Builder Assignment Decision Tree

Planner uses this when writing tasks:

1. Touches schema, migrations, or queries? → `builder-data`
2. Calls external API or third-party service? → `builder-integration`
3. Creates new reusable component, service, or utility? → `builder-systems`
4. Wires existing parts into a feature? → `builder-composer`
5. None of the above or spans categories? → `builder-generalist`

If >20% of tasks land on `builder-generalist`, task specs are too broad — split them.

---

## Gate Logic

| Gate | Who approves |
|------|-------------|
| Builder output quality | Architect (cycle approval) |
| UI compliance | Architect (via UI Reviewer report) |
| Security CRITICAL/HIGH | Lauri (flagged in Reviewer output) |
| PR merge | Lauri always |
| Deployment | Lauri always (triggered by merge) |

---

## Researcher Trigger Criteria

Only trigger Researcher for tasks requiring external knowledge:
- Library evaluation and comparison
- External API investigation
- Competitive analysis
- Technology selection
- Security advisories for dependencies

Do not trigger for tasks answerable from the codebase.

---

## Design Guardian Trigger Criteria

Required before any builder task that touches UI. Planner must insert a Design Guardian task in `depends_on` for every UI builder task.

If `DESIGN_SYSTEM.md` does not exist for the project: Design Guardian stops and alerts Lauri.

---

## Initialising a New Project

```bash
cd ~/Library/CloudStorage/Dropbox/ClaudeFolder/Agents
./shared/init-project.sh PROJECT_NAME
```

## Adding Agents to an Existing Project

For projects that existed before the agent system:

```bash
./shared/add-workspace.sh PROJECT_NAME
```

Creates only `agent-workspace/` and missing config files. Skips anything already present — safe to re-run. Then fill in `.agent-config.json` with the project's stack, git_repo, and budget.

Then fill:
1. `.agent-config.json` — set stack, git_repo, budget, regression_scope
2. `DESIGN_SYSTEM.md` — required before any UI tasks
3. `CONVENTIONS.md` — required before any builder tasks

---

## Runners

Two runner implementations are available. Each watcher agent has a corresponding script for each:

| File | Runner | Requires |
|------|--------|----------|
| `watch.sh` | Claude Code CLI (`claude`) | Claude Code installed |
| `watch-api.sh` | Anthropic API (`claude-api-runner.py`) | `pip install anthropic` + `ANTHROPIC_API_KEY` |

Interactive agents (Planner, Architect, Design Guardian, Researcher) are always run as Claude Code sessions — no watcher script, no runner choice.

---

## Launching Agents

**Claude Code runner:**
```bash
./shared/launch-agent.sh AGENT PROJECT_NAME
```

**Anthropic API runner:**
```bash
./shared/launch-api-agent.sh AGENT PROJECT_NAME
```

`start-project.sh` prints one launch command per terminal tab (Claude Code runner by default).

Startup order:
1. Run pre-flight (resuming an existing session): `./shared/preflight.sh PROJECT_NAME`
   - Planner audits state: resets stuck tasks, clears stale locks, archives orphaned signals
   - Review report, address any failed tasks, then continue to step 4
2. Launch Orchestrator tab (background coordinator — must be running first)
3. Run Planner → PRD + manifest.json  _(new session only — skip if resuming)_
4. Run Architect → ADR-phase-N.md + interface contracts  _(new session only — skip if resuming)_
5. Run Validator → `./shared/validate-manifest.sh PROJECT_NAME`
   - BLOCK items found: bring report to Planner, fix manifest, re-run Validator
   - PASS: Validator drops `signals/manifest.validated.json`, Orchestrator begins activating tasks
6. Launch remaining watcher tabs

---

## Parallel Builders

Safe to run multiple instances of the same builder — Orchestrator serialises task activation so two instances never pick up the same task:

```bash
./shared/launch-agent.sh builder-composer PROJECT_NAME      # tab A (Claude Code)
./shared/launch-agent.sh builder-composer PROJECT_NAME      # tab B (Claude Code)

# or with the API runner:
./shared/launch-api-agent.sh builder-composer PROJECT_NAME  # tab A (API)
./shared/launch-api-agent.sh builder-composer PROJECT_NAME  # tab B (API)
```

---

## Cost Reporting

```bash
./shared/cost-report.sh PROJECT_NAME
```

Outputs: Agent | Tasks | Tokens In | Tokens Out | Cost USD

---

## Protected Files Policy

These files require explicit approval flags in the task spec before a builder may touch them:
- `schema.prisma` — requires `SCHEMA_CHANGE_APPROVED_BY_LAURI` in task input
- `.env.example` — list in `git.protected_files` in config
- `package.json`, `package-lock.json` — list in `git.protected_files` in config

builder-data enforces the schema.prisma rule. All agents must refuse to modify protected files without the flag.

---

## ADR Format

Architect writes `ADR.md` to project root before builders start:

```markdown
## ADR — [Feature Name]
Date:   ISO date
Status: proposed

### Technical Approach
### Key Decisions
Decision | Rationale | Alternatives considered
### Interface Contracts
Component/service | Inputs | Outputs | Behaviour
### Data Shape
### Risks
### What Builders Must Not Do
```

---

## Trace Block Format (Thinking Agents)

Planner, Architect, Researcher, and Design Guardian end every response with:

```
<trace>
  decision:               what you chose to do and why
  alternatives_considered: other approaches you ruled out
  assumptions:            things you assumed that aren't explicit in the input
  confidence:             high / medium / low
  flags:                  anything downstream agents or Lauri should know
</trace>
```

Orchestrator saves trace content to `agent-workspace/decisions/[task-id]-trace.md`.

---

## Folder Structure

```
Agents/
  planner/CLAUDE.md
  validator/CLAUDE.md
  orchestrator/CLAUDE.md + watch.sh
  architect/CLAUDE.md
  researcher/CLAUDE.md
  design-guardian/CLAUDE.md
  builder-composer/CLAUDE.md + watch.sh + watch-api.sh
  builder-systems/CLAUDE.md + watch.sh + watch-api.sh
  builder-data/CLAUDE.md + watch.sh + watch-api.sh
  builder-integration/CLAUDE.md + watch.sh + watch-api.sh
  builder-generalist/CLAUDE.md + watch.sh + watch-api.sh
  tester/CLAUDE.md + watch.sh + watch-api.sh
  reviewer/CLAUDE.md + watch.sh + watch-api.sh
  ui-reviewer/CLAUDE.md + watch.sh + watch-api.sh
  shared/
    preflight.sh        — runs Planner in pre-flight mode (state audit + correction)
    validate-manifest.sh — runs the Validator agent against a project manifest
    launch-agent.sh     — launches a watcher agent (Claude Code CLI runner)
    launch-api-agent.sh — launches a watcher agent (Anthropic API runner)
    claude-api-runner.py — drop-in API replacement for `claude --print --output-format json`
    start-project.sh    — prints all launch commands for a project
    init-project.sh     — initialises project workspace
    cost-report.sh      — prints cost summary
    costs.json          — model pricing table
  templates/
    project-config-template.json
    design-system-template.md
    manifest-template.json
    signal-schema.json
    ci.yml
  INDEX.md              — this file
```

Project workspaces live at `ClaudeFolder/ClaudeProjects/PROJECT_NAME/` — outside this repo.
