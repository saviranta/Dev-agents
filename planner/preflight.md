# Pre-flight Mode

You are auditing and correcting the state left by the previous session so the next session starts clean. This is not a planning task. Do not write a PRD or task graph.

**Write access exception:** You may write `manifest.json` directly in this mode. Orchestrator is not running — you are the only agent active. Do not use this permission outside of pre-flight mode.

---

## Checks — run in this order

### 1. Manifest JSON validity
Parse `manifest.json`. If it fails: STOP, report to Lauri — do not proceed. A corrupt manifest requires manual inspection before anything else can run.

### 2. Stale `manifest.validated.json`
If `signals/manifest.validated.json` exists from a previous run: delete it. A new session requires a fresh validation pass.

### 3. Orphaned signal files
Check `signals/` for any `.json` files other than `manifest.validated.json` and `cycle.approved.json`. These are signals Orchestrator never processed (it crashed or was stopped mid-cycle).

For each orphaned signal:
- Read its content and log it
- Move it to `signals/archived/[original-filename]-[ISO_TIMESTAMP].json`
- Report which signals were archived

### 4. Stale file locks
If `locked_files` in the manifest is non-empty: the locks are stale (Orchestrator is not running).
- Clear `locked_files` to `{}`
- Report which files were unlocked

### 5. Tasks stuck in `running`
For each task with `status: running`:
- Check the task's `output_file` field
- If `output_file` is set **and the file exists**: task likely completed but its signal was lost → set status to `done`
- If `output_file` is not set **or the file does not exist**: task was interrupted before completion → reset to `pending` (no `depends_on`) or `waiting` (has `depends_on`)
- Report each case with what was decided and why

### 6. Failed tasks from last session
Do not auto-fix. List each task with `status: failed` — its `id`, `assigned_to`, and `output_file` path — so Lauri can inspect before deciding to requeue or drop.

---

## Output format

```
PRE-FLIGHT — project-name
==========================
✓ manifest.json valid
✓ Stale manifest.validated.json removed
⚠ signals/archived: task-003.done.json, task-007.failed.json (Orchestrator stopped mid-cycle)
✓ locked_files cleared: src/schema.prisma, app/api/route.ts
⚠ task-005 [running → done]: output file found at agent-workspace/builder-systems/output/task-005.md
⚠ task-009 [running → pending]: no output file — task was interrupted
✗ task-011 [failed]: check agent-workspace/tester/output/task-011.md before requeuing

Ready. Run Validator next, then launch Orchestrator and watcher tabs.
```

After printing the report, write the corrected manifest (updated statuses, cleared locks). End with a trace block as normal.
