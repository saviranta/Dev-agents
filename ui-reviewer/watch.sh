#!/bin/bash
# builder-composer/watch.sh
# Launched via: shared/launch-agent.sh builder-composer PROJECT_NAME

AGENT="ui-reviewer"
SIGNAL_STATUS="reviewed"   # builders and tester emit "done"; reviewers emit "reviewed"

CF="$HOME/Library/CloudStorage/Dropbox/ClaudeFolder"
COSTS_FILE="$CF/Agents/shared/costs.json"

# ── Load config ───────────────────────────────────────────────────────────────
if [ -z "$PROJECT_CONFIG" ]; then
  echo "❌ PROJECT_CONFIG env var not set. Use launch-agent.sh to start this agent."
  exit 1
fi

MANIFEST=$(echo  "$PROJECT_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin)['manifest'])")
WORKSPACE=$(echo "$PROJECT_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin)['workspace'])")
SIGNALS=$(echo   "$PROJECT_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin)['signals'])")
MODEL=$(echo       "$PROJECT_CONFIG" | python3 -c "import sys,json; print(json.load(sys.stdin)['agents']['$AGENT']['model'])")
PROJECT_ROOT=$(echo "$PROJECT_CONFIG" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('app_root', d.get('project_root','')))")

OUTPUT_DIR="$WORKSPACE/$AGENT/output"
mkdir -p "$OUTPUT_DIR"

echo "🤖 $AGENT watching for pending tasks (model: $MODEL)"
echo "   Manifest: $MANIFEST"
echo ""

# ── Cost calculation ──────────────────────────────────────────────────────────
calc_cost() {
  local tokens_in=$1 tokens_out=$2
  python3 -c "
import json
with open('$COSTS_FILE') as f:
    costs = json.load(f)
m = costs.get('$MODEL', costs.get('claude-sonnet-4-6', {}))
cost = ($tokens_in * m.get('input', 0)) + ($tokens_out * m.get('output', 0))
print(f'{cost:.6f}')
"
}

ts() { date -u +"%Y-%m-%dT%H:%M:%SZ"; }

# ── Main loop ─────────────────────────────────────────────────────────────────
while true; do
  if [ ! -f "$MANIFEST" ]; then
    sleep 30; continue
  fi

  TASK=$(python3 -c "
import json, sys
with open('$MANIFEST') as f:
    m = json.load(f)
for task in m.get('tasks', []):
    if task.get('assigned_to') == '$AGENT' and task.get('status') == 'pending':
        print(json.dumps(task))
        sys.exit(0)
sys.exit(1)
" 2>/dev/null)

  if [ $? -ne 0 ] || [ -z "$TASK" ]; then
    sleep 30; continue
  fi

  TASK_ID=$(echo    "$TASK" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  TASK_INPUT=$(echo "$TASK" | python3 -c "import sys,json; print(json.load(sys.stdin)['input'])")

  echo "$(ts) 📋 $TASK_ID — picked up"

  START_TIME=$(ts)
  START_EPOCH=$(date +%s)

  RESPONSE_FILE="/tmp/${AGENT}-${TASK_ID}-response.json"
  ERROR_FILE="/tmp/${AGENT}-${TASK_ID}-error.txt"

  SAFE_INPUT=$(printf '<task id="%s">\n%s\n</task>' "$TASK_ID" "$TASK_INPUT")
  echo "$SAFE_INPUT" | claude --model "$MODEL" --print --output-format json \
    --allowedTools "Read,Write,Edit,Glob,Grep" \
    --allowedPaths "$PROJECT_ROOT,$WORKSPACE" \
    > "$RESPONSE_FILE" 2>"$ERROR_FILE"
  CLAUDE_EXIT=$?

  END_EPOCH=$(date +%s)
  DURATION=$((END_EPOCH - START_EPOCH))
  COMPLETED=$(ts)

  if [ $CLAUDE_EXIT -ne 0 ] || [ ! -s "$RESPONSE_FILE" ]; then
    ERROR_MSG=$(head -5 "$ERROR_FILE" 2>/dev/null)
    cat > "$OUTPUT_DIR/${TASK_ID}.md" << EOF
# $TASK_ID — FAILED
Agent: $AGENT
Error: Claude exited with code $CLAUDE_EXIT
$ERROR_MSG
EOF
    cat > "$SIGNALS/${TASK_ID}.failed.json" << SIGEOF
{"task_id":"$TASK_ID","agent":"$AGENT","status":"failed","tokens_in":0,"tokens_out":0,"cost_usd":0,"started":"$START_TIME","completed":"$COMPLETED","duration_seconds":$DURATION,"output_file":"$OUTPUT_DIR/${TASK_ID}.md","flags":"exit_$CLAUDE_EXIT"}
SIGEOF
    echo "$(ts) ❌ $TASK_ID failed (exit $CLAUDE_EXIT)"
    sleep 30; continue
  fi

  TOKENS_IN=$(python3  -c "import json; print(json.load(open('$RESPONSE_FILE')).get('usage',{}).get('input_tokens',0))"  2>/dev/null || echo 0)
  TOKENS_OUT=$(python3 -c "import json; print(json.load(open('$RESPONSE_FILE')).get('usage',{}).get('output_tokens',0))" 2>/dev/null || echo 0)
  RESULT=$(python3     -c "import json; print(json.load(open('$RESPONSE_FILE')).get('result',''))"                        2>/dev/null || echo "")
  COST=$(calc_cost "$TOKENS_IN" "$TOKENS_OUT")

  CHANGED_FILES=$(cd "$PROJECT_ROOT" && git diff --name-only HEAD 2>/dev/null | tr '\n' ',' | sed 's/,$//')

  echo "$RESULT" > "$OUTPUT_DIR/${TASK_ID}.md"

  cat > "$SIGNALS/${TASK_ID}.${SIGNAL_STATUS}.json" << SIGEOF
{"task_id":"$TASK_ID","agent":"$AGENT","status":"$SIGNAL_STATUS","tokens_in":$TOKENS_IN,"tokens_out":$TOKENS_OUT,"cost_usd":$COST,"started":"$START_TIME","completed":"$COMPLETED","duration_seconds":$DURATION,"output_file":"$WORKSPACE/$AGENT/output/${TASK_ID}.md","files_changed":"$CHANGED_FILES","flags":""}
SIGEOF

  echo "$(ts) 📤 Signal: ${TASK_ID}.${SIGNAL_STATUS}.json | ${TOKENS_IN}/${TOKENS_OUT} tokens | \$$COST"
  sleep 30
done
