# Agent-SI System Journal

Living record of observations, improvements, and outcomes for the agent system.
Append-only. Any agent (Planner, Architect, Reviewer, Tester) may write here.
Agent-SI reads everything during audit.

Entry types: `audit` | `improvement` | `outcome` | `agent-observation` | `user-feedback` | `suggestion`

---

## 2026-03-21 — ECC comparison: suggestion 6 — agent pattern capture
Type: suggestion
Source: agent-si (ECC comparative analysis)

### Summary
Add post-cycle tactical pattern capture to Agent-SI so that debugging resolutions and workarounds that don't rise to RFC level are preserved across sessions.

### Problem
The RFC + journal system captures system-level improvements well. Tactical patterns — "when builder-data fails on Prisma migration with constraint violation X, the fix is Y" — are currently lost when a session ends. There is no mechanism to carry forward operational knowledge that is below RFC threshold.

### ECC reference
ECC's `/learn` command (`commands/learn.md`) extracts reusable patterns from sessions at any point. The user runs `/learn` after solving a non-trivial problem; Claude reviews the session, identifies the most valuable insight, drafts a skill file at `~/.claude/skills/learned/[pattern-name].md`, and asks for confirmation before saving. ECC also runs `evaluate-session.js` as an async Stop hook (`hooks/hooks.json` → `stop:evaluate-session`) that automatically scores each session for extractable patterns — no user prompt required.

### Proposed approach
1. Extend the existing audit Step 2 questionnaire with a fifth question: "Any debugging or resolution pattern worth noting? (free text or 'none')."
2. Non-none answers are saved as pattern files in `$CF/Agents/agent-si/patterns/[slug].md` with a standard header (date, project, stack, pattern body).
3. Agent-SI reads `patterns/` at the start of improvement sessions, similar to how it reads the journal.
4. Patterns are tagged with stack context so stale or project-specific patterns can be filtered.

### Trade-offs
- *Benefit:* Operational knowledge is retained and surfaced in future improvement sessions. Reduces repeated root-cause diagnosis for known failure modes.
- *Risk:* Patterns can become stale or project-specific and mislead future sessions if applied without checking current context. Mitigation: include a `verified_for_stack` field and a last-confirmed date.
- *Effort:* Low — no agent instruction changes needed beyond a new questionnaire item and a new directory.

### Suggested review
After first audit that captures a pattern, check whether the pattern was usefully applied in the following session.

---

## 2026-03-21 — ECC comparison: suggestion 5 — stall detection in Orchestrator
Type: suggestion
Source: agent-si (ECC comparative analysis)

### Summary
Add time-aware stall detection to Orchestrator's polling loop so that silent builder failures (crashed session, API error, closed terminal) are surfaced immediately rather than discovered by the user on dashboard inspection.

### Problem
When a builder stall occurs (Claude Code session crashes, API timeout, terminal closed), the builder produces no signal. Orchestrator continues polling every 15 seconds with no indication that a task is frozen. The user discovers the stall only when they check the dashboard manually. There is no proactive alerting.

### ECC reference
ECC's `loop-operator` agent (`agents/loop-operator.md`) explicitly escalates when "no progress across two consecutive checkpoints" and when "repeated failures with identical stack traces." It also tracks "cost drift outside budget window" as an escalation trigger. The agent runs as a named subagent invoked by Claude, but the pattern — periodic progress checkpoints with escalation on no-movement — is directly applicable to a polling architecture. ECC's `cost-tracker` Stop hook (`hooks/hooks.json` → `stop:cost-tracker`) logs token and cost metrics per session to support drift detection.

### Proposed approach
1. Orchestrator already writes `"started"` to the manifest when activating a task (current instruction in `orchestrator/CLAUDE.md`).
2. On each poll cycle, compute elapsed time for every `in_progress` task: `now - started`.
3. If elapsed > `stall_threshold_minutes` (default: 20, configurable in `.agent-config.json`), print a warning banner naming the stalled task and suggesting the user check the builder terminal.
4. Do not halt or auto-retry — only alert. User decides the action.
5. Optionally: emit a `stall_suspected` event to `run-log.jsonl` so Agent-SI can track stall frequency in metrics.

