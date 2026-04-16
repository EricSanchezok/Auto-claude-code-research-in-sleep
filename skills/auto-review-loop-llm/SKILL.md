---
name: auto-review-loop-llm
description: Autonomous research review loop using any OpenAI-compatible LLM API. Configure via llm-chat MCP server or environment variables. Trigger with "auto review loop llm" or "llm review".
argument-hint: [topic-or-scope]
allowed-tools: Bash(*), Read, Grep, Glob, Write, Edit, Skill, Task
---

# Auto Review Loop (Generic LLM): Autonomous Research Improvement

Autonomously iterate: review → implement fixes → re-review, until the external reviewer gives a positive assessment or MAX_ROUNDS is reached.

## Context: $ARGUMENTS

## Constants

- MAX_ROUNDS = 4
- POSITIVE_THRESHOLD: score >= 6/10, or verdict contains "accept", "sufficient", "ready for submission"
- REVIEW_DOC: `review-stage/AUTO_REVIEW.md` (cumulative log) *(fall back to `./AUTO_REVIEW.md` for legacy projects)*

## LLM Configuration

This skill uses **any OpenAI-compatible API** for external review via the `llm-chat` MCP server.

### Configuration via MCP Server (Recommended)

Configure the `llm-chat` MCP server with the following environment variables:

```json
{
  "llm-chat": {
    "command": "/usr/bin/python3",
    "args": ["path/to/mcp-servers/llm-chat/server.py"],
    "env": {
      "LLM_API_KEY": "your-api-key",
      "LLM_BASE_URL": "https://api.deepseek.com/v1",
      "LLM_MODEL": "deepseek-chat"
    }
  }
}
```

### Supported Providers

| Provider | LLM_BASE_URL | LLM_MODEL |
|----------|--------------|-----------|
| **OpenAI** | `https://api.openai.com/v1` | `gpt-4o`, `o3` |
| **DeepSeek** | `https://api.deepseek.com/v1` | `deepseek-chat`, `deepseek-reasoner` |
| **MiniMax** | `https://api.minimax.io/v1` | `MiniMax-M2.7` |
| **Kimi (Moonshot)** | `https://api.moonshot.cn/v1` | `moonshot-v1-8k`, `moonshot-v1-32k` |
| **ZhiPu (GLM)** | `https://open.bigmodel.cn/api/paas/v4` | `glm-4`, `glm-4-plus` |
| **SiliconFlow** | `https://api.siliconflow.cn/v1` | `Qwen/Qwen2.5-72B-Instruct` |
| **阿里云百炼** | `https://dashscope.aliyuncs.com/compatible-mode/v1` | `qwen-max` |
| **零一万物** | `https://api.lingyiwanwu.com/v1` | `yi-large` |

## API Call Method

**Primary: MCP Tool**

```
mcp__llm-chat__chat:
  prompt: |
    [Review prompt content]
  model: "deepseek-chat"
  system: "You are a senior ML reviewer..."
```

**Fallback: curl**

```bash
curl -s "${LLM_BASE_URL}/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LLM_API_KEY}" \
  -d '{
    "model": "${LLM_MODEL}",
    "messages": [
      {"role": "system", "content": "You are a senior ML reviewer..."},
      {"role": "user", "content": "[review prompt]"}
    ],
    "max_tokens": 4096
  }'
```

## DAG Orchestration

The review loop is a repeating subgraph where each round is a linear chain of phases, with potential parallelism inside Phase C.

```
┌─────────────────────────── Loop: round_1 .. round_N ───────────────────────────┐
│                                                                                 │
│  ┌──────────┐    ┌──────────┐    ┌──────────────┐    ┌──────┐    ┌──────────┐  │
│  │ Phase A  │───▶│ Phase B  │───▶│   Phase C    │───▶│Phase │───▶│ Phase E  │  │
│  │ Review   │    │ Parse    │    │  Implement   │    │  D   │    │ Document │  │
│  │ (LLM)    │    │Assessment│    │   Fixes      │    │Wait  │    │ Round    │  │
│  └──────────┘    └──────────┘    └──────────────┘    └──────┘    └──────────┘  │
│                                        │                                        │
│                          ┌─────────────┼─────────────┐                          │
│                          ▼             ▼             ▼                          │
│                    ┌──────────┐  ┌──────────┐  ┌──────────┐                     │
│                    │ Fix #1   │  │ Fix #2   │  │ Fix #3   │  (parallelizable)   │
│                    │(indep.)  │  │(indep.)  │  │(indep.)  │                     │
│                    └────┬─────┘  └────┬─────┘  └────┬─────┘                     │
│                         └─────────────┼─────────────┘                          │
│                                       ▼                                        │
│                                 (join / sync)                                  │
│                                                                                 │
└─────────────────────────────────────────────────────────────────────────────────┘

round_N ──▶ [if score < 6 or verdict ≠ ready] ──▶ round_N+1
         ──▶ [if score ≥ 6 and verdict = ready] ──▶ Termination
```

