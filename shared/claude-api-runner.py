#!/usr/bin/env python3
"""
claude-api-runner.py — Drop-in replacement for `claude --print --output-format json`.

Reads a prompt from stdin, runs an agentic tool-use loop via the Anthropic API,
and writes a single JSON line to stdout:
  {"usage": {"input_tokens": N, "output_tokens": N}, "result": "..."}

Reads the agent system prompt from CLAUDE.md in the current working directory
(same directory the watch.sh runs from).

Usage:
  echo "prompt" | python3 claude-api-runner.py \
    --model MODEL \
    --allowedTools "Bash,Read,Write,Edit,Glob,Grep" \
    --add-dir /path/to/project \
    --add-dir /path/to/workspace

Requires:
  pip install anthropic
  export ANTHROPIC_API_KEY=sk-ant-...
"""

import argparse
import glob as glob_module
import json
import os
import subprocess
import sys
from pathlib import Path

try:
    import anthropic
except ImportError:
    print("Error: anthropic package not installed. Run: pip install anthropic", file=sys.stderr)
    sys.exit(1)

# ── Argument parsing ──────────────────────────────────────────────────────────

parser = argparse.ArgumentParser(add_help=False)
parser.add_argument("--model", default="claude-sonnet-4-6")
parser.add_argument("--allowedTools", default="Read,Glob,Grep")
parser.add_argument("--add-dir", action="append", dest="add_dirs", default=[])
# Ignore flags that Claude Code CLI uses but we don't need
parser.add_argument("--print", action="store_true", default=True)
parser.add_argument("--output-format", default="json")
args, _ = parser.parse_known_args()

allowed_tools = set(t.strip() for t in args.allowedTools.split(","))

# ── Read system prompt from CLAUDE.md in CWD ──────────────────────────────────

system_prompt = ""
claude_md = Path.cwd() / "CLAUDE.md"
if claude_md.exists():
    system_prompt = claude_md.read_text(encoding="utf-8")

# Append directory context so Claude knows where to look
if args.add_dirs:
    dirs_note = "\n\n## Available Directories\n" + "\n".join(f"- {d}" for d in args.add_dirs if d)
    system_prompt += dirs_note

# ── Read user prompt from stdin ───────────────────────────────────────────────

user_prompt = sys.stdin.read().strip()
if not user_prompt:
    print(json.dumps({"usage": {"input_tokens": 0, "output_tokens": 0}, "result": ""}))
    sys.exit(0)

# ── Tool definitions ──────────────────────────────────────────────────────────

TOOL_DEFINITIONS = []

if "Bash" in allowed_tools:
    TOOL_DEFINITIONS.append({
        "name": "Bash",
        "description": (
            "Execute a bash command and return its output. "
            "Use for running tests, lint, build commands, git operations, and other shell tasks."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "command": {"type": "string", "description": "The bash command to execute"},
                "description": {"type": "string", "description": "Brief description of what the command does"},
            },
            "required": ["command"],
        },
    })

if "Read" in allowed_tools:
    TOOL_DEFINITIONS.append({
        "name": "Read",
        "description": "Read the contents of a file. Returns content with line numbers.",
        "input_schema": {
            "type": "object",
            "properties": {
                "file_path": {"type": "string", "description": "Absolute path to the file"},
                "offset": {"type": "integer", "description": "Line number to start reading from (1-indexed)"},
                "limit": {"type": "integer", "description": "Maximum number of lines to read"},
            },
            "required": ["file_path"],
        },
    })

if "Write" in allowed_tools:
    TOOL_DEFINITIONS.append({
        "name": "Write",
        "description": "Write content to a file, creating it or overwriting it entirely.",
        "input_schema": {
            "type": "object",
            "properties": {
                "file_path": {"type": "string", "description": "Absolute path to the file"},
                "content": {"type": "string", "description": "Content to write"},
            },
            "required": ["file_path", "content"],
        },
    })

