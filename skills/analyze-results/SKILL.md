---
name: analyze-results
description: Analyze ML experiment results, compute statistics, generate comparison tables and insights. Use when user says "analyze results", "compare", or needs to interpret experimental data.
argument-hint: [results-path-or-description]
allowed-tools: Bash(*), Read, Grep, Glob, Write, Edit, Task
---

# Analyze Experiment Results

Analyze: $ARGUMENTS

## Workflow

### Step 1: Locate Results
Find all relevant JSON/CSV result files:
- Check `figures/`, `results/`, or project-specific output directories
- Parse JSON results into structured data

### Step 2: Build Comparison Table
Organize results by:
- **Independent variables**: model type, hyperparameters, data config
- **Dependent variables**: primary metric (e.g., perplexity, accuracy, loss), secondary metrics
- **Delta vs baseline**: always compute relative improvement

### Step 3: Statistical Analysis

#### 3a: Descriptive Statistics
- If multiple seeds: report mean ± std, check reproducibility
- If sweeping a parameter: identify trends (monotonic, U-shaped, plateau)
- Flag outliers or suspicious results

#### 3b: Statistical Significance Testing

For **every method-vs-baseline comparison** in the results table, compute a statistical test. This is mandatory — raw delta without significance is meaningless.

| Condition | Test | Output |
|-----------|------|--------|
| ≥3 seeds per method | Paired t-test (same seed → paired) or Wilcoxon signed-rank (non-normal) | p-value, Cohen's d |
| 1-2 seeds | Bootstrap confidence interval (resample predictions, 1000 iterations) | 95% CI, whether CI includes 0 |
| Single run, no seed variance | Report as `inconclusive` — no significance claim possible | N/A |

**Implementation** — generate and run a Python script:

```python
import json, numpy as np
from scipy import stats

results = json.load(open("results.json"))
baseline_scores = [r["metric"] for r in results if r["system"] == "baseline"]
method_scores = [r["metric"] for r in results if r["system"] == "method"]

if len(baseline_scores) >= 3 and len(method_scores) >= 3:
    t_stat, p_value = stats.ttest_rel(method_scores, baseline_scores)
    diff = np.array(method_scores) - np.array(baseline_scores)
    cohens_d = diff.mean() / diff.std() if diff.std() > 0 else float('inf')
    print(f"p={p_value:.4f}, Cohen's d={cohens_d:.2f}")
else:
    # Bootstrap
    diffs = []
    for _ in range(1000):
        idx = np.random.choice(len(method_scores), len(method_scores), replace=True)
        diffs.append(np.mean(np.array(method_scores)[idx]) - np.mean(np.array(baseline_scores)[idx]))
    ci_low, ci_high = np.percentile(diffs, [2.5, 97.5])
    print(f"95% CI: [{ci_low:.4f}, {ci_high:.4f}]")
```

#### 3c: Significance Annotation

Add significance columns to every comparison table:

```
| Method | Metric | Mean ± Std | Δ vs Baseline | p-value | Effect Size | Significant |
|--------|--------|-----------|---------------|---------|-------------|-------------|
| Ours   | Acc    | 61.2±0.3  | +0.4%         | 0.38    | d=0.12      | ❌ No       |
| Ours   | F1     | 58.7±0.5  | +2.1%         | 0.003   | d=0.82      | ✅ Yes      |
```

**Significance rules:**
- p < 0.05 AND effect size ≥ small (d ≥ 0.2): `✅ Significant`
- p < 0.05 AND effect size < small: `⚠️ Marginal` (statistically significant but trivial)
- p ≥ 0.05: `❌ Not significant`
- Single seed, no variance data: `❓ Inconclusive`

> A method that improves by 0.4% with p=0.38 is NOT better than baseline. Do not report it as an improvement. Report it as "comparable" or "within noise".

### Step 4: Generate Insights
For each finding, structure as:
1. **Observation**: what the data shows (with numbers)
2. **Interpretation**: why this might be happening
3. **Implication**: what this means for the research question
4. **Next step**: what experiment would test the interpretation

### Step 5: Update Documentation
If findings are significant:
- Propose updates to project notes or experiment reports
- Draft a concise finding statement (1-2 sentences)

## Output Format
Always include:
1. Raw data table
2. Key findings (numbered, concise)
3. Suggested next experiments (if any)
