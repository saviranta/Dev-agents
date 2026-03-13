#!/bin/bash
# launch-api-agent.sh — launch a watcher agent using the Anthropic API runner (no Claude Code CLI required)
# Usage: ./shared/launch-api-agent.sh AGENT PROJECT_NAME
#
# Example:
#   ./shared/launch-api-agent.sh builder-composer flat_value
#   ./shared/launch-api-agent.sh orchestrator     flat_value
#
# Requires:
#   export ANTHROPIC_API_KEY=sk-ant-...
#   pip install anthropic

AGENT=$1
PROJECT=$2

CF="$HOME/Library/CloudStorage/Dropbox/ClaudeFolder"
AGENTS_DIR="$CF/Agents"
CONFIG_FILE="$CF/ClaudeProjects/$PROJECT/.agent-config.json"

# ── Validate ──────────────────────────────────────────────────────────────────
if [ -z "$AGENT" ] || [ -z "$PROJECT" ]; then
  echo "Usage: ./shared/launch-api-agent.sh AGENT PROJECT_NAME"
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

if [ ! -f "$AGENTS_DIR/$AGENT/watch-api.sh" ]; then
  echo "❌ $AGENT has no watch-api.sh — it is an interactive agent, not a watcher"
  echo "   Open Cursor in $AGENTS_DIR/$AGENT/ and run: claude"
  exit 1
fi

# ── Check requirements ────────────────────────────────────────────────────────
if [ -z "$ANTHROPIC_API_KEY" ]; then
  echo "❌ ANTHROPIC_API_KEY is not set."
  echo "   Export it before launching: export ANTHROPIC_API_KEY=sk-ant-..."
  exit 1
fi

if ! python3 -c "import anthropic" 2>/dev/null; then
  echo "❌ anthropic Python package not installed."
  echo "   Run: pip install anthropic"
  exit 1
fi

# ── Launch ────────────────────────────────────────────────────────────────────
export PROJECT_CONFIG=$(cat "$CONFIG_FILE")
export AGENT_NAME="$AGENT"

echo "🚀 Launching $AGENT for project: $PROJECT (Anthropic API runner)"

cd "$AGENTS_DIR/$AGENT" && bash watch-api.sh
