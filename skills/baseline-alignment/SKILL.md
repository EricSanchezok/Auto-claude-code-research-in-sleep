---
name: baseline-alignment
description: "Verify experiment implementation correctness before full-scale deployment. Runs baseline first, confirms results match known numbers, then validates method results are in a plausible range. Blocks full deployment if baseline cannot be reproduced or method results are catastrophically low. Use after sanity check passes, before deploying the full experiment suite."
argument-hint: [experiment-plan-path-or-topic]
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob, Task
---

# Baseline Alignment: Pre-Deployment Correctness Gate

Verify experiment correctness for: **$ARGUMENTS**

## Why This Exists

LLM agents commonly produce experiment code with subtle bugs that pass sanity checks (no crashes, metrics computed, output files written) yet produce catastrophically wrong results — e.g., a method scoring 10% on a benchmark where the baseline is 60%. These bugs waste GPU hours because the full experiment suite deploys on broken code and the problem is only caught much later in `/auto-review-loop`.

This skill inserts a gate **between sanity check and full deployment** that verifies:

1. The baseline can be reproduced within a plausible range
2. The method's early results are not catastrophically below baseline (which indicates a code bug, not a weak algorithm)

## Constants

- **BASELINE_TOLERANCE = 0.10** — Allowed relative deviation from known baseline. If baseline is 60%, acceptable range is 54%–66% (60% × 0.90 to 60% × 1.10). Override via `$ARGUMENTS`.
- **CATASTROPHIC_THRESHOLD = 0.65** — If method result is below `baseline × CATASTROPHIC_THRESHOLD`, it is flagged as a likely code bug. If baseline is 60%, anything below 39% triggers the flag. Override via `$ARGUMENTS`.
- **MAX_DEBUG_ROUNDS = 4** — Maximum automatic debug attempts before stopping and reporting.
- **QUICK_RUN_OVERRIDE = false** — When `true`, run baseline alignment with reduced data/fewer steps for faster turnaround. Useful when compute is expensive.

> 💡 Override: `/baseline-alignment "topic" — baseline_tolerance: 0.15, catastrophic_threshold: 0.50, quick_run: true`

## When to Use

- After `/experiment-bridge` Phase 3 (sanity check) passes
- Before deploying the full experiment suite
- When a new experiment implementation has not been validated against known baselines
- **Skip when:** the experiment has no published baseline numbers to compare against, or the user explicitly confirms the code is trusted

## Inputs

1. **`refine-logs/EXPERIMENT_PLAN.md`** — contains baseline systems, expected metrics, and success criteria
2. **`refine-logs/EXPERIMENT_TRACKER.md`** — current run status
3. **Experiment code** — the implemented scripts
4. **Project `CLAUDE.md`** — GPU backend and server configuration

## Workflow

### Phase 1: Extract Reference Numbers

Read `EXPERIMENT_PLAN.md` and any cited papers/resources to extract:

1. **Baseline systems** and their **expected metric values** on each dataset/split
2. **The method's hypothesized performance range** (from claims or pilot results)
3. **Which datasets/splits are used** for the main comparison

If no baseline numbers are available from the plan:
- Search for published numbers in the dataset's official leaderboard or benchmark papers
- If still unavailable, ask the user for reference numbers — do not proceed without a reference point

Write the reference table to `refine-logs/BASELINE_REFERENCES.md`:

```markdown
# Baseline Reference Numbers

| System | Dataset | Split | Metric | Expected Value | Source |
|--------|---------|-------|--------|---------------|--------|
| Baseline A | WikiText-103 | test | PPL | 20.5 | Smith et al. 2025 |
| Baseline B | WikiText-103 | test | PPL | 22.1 | Jones et al. 2024 |
| Random | WikiText-103 | test | PPL | ~1000 | theoretical |
```

### Phase 2: Run Baseline Experiment

Run the **smallest, fastest baseline** from the plan using `/run-experiment` or `/parallel-experiment-engine`:

- Use a **single seed** (fastest configuration)
- Use the **same data pipeline** the method will use (same preprocessing, same splits)
- If `QUICK_RUN_OVERRIDE = true`: reduce data to 10% or use a subset, but keep the same eval split

Wait for the baseline to complete. Parse the result.

### Phase 3: Baseline Verification

Compare the baseline result against expected values:

```
Baseline Result Verification:
  System:    [baseline name]
  Dataset:   [dataset/split]
  Metric:    [metric name]
  Expected:  [value from reference]
  Observed:  [actual result]
  Deviation: [X%]

  Tolerance: ±[BASELINE_TOLERANCE × 100]%
  Verdict:   ✅ ALIGNED / ⚠️ MARGINAL / ❌ MISALIGNED
```

