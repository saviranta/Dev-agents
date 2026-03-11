#!/bin/bash
# cost-report.sh — print cost summary for a project
# Usage: ./shared/cost-report.sh PROJECT_NAME

PROJECT=$1
CF="$HOME/Library/CloudStorage/Dropbox/ClaudeFolder"
RUN_LOG="$CF/ClaudeProjects/$PROJECT/agent-workspace/run-log.jsonl"

if [ -z "$PROJECT" ]; then
  echo "Usage: ./shared/cost-report.sh PROJECT_NAME"
  exit 1
fi

if [ ! -f "$RUN_LOG" ]; then
  echo "❌ No run log found: $RUN_LOG"
  exit 1
fi

python3 << EOF
import json
from collections import defaultdict

data = defaultdict(lambda: {"tasks": 0, "tokens_in": 0, "tokens_out": 0, "cost_usd": 0.0})

with open("$RUN_LOG") as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        entry = json.loads(line)
        agent = entry.get("agent", "unknown")
        data[agent]["tasks"]      += 1
        data[agent]["tokens_in"]  += entry.get("tokens_in", 0)
        data[agent]["tokens_out"] += entry.get("tokens_out", 0)
        data[agent]["cost_usd"]   += entry.get("cost_usd", 0.0)

# Totals
total = {"tasks": 0, "tokens_in": 0, "tokens_out": 0, "cost_usd": 0.0}
for v in data.values():
    total["tasks"]      += v["tasks"]
    total["tokens_in"]  += v["tokens_in"]
    total["tokens_out"] += v["tokens_out"]
    total["cost_usd"]   += v["cost_usd"]

# Print
col = 22
print(f"\n{'Cost Report — $PROJECT':}")
print("=" * 72)
print(f"{'Agent':<{col}} {'Tasks':>6}  {'Tokens In':>12}  {'Tokens Out':>12}  {'Cost USD':>10}")
print("-" * 72)
for agent, v in sorted(data.items()):
    print(f"{agent:<{col}} {v['tasks']:>6}  {v['tokens_in']:>12,}  {v['tokens_out']:>12,}  \${v['cost_usd']:>9.4f}")
print("-" * 72)
print(f"{'TOTAL':<{col}} {total['tasks']:>6}  {total['tokens_in']:>12,}  {total['tokens_out']:>12,}  \${total['cost_usd']:>9.4f}")
print()
EOF
