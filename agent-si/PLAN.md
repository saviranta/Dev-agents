# Agent-SI — Implementation Plan

A single interactive agent for improving the agent system itself. Launched as a normal Claude Code session; you talk to it and ask it to audit or propose improvements.

```bash
./shared/launch-agent.sh agent-si PROJECT_NAME
# or without a project context:
./shared/launch-agent.sh agent-si
```

---

## Folder structure

```
Agents/
  meta/
    CLAUDE.md               ← agent instructions
    system-journal.md       ← living record of observations + outcomes
    metrics-baseline.md     ← rolling metric snapshots (one column per audit)
    rfcs/
      RFC-001.md
      RFC-002.md
      ...
    extract-metrics.sh      ← data extraction script
    PLAN.md                 ← this file
```

---

## What the agent does

Two things, triggered conversationally:

**Audit** — you ask "run an audit on the last project" or "what does the baseline look like"
1. Calls `extract-metrics.sh PROJECT_NAME` → structured JSON
2. Reads `agent-workspace/decisions/` trace files
3. Reads reviewer output files for CRITICAL/HIGH flag counts
4. Asks you 4 structured questions (see below)
5. Appends a column to `metrics-baseline.md`
6. Writes a journal entry with observations and any flagged trends
7. Checks open `implemented` RFCs — if enough projects have passed, evaluates outcome against targets

**Improve** — you ask "propose an improvement for X" or "look at the fix task rate"
1. Reads journal + baseline + all agent CLAUDE.md files + INDEX.md + shared scripts
2. Identifies root cause from available data
3. Writes an RFC to `agent-si/rfcs/RFC-NNN.md`
4. Presents it to you for review
5. On approval: implements the changes, commits with RFC number in message
6. Writes a journal entry: what changed, metric targets, suggested review date

---

## Post-audit user questions

Asked during every audit after auto-collection:

```
1. Builder output quality overall (1–5):
2. Manual interventions mid-session (0 / 1–3 / 4+):
3. Any agents that caused repeated problems? (free text or none):
4. Anything that worked unusually well? (free text or none):
```

Answers written into the journal as a `user-feedback` entry tied to the project and date.

---

## Agent-written journal entries

Planner and Architect (and optionally Reviewer, Tester) can write directly to `system-journal.md` during their normal sessions — not just during a Meta audit. This captures problems and fixes while they are fresh, without requiring the user to remember them later.

**When agents should write:**
- Planner: when it has to replan significantly mid-session (e.g. Architect Mode 1 flags major risks, scope changes)
- Architect: when a PR or cycle fails repeatedly — lint errors, CI failures, repeated rejections — and it resolves them
- Architect: when it notices a pattern in what builders are getting wrong
- Reviewer: when it flags the same class of issue across multiple tasks in one project
- Tester: when tests fail repeatedly due to environment or tooling issues rather than code issues

**How:** agents append directly to `system-journal.md`. The file is append-only; any agent can write to it. Agent-SI reads everything during audit.

**Entry format for agent-written observations:**

```markdown
## [date] — [project name]
Type: agent-observation
Source: architect | planner | reviewer | tester

### What happened
[Concise description — what went wrong or what pattern was noticed]

### How it was resolved (if applicable)
[What the agent did to fix it]

### Suggested system improvement
[Optional — if the agent thinks a change to its own instructions or another agent's
instructions would prevent this in future. Agent-SI will evaluate during next improve session.]

---
```

The `Suggested system improvement` field is the key one — it gives Agent-SI a concrete lead rather than just a log entry.

**Rule for agents:** only write to the journal when something unexpected happened or a pattern was noticed. Do not write routine progress updates.

---

## system-journal.md structure

```markdown
## [date] — [project name or "cross-project"]
Type: audit | improvement | outcome | agent-observation | user-feedback

### Observations
### Metrics snapshot (ref: metrics-baseline.md [date column])
### User feedback
### Flagged issues
### Open questions

---

## [date] — RFC-NNN implemented
Type: improvement

### Change
### Files modified
### Metric targets set
### Suggested review date

---

## [date] — RFC-NNN outcome
Type: outcome

### Targets vs actuals
| Metric | Target | Actual | Result |
### Notes
```

---

## metrics-baseline.md structure

```markdown
## Metrics Baseline

| Metric                   | Unit               | [date-1] | [date-2] | [date-3] | Source |
|--------------------------|--------------------|----------|----------|----------|--------|
| Token usage              | tokens/task (avg)  |          |          |          | cost-report.sh |
| Cost                     | USD/task (avg)     |          |          |          | cost-report.sh |
| Agent fail rate          | % of tasks failed  |          |          |          | run-log.jsonl |
| Cycle rejection rate     | rejections/project |          |          |          | run-log.jsonl |
| Tasks — initial          | count              |          |          |          | manifest.json |
| Tasks — replan           | count              |          |          |          | manifest.json |
| Tasks — fix              | count              |          |          |          | manifest.json |
| Tasks — design           | count              |          |          |          | manifest.json |
| Fix rate                 | fix+design / total |          |          |          | manifest.json |
| Replan rate              | replan / total     |          |          |          | manifest.json |
| Reviewer flag rate       | CRITICAL+HIGH/task |          |          |          | reviewer output |
| Generalist overflow      | % of tasks         |          |          |          | manifest.json |
| Task duration (avg)      | minutes/task       |          |          |          | run-log.jsonl |
| User quality score       | 1–5                |          |          |          | user feedback |
| Manual interventions     | 0/1–3/4+ band      |          |          |          | user feedback |

### Notes
[Anything that distorts a snapshot — unusual project complexity, partial data, etc.]
```