if "Edit" in allowed_tools:
    TOOL_DEFINITIONS.append({
        "name": "Edit",
        "description": (
            "Replace an exact string in a file. "
            "The old_string must be unique in the file unless replace_all is true."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "file_path": {"type": "string", "description": "Absolute path to the file"},
                "old_string": {"type": "string", "description": "The exact string to find and replace"},
                "new_string": {"type": "string", "description": "The replacement string"},
                "replace_all": {
                    "type": "boolean",
                    "description": "Replace every occurrence (default: false — only the first)",
                },
            },
            "required": ["file_path", "old_string", "new_string"],
        },
    })

if "Glob" in allowed_tools:
    TOOL_DEFINITIONS.append({
        "name": "Glob",
        "description": "Find files matching a glob pattern. Returns matching paths sorted by modification time.",
        "input_schema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string", "description": "Glob pattern, e.g. '**/*.ts' or 'src/**/*.tsx'"},
                "path": {"type": "string", "description": "Directory to search in (defaults to current directory)"},
            },
            "required": ["pattern"],
        },
    })

if "Grep" in allowed_tools:
    TOOL_DEFINITIONS.append({
        "name": "Grep",
        "description": "Search file contents using a regex pattern.",
        "input_schema": {
            "type": "object",
            "properties": {
                "pattern": {"type": "string", "description": "Regex pattern to search for"},
                "path": {"type": "string", "description": "File or directory to search in"},
                "glob": {"type": "string", "description": "Glob filter, e.g. '*.ts'"},
                "output_mode": {
                    "type": "string",
                    "enum": ["content", "files_with_matches", "count"],
                    "description": "Output format (default: files_with_matches)",
                },
                "-i": {"type": "boolean", "description": "Case insensitive search"},
                "context": {"type": "integer", "description": "Lines of context around each match"},
            },
            "required": ["pattern"],
        },
    })

# ── Tool execution ────────────────────────────────────────────────────────────

def execute_tool(name: str, inputs: dict) -> str:
    try:
        if name == "Bash":
            cmd = inputs["command"]
            result = subprocess.run(
                cmd, shell=True, capture_output=True, text=True, timeout=120
            )
            output = result.stdout
            if result.returncode != 0:
                if result.stderr:
                    output += f"\n[stderr]: {result.stderr.strip()}"
                output += f"\n[exit code: {result.returncode}]"
            return output.strip() or "(no output)"

        elif name == "Read":
            file_path = inputs["file_path"]
            offset = max(1, inputs.get("offset") or 1)
            limit = inputs.get("limit")
            try:
                with open(file_path, "r", encoding="utf-8", errors="replace") as f:
                    lines = f.readlines()
                start = offset - 1
                end = start + limit if limit else len(lines)
                selected = lines[start:end]
                result = "".join(f"{start + i + 1}\t{line}" for i, line in enumerate(selected))
                return result or "(empty file)"
            except FileNotFoundError:
                return f"Error: File not found: {file_path}"
            except Exception as e:
                return f"Error reading file: {e}"

        elif name == "Write":
            file_path = inputs["file_path"]
            content = inputs["content"]
            try:
                Path(file_path).parent.mkdir(parents=True, exist_ok=True)
                with open(file_path, "w", encoding="utf-8") as f:
                    f.write(content)
                return f"Written: {file_path}"
            except Exception as e:
                return f"Error writing file: {e}"

        elif name == "Edit":
            file_path = inputs["file_path"]
            old_string = inputs["old_string"]
            new_string = inputs["new_string"]
            replace_all = inputs.get("replace_all", False)
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    content = f.read()
                count = content.count(old_string)
                if count == 0:
                    return f"Error: old_string not found in {file_path}"
                if not replace_all and count > 1:
                    return (
                        f"Error: old_string appears {count} times in {file_path}. "
                        "Provide more surrounding context to make it unique, or use replace_all: true."
                    )
                new_content = content.replace(old_string, new_string) if replace_all \
                    else content.replace(old_string, new_string, 1)
                with open(file_path, "w", encoding="utf-8") as f:
                    f.write(new_content)
                replaced = count if replace_all else 1
                return f"Replaced {replaced} occurrence(s) in {file_path}"
            except FileNotFoundError:
                return f"Error: File not found: {file_path}"
            except Exception as e:
                return f"Error editing file: {e}"

        elif name == "Glob":
            pattern = inputs["pattern"]
            search_path = inputs.get("path") or "."
            try:
                full_pattern = os.path.join(search_path, pattern)
                matches = glob_module.glob(full_pattern, recursive=True)
                matches.sort(key=lambda p: os.path.getmtime(p) if os.path.exists(p) else 0, reverse=True)
                return "\n".join(matches) if matches else "(no matches)"
            except Exception as e:
                return f"Error: {e}"

        elif name == "Grep":
            pattern = inputs["pattern"]
            search_path = inputs.get("path", ".")
            file_glob = inputs.get("glob")
            output_mode = inputs.get("output_mode", "files_with_matches")
            case_insensitive = inputs.get("-i", False)
            context = inputs.get("context", 0)

            cmd = ["rg", "--no-messages"]
            if case_insensitive:
                cmd.append("-i")
            if output_mode == "files_with_matches":
                cmd.append("-l")
            elif output_mode == "count":
                cmd.append("--count")
            else:
                cmd.append("-n")
                if context:
                    cmd.extend(["-C", str(context)])
            if file_glob:
                cmd.extend(["--glob", file_glob])
            cmd.extend([pattern, search_path])

            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0:
                return result.stdout.strip() or "(no matches)"
            elif result.returncode == 1:
                return "(no matches)"
            else:
                # Fallback: grep
                gcmd = ["grep", "-r"]
                if case_insensitive:
                    gcmd.append("-i")
                if output_mode == "files_with_matches":
                    gcmd.append("-l")
                elif output_mode == "count":
                    gcmd.append("-c")
                else:
                    gcmd.append("-n")
                    if context:
                        gcmd.extend(["-C", str(context)])
                gcmd.extend([pattern, search_path])
                r2 = subprocess.run(gcmd, capture_output=True, text=True)
                return r2.stdout.strip() or "(no matches)"

        else:
            return f"Error: Unknown tool: {name}"

    except subprocess.TimeoutExpired:
        return f"Error: {name} timed out (120s)"
    except Exception as e:
        return f"Error executing {name}: {e}"


