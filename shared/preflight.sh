#!/bin/bash
# preflight.sh — run Planner in pre-flight mode for a project
# Usage: ./shared/preflight.sh PROJECT_NAME
#
# Audits and corrects session state (stuck tasks, stale locks, orphaned signals)
# before launching Orchestrator and watcher agents.

PROJECT=$1

CF="$HOME/Library/CloudStorage/Dropbox/ClaudeFolder"
AGENTS_DIR="$CF/Agents"
CONFIG_FILE="$CF/ClaudeProjects/$PROJECT/.agent-config.json"

# ── Validate args ──────────────────────────────────────────────────────────────
if [ -z "$PROJECT" ]; then
  echo "Usage: ./shared/preflight.sh PROJECT_NAME"
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Config not found: $CONFIG_FILE"
  echo "   Run init-project.sh $PROJECT first"
  exit 1
fi

# ── Derive manifest path from config ──────────────────────────────────────────
MANIFEST=$(python3 -c "
import json, sys
cfg = json.load(open('$CONFIG_FILE'))
print(cfg.get('manifest', ''))
" 2>/dev/null)

if [ -z "$MANIFEST" ] || [ ! -f "$MANIFEST" ]; then
  echo "❌ manifest.json not found at: $MANIFEST"
  echo "   Run Planner first to generate the manifest."
  exit 1
fi

echo "🔧 Pre-flight for project: $PROJECT"
echo "   Manifest: $MANIFEST"
echo ""

# ── Launch Planner in pre-flight mode ─────────────────────────────────────────
export PROJECT_CONFIG=$(cat "$CONFIG_FILE")
export AGENT_NAME="planner"

cd "$AGENTS_DIR/planner" && claude "run pre-flight"
