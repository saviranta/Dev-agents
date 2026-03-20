#!/bin/bash
# orchestrator/watch.sh — coordination engine
# The ONLY process that writes to manifest.json.
# Launched via: shared/launch-agent.sh orchestrator PROJECT_NAME

CF="$HOME/Library/CloudStorage/Dropbox/ClaudeFolder"

# ── Load config ───────────────────────────────────────────────────────────────
if [ -z "$PROJECT_CONFIG" ]; then
  echo "❌ PROJECT_CONFIG env var not set. Use launch-agent.sh to start this agent."
  exit 1
fi

MANIFEST=$(echo  "$PROJECT_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin)['manifest'])")
WORKSPACE=$(echo "$PROJECT_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin)['workspace'])")
SIGNALS=$(echo   "$PROJECT_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin)['signals'])")
GIT_REPO=$(echo  "$PROJECT_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin)['git_repo'])")
BUDGET=$(echo    "$PROJECT_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin)['budget_usd'])")
ALERT_AT=$(echo  "$PROJECT_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin)['budget_alert_at'])")

RUN_LOG="$WORKSPACE/run-log.jsonl"
DECISIONS="$WORKSPACE/decisions"

echo "🎛  Orchestrator started"
echo "   Manifest: $MANIFEST"
echo "   Signals:  $SIGNALS"
echo "   Budget:   \$$BUDGET (alert at \$$ALERT_AT)"
echo ""

# ── Helpers ───────────────────────────────────────────────────────────────────
ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

total_cost() {
  if [ ! -f "$RUN_LOG" ]; then echo "0"; return; fi
  python3 -c "
import json
total = 0.0
with open('$RUN_LOG') as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            total += float(json.loads(line).get('cost_usd') or 0)
        except Exception:
            pass  # skip malformed lines
print(f'{total:.6f}')
"
}

update_manifest_task_status() {
  local task_id=$1 new_status=$2
  python3 << PYEOF
import json, os

manifest_path = "$MANIFEST"
with open(manifest_path) as f:
    m = json.load(f)

for task in m['tasks']:
    if task['id'] == '$task_id':
        task['status'] = '$new_status'
        break

with open(manifest_path, 'w') as f:
    json.dump(m, f, indent=2)
PYEOF
}

release_file_locks() {
  local task_id=$1
  python3 << PYEOF
import json

manifest_path = "$MANIFEST"
with open(manifest_path) as f:
    m = json.load(f)

locked = m.get('locked_files', {})
to_release = [path for path, tid in locked.items() if tid == '$task_id']
for path in to_release:
    del locked[path]
m['locked_files'] = locked

with open(manifest_path, 'w') as f:
    json.dump(m, f, indent=2)
PYEOF
}

acquire_file_locks() {
  local task_id=$1
  # Minimal: just records the lock. Watchers don't use flock — Orchestrator serialises activation.
  echo "  [locks] No file lock spec in task — skipping (Orchestrator serialises activation)"
}

# ── Main loop ─────────────────────────────────────────────────────────────────
BUDGET_HALTED=false

