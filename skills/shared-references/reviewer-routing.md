# Agent Routing

## Agent Selection

ARIS skills delegate to different Synergy agents based on the task role:

| Task role | subagent_type | category | When to use |
|-----------|--------------|----------|-------------|
| Adversarial scientific critique | `reviewer` | `most-capable` | Score 1-10, find weaknesses, accept/reject, patent examiner |
| Experiment integrity audit | `auditor` | `most-capable` | Cross-verify numbers, catch fabrication, code audit |
| Literature / SOTA analysis | `scholar` | `general` | Paper search, novelty assessment, idea evaluation |
| Writing quality / prose | `scribe` | `writing` | Narrative structure, clarity, style polish |
| Code / implementation | `master` | `general` | LaTeX debugging, script fixes, implementation |

**Default**: When in doubt, use `reviewer` with `category="most-capable"`.

## Difficulty Levels

The `reviewer` agent supports three difficulty levels, passed as context in the task prompt:

| Level | Behavior |
|-------|----------|
| `medium` (default) | Standard review based on provided file paths. Reviewer reads files and judges independently. |
| `hard` | Adds **Reviewer Memory** (reviewer tracks suspicions across rounds via `REVIEWER_MEMORY.md`) + **Debate Protocol** (executor can rebut, reviewer rules). |
| `nightmare` | Everything in `hard` + reviewer gets full repo access + **Adversarial Verification** (reviewer independently checks if code matches claims). Use the `auditor` agent for the verification step. |

## Routing Logic

```
Parse $ARGUMENTS for `— reviewer:` directive.

If not specified:
    → Use task(subagent_type="reviewer", category="most-capable") with the standard prompt
    → This is the DEFAULT.

If `— reviewer: auditor`:
    → Use task(subagent_type="auditor", category="most-capable") for integrity-focused review
    → The auditor reads code, result files, and logs independently
    → Best for nightmare difficulty or experiment verification
```

## Task Call Formats

### Reviewer (adversarial critique)

```
task(
  subagent_type="reviewer",
  category="most-capable",
  prompt="""
    [role + difficulty level + round context]

    Files to read:
    - /absolute/path/to/file1
    - /absolute/path/to/file2

    [review instructions + output format]
  """
)
```

### Auditor (integrity verification)

```
task(
  subagent_type="auditor",
  category="most-capable",
  prompt="""
    Audit the experiment integrity for this project.

    Project directory: /absolute/path/to/project
    Claims document: /absolute/path/to/NARRATIVE_REPORT.md
    Results directory: /absolute/path/to/results/

    [audit instructions]
  """
)
```

### Scholar (literature / SOTA)

```
task(
  subagent_type="scholar",
  category="general",
  prompt="""
    Search for related work on [topic].

    Focus on: [specific aspect]
    Exclude: [known work to skip]

    For each paper found, provide: title, authors, year, key contribution, relevance.
  """
)
```

### Scribe (writing quality)

```
task(
  subagent_type="scribe",
  category="writing",
  prompt="""
    Review the writing quality of this paper section.

    Files to read:
    - /absolute/path/to/section.tex

    Focus on: clarity, narrative flow, active voice, redundancy.
  """
)
```

The `category` parameter for reviewer/auditor is a hard invariant — reviewer quality is non-negotiable. Scholar and scribe use lower categories since they don't need adversarial reasoning. See `effort-contract.md` for the full effort system.

## Invariants

- Reviewer independence protocol still applies (pass file paths, not summaries)
- `difficulty` controls how adversarial the review is, not which agent to use
- For nightmare difficulty, dispatch both `reviewer` and `auditor` agents for maximum coverage
- `beast` mode may recommend auditor verification but never requires it