**Verdict rules:**

| Condition | Verdict | Action |
|-----------|---------|--------|
| `|observed - expected| / expected ≤ BASELINE_TOLERANCE` | ✅ ALIGNED | Proceed to Phase 4 |
| `BASELINE_TOLERANCE < deviation ≤ 2 × BASELINE_TOLERANCE` | ⚠️ MARGINAL | Log warning, proceed to Phase 4 with flag |
| `deviation > 2 × BASELINE_TOLERANCE` | ❌ MISALIGNED | Enter Phase 3.5 (debug) |

### Phase 3.5: Baseline Debug (on MISALIGNED)

When baseline results are far from expected, the implementation has a bug in the data pipeline, evaluation logic, or model loading. **Do not proceed to full deployment.**

**Common bug checklist** (check in order of likelihood):

1. **Data pipeline issues**
   - Wrong dataset split (train instead of test)
   - Incorrect preprocessing (normalization, tokenization mismatch)
   - Data leakage or anti-leakage (training samples in eval set, or vice versa)

2. **Evaluation logic bugs**
   - Wrong metric computation (accuracy vs error rate, PPL vs loss)
   - Ground truth source: using model predictions as GT instead of dataset labels
   - Averaging method wrong (micro vs macro, per-sample vs per-class)

3. **Model loading issues**
   - Loading wrong checkpoint or random initialization instead of pretrained weights
   - Wrong model config (hidden size, num layers mismatch)
   - Frozen vs trainable parameters misconfigured

4. **Training bugs** (if baseline requires training)
   - Learning rate too high/low
   - Loss function direction reversed (maximizing instead of minimizing)
   - Gradients not flowing (detached computation graph, stop_gradient in wrong place)
   - Optimizer not stepping or stepping twice

**Debug workflow:**

1. Read the baseline evaluation script line by line
2. Check each item on the checklist above
3. Fix the most likely issue
4. Re-run baseline with the fix
5. If still MISALIGNED after `MAX_DEBUG_ROUNDS` attempts, stop and report:

```markdown
# Baseline Alignment Failed

## Problem
Baseline [name] produced [observed] but expected [expected] (deviation: [X]%).

## Debug Attempts
1. [What was tried] → result: [still misaligned, new value]
2. [What was tried] → result: [still misaligned, new value]
3. [What was tried] → result: [still misaligned, new value]

## Likely Root Cause
[Best assessment of what's wrong]

## Recommendation
- [Specific action for the user to take]
- Do NOT deploy full experiments until baseline is aligned
```

### Phase 4: Method Sanity Check

Once baseline is ALIGNED (or MARGINAL with flag), run a **small-scale version of the method**:

- Same dataset/split as baseline
- Single seed
- If `QUICK_RUN_OVERRIDE = true`: same reduced data as baseline

Wait for completion. Compare against baseline:

```
Method Sanity Check:
  Method:    [method name]
  Dataset:   [dataset/split]
  Metric:    [metric name]
  Baseline:  [value]
  Method:    [value]
  Ratio:     [method / baseline]

  Catastrophic threshold: [CATASTROPHIC_THRESHOLD]
  Verdict:   ✅ PLAUSIBLE / ❌ CATASTROPHIC / ⚠️ BELOW_BASELINE
```

**Verdict rules:**

| Condition | Verdict | Action |
|-----------|---------|--------|
| `method ≥ baseline × CATASTROPHIC_THRESHOLD` | ✅ PLAUSIBLE | Proceed to full deployment |
| `method < baseline × CATASTROPHIC_THRESHOLD` | ❌ CATASTROPHIC | Enter Phase 4.5 (method debug) |
| `CATASTROPHIC_THRESHOLD ≤ ratio < 1.0` | ⚠️ BELOW_BASELINE | Log warning, proceed — method may just be weaker |

> The catastrophic check catches clear code bugs. A method at 10% vs a 60% baseline is almost certainly a bug (ratio = 0.17). A method at 55% vs 60% is plausibly just weaker — that's a research problem, not a code problem.

### Phase 4.5: Method Debug (on CATASTROPHIC)

Same debug workflow as Phase 3.5, but focused on method-specific bugs:

**Method-specific bug checklist:**

1. **Loss / objective**
   - Loss computed incorrectly (wrong reduction, wrong sign)
   - Loss not backpropagated (detached tensor, `.item()` before backward)
   - Multiple losses but only one has gradient

2. **Architecture**
   - Wrong layer dimensions (input/output mismatch)
   - Missing connections (residual skip broken)
   - Activations applied in wrong order