Metrics are normalised per task where possible so projects of different sizes are comparable.

---

## RFC format

```markdown
## RFC — [short title]
Number: RFC-NNN
Date:
Status: proposed | approved | rejected | implemented | verified | missed

### Problem

### Proposed change

### Files affected

### Metrics impacted
| Metric | Direction | Current baseline | Target | How measured |
|--------|-----------|-----------------|--------|--------------|
|        | improve/reduce/stabilise | | | |

### Expected outcome

### Risks

### Rollback plan
```

RFC status lifecycle:
- `proposed` → presented to user
- `approved` / `rejected` → user decision
- `implemented` → change made and committed
- `verified` / `missed` → set by next audit that checks outcome against targets

---

## extract-metrics.sh output

```json
{
  "project": "my-app",
  "audit_date": "2026-03-21",
  "tasks_total": 42,
  "tasks_by_phase": {
    "initial": 30,
    "replan": 5,
    "fix": 6,
    "design": 1
  },
  "fix_rate": 0.14,
  "replan_rate": 0.12,
  "agent_fails": {
    "builder-composer": 2,
    "tester": 1
  },
  "cycle_rejections": 3,
  "tokens_per_task": 12400,
  "cost_per_task_usd": 0.18,
  "generalist_task_pct": 0.08,
  "avg_task_duration_minutes": null
}
```

`avg_task_duration_minutes` is null until Orchestrator logs task start timestamps (see instrumentation RFCs below).

---

## Phase stamps — full implementation

Every task in `manifest.json` carries a `"phase"` field. Four values:

| Phase | Meaning | Set by |
|-------|---------|--------|
| `initial` | In the original plan | Planner |
| `replan` | Added after Architect Mode 1 risk flags | Planner |
| `fix` | Added after Architect Mode 2 cycle rejection | Orchestrator (from `cycle.rejected.json`) |
| `design` | Added after Design Guardian flags a constraint violation | Orchestrator (from `design.rejected.json`) |

### Changes required per agent

**planner/CLAUDE.md**
- Stamp `"phase": "initial"` on every task when writing manifest.json
- Stamp `"phase": "replan"` on any tasks added after Architect Mode 1 risk flags
- Rule: no task may be written to manifest without a phase field

**architect/CLAUDE.md**
- Every task object inside `cycle.rejected.json` must include `"phase": "fix"`
- Rule: no fix task may be written to the signal without a phase field

**design-guardian/CLAUDE.md**
- New behaviour: if a constraint violation requires a new task, write `signals/design.rejected.json`
- Same structure as `cycle.rejected.json`; tasks stamped `"phase": "design"`
- After writing the signal: stop and notify the user
- Rule: do not attempt to append tasks to manifest directly

**orchestrator/CLAUDE.md**
- Handle `signals/design.rejected.json`: append tasks to manifest preserving phase, log event to run-log.jsonl, delete signal
- When appending tasks from any signal: copy `phase` from signal task object into manifest task verbatim — never set or override phase
- When logging task status events to run-log.jsonl: include the `phase` field so extract-metrics.sh can group by phase without re-reading manifest

**templates/manifest-template.json**
- Add `"phase": "initial"` to the task object template

**templates/signal-schema.json**
- Add `"phase"` as a required field in task objects
- Add `design.rejected.json` as a recognised signal type alongside `cycle.rejected.json`

---

## Instrumentation RFCs (first proposals Agent-SI should make)

These are the small additions needed to make future metrics reliable. Agent-SI should propose them as its first act after the initial audit.

**RFC-001: Richer run-log.jsonl entries**
- Add `phase` field to every task status event
- Add task start timestamp when Orchestrator activates a task (enables duration tracking)
- Add `cycle_rejected` event type when Orchestrator processes `cycle.rejected.json`
- Files: `orchestrator/CLAUDE.md`

**RFC-002: Structured reviewer summary block**
- Reviewer appends a machine-readable block to its output file:
  ```
  <!-- metrics: CRITICAL=N HIGH=N MEDIUM=N LOW=N -->
  ```
- extract-metrics.sh parses this instead of prose
- Files: `reviewer/CLAUDE.md`, `agent-si/extract-metrics.sh`

**RFC-003: Architect rejection reason in cycle.rejected.json**
- Add a `"reason"` field: `quality | incomplete | wrong_approach | missing_contracts`
- Enables grouping rejections by root cause
- Files: `architect/CLAUDE.md`, `templates/signal-schema.json`

These three RFCs should be proposed and approved before the first real audit, so the baseline data is rich from the start.

---

## Operating cadence

| When | What |
|------|------|
| After each project | Ask Agent-SI to audit |
| Every 3–5 projects | Ask if any metric trends warrant an RFC |
| When something breaks noticeably | Ask Agent-SI to look into it immediately |
| 2 projects after an RFC is implemented | Next audit auto-checks outcome |

---

## Build order

1. `agent-si/extract-metrics.sh` — data foundation; audit is useless without it
2. `agent-si/CLAUDE.md` — agent instructions covering audit, improve, RFC workflow
3. `agent-si/system-journal.md` — empty template with structure comments
4. `agent-si/metrics-baseline.md` — empty table ready for first column
5. Phase stamp changes — `planner`, `architect`, `design-guardian`, `orchestrator` CLAUDE.md files + both templates
6. Journal write instructions — add to `planner/CLAUDE.md`, `architect/CLAUDE.md`, and optionally `reviewer/CLAUDE.md`, `tester/CLAUDE.md`
7. First run: Agent-SI audits a past project, proposes RFC-001/002/003 as its first act
