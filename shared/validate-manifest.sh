#!/bin/bash
# validate-manifest.sh — run the Validator agent against a project's manifest
# Usage: ./shared/validate-manifest.sh PROJECT_NAME
#
# Validator checks all tasks for structural and content issues before
# Orchestrator is allowed to activate any tasks.
# On success it drops signals/manifest.validated.json.
# On failure it prints a BLOCK report and exits — Orchestrator stays idle.

PROJECT=$1

CF="$HOME/Library/CloudStorage/Dropbox/ClaudeFolder"
AGENTS_DIR="$CF/Agents"
CONFIG_FILE="$CF/ClaudeProjects/$PROJECT/.agent-config.json"

# ── Validate args ──────────────────────────────────────────────────────────────
if [ -z "$PROJECT" ]; then
  echo "Usage: ./shared/validate-manifest.sh PROJECT_NAME"
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

echo "🔍 Validating manifest for project: $PROJECT"
echo "   Manifest: $MANIFEST"
echo ""

# ── Launch Validator (interactive Claude Code session) ─────────────────────────
export PROJECT_CONFIG=$(cat "$CONFIG_FILE")
export AGENT_NAME="validator"

cd "$AGENTS_DIR/validator" && claude
