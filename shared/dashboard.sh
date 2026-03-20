#!/bin/bash
# shared/dashboard.sh — live agent dashboard
# Usage: ./shared/dashboard.sh PROJECT_NAME

PROJECT=$1
CF="$HOME/Library/CloudStorage/Dropbox/ClaudeFolder"
CONFIG_FILE="$CF/ClaudeProjects/$PROJECT/.agent-config.json"

if [ -z "$PROJECT" ]; then
  echo "Usage: ./shared/dashboard.sh PROJECT_NAME"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Config not found: $CONFIG_FILE"
  exit 1
fi

WORKSPACE=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE'))['workspace'])")
MANIFEST=$(python3  -c "import json; print(json.load(open('$CONFIG_FILE'))['manifest'])")
RUN_LOG="$WORKSPACE/run-log.jsonl"
STATUS_DIR="$WORKSPACE/status"
BUDGET=$(python3    -c "import json; print(json.load(open('$CONFIG_FILE'))['budget_usd'])")

while true; do
  clear
  python3 << PYEOF
import json, os, time
from datetime import datetime, timezone

workspace   = "$WORKSPACE"
manifest_f  = "$MANIFEST"
run_log_f   = "$RUN_LOG"
status_dir  = "$STATUS_DIR"
budget      = float("$BUDGET")
project     = "$PROJECT"

now = datetime.now(timezone.utc)

def ago(iso):
    if not iso or iso == "None":
        return "—"
    try:
        t = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        s = int((now - t).total_seconds())
        if s < 60:   return f"{s}s ago"
        if s < 3600: return f"{s//60}m ago"
        return f"{s//3600}h ago"
    except:
        return "—"

def elapsed(iso):
    if not iso or iso == "None":
        return "—"
    try:
        t = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        s = int((now - t).total_seconds())
        if s < 60:   return f"{s}s"
        if s < 3600: return f"{s//60}m {s%60}s"
        return f"{s//3600}h {(s%3600)//60}m"
    except:
        return "—"

def status_icon(s):
    return {"done": "✅", "reviewed": "✅", "failed": "❌", "running": "⚙️ ", "idle": "💤"}.get(s, "❓")

# ── Total cost ──────────────────────────────────────────────────────────────
total_cost = 0.0
recent = []
if os.path.exists(run_log_f):
    with open(run_log_f) as f:
        for line in f:
            line = line.strip()
            if not line: continue
            try:
                entry = json.loads(line)
                total_cost += float(entry.get("cost_usd") or 0)
                recent.append(entry)
            except:
                pass
recent = recent[-6:][::-1]

pct = (total_cost / budget * 100) if budget > 0 else 0
bar_len = 20
filled = int(bar_len * pct / 100)
bar = "█" * filled + "░" * (bar_len - filled)

# ── Header ──────────────────────────────────────────────────────────────────
print(f"{'═'*70}")
print(f"  🎛  {project}   [{now.strftime('%H:%M:%S')} UTC]")
print(f"  Budget: \${total_cost:.4f} / \${budget:.2f}  [{bar}] {pct:.1f}%")
print(f"{'═'*70}")

# ── Agent statuses ──────────────────────────────────────────────────────────
print()
print(f"  {'AGENT':<22} {'STATUS':<10} {'TASK':<12} {'TIME':<10} PREVIEW")
print(f"  {'─'*22} {'─'*10} {'─'*12} {'─'*10} {'─'*20}")

statuses = []
if os.path.exists(status_dir):
    for fn in sorted(os.listdir(status_dir)):
        if not fn.endswith(".json"): continue
        try:
            s = json.loads(open(os.path.join(status_dir, fn)).read())
            statuses.append(s)
        except:
            pass

if not statuses:
    print("  (no agents running — start agents to see status here)")
else:
    for s in statuses:
        agent  = s.get("agent", "?")
        status = s.get("status", "?")
        icon   = status_icon(status)
        if status == "running":
            task_id  = s.get("task_id") or "—"
            duration = elapsed(s.get("started"))
            preview  = (s.get("input_preview") or "")[:40]
            print(f"  {agent:<22} {icon} {status:<8} {task_id:<12} {duration:<10} {preview}")
        else:
            last_id  = s.get("last_task_id") or "—"
            last_st  = s.get("last_status") or "—"
            last_ico = status_icon(last_st)
            last_ago = ago(s.get("last_completed"))
            print(f"  {agent:<22} {icon} {'idle':<8} {'—':<12} {'—':<10} last: {last_id} {last_ico} {last_ago}")

