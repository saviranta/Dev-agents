#!/bin/bash
# init-project.sh — initialise workspace for a new project
# Usage: ./shared/init-project.sh PROJECT_NAME

PROJECT=$1
CF="$HOME/Library/CloudStorage/Dropbox/ClaudeFolder"
AGENTS_DIR="$CF/Agents"
TEMPLATES="$AGENTS_DIR/templates"
PROJECT_DIR="$CF/ClaudeProjects/$PROJECT"

if [ -z "$PROJECT" ]; then
  echo "Usage: ./shared/init-project.sh PROJECT_NAME"
  exit 1
fi

if [ -d "$PROJECT_DIR" ]; then
  echo "❌ Project already exists: $PROJECT_DIR"
  echo "   Delete it first if you want to reinitialise"
  exit 1
fi

echo "Creating workspace for: $PROJECT"

# ── Create directory tree ─────────────────────────────────────────────────────
mkdir -p "$PROJECT_DIR"/{.github/workflows,agent-workspace/{signals,decisions,planner/output,architect/output,builder-composer/output,builder-systems/output,builder-data/output,builder-integration/output,builder-generalist/output,tester/output,reviewer/output,ui-reviewer/output,design-guardian/output}}

# ── Copy and substitute templates ─────────────────────────────────────────────
# .agent-config.json — substitute PROJECT_NAME
sed "s/PROJECT_NAME/$PROJECT/g" "$TEMPLATES/project-config-template.json" \
  > "$PROJECT_DIR/.agent-config.json"

# DESIGN_SYSTEM.md
sed "s/PROJECT_NAME/$PROJECT/g" "$TEMPLATES/design-system-template.md" \
  > "$PROJECT_DIR/DESIGN_SYSTEM.md"

# manifest.json (empty template)
sed "s/PROJECT_NAME/$PROJECT/g" "$TEMPLATES/manifest-template.json" \
  > "$PROJECT_DIR/agent-workspace/manifest.json"

# GitHub Actions CI
cp "$TEMPLATES/ci.yml" "$PROJECT_DIR/.github/workflows/ci.yml"

# ── Create empty files ────────────────────────────────────────────────────────
touch "$PROJECT_DIR/CONVENTIONS.md"
touch "$PROJECT_DIR/ADR.md"
touch "$PROJECT_DIR/PRD.md"
echo "{}" > "$PROJECT_DIR/agent-workspace/quality-log.json"
touch "$PROJECT_DIR/agent-workspace/run-log.jsonl"

# ── Done ──────────────────────────────────────────────────────────────────────
echo ""
echo "Project workspace created: $PROJECT"
echo ""
echo "Before starting:"
echo "  1. Edit $PROJECT_DIR/.agent-config.json"
echo "       Set: stack, git_repo, budget, regression_scope"
echo "  2. Fill $PROJECT_DIR/DESIGN_SYSTEM.md"
echo "       Required before any UI tasks"
echo "  3. Fill $PROJECT_DIR/CONVENTIONS.md"
echo "       Required before any builder tasks"
echo "  4. Set up GitHub Actions secrets if deploying"
echo ""
echo "To get all launch commands:"
echo "  $AGENTS_DIR/shared/start-project.sh $PROJECT"
echo ""
echo "Startup order:"
echo "  1. Launch Orchestrator tab first (background coordinator)"
echo "  2. Run Planner -> PRD + manifest.json"
echo "  3. Run Architect -> ADR.md + interface contracts"
echo "  4. Launch remaining watcher tabs"
echo ""