- **Phase A → B**: strictly sequential (B depends on A's output)
- **Phase C**: independent fixes within the same round can run in parallel; fixes with dependencies (e.g., "add metric" before "re-run ablation") must be ordered
- **Phase C → D**: sequential (D waits for all C fixes to complete or launch)
- **Phase D → E**: sequential (E needs D's results)
- **Round boundary**: E writes `REVIEW_STATE.json`, then B's stop-check gates the next round

> **Note**: Without DAG support, the linear workflow below still works identically — phases execute sequentially within each round.

## State Persistence (Compact Recovery)

Persist state to `review-stage/REVIEW_STATE.json` after each round:

```json
{
  "round": 2,
  "status": "in_progress",
  "last_score": 5.0,
  "last_verdict": "not ready",
  "pending_experiments": [],
  "timestamp": "2026-03-15T10:00:00"
}
```

**Write this file at the end of every Phase E** (after documenting the round).

**On completion**, set `"status": "completed"`.

## Workflow

### Initialization

1. **Check `review-stage/REVIEW_STATE.json`** for recovery *(fall back to `./REVIEW_STATE.json` if not found — legacy path)*
2. Read project context and prior reviews
3. Initialize round counter

### Loop (up to MAX_ROUNDS)

#### Phase A: Review

**If MCP available:**
```
mcp__llm-chat__chat:
  system: "You are a senior ML reviewer (NeurIPS/ICML level)."
  prompt: |
    [Round N/MAX_ROUNDS of autonomous review loop]

    [Full research context: claims, methods, results, known weaknesses]
    [Changes since last round, if any]

    1. Score this work 1-10 for a top venue
    2. List remaining critical weaknesses (ranked by severity)
    3. For each weakness, specify the MINIMUM fix
    4. State clearly: is this READY for submission? Yes/No/Almost

    Be brutally honest. If the work is ready, say so clearly.
```

**If MCP NOT available:**
```bash
curl -s "${LLM_BASE_URL}/chat/completions" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${LLM_API_KEY}" \
  -d '{
    "model": "${LLM_MODEL}",
    "messages": [
      {"role": "system", "content": "You are a senior ML reviewer (NeurIPS/ICML level)."},
      {"role": "user", "content": "[Full review prompt]"}
    ],
    "max_tokens": 4096
  }'
```

#### Phase B: Parse Assessment

**CRITICAL: Save the FULL raw response** verbatim. Then extract:
- **Score** (numeric 1-10)
- **Verdict** ("ready" / "almost" / "not ready")
- **Action items** (ranked list of fixes)

**STOP**: If score >= 6 AND verdict contains "ready/almost"

#### Phase C: Implement Fixes

Priority: metric additions > reframing > new experiments

#### Phase D: Wait for Results

Monitor remote experiments

#### Phase E: Document Round

Append to `review-stage/AUTO_REVIEW.md`:

```markdown
## Round N (timestamp)

### Assessment (Summary)
- Score: X/10
- Verdict: [ready/almost/not ready]
- Key criticisms: [bullet list]

### Reviewer Raw Response

<details>
<summary>Click to expand full reviewer response</summary>

[Paste the COMPLETE raw response here — verbatim, unedited.]

</details>

### Actions Taken
- [what was implemented/changed]

### Results
- [experiment outcomes, if any]

### Status
- [continuing to round N+1 / stopping]
```

**Write `review-stage/REVIEW_STATE.json`** with current state.

### Termination

1. Set `review-stage/REVIEW_STATE.json` status to "completed"
2. Write final summary

## Agenda Integration

The review loop can take hours across multiple rounds. Use agenda items for automated monitoring and continuation instead of manual polling.

### Phase D: Watch Triggers for Experiment Results

When Phase D launches long-running experiments, set a watch trigger to detect result readiness. Choose the pattern that matches your platform:

**Local results (file watch):**
```
triggers:
  - type: "watch"
    watch:
      kind: "file"
      glob: "results/**/metrics.json"
      event: "add"
```

**Remote GPU server (SSH poll, requires passwordless login):**
```
triggers:
  - type: "watch"
    watch:
      kind: "poll"
      command: "ssh <server> 'ls /path/to/results/final_metrics.json 2>/dev/null && echo DONE || echo PENDING'"
      interval: "5m"
      trigger: "match"
      match: "DONE"
```

**启智平台 (qzcli poll):**
```
triggers:
  - type: "watch"
    watch:
      kind: "poll"
      command: "qzcli qz_list_jobs --running-only 2>/dev/null | grep <job-name> || echo DONE"
      interval: "5m"
      trigger: "match"
      match: "DONE"
```

Full example using local file watch:

```
agenda_create:
  title: "Watch experiment results for review loop"
  triggers:
    - type: "watch"
      watch:
        kind: "file"
        glob: "results/**/metrics.json"
        event: "add"
  workDirectory: "<current project directory>"
  delivery: "auto"
  sessionRefs:
    - sessionID: "<current-session-id>"
      hint: "Review loop in progress — check REVIEW_STATE.json for round context"
  prompt: |
    An experiment result file was created. Check review-stage/REVIEW_STATE.json
    for current loop state. If Phase D is active and results are ready,
    use session_send to continue the loop:
      session_send(target: "<session-ID>", role: "user",
        content: "Experiment results are ready. Continue review loop — proceed to Phase E.")
```

### Long Loop Monitoring

For the full loop (up to 4 rounds), create a periodic check that inspects `REVIEW_STATE.json`:

```
agenda_create:
  title: "Monitor review loop progress"
  triggers:
    - type: "every"
      interval: "30m"
  workDirectory: "<current project directory>"
  delivery: "auto"
  sessionRefs:
    - sessionID: "<current-session-id>"
      hint: "Active review loop — this session contains the full loop context"
  prompt: |
    Check review-stage/REVIEW_STATE.json. Report status:
    - If status is "completed": loop finished, no action needed.
    - If status is "in_progress" and last timestamp is > 2h old:
      the loop may be stalled. Use session_send to wake the session:
        session_send(target: "<session-ID>", role: "user",
          content: "Review loop appears stalled. Check REVIEW_STATE.json and continue from last checkpoint.")
    - Otherwise: loop is progressing, no action needed.
```

### Key Config Details

| Field | Value | Reason |
|-------|-------|--------|
| `workDirectory` | Current project dir | Correct scope for file access |
| `delivery` | `"auto"` | Sends results back to originating conversation |
| `sessionRefs` | Current session ID + hint | Provides loop context to the triggered agent |

**Important**: `delivery: "auto"` delivers as **assistant** role, which does **not** wake the session's agent. To trigger automated continuation, use `session_send(target: "<session-ID>", role: "user", content: "...")` inside the agenda prompt. A user-role message wakes the target session's agent, enabling hands-free loop continuation.

## Key Rules

- **Large file handling**: If the Write tool fails due to file size, immediately retry using Bash (`cat << 'EOF' > file`) to write in chunks. Do NOT ask the user for permission — just do it silently.

- **Anti-hallucination citations**: When adding references, NEVER fabricate BibTeX. Use DBLP → CrossRef → `[VERIFY]` chain. Do NOT generate BibTeX from memory.
- Be honest about weaknesses
- Implement fixes BEFORE re-reviewing
- Document everything
- Include previous context in round 2+ prompts
- Prefer MCP tool over curl when available

## Prompt Template for Round 2+

```
mcp__llm-chat__chat:
  system: "You are a senior ML reviewer (NeurIPS/ICML level)."
  prompt: |
    [Round N/MAX_ROUNDS of autonomous review loop]

    ## Previous Review Summary (Round N-1)
    - Previous Score: X/10
    - Previous Verdict: [ready/almost/not ready]
    - Previous Key Weaknesses: [list]

    ## Changes Since Last Review
    1. [Action 1]: [result]
    2. [Action 2]: [result]

    ## Updated Results
    [paste updated metrics/tables]

    Please re-score and re-assess:
    1. Score this work 1-10 for a top venue
    2. List remaining critical weaknesses (ranked by severity)
    3. For each weakness, specify the MINIMUM fix
    4. State clearly: is this READY for submission? Yes/No/Almost

    Be brutally honest. If the work is ready, say so clearly.
```

## Output Protocols

> Follow these shared protocols for all output files:
> - **[Output Versioning Protocol](../shared-references/output-versioning.md)** — write timestamped file first, then copy to fixed name
> - **[Output Manifest Protocol](../shared-references/output-manifest.md)** — log every output to MANIFEST.md
> - **[Output Language Protocol](../shared-references/output-language.md)** — respect the project's language setting