# ── Manifest summary ────────────────────────────────────────────────────────
print()
print(f"  {'─'*68}")
if os.path.exists(manifest_f):
    try:
        m = json.load(open(manifest_f))
        tasks = m.get("tasks", [])
        counts = {}
        for t in tasks:
            st = t["status"]
            counts[st] = counts.get(st, 0) + 1
        phase = m.get("phase", "?")
        total = len(tasks)
        done  = counts.get("done", 0) + counts.get("reviewed", 0)
        print(f"  MANIFEST  phase {phase}  |  {done}/{total} complete  |  "
              f"pending: {counts.get('pending',0)}  "
              f"waiting: {counts.get('waiting',0)}  "
              f"failed: {counts.get('failed',0)}")

        # Build running-task lookup from status files
        running_tasks = {}
        if os.path.exists(status_dir):
            for fn in sorted(os.listdir(status_dir)):
                if not fn.endswith(".json"): continue
                try:
                    s = json.loads(open(os.path.join(status_dir, fn)).read())
                    if s.get("status") == "running" and s.get("task_id"):
                        running_tasks[s["task_id"]] = s["agent"]
                except:
                    pass

        # Build cost lookup from run-log
        task_cost = {}
        if os.path.exists(run_log_f):
            with open(run_log_f) as f:
                for line in f:
                    line = line.strip()
                    if not line: continue
                    try:
                        entry = json.loads(line)
                        tid = entry.get("task_id")
                        if tid:
                            task_cost[tid] = task_cost.get(tid, 0) + float(entry.get("cost_usd") or 0)
                    except:
                        pass

        # Show all tasks in current phase
        status_order = {"running": 0, "in_progress": 1, "pending": 2, "waiting": 3, "done": 4, "reviewed": 4, "failed": 5}
        def effective_status(t):
            return "running" if t["id"] in running_tasks else t["status"]
        sorted_tasks = sorted(tasks, key=lambda t: (status_order.get(effective_status(t), 9), t["id"]))
        status_icon_map = {"done": "✅", "reviewed": "✅", "failed": "❌", "running": "⚙️ ", "in_progress": "⚙️ ", "pending": "⏳", "waiting": "💤"}
        print()
        print(f"  {'TASK':<14} {'ASSIGNED TO':<22} {'STATUS':<12} {'COST':>7}  DEPENDS ON")
        print(f"  {'─'*14} {'─'*22} {'─'*12} {'─'*7}  {'─'*20}")
        for t in sorted_tasks:
            tid   = t["id"]
            agent = t.get("assigned_to", "?")
            st    = effective_status(t)
            icon  = status_icon_map.get(st, "❓")
            cost  = task_cost.get(tid, 0)
            cost_s = f"${cost:.4f}" if cost else "—"
            deps  = ", ".join(t.get("depends_on", [])) or "—"
            print(f"  {tid:<14} {agent:<22} {icon} {st:<10} {cost_s:>7}  {deps}")
    except:
        print("  (manifest unreadable)")
else:
    print("  (no manifest found)")

# ── Recent completions ──────────────────────────────────────────────────────
print()
print(f"  {'─'*68}")
print(f"  RECENT COMPLETIONS")
for r in recent:
    tid   = r.get("task_id", "?")
    agent = r.get("agent", "?")
    st    = r.get("status", "?")
    icon  = status_icon(st)
    dur   = r.get("duration_seconds", 0)
    dur_s = f"{dur}s" if dur < 60 else f"{dur//60}m {dur%60}s"
    cost  = float(r.get("cost_usd") or 0)
    comp  = ago(r.get("completed"))
    print(f"  {icon} {tid:<12} {agent:<22} {dur_s:<8} \${cost:.4f}  {comp}")

print()
print(f"  [refreshing every 5s — Ctrl+C to exit]")
PYEOF

  sleep 5
done