### Trade-offs
- *Benefit:* Silent failures become visible within one stall-threshold period. Prevents long undetected stalls wasting wall-clock time.
- *Risk:* False positives on legitimately long tasks (e.g. a builder-composer touching 3 files with full TypeScript compilation may take 12-15 minutes). Mitigate with a conservative default threshold and per-agent-type overrides in config.
- *Effort:* Low — pure Orchestrator watch loop change, no new files, no new agents.

### Suggested review
After implementation, check run-log.jsonl for `stall_suspected` events across the next two projects to calibrate the threshold.

---

## 2026-03-21 — ECC comparison: suggestion 4 — deterministic harness scoring
Type: suggestion
Source: agent-si (ECC comparative analysis)

### Summary
Add a deterministic scoring script to Agent-SI that produces a reproducible numeric score per audit, so that RFC outcomes can be measured quantitatively rather than qualitatively.

### Problem
Agent-SI audits compare metric snapshots in `metrics-baseline.md` across projects. The comparison is qualitative — "fix_rate improved." There is no single headline score that summarises system health, and RFC outcomes ("did this RFC improve the system?") rely on the reviewer reading multiple metric columns and forming a judgment. This is fragile: different auditors (different Claude sessions) may weigh the same data differently.

### ECC reference
ECC's `harness-audit` command (`commands/harness-audit.md`) runs `node scripts/harness-audit.js` which scores 7 fixed dimensions (Tool Coverage, Context Efficiency, Quality Gates, Memory Persistence, Eval Coverage, Security Guardrails, Cost Efficiency) each 0–10, for a maximum of 70. The rubric is versioned (`Rubric version: 2026-03-16`). The score is computed from file/rule checks — not LLM estimation — so the same codebase state always produces the same score. This makes RFC before/after comparisons objective. The `harness-optimizer` agent (`agents/harness-optimizer.md`) runs this audit, identifies top 3 leverage areas, and reports before/after deltas.

### Proposed approach
1. Write `$CF/Agents/agent-si/harness-score.sh` that reads `run-log.jsonl` for the most recent completed project and outputs a JSON score object.
2. Dimensions (suggested): (1) manifest validation pass rate (BLOCKs per manifest), (2) fix task rate (fix-phase tasks / total tasks), (3) average cost per task, (4) cycle rejection rate (rejections / cycles), (5) builder BLOCKED signal rate, (6) reviewer CRITICAL+HIGH finding rate.
3. Each dimension is scored 0–10 against defined thresholds written into the script.
4. Agent-SI calls this script during audit Step 1 (alongside `extract-metrics.sh`) and appends the score to `metrics-baseline.md`.
5. RFC outcome tracking (audit Step 5) compares scores directly rather than comparing prose.

### Trade-offs
- *Benefit:* RFC outcomes become verifiable ("score moved from 54 to 61"). Reduces inter-session variance in audit quality. Score trends over time are a leading indicator of system drift.
- *Risk:* A poorly designed rubric creates false confidence. The six dimensions above are proxies — a high score does not guarantee good output quality, only that measurable indicators are within thresholds. Should be treated as one input, not the only input.
- *Effort:* Medium — requires writing and calibrating the scoring script, and deciding on threshold values from existing baseline data.

### Suggested review
After first scored audit, compare the score-based outcome assessment with the qualitative assessment from the same audit. If they disagree, recalibrate thresholds.

---

## 2026-03-21 — ECC comparison: suggestion 3 — per-edit type-checking in builder sessions
Type: suggestion
Source: agent-si (ECC comparative analysis)

### Summary
Add a PostToolUse hook that runs TypeScript type-checking after every file edit in builder sessions, so type errors are caught turn-by-turn rather than at cycle end.

### Problem
Builders currently run `tsc --noEmit` once before writing their output file (enforced by builder CLAUDE.md rules). A type error introduced at turn 3 of a 12-turn task is not detected until turn 12. At that point, fixing it may require re-reading files already out of the builder's active context, increasing the chance of a `failed` signal and a fix task being added by Architect. Earlier detection is cheaper.

