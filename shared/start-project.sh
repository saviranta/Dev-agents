#!/bin/bash
# start-project.sh — print launch commands for all agents
# Usage: ./shared/start-project.sh PROJECT_NAME

PROJECT=$1
CF="$HOME/Library/CloudStorage/Dropbox/ClaudeFolder"
AGENTS_DIR="$CF/Agents"
SHARED="$AGENTS_DIR/shared"

if [ -z "$PROJECT" ]; then
  echo "Usage: ./shared/start-project.sh PROJECT_NAME"
  exit 1
fi

if [ ! -f "$CF/ClaudeProjects/$PROJECT/.agent-config.json" ]; then
  echo "❌ No .agent-config.json found for: $PROJECT"
  echo "   Run init-project.sh $PROJECT first"
  exit 1
fi

echo ""
echo "Agent launch commands for: $PROJECT"
echo "Open a new Cursor terminal tab for each line"
echo "Rename each tab to the agent name for easy tracking"
echo ""
echo "── BACKGROUND WATCHER (launch first) ───────────────────────────────────"
echo "$SHARED/launch-agent.sh orchestrator        $PROJECT"
echo ""
echo "── WATCHER AGENTS ───────────────────────────────────────────────────────"
echo "$SHARED/launch-agent.sh builder-composer    $PROJECT"
echo "$SHARED/launch-agent.sh builder-systems     $PROJECT"
echo "$SHARED/launch-agent.sh builder-data        $PROJECT"
echo "$SHARED/launch-agent.sh builder-integration $PROJECT"
echo "$SHARED/launch-agent.sh builder-generalist  $PROJECT"
echo "$SHARED/launch-agent.sh tester              $PROJECT"
echo "$SHARED/launch-agent.sh reviewer            $PROJECT"
echo "$SHARED/launch-agent.sh ui-reviewer         $PROJECT"
echo ""
echo "── INTERACTIVE AGENTS (open Cursor in these folders) ────────────────────"
echo "$AGENTS_DIR/planner/          -> run: claude"
echo "$AGENTS_DIR/architect/        -> run: claude"
echo "$AGENTS_DIR/design-guardian/  -> run: claude  (UI tasks only)"
echo "$AGENTS_DIR/researcher/       -> run: claude  (when needed)"
echo ""
echo "── STARTUP ORDER ────────────────────────────────────────────────────────"
echo "1. Launch Orchestrator tab (background watcher)"
echo "2. Run Planner to write PRD + manifest.json"
echo "3. Run Architect to write ADR + interface contracts"
echo "4. Launch remaining watcher tabs — they pick up tasks immediately"
echo ""
echo "── OPTIONAL: PARALLEL BUILDERS ─────────────────────────────────────────"
echo "Run the same builder twice for faster parallel execution:"
echo "$SHARED/launch-agent.sh builder-composer $PROJECT  # tab A"
echo "$SHARED/launch-agent.sh builder-composer $PROJECT  # tab B"
echo ""
