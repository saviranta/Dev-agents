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

        # Show pending/running tasks
        active = [t for t in tasks if t["status"] in ("pending", "in_progress")]
        if active:
            print()
            print(f"  {'QUEUED/ACTIVE':<14} {'TASK':<12} {'ASSIGNED TO':<22} DEPENDS ON")
            for t in active:
                deps = ", ".join(t.get("depends_on", [])) or "—"
                print(f"  {'':14} {t['id']:<12} {t['assigned_to']:<22} {deps}")
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