# ── Agentic loop ──────────────────────────────────────────────────────────────

api_key = os.environ.get("ANTHROPIC_API_KEY")
if not api_key:
    print("Error: ANTHROPIC_API_KEY environment variable not set.", file=sys.stderr)
    sys.exit(1)

client = anthropic.Anthropic(api_key=api_key)

messages = [{"role": "user", "content": user_prompt}]
total_input_tokens = 0
total_output_tokens = 0
final_result = ""
MAX_TURNS = 80

for turn in range(MAX_TURNS):
    kwargs = {
        "model": args.model,
        "max_tokens": 8192,
        "messages": messages,
    }
    if system_prompt:
        kwargs["system"] = system_prompt
    if TOOL_DEFINITIONS:
        kwargs["tools"] = TOOL_DEFINITIONS

    try:
        response = client.messages.create(**kwargs)
    except anthropic.APIError as e:
        print(f"API error: {e}", file=sys.stderr)
        sys.exit(1)

    total_input_tokens += response.usage.input_tokens
    total_output_tokens += response.usage.output_tokens

    messages.append({"role": "assistant", "content": response.content})

    if response.stop_reason == "end_turn":
        for block in response.content:
            if hasattr(block, "text"):
                final_result = block.text
        break

    if response.stop_reason != "tool_use":
        for block in response.content:
            if hasattr(block, "text"):
                final_result = block.text
        break

    # Execute tool calls and collect results
    tool_results = []
    for block in response.content:
        if block.type == "tool_use":
            print(f"  [tool] {block.name}({list(block.input.keys())})", file=sys.stderr)
            output = execute_tool(block.name, block.input)
            tool_results.append({
                "type": "tool_result",
                "tool_use_id": block.id,
                "content": output,
            })

    if tool_results:
        messages.append({"role": "user", "content": tool_results})
    else:
        break  # tool_use stop_reason but no tool_use blocks — shouldn't happen

else:
    print(f"Warning: Reached max turns ({MAX_TURNS})", file=sys.stderr)

# ── Output JSON (compatible with watch.sh expectations) ──────────────────────

print(json.dumps({
    "usage": {
        "input_tokens": total_input_tokens,
        "output_tokens": total_output_tokens,
    },
    "result": final_result,
}))
