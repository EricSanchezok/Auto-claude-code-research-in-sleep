---
name: meta-optimize
description: "Analyze ARIS usage logs and propose optimizations to SKILL.md files, default parameters, and convergence rules. Self-improving outer loop for the ARIS harness. Use when user says \"优化技能\", \"meta optimize\", \"improve skills\", \"分析使用记录\", or wants to optimize ARIS's own skills based on accumulated experience."
argument-hint: [target-skill-or-all]
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob, LlmReview
---

# Meta-Optimize: Outer-Loop Harness Optimization for ARIS-Code

Analyze accumulated usage logs and propose optimizations for: **$ARGUMENTS**

## What This Skill Optimizes

| Component | Example | Optimizable? |
|-----------|---------|:---:|
| SKILL.md prompts | Reviewer instructions, quality gates, step descriptions | Yes |
| Default parameters | `difficulty: medium`, `MAX_ROUNDS: 4`, `threshold: 6/10` | Yes |
| Convergence rules | When to stop the review loop, retry counts | Yes |
| Workflow ordering | Skill chain sequence within a workflow | Yes |

**Not optimized**: Research artifacts (papers, code, experiments) — that's what the regular workflows do.

## Prerequisites

1. **Logging must be active.** Set `meta_logging` to `metadata` or `content` in `~/.config/aris/config.json`, or set `ARIS_META_LOGGING=metadata` environment variable.
2. **Sufficient data.** At least 5 skill invocations logged in `~/.config/aris/meta/events.jsonl`.

## CRITICAL SAFETY RULES

**You MUST NOT use `write_file` or `edit_file` to write SKILL.md files directly.**

Instead, you MUST output proposals as structured JSON and save them to `~/.config/aris/meta/proposals/`. The user then uses `/meta-optimize apply N` (implemented in Rust with path validation) to safely apply changes.

**Proposal format** — write to `~/.config/aris/meta/proposals/proposal_N.json`:

```json
{
  "id": 1,
  "target_skill": "auto-review-loop",
  "description": "Raise default score threshold from 6 to 7",
  "rationale": "60% of users override to 7+ based on usage logs",
  "reviewer_score": null,
  "reviewer_notes": null,
  "new_content": "... full new SKILL.md content ...",
  "original_hash": "sha256 of current SKILL.md",
  "created_at": "2026-04-05T12:00:00Z",
  "status": "pending"
}
```

## Workflow

### Step 0: Check Data Availability

Read `~/.config/aris/meta/events.jsonl` and count events:

```bash
EVENTS_FILE="$HOME/.config/aris/meta/events.jsonl"
if [ ! -f "$EVENTS_FILE" ]; then
    echo "No event log found. Enable logging: set ARIS_META_LOGGING=metadata"
    exit 0
fi
wc -l < "$EVENTS_FILE"
grep -c '"skill_invoke"' "$EVENTS_FILE" || echo 0
```

If fewer than 5 skill invocations, inform the user and stop.

### Step 1: Analyze Usage Patterns

Read the event log and compute:

- **Frequency**: Which skills are invoked most? Which slash commands?
- **Failures**: Which tools fail most often? In which skills? Error patterns?
- **Parameter overrides**: What do users override most? (Bad defaults.)
- **Convergence** (for review loops): Average rounds, score trajectories, plateaus?
- **Human intervention**: Where do users interrupt with manual corrections?

Present findings as a structured summary table.

### Step 2: Identify Optimization Targets

Rank optimization opportunities by expected impact:

```markdown
| # | Target Skill | Signal | Proposed Change | Expected Impact |
|---|-------------|--------|-----------------|-----------------|
| 1 | auto-review-loop | Users override threshold 60% | Raise default 6→7 | Fewer overrides |
| 2 | experiment-bridge | 40% OOM failures | Add batch size fallback | Fewer failures |
```

If `$ARGUMENTS` specifies a target skill, focus on that skill only.

### Step 3: Generate Proposals

For each optimization target:

1. Read the current SKILL.md (from bundled or user skills)
2. Compute SHA-256 hash of current content
3. Generate the modified SKILL.md content
4. Create a proposal JSON file

**Rules:**
- One proposal per optimization target
- Each proposal MUST include data-backed rationale from the event log
- Minimal changes — don't rewrite entire skills
- Never change MCP/bridge config

### Step 4: Cross-Model Review

Send each proposal to the reviewer via `LlmReview`:

```
LlmReview:
  prompt: |
    You are reviewing a proposed optimization to an ARIS SKILL.md file.

    ## Original Skill (relevant section)
    [paste original]

    ## Proposed Changes
    [describe the diff]

    ## Evidence from Usage Log
    [paste summary stats]

    Review this patch:
    1. Does the evidence support the change?
    2. Could this change hurt other use cases?
    3. Is the change minimal and safe?
    4. Score 1-10: should this be applied?
```

Update the proposal with `reviewer_score` and `reviewer_notes`.

### Step 5: Present Results

Output a structured report:

```markdown
# ARIS Meta-Optimization Report

**Date**: [today]
**Data**: [N] events, [M] skill invocations

## Proposed Changes

### Proposal #1: [title]
- **Target**: /[skill-name]
- **Signal**: [what the data shows]
- **Reviewer Score**: [X/10]
- **Status**: ✅ Recommended / ⚠️ Needs more data / ❌ Rejected

## How to Apply

Run `/meta-optimize apply 1` to apply a specific change.
Run `/meta-optimize status` to see all proposals.
```

## Key Rules

- **Log-driven, not speculative.** Every change must cite data from the event log.
- **Minimal patches.** Change one thing at a time.
- **Reviewer-gated.** Every proposal goes through LlmReview.
- **Never auto-apply.** Only `/meta-optimize apply N` (Rust code) writes to disk.
- **Honest about uncertainty.** If data is insufficient, say so.
- **NEVER use write_file/edit_file on SKILL.md files.** Only write proposal JSON files.
