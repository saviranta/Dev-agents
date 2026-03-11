#!/bin/bash
# add-workspace.sh — add agent workspace to an existing project
# Usage: ./shared/add-workspace.sh PROJECT_NAME
#
# Safe to re-run — skips anything that already exists.

PROJECT=$1
CF="$HOME/Library/CloudStorage/Dropbox/ClaudeFolder"
AGENTS_DIR="$CF/Agents"
TEMPLATES="$AGENTS_DIR/templates"
PROJECT_DIR="$CF/ClaudeProjects/$PROJECT"

if [ -z "$PROJECT" ]; then
  echo "Usage: ./shared/add-workspace.sh PROJECT_NAME"
  exit 1
fi

if [ ! -d "$PROJECT_DIR" ]; then
  echo "❌ Project not found: $PROJECT_DIR"
  echo "   For a new project use init-project.sh instead"
  exit 1
fi

echo "Adding agent workspace to existing project: $PROJECT"
echo ""

CREATED=()
SKIPPED=()

# ── Helper ────────────────────────────────────────────────────────────────────
make_dir() {
  if [ ! -d "$1" ]; then
    mkdir -p "$1"
    CREATED+=("$1")
  fi
}

make_file() {
  local dest=$1 src=$2
  if [ ! -f "$dest" ]; then
    if [ -n "$src" ]; then
      sed "s/PROJECT_NAME/$PROJECT/g" "$src" > "$dest"
    else
      touch "$dest"
    fi
    CREATED+=("$dest")
  else
    SKIPPED+=("$dest")
  fi
}

# ── agent-workspace/ folder tree ─────────────────────────────────────────────
WORKSPACE="$PROJECT_DIR/agent-workspace"

make_dir "$WORKSPACE"
make_dir "$WORKSPACE/signals"
make_dir "$WORKSPACE/decisions"

for AGENT in planner architect builder-composer builder-systems builder-data \
             builder-integration builder-generalist tester reviewer ui-reviewer \
             design-guardian; do
  make_dir "$WORKSPACE/$AGENT/output"
done

# ── Workspace files ───────────────────────────────────────────────────────────
make_file "$WORKSPACE/manifest.json"    "$TEMPLATES/manifest-template.json"
make_file "$WORKSPACE/run-log.jsonl"    ""
if [ ! -f "$WORKSPACE/quality-log.json" ]; then
  echo "{}" > "$WORKSPACE/quality-log.json"
  CREATED+=("$WORKSPACE/quality-log.json")
else
  SKIPPED+=("$WORKSPACE/quality-log.json")
fi

# ── Project root files ────────────────────────────────────────────────────────
make_file "$PROJECT_DIR/.agent-config.json" "$TEMPLATES/project-config-template.json"
make_file "$PROJECT_DIR/ADR.md"             ""
make_file "$PROJECT_DIR/PRD.md"             ""

# CONVENTIONS.md and DESIGN_SYSTEM.md — only create if missing
make_file "$PROJECT_DIR/CONVENTIONS.md"    ""
make_file "$PROJECT_DIR/DESIGN_SYSTEM.md"  "$TEMPLATES/design-system-template.md"

# GitHub Actions CI — only if .github doesn't exist yet
if [ ! -f "$PROJECT_DIR/.github/workflows/ci.yml" ]; then
  make_dir "$PROJECT_DIR/.github/workflows"
  cp "$TEMPLATES/ci.yml" "$PROJECT_DIR/.github/workflows/ci.yml"
  CREATED+=("$PROJECT_DIR/.github/workflows/ci.yml")
else
  SKIPPED+=("$PROJECT_DIR/.github/workflows/ci.yml")
fi

# ── Report ────────────────────────────────────────────────────────────────────
echo "Created:"
for f in "${CREATED[@]}"; do
  echo "  + ${f/$CF\//}"
done

if [ ${#SKIPPED[@]} -gt 0 ]; then
  echo ""
  echo "Skipped (already exist):"
  for f in "${SKIPPED[@]}"; do
    echo "  ~ ${f/$CF\//}"
  done
fi

echo ""
echo "Before running agents, fill in:"
echo ""

NEEDS_FILL=()
if grep -q "PROJECT_NAME\|describe tech stack" "$PROJECT_DIR/.agent-config.json" 2>/dev/null; then
  NEEDS_FILL+=(".agent-config.json  — set stack, git_repo, budget, regression_scope")
fi
if [ ! -s "$PROJECT_DIR/CONVENTIONS.md" ]; then
  NEEDS_FILL+=("CONVENTIONS.md      — required before any builder tasks")
fi
if grep -q "PROJECT_NAME\|#XXXXXX" "$PROJECT_DIR/DESIGN_SYSTEM.md" 2>/dev/null; then
  NEEDS_FILL+=("DESIGN_SYSTEM.md    — required before any UI tasks")
fi

if [ ${#NEEDS_FILL[@]} -gt 0 ]; then
  for item in "${NEEDS_FILL[@]}"; do
    echo "  ! $item"
  done
else
  echo "  All config files look filled. Ready to go."
fi

echo ""
echo "To get all launch commands:"
echo "  $AGENTS_DIR/shared/start-project.sh $PROJECT"
echo ""
