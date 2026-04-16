# ARIS for Synergy

This is a Synergy-adapted fork of [ARIS (Auto-claude-code-research-in-sleep)](https://github.com/wanshuiyin/Auto-claude-code-research-in-sleep) — the autonomous ML research workflow system.

## What changed

The upstream ARIS system relies on **Codex MCP** (`mcp__codex__codex`) for cross-model review — Claude Code executes while GPT reviews via MCP tool calls. This fork replaces that architecture with **Synergy-native agents and task delegation**:

- `mcp__codex__codex` / `mcp__codex__codex-reply` → `task(subagent_type="reviewer", ...)`
- `codex exec` (nightmare mode) → `task(subagent_type="auditor", ...)`
- `reasoning_effort: xhigh` → `category: "most-capable"` (Synergy's task category system)
- MCP threadId conversation threading → stateless task calls with full context per round
- `~/.claude/feishu.json` → platform-agnostic feishu notification config
- Three workflow skills (`research-pipeline`, `idea-discovery`, `paper-writing`) now include optional DAG orchestration sections for parallel execution in Synergy

Everything else is preserved: workflow logic, artifact contracts (Markdown files like `AUTO_REVIEW.md`, `REVIEWER_MEMORY.md`, etc.), scoring rubrics, difficulty levels, SSH experiment deployment, and the full skill set.

### Removed

- `skills/skills-codex/` — Codex CLI variant (replaced by native adaptation)
- `skills/skills-codex-gemini-review/` — Gemini reviewer variant
- `skills/skills-codex-claude-review/` — Claude reviewer variant
- `mcp-servers/claude-review/` — Claude review MCP server
- `mcp-servers/gemini-review/` — Gemini review MCP server

### Retained

- `mcp-servers/feishu-bridge/` — Feishu notification bridge (still useful)
- `mcp-servers/llm-chat/` — Generic LLM API chat (still useful for `auto-review-loop-llm`)
- `mcp-servers/minimax-chat/` — MiniMax API chat (still useful for `auto-review-loop-minimax`)
- `tools/` — Helper scripts (arxiv_fetch.py, save_trace.sh, etc.)

## Installation

### One-click install

```bash
curl -sL https://raw.githubusercontent.com/EricSanchezok/Auto-claude-code-research-in-sleep/main/install.sh | bash
```

The installer will:
1. Clone the repo to `~/.synergy/aris/` (persistent, not a temp dir)
2. Symlink all skills to `~/.synergy/config/skills/` (or copy if symlinks fail)
3. Copy `reviewer.md` and `auditor.md` agents to `~/.synergy/config/agent/`
4. Skip skills that already exist (won't overwrite your customizations)

### Update

Run the same command again — it will `git pull` the persistent clone and refresh symlinks:

```bash
curl -sL https://raw.githubusercontent.com/EricSanchezok/Auto-claude-code-research-in-sleep/main/install.sh | bash
```

### Uninstall

```bash
curl -sL https://raw.githubusercontent.com/EricSanchezok/Auto-claude-code-research-in-sleep/main/install.sh | bash -s -- --uninstall
```

### Manual install

If you prefer manual control:

```bash
git clone https://github.com/EricSanchezok/Auto-claude-code-research-in-sleep.git
cd Auto-claude-code-research-in-sleep

# Skills (symlink recommended for easy git pull updates)
ln -s "$(pwd)/skills"/* ~/.synergy/config/skills/

# Agents
cp agents/reviewer.md agents/auditor.md ~/.synergy/config/agent/
```

### MCP servers (optional)

If you want Feishu notifications or alternative LLM reviewer backends:

```bash
# Feishu bridge
cd mcp-servers/feishu-bridge && npm install

# Generic LLM chat (for auto-review-loop-llm)
cd mcp-servers/llm-chat && npm install

# MiniMax (for auto-review-loop-minimax)
cd mcp-servers/minimax-chat && npm install
```

## Agents

### reviewer

Cross-model research reviewer for adversarial scientific critique. Scores research work 1-10, identifies weaknesses, and demands minimum viable fixes. Supports three difficulty levels: medium (standard), hard (with reviewer memory), and nightmare (full repo access).

### auditor

Experiment integrity auditor. Independently reads code, result files, and logs to verify that reported numbers match actual outputs. Catches fabricated ground truth, self-normalized scores, phantom results, and scope overclaims.

## Usage

All upstream ARIS commands work as Synergy skills:

```
/research-pipeline "your research direction"
/idea-discovery "broad topic"
/auto-review-loop "scope"
/paper-writing "paper directory"
/rebuttal "paper/ + reviews" — venue: ICML, character limit: 5000
```

See the upstream [README.md](README.md) for the full command reference, workflow descriptions, and parameter documentation.

## DAG orchestration

The three main pipeline skills now include optional DAG sections. When you invoke them in Synergy, the executor can create a DAG to track progress and parallelize independent steps. This is transparent — if the executor doesn't create a DAG, the linear workflow still works identically.

## Compatibility

This fork maintains backward compatibility with Claude Code. The skills use `task()` patterns that Claude Code will simply treat as pseudocode comments (they're in markdown code blocks), while the actual workflow logic remains the same. Users running Claude Code can still use these skills — the `task()` blocks serve as documentation of the intended delegation pattern.