### ECC reference
ECC has a `post:edit:typecheck` PostToolUse hook (`hooks/hooks.json`) that runs `scripts/hooks/post-edit-typecheck.js` after editing any `.ts`/`.tsx` file. It fires synchronously (blocks the next turn) so the builder sees the error immediately. ECC also has a `post:edit:format` hook (auto-format after edits) and a `post:edit:console-warn` hook (warn on `console.log` after edits). These are all conditioned on the `Edit` tool matcher and specific file extensions. ECC's builder-equivalent agents (`build-error-resolver.md`) also run incremental type checks as their primary diagnostic step.

### Proposed approach
1. Add a PostToolUse hook to each builder's `.claude/settings.local.json` (or a shared builder settings file) matching `Edit|Write` on `.ts`/`.tsx` files.
2. The hook runs `npx tsc --noEmit --incremental` with a 15-second timeout. On non-zero exit, the hook output is shown to the builder as a tool result, prompting immediate correction.
3. Apply initially to `builder-composer` and `builder-systems` (highest volume, most TypeScript). Exclude `builder-data` (SQL/migration files).
4. Use `--incremental` to keep check time under 5 seconds on warm cache.

### Trade-offs
- *Benefit:* Type errors caught after each edit rather than at cycle end. Reduces late-cycle `failed` signals and avoids Architect fix tasks for purely mechanical type issues.
- *Risk:* Adds 2-8s latency per edit. On a 10-edit task, this is 20-80s of overhead. Mid-edit states (function partially written) may produce spurious errors that confuse the builder. Mitigation: run only on complete file saves, not partial writes; skip if file is shorter than N lines.
- *Effort:* Low — settings.local.json hook addition. No CLAUDE.md changes.

### Suggested review
After two projects with the hook enabled, compare `failed` signal rate for TypeScript-related errors against the pre-hook baseline.

---

## 2026-03-21 — ECC comparison: suggestion 2 — PreCompact hook for Orchestrator and Planner
Type: suggestion
Source: agent-si (ECC comparative analysis)

### Summary
Add a PreCompact hook to Orchestrator that saves coordination state before context compaction, and a similar hook for Planner that preserves PRD and last decision context.

### Problem
Orchestrator and Planner are long-running interactive sessions that accumulate coordination state in their context windows. If Claude Code compacts the context during a long session, Orchestrator must reconstruct its understanding of the manifest from scratch (it re-reads manifest.json on each poll, so task state survives, but the "why" context — recent signal history, rejection notes, budget trajectory — is lost). Planner is more vulnerable: PRD reasoning, scope decisions, and open questions are held in context and are not persisted anywhere except the PRD.md file itself.

### ECC reference
ECC's PreCompact hook (`hooks/hooks.json` → `pre:compact`) runs `scripts/hooks/pre-compact.js` before every context compaction. The hook saves session state (current task, in-progress decisions, open threads) to a `.claude/session-state.json` file. The companion SessionStart hook (`session:start` → `scripts/hooks/session-start.js`) reloads this state at the beginning of each new session, so context continuity survives both compaction and full session restarts. ECC treats this as a `minimal` profile hook — it runs even in the most restrictive configuration. ECC also has a `session:end:marker` SessionEnd hook for lifecycle tracking.

### Proposed approach
1. Add a PreCompact hook to `orchestrator/.claude/settings.local.json` that writes the current manifest summary (last 5 signal events, current in_progress tasks, budget remaining) to `agent-workspace/orchestrator-state.json`.
2. Add a PreCompact hook to `planner/.claude/settings.local.json` that writes the PRD summary, last replanning decision, and open questions to `agent-workspace/planner-state.json`.
3. Update Orchestrator CLAUDE.md: at session start, check for `orchestrator-state.json` and read it as context before beginning the poll loop.
4. Update Planner CLAUDE.md: at session start in pre-flight mode, read `planner-state.json` if present.

