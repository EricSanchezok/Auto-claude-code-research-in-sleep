# Reviewer Routing

## Default

All review calls use the **reviewer** agent via `task(subagent_type="reviewer")`.

This is the default for ALL skills. No parameter or config changes this.

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
    → Use task(subagent_type="reviewer") with the standard prompt
    → This is the DEFAULT.

If `— reviewer: auditor`:
    → Use task(subagent_type="auditor") for integrity-focused review
    → The auditor reads code, result files, and logs independently
    → Best for nightmare difficulty or experiment verification
```

## Task Category

All reviewer and auditor task calls should use `category: "most-capable"` to ensure maximum reasoning depth. This is the Synergy equivalent of the upstream `reasoning_effort: xhigh` setting.

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

For auditor tasks (experiment integrity, code verification):

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

The `category` parameter is a hard invariant — reviewer quality is non-negotiable. See `effort-contract.md` for the full effort system.

## Invariants

- Reviewer independence protocol still applies (pass file paths, not summaries)
- `difficulty` controls how adversarial the review is, not which backend to use
- For nightmare difficulty, dispatch both `reviewer` and `auditor` agents for maximum coverage
- `beast` mode may recommend auditor verification but never requires it
