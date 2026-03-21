#!/bin/bash
# extract-metrics.sh — extract project metrics for Agent-SI audit
# Usage: ./agent-si/extract-metrics.sh PROJECT_NAME
# Output: JSON to stdout

PROJECT=$1
CF="$HOME/Library/CloudStorage/Dropbox/ClaudeFolder"
WORKSPACE="$CF/ClaudeProjects/$PROJECT/agent-workspace"
RUN_LOG="$WORKSPACE/run-log.jsonl"
MANIFEST="$WORKSPACE/manifest.json"
REVIEWER_OUTPUT="$WORKSPACE/reviewer/output"

if [ -z "$PROJECT" ]; then
  echo "Usage: ./agent-si/extract-metrics.sh PROJECT_NAME" >&2
  exit 1
fi

if [ ! -f "$RUN_LOG" ]; then
  echo "❌ No run log found: $RUN_LOG" >&2
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "❌ No manifest found: $MANIFEST" >&2
  exit 1
fi

python3 << PYEOF
import json
import os
import re
from collections import defaultdict
from datetime import datetime

run_log_path     = "$RUN_LOG"
manifest_path    = "$MANIFEST"
reviewer_dir     = "$REVIEWER_OUTPUT"
project          = "$PROJECT"

# ── Run log ──────────────────────────────────────────────────────────────────

agent_fails      = defaultdict(int)
tokens_in_total  = 0
tokens_out_total = 0
cost_total       = 0.0
task_count_log   = 0
duration_total   = 0
duration_count   = 0
cycle_rejections = 0

with open(run_log_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue

        event = entry.get("event")

        # Cycle rejection events (RFC-001 — may be absent in older logs)
        if event == "cycle_rejected":
            cycle_rejections += 1
            continue

        # Task completion entries
        agent  = entry.get("agent", "unknown")
        status = entry.get("status", "")

        if status == "failed":
            agent_fails[agent] += 1

        if status in ("done", "reviewed", "failed"):
            task_count_log   += 1
            tokens_in_total  += entry.get("tokens_in", 0)
            tokens_out_total += entry.get("tokens_out", 0)
            cost_total       += entry.get("cost_usd", 0.0)

            started   = entry.get("started")
            completed = entry.get("completed")
            if started and completed:
                try:
                    s = datetime.fromisoformat(started.replace("Z", "+00:00"))
                    c = datetime.fromisoformat(completed.replace("Z", "+00:00"))
                    duration_total += (c - s).total_seconds()
                    duration_count += 1
                except Exception:
                    pass

tokens_per_task       = round(tokens_in_total / task_count_log) if task_count_log else None
cost_per_task         = round(cost_total / task_count_log, 4)   if task_count_log else None
avg_duration_minutes  = round(duration_total / duration_count / 60, 1) if duration_count else None
# Cycle rejections: null if RFC-001 not yet in place (no cycle_rejected events logged)
cycle_rejections_out  = cycle_rejections if cycle_rejections > 0 else None

# ── Manifest ─────────────────────────────────────────────────────────────────

with open(manifest_path) as f:
    manifest = json.load(f)

tasks = manifest.get("tasks", [])
tasks_total = len(tasks)

phase_counts = defaultdict(int)
generalist_count = 0

for task in tasks:
    phase = task.get("phase", "initial")  # default to initial if missing (pre-stamp)
    phase_counts[phase] += 1
    if task.get("assigned_to") == "builder-generalist":
        generalist_count += 1

fix_design = phase_counts.get("fix", 0) + phase_counts.get("design", 0)
fix_rate    = round(fix_design / tasks_total, 3)      if tasks_total else None
replan_rate = round(phase_counts.get("replan", 0) / tasks_total, 3) if tasks_total else None
generalist_pct = round(generalist_count / tasks_total, 3) if tasks_total else None

# ── Reviewer output — CRITICAL/HIGH counts ────────────────────────────────────

critical_count = 0
high_count     = 0

if os.path.isdir(reviewer_dir):
    for fname in os.listdir(reviewer_dir):
        if not fname.endswith(".md"):
            continue
        fpath = os.path.join(reviewer_dir, fname)
        with open(fpath) as f:
            content = f.read()

        # RFC-002 machine-readable block (preferred)
        match = re.search(r'<!--\s*metrics:\s*CRITICAL=(\d+)\s+HIGH=(\d+)', content)
        if match:
            critical_count += int(match.group(1))
            high_count     += int(match.group(2))
        else:
            # Fallback: count severity rows in findings tables
            for line in content.splitlines():
                cols = [c.strip() for c in line.split("|")]
                if len(cols) >= 2:
                    if cols[1] == "CRITICAL":
                        critical_count += 1
                    elif cols[1] == "HIGH":
                        high_count += 1

reviewer_flags = critical_count + high_count
reviewer_flag_rate = round(reviewer_flags / tasks_total, 3) if tasks_total else None

# ── Output ────────────────────────────────────────────────────────────────────

result = {
    "project":               project,
    "audit_date":            datetime.now().strftime("%Y-%m-%d"),
    "tasks_total":           tasks_total,
    "tasks_by_phase": {
        "initial": phase_counts.get("initial", 0),
        "replan":  phase_counts.get("replan",  0),
        "fix":     phase_counts.get("fix",     0),
        "design":  phase_counts.get("design",  0),
    },
    "fix_rate":              fix_rate,
    "replan_rate":           replan_rate,
    "agent_fails":           dict(agent_fails),
    "cycle_rejections":      cycle_rejections_out,
    "reviewer_critical":     critical_count,
    "reviewer_high":         high_count,
    "reviewer_flag_rate":    reviewer_flag_rate,
    "generalist_task_pct":   generalist_pct,
    "tokens_in_total":       tokens_in_total,
    "tokens_out_total":      tokens_out_total,
    "tokens_per_task":       tokens_per_task,
    "cost_total_usd":        round(cost_total, 4),
    "cost_per_task_usd":     cost_per_task,
    "avg_task_duration_minutes": avg_duration_minutes,
}

print(json.dumps(result, indent=2))
PYEOF
