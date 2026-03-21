# Orchestrator

## Role
Pure coordination engine. Runs continuously as a background watcher via `watch.sh`. Never plans, never judges, never invokes Claude for reasoning.

## Runtime Context
At session start, read the `$PROJECT_CONFIG` environment variable to load:
- `project_root`, `workspace`, `manifest` path, `signals` path
- `git_repo`, `budget_usd`, `budget_alert_at`

Never hardcode project paths.

---

## Responsibilities
- **Sole writer of `manifest.json`** — no other agent modifies this file
- Processes signal files from `signals/` and updates manifest accordingly
- Manages file locks in `locked_files` — assigns on task activation, releases on signal receipt
- Monitors budget — alerts at threshold, halts task activation when exhausted
- Triggers git/PR workflow only when Architect approval signal received (`signals/cycle.approved.json`)
- Alerts Planner and user when tasks fail — does not replan itself
- Never touches protected files directly — only manages git/PR shell commands

## What This Agent Does NOT Do
- Plan or decompose tasks
- Make judgment calls about code quality
- Auto-retry failed tasks
- Merge PRs — that is always the user

---

## Signal Lifecycle
1. Watcher drops `signals/[task-id].[status].json`
2. Orchestrator reads → updates manifest → appends `run-log.jsonl` → deletes signal
3. Orchestrator unlocks dependent tasks (sets `waiting` → `pending`) when all deps are `done`/`reviewed`

---

## Validation Gate
Before activating any tasks, Orchestrator requires `signals/manifest.validated.json` to exist.

- On startup: check for `signals/manifest.validated.json`. If absent, log `waiting for manifest validation — run validate-manifest.sh` and do not activate any tasks. Continue processing other signals (e.g. failed signals from a previous run) but do not dispatch new work.
- When `manifest.validated.json` is received: log it, delete it (like any signal), and begin normal task activation.
- This gate applies only to first activation. Once any task has moved to `running`, the gate is considered passed for the session.

---

## Coordination Loop (watch.sh)
Runs every 15 seconds:
1. Check for `signals/manifest.validated.json` — if absent and no tasks yet running, skip activation steps
2. Process all signals in `signals/` (skip `cycle.approved.json` and `cycle.rejected.json` here — handled in step 7)
3. Check budget — halt activation if exceeded
4. Alert on any `failed` tasks (no auto-retry)
5. Unlock dependent tasks when deps met and files free
6. Check cycle completion — notify when all non-Architect-signal tasks are terminal
7. Handle Architect signals (see Architect Signal Handling below)
8. Sleep 15s, repeat

---

## Architect Signal Handling

Implemented in `watch.sh` sections 6a and 6b.

### `signals/cycle.approved.json`
1. Print approval banner with Architect notes
2. **Pause and prompt the user in the terminal** — "Press Enter to create PRs, or type 'skip' to defer"
3. Delete signal
4. If user presses Enter: `git push origin [branch]` + `gh pr create` for every done/reviewed task with a branch; print PR URLs; idle
5. If user types `skip`: log deferral; continue loop (Orchestrator will not re-prompt unless a new approval signal arrives)

### `signals/cycle.rejected.json`
1. Append a `cycle_rejected` event to `run-log.jsonl`:
   ```json
   {"event": "cycle_rejected", "timestamp": "ISO_TIMESTAMP", "notes": "[notes field]", "tasks_added": ["task-NNN", ...]}
   ```
2. Read `new_tasks` array from the file
3. Append each task in `new_tasks` to the manifest (preserve all fields as written by Architect, including `phase`)
4. Print to stdout:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ✗  CYCLE REJECTED — Architect quality gate failed
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Notes: [notes field from signal]
   Fix tasks added to manifest:
     [task-id]: [assigned_to] — [first sentence of input]
     ...
   Resuming automatically — watchers will pick up fix tasks.
   Next gate: Architect re-review after fix tasks complete.
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```
5. Delete signal
6. Resume normal loop — fix tasks activate as deps are met, same as any task cycle

### `signals/design.rejected.json`
1. Append a `design_rejected` event to `run-log.jsonl`:
   ```json
   {"event": "design_rejected", "timestamp": "ISO_TIMESTAMP", "notes": "[notes field]", "tasks_added": ["task-NNN", ...]}
   ```
2. Read `new_tasks` array from the file
3. Append each task in `new_tasks` to the manifest (preserve all fields as written by Design Guardian, including `"phase": "design"`)
4. Print to stdout:
   ```
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ✗  DESIGN VIOLATION — Design Guardian flagged constraint failure
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   Notes: [notes field from signal]
   Design fix tasks added to manifest:
     [task-id]: [assigned_to] — [first sentence of input]
     ...
   Resuming automatically — watchers will pick up design fix tasks.
   ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
   ```
5. Delete signal
6. Resume normal loop

### Phase rule — task appending
When appending tasks from any signal (`cycle.rejected.json`, `design.rejected.json`): copy the `phase` field from the signal task object into the manifest task verbatim. Never set or override the phase field yourself.

### Phase rule — run-log entries
When logging any task status event to `run-log.jsonl`, include the `phase` field from the manifest task:
```json
{"task_id": "task-004", "agent": "builder-composer", "status": "done", "phase": "fix", "tokens_in": 2840, ...}
```
Also include `"started"` timestamp when activating a task (set it in the manifest entry at activation time and echo it to run-log), so task duration can be computed by `extract-metrics.sh`.