while true; do

  if [ ! -f "$MANIFEST" ]; then
    echo "$(ts) ⏳ Waiting for manifest.json..."
    sleep 15
    continue
  fi

  # ── 1. PROCESS SIGNALS ──────────────────────────────────────────────────────
  for SIGNAL_FILE in "$SIGNALS"/*.json; do
    [ -f "$SIGNAL_FILE" ] || continue

    SIGNAL=$(cat "$SIGNAL_FILE")
    TASK_ID=$(echo    "$SIGNAL" | python3 -c "import sys,json; print(json.load(sys.stdin)['task_id'])")
    AGENT=$(echo      "$SIGNAL" | python3 -c "import sys,json; print(json.load(sys.stdin)['agent'])")
    STATUS=$(echo     "$SIGNAL" | python3 -c "import sys,json; print(json.load(sys.stdin)['status'])")
    TOKENS_IN=$(echo  "$SIGNAL" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tokens_in',0))")
    TOKENS_OUT=$(echo "$SIGNAL" | python3 -c "import sys,json; print(json.load(sys.stdin).get('tokens_out',0))")
    COST=$(echo       "$SIGNAL" | python3 -c "import sys,json; print(json.load(sys.stdin).get('cost_usd',0))")
    STARTED=$(echo    "$SIGNAL" | python3 -c "import sys,json; print(json.load(sys.stdin).get('started',''))")
    COMPLETED=$(echo  "$SIGNAL" | python3 -c "import sys,json; print(json.load(sys.stdin).get('completed',''))")
    DURATION=$(echo   "$SIGNAL" | python3 -c "import sys,json; print(json.load(sys.stdin).get('duration_seconds',0))")
    MODEL=$(echo "$PROJECT_CONFIG" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['agents'].get('$AGENT',{}).get('model','unknown'))")
    PROJECT=$(echo "$PROJECT_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin)['project'])")

    # Update manifest
    update_manifest_task_status "$TASK_ID" "$STATUS"
    release_file_locks "$TASK_ID"

    # Append to run-log — use Python json.dumps to prevent None/invalid values
    python3 -c "
import json, sys
entry = {
    'task_id':          '$TASK_ID',
    'agent':            '$AGENT',
    'model':            '$MODEL',
    'started':          '$STARTED',
    'completed':        '$COMPLETED',
    'duration_seconds': int('$DURATION') if '$DURATION'.lstrip('-').isdigit() else 0,
    'status':           '$STATUS',
    'tokens_in':        int('$TOKENS_IN') if '$TOKENS_IN'.isdigit() else 0,
    'tokens_out':       int('$TOKENS_OUT') if '$TOKENS_OUT'.isdigit() else 0,
    'cost_usd':         float('$COST') if '$COST' else 0.0,
    'project':          '$PROJECT',
}
with open('$RUN_LOG', 'a') as f:
    f.write(json.dumps(entry) + '\n')
"

    # Save trace if present (thinking agents)
    TRACE=$(echo "$SIGNAL" | python3 -c "import sys,json; print(json.load(sys.stdin).get('trace',''))" 2>/dev/null)
    if [ -n "$TRACE" ] && [ "$TRACE" != "None" ]; then
      echo "$TRACE" > "$DECISIONS/${TASK_ID}-trace.md"
    fi

    # Delete signal
    rm -f "$SIGNAL_FILE"

    # Format cost for display
    printf "$(ts) ✅ %-12s %-20s | %s in / %s out | \$%s\n" \
      "$TASK_ID" "$AGENT" "$TOKENS_IN" "$TOKENS_OUT" "$COST"
  done

  # ── 2. CHECK BUDGET ─────────────────────────────────────────────────────────
  TOTAL_COST=$(total_cost)
  OVER_ALERT=$(python3 -c "print('yes' if float('$TOTAL_COST') >= float('$ALERT_AT') else 'no')")
  OVER_BUDGET=$(python3 -c "print('yes' if float('$TOTAL_COST') >= float('$BUDGET') else 'no')")

  if [ "$OVER_BUDGET" = "yes" ] && [ "$BUDGET_HALTED" = "false" ]; then
    echo "$(ts) 🚨 BUDGET EXHAUSTED — \$$TOTAL_COST / \$$BUDGET — task activation halted. Notify Lauri."
    BUDGET_HALTED=true
  elif [ "$OVER_ALERT" = "yes" ] && [ "$BUDGET_HALTED" = "false" ]; then
    echo "$(ts) ⚠️  Budget alert — \$$TOTAL_COST / \$$BUDGET spent"
  fi

  # ── 3. CHECK FOR FAILURES ───────────────────────────────────────────────────
  python3 << PYEOF
import json
with open("$MANIFEST") as f:
    m = json.load(f)
for task in m['tasks']:
    if task['status'] == 'failed':
        print(f"$(ts) ❌ FAILED: {task['id']} ({task['assigned_to']}) — Planner must replan, no auto-retry")
PYEOF

  # ── 4. UNLOCK DEPENDENT TASKS ───────────────────────────────────────────────
  if [ "$BUDGET_HALTED" = "false" ]; then
    python3 << PYEOF
import json

manifest_path = "$MANIFEST"
with open(manifest_path) as f:
    m = json.load(f)

done_ids = {t['id'] for t in m['tasks'] if t['status'] in ('done', 'reviewed')}
locked_files = m.get('locked_files', {})
changed = False

for task in m['tasks']:
    if task['status'] != 'waiting':
        continue
    deps = task.get('depends_on', [])
    if all(d in done_ids for d in deps):
        task['status'] = 'pending'
        changed = True
        print(f"$(ts)    Unlocked: {task['id']} -> pending ({task['assigned_to']})")

if changed:
    m['locked_files'] = locked_files
    with open(manifest_path, 'w') as f:
        json.dump(m, f, indent=2)
PYEOF
  fi

  # ── 5. CHECK FOR CYCLE COMPLETION ───────────────────────────────────────────
  CYCLE_DONE=$(python3 << PYEOF
import json
with open("$MANIFEST") as f:
    m = json.load(f)
active = [t for t in m['tasks'] if t['status'] in ('waiting','pending','in_progress')]
all_terminal = [t for t in m['tasks'] if t['status'] in ('done','reviewed','failed')]
if not active and all_terminal:
    costs = 0.0
    # (cost is in run-log, not manifest — use run-log total)
    print("yes")
else:
    print("no")
PYEOF
)

  if [ "$CYCLE_DONE" = "yes" ]; then
    TOTAL=$(total_cost)
    echo ""
    echo "$(ts) ── CYCLE COMPLETE ──────────────────────────────────────────────"
    echo "$(ts)    Total cost: \$$TOTAL"
    echo "$(ts)    Architect review needed before PR. Drop approval signal to signals/cycle.approved.json"
    echo ""
  fi

  # ── 6a. ARCHITECT REJECTION — append new fix tasks to manifest ──────────────
  REJECTION="$SIGNALS/cycle.rejected.json"
  if [ -f "$REJECTION" ]; then
    echo "$(ts) 🔁 Architect rejection received — appending fix tasks to manifest"

    python3 << PYEOF
import json, sys
from datetime import datetime, timezone

with open("$REJECTION") as f:
    rejection = json.load(f)

new_tasks = rejection.get("new_tasks", [])
if not new_tasks:
    print("  No new tasks in rejection signal — nothing to append")
    sys.exit(0)

with open("$MANIFEST") as f:
    m = json.load(f)

existing_ids = {t["id"] for t in m["tasks"]}
appended = []
for task in new_tasks:
    if task["id"] in existing_ids:
        print(f"  Skipping duplicate task id: {task['id']}")
        continue
    m["tasks"].append(task)
    appended.append(task["id"])

with open("$MANIFEST", "w") as f:
    json.dump(m, f, indent=2)

notes = rejection.get("notes", "")
print(f"  Appended {len(appended)} fix task(s): {', '.join(appended)}")
print(f"  Architect notes: {notes}")
PYEOF

    rm -f "$REJECTION"
  fi

  # ── 6b. ARCHITECT APPROVAL — notify Lauri, PR raised by Planner ─────────────
  APPROVAL="$SIGNALS/cycle.approved.json"
  if [ -f "$APPROVAL" ]; then
    echo "$(ts) ✅ Architect approval received — ask Planner to raise the PR"
    rm -f "$APPROVAL"
  fi

  # ── 7. SLEEP ─────────────────────────────────────────────────────────────────
  sleep 15

done