### Trade-offs
- *Benefit:* Orchestrator and Planner sessions survive context compaction without losing coordination context. Particularly valuable for Planner in long planning sessions with multiple Architect feedback loops.
- *Risk:* Low. PreCompact hooks run before compaction and write to files. The main risk is that stale state files from a previous session are accidentally loaded — mitigate by including a session timestamp in the state file and checking it matches the current session.
- *Effort:* Low — settings.local.json additions and minor CLAUDE.md updates for Orchestrator and Planner. No new agents.

### Suggested review
After the next two projects, check whether any compaction events occurred during Orchestrator or Planner sessions and whether the state files were used for recovery.

---

## 2026-03-21 — ECC comparison: suggestion 1 — model routing by task type
Type: suggestion
Source: agent-si (ECC comparative analysis)

### Summary
Add a `model` field to the manifest task schema and builder CLAUDE.md files so that mechanical, low-judgment tasks run on Haiku rather than Sonnet, reducing cost significantly on eligible task types.

### Problem
All builders currently run on whatever model the user launches them with (typically Sonnet). Many tasks are mechanical — a database migration adding a single column, a single-function integration shim, a fix task replacing three lines with a corrected version. These tasks require no architectural judgment and do not benefit from Sonnet's reasoning depth. Running them on Sonnet spends 20-40x more than necessary for the task at hand.

### ECC reference
ECC's `/model-route` command (`commands/model-route.md`) recommends model tier by task complexity: haiku for "deterministic, low-risk mechanical changes", sonnet for "default for implementation and refactors", opus for "architecture, deep review, ambiguous requirements." The `harness-optimizer` agent (`agents/harness-optimizer.md`) includes "routing" as one of its top 5 leverage areas. ECC's `doc-updater` agent (`agents/doc-updater.md`) is explicitly assigned `model: haiku` in its frontmatter — a documentation/codemap agent with well-defined mechanical outputs. ECC's AGENTS.md also notes: "Avoid last 20% of context window for large refactoring and multi-file features. Lower-sensitivity tasks (single edits, docs, simple fixes) tolerate higher utilisation" — implicitly acknowledging model-tier differentiation.

### Proposed approach
1. Add an optional `"model"` field to the manifest task schema (values: `"haiku"` | `"sonnet"` | `"opus"`; default: `"sonnet"` if absent).
2. Update `templates/signal-schema.json` and `templates/manifest-template.json` accordingly.
3. Update builder `watch.sh` scripts to read the `model` field from the assigned task and pass it to the `claude` invocation (e.g. `--model claude-haiku-4-5-20251001`).
4. Update Planner CLAUDE.md with a routing heuristic:
   - `haiku`: SQL migration with explicit before/after schema (no judgment), single-function fix task with exact replacement snippet, documentation update
   - `sonnet`: default for all builder tasks
   - (Opus is reserved for interactive agents — Planner, Architect — never set in manifest tasks)
5. Update Validator to accept `"model"` as a valid optional task field.

### Trade-offs
- *Benefit:* Mechanical tasks at Haiku cost are ~20-40x cheaper than Sonnet. On a project where 20-30% of tasks are migrations, fix tasks, and doc updates, this could reduce total builder cost by 15-25%.
- *Risk:* Haiku has lower instruction-following reliability than Sonnet. A Haiku builder that silently skips a required step (e.g. running `tsc --noEmit`) and emits a `done` signal produces a false pass that reaches Architect review. Mitigation: restrict `haiku` to tasks with explicit before/after snippets in the input (i.e. tasks that require zero codebase exploration) and where the outcome is mechanically verifiable (e.g. `tsc --noEmit` exit code).
- *Risk 2:* Planner must correctly classify tasks at write time, which requires more judgment from Planner. Mis-routing a non-trivial task to Haiku is worse than not routing at all. Mitigation: conservative defaults (only recommend Haiku when both conditions hold: the task input contains a full before/after snippet AND the task touches ≤1 file).
- *Effort:* Medium — manifest schema change, watch.sh updates for all builders, Planner instruction update, Validator update.

### Suggested review
After the first project using model routing, compare cost/task for Haiku-routed vs. Sonnet-routed tasks and check whether Haiku-routed tasks had a higher failed-signal rate.

---

<!-- Add new entries above this line, newest at top -->
