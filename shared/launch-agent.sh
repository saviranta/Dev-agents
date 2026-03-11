#!/bin/bash
# launch-agent.sh — launch a watcher agent for a project
# Usage: ./shared/launch-agent.sh AGENT PROJECT_NAME
#
# Example:
#   ./shared/launch-agent.sh builder-composer flat_value
#   ./shared/launch-agent.sh orchestrator     flat_value

AGENT=$1
PROJECT=$2

CF="$HOME/Library/CloudStorage/Dropbox/ClaudeFolder"
AGENTS_DIR="$CF/Agents"
CONFIG_FILE="$CF/ClaudeProjects/$PROJECT/.agent-config.json"

# ── Validate ──────────────────────────────────────────────────────────────────
if [ -z "$AGENT" ] || [ -z "$PROJECT" ]; then
  echo "Usage: ./shared/launch-agent.sh AGENT PROJECT_NAME"
  echo ""
  echo "Available agents:"
  ls "$AGENTS_DIR" | grep -v shared | grep -v templates | grep -v INDEX | grep -v '\.gitignore' | grep -v '\.git'
  exit 1
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "❌ Config not found: $CONFIG_FILE"
  echo "   Run init-project.sh $PROJECT first"
  exit 1
fi

if [ ! -d "$AGENTS_DIR/$AGENT" ]; then
  echo "❌ Unknown agent: $AGENT"
  echo "   Check available agents in $AGENTS_DIR"
  exit 1
fi

if [ ! -f "$AGENTS_DIR/$AGENT/watch.sh" ]; then
  echo "❌ $AGENT has no watch.sh — it is an interactive agent, not a watcher"
  echo "   Open Cursor in $AGENTS_DIR/$AGENT/ and run: claude"
  exit 1
fi

# ── Launch ────────────────────────────────────────────────────────────────────
export PROJECT_CONFIG=$(cat "$CONFIG_FILE")
export AGENT_NAME="$AGENT"

echo "🚀 Launching $AGENT for project: $PROJECT"

cd "$AGENTS_DIR/$AGENT" && bash watch.sh