3. **Training loop**
   - Model in eval mode during training (dropout disabled, batch norm frozen)
   - Model in train mode during evaluation (dropout active, batch norm updating)
   - Optimizer not connected to correct parameters

4. **Data flow**
   - Input features not reaching the model (placeholder/dummy data)
   - Predictions not reaching the evaluation (discarded, overwritten)

Fix → re-run → check → repeat up to `MAX_DEBUG_ROUNDS`.

If still CATASTROPHIC after all debug rounds, stop and report with full diagnosis. **Do not deploy full experiments.**

### Phase 5: Write Gate Report

Write `refine-logs/BASELINE_ALIGNMENT.md`:

```markdown
# Baseline Alignment Report

**Date**: [today]
**Status**: ✅ PASSED / ⚠️ PASSED WITH FLAGS / ❌ BLOCKED

## Baseline Verification
| System | Dataset | Expected | Observed | Deviation | Verdict |
|--------|---------|----------|----------|-----------|---------|
| [name] | [split] | [val]    | [val]    | [X%]      | ✅/⚠️/❌ |

## Method Sanity Check
| Method | Dataset | Baseline | Method | Ratio | Verdict |
|--------|---------|----------|--------|-------|---------|
| [name] | [split] | [val]    | [val]  | [X%]  | ✅/⚠️/❌ |

## Flags (if any)
- [⚠️ Baseline marginally aligned: ...]
- [⚠️ Method below baseline: ...]

## Decision
- [✅ Cleared for full deployment]
- [❌ Blocked — see debug report above]
```

Also write `refine-logs/BASELINE_ALIGNMENT.json` for machine consumption:

```json
{
  "date": "2026-04-19",
  "status": "passed",
  "baseline_checks": [
    {
      "system": "Baseline A",
      "dataset": "WikiText-103",
      "metric": "PPL",
      "expected": 20.5,
      "observed": 21.2,
      "deviation_pct": 3.4,
      "verdict": "aligned"
    }
  ],
  "method_check": {
    "method": "Our Method",
    "dataset": "WikiText-103",
    "metric": "PPL",
    "baseline_value": 21.2,
    "method_value": 19.8,
    "ratio": 0.934,
    "verdict": "plausible"
  },
  "flags": []
}
```

### Phase 6: Gate Decision

Present the gate result:

```
🔬 Baseline Alignment Gate

  Baseline:  ✅ [system] = [value] (expected [value], deviation [X%])
  Method:    ✅ [method] = [value] (baseline ratio [X%])

  Gate: ✅ OPEN — cleared for full deployment

  Report: refine-logs/BASELINE_ALIGNMENT.md
```

Or on failure:

```
🔬 Baseline Alignment Gate

  Baseline:  ❌ [system] = [value] (expected [value], deviation [X%])
  Method:    — (blocked by baseline failure)

  Gate: ❌ BLOCKED — fix bugs before deploying full experiments
  Debug attempts: [N]/[MAX_DEBUG_ROUNDS]

  See: refine-logs/BASELINE_ALIGNMENT.md
```

## Integration with Other Skills

### Called by `/experiment-bridge` (Phase 3.5)

```
/experiment-bridge
  Phase 2:  Implement code
  Phase 2.5: Code review
  Phase 3:  Sanity check (no crash)
  Phase 3.5: /baseline-alignment  ← NEW
  Phase 4:  Full deployment (only if gate OPEN)
```

### Read by `/auto-review-loop`

```
if refine-logs/BASELINE_ALIGNMENT.json exists:
    read status field
    if status == "blocked":
        skip review — experiments were never deployed
    if status == "passed_with_flags":
        note flags in review context
```

### Read by `/experiment-audit`

```
if refine-logs/BASELINE_ALIGNMENT.json exists AND status != "passed":
    add to audit report: "Baseline alignment gate was not passed"
```

## Key Rules

- **Never skip this gate for new implementations.** If the code has never been validated against a known baseline, running full experiments is a gamble with GPU time.
- **Catastrophic results are code bugs until proven otherwise.** A method at 10% on a 60% baseline is not "a weak method" — it's almost certainly a bug. Debug first, conclude later.
- **Baseline alignment is about the pipeline, not the algorithm.** We are verifying that data loading, evaluation, and training logic work correctly. We are NOT verifying that the method is good.
- **Report honestly.** If baseline cannot be reproduced, say so. If the method is just weak (55% vs 60%), that's fine — flag it but don't block.
- **Respect the debug budget.** After `MAX_DEBUG_ROUNDS` failed attempts, stop and report. Let the user take over rather than burning more compute on guesswork.
- **No fabrication.** Do not adjust thresholds to make results "pass". If the baseline is off by 20%, the right answer is to fix the bug, not widen the tolerance.
