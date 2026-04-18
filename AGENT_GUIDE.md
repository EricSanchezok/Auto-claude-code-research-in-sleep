# ARIS Agent Guide

> **For AI agents reading this repo.** If you are a human, see [README.md](README.md).

ARIS is a research harness: composable Markdown skills that orchestrate the ML research lifecycle through cross-model adversarial collaboration.

## How to Invoke Skills

**Claude Code / Cursor / Trae:**
```
/skill-name "arguments" — key: value, key2: value2
```

**Codex CLI:**
```
/skill-name "arguments" — key: value
```
Codex skills are in `skills/skills-codex/`.

## Common Parameters

Every skill accepts:
```
— effort: lite | balanced | max | beast      # work intensity (default: balanced)
— human checkpoint: true | false             # pause for approval (default: false)
— AUTO_PROCEED: true | false                 # auto-continue at gates (default: true)
```

Workflow-specific:
```
— difficulty: medium | hard | nightmare      # reviewer adversarial level
— venue: ICLR | NeurIPS | ICML | ...        # target venue
— sources: web, zotero, deepxiv, ...        # literature sources
— gpu: local | remote | vast | modal | qzcli  # compute backend
— baseline_alignment: true | false           # verify results before full deploy (default: true)
— parallel_deploy: true | false              # parallel experiment scheduling (default: true)
— baseline_tolerance: 0.15                   # allowed baseline deviation (default: 15%)
— catastrophic_threshold: 0.50               # method < baseline × this → likely bug (default: 0.50)
```

Parameters pass through workflow chains automatically.

## Workflow Index

### Full Pipeline
```
/research-pipeline "direction" → W1 → W1.5 → W1.6 → W1.7 → W2 → W3
```

### Individual Workflows

| Workflow | Invoke | Input | Output | When to use |
|----------|--------|-------|--------|-------------|
| W1: Idea Discovery | `/idea-discovery "direction"` | research direction | IDEA_REPORT.md, EXPERIMENT_PLAN.md | Starting new research |
| W1.5: Experiment Bridge | `/experiment-bridge` | EXPERIMENT_PLAN.md | running code, EXPERIMENT_LOG.md | Have a plan, need to implement |
| W1.6: Baseline Alignment | `/baseline-alignment` | EXPERIMENT_PLAN.md | BASELINE_ALIGNMENT.md | Verify results plausible before full deploy |
| W1.7: Parallel Deploy | `/parallel-experiment-engine` | EXPERIMENT_PLAN.md | PARALLEL_PLAN.md | Multi-backend parallel experiment scheduling |
| W2: Auto Review | `/auto-review-loop "scope"` | paper + results | improved paper | Iterative improvement |
| W3: Paper Writing | `/paper-writing "NARRATIVE_REPORT.md"` | narrative report | paper/main.pdf | Ready to write |
| W4: Rebuttal | `/rebuttal "paper/ + reviews"` | paper + reviews | PASTE_READY.txt | Reviews received |

### Standalone Skills

| Skill | Invoke | What it does |
|-------|--------|-------------|
| `/alphaxiv "arxiv-id"` | Paper lookup | LLM-optimized summary with tiered fallback |
| `/research-lit "topic"` | Literature survey | Finds papers, builds landscape |
| `/idea-creator "direction"` | Idea generation | Brainstorms and ranks ideas |
| `/novelty-check "idea"` | Novelty verification | Checks against existing work |
| `/research-review "draft"` | External review | GPT-5.4 xhigh deep critique |
| `/experiment-audit` | Integrity check | Cross-model audit of eval code |
| `/baseline-alignment` | Baseline alignment | Verify results plausible before full deployment |
| `/parallel-experiment-engine` | Parallel deployment | Multi-backend parallel experiment scheduling |
| `/result-to-claim` | Verdict judgment | Codex judges if claims are supported |
| `/paper-plan "topic"` | Outline creation | Structured outline + claims matrix |
| `/paper-figure "plan"` | Figure generation | Plots from experiment data |
| `/paper-write "plan"` | LaTeX drafting | Section-by-section with citation check |
| `/paper-compile "paper/"` | PDF compilation | Multi-pass with auto-repair |
| `/research-wiki init` | Knowledge base | Persistent project memory |
| `/meta-optimize` | Self-improvement | Analyze usage, propose skill edits |
| `/analyze-results` | Result analysis | Statistics and comparison tables |
| `/ablation-planner` | Ablation design | Reviewer-perspective ablations |

## Artifact Contracts

Skills communicate through plain-text files:

| Artifact | Created by | Consumed by |
|----------|-----------|-------------|
| `IDEA_REPORT.md` | idea-discovery | experiment-bridge |
| `EXPERIMENT_PLAN.md` | experiment-plan | experiment-bridge |
| `EXPERIMENT_LOG.md` | experiment-bridge | auto-review-loop, result-to-claim |
| `NARRATIVE_REPORT.md` | auto-review-loop | paper-writing |
| `paper/main.tex` | paper-write | paper-compile |
| `paper/main.pdf` | paper-compile | auto-paper-improvement-loop |
| `EXPERIMENT_AUDIT.md` | experiment-audit | result-to-claim |
| `EXPERIMENT_AUDIT.json` | experiment-audit | result-to-claim (machine-readable) |
| `BASELINE_ALIGNMENT.md` | baseline-alignment | auto-review-loop, experiment-audit |
| `BASELINE_ALIGNMENT.json` | baseline-alignment | auto-review-loop (machine-readable) |
| `PARALLEL_PLAN.md` | parallel-experiment-engine | monitor-experiment |
| `research-wiki/` | research-wiki | idea-creator, research-lit, result-to-claim |
| `.aris/meta/events.jsonl` | hooks (passive) | meta-optimize |

## Cross-Model Protocol

- **Executor** (Claude/Codex): writes code, runs experiments, drafts papers
- **Reviewer** (GPT-5.4/Gemini/GLM): critiques, scores, demands revisions
- **Rule**: executor and reviewer must be different model families
- **Reviewer independence**: pass file paths only, never summaries or interpretations
- **Experiment integrity**: executor must NOT judge its own eval code — reviewer audits directly

## Shared References

Read these before invoking review-related skills:
- `skills/shared-references/reviewer-independence.md` — cross-model review protocol
- `skills/shared-references/experiment-integrity.md` — prohibited fraud patterns
- `skills/shared-references/effort-contract.md` — effort level specifications
- `skills/shared-references/citation-discipline.md` — citation rules
- `skills/shared-references/writing-principles.md` — writing standards
- `skills/shared-references/venue-checklists.md` — venue formatting

## Research Wiki (Optional)

If `research-wiki/` exists in the project:
- `/research-lit` auto-ingests discovered papers
- `/idea-creator` reads wiki before ideation, writes ideas back after
- `/result-to-claim` updates claim status
- Failed ideas become anti-repetition memory

Initialize with `/research-wiki init`.

## Effort Levels

| Level | Tokens | What changes |
|-------|:------:|-------------|
| `lite` | 0.4x | Fewer papers, ideas, rounds |
| `balanced` | 1x | Current default behavior |
| `max` | 2.5x | More papers, deeper review |
| `beast` | 5-8x | Every knob to maximum |

Codex reasoning is **always xhigh** regardless of effort.

## Source of Truth

- Each skill's behavior: read its `skills/<name>/SKILL.md`
- System-wide rules: read `skills/shared-references/*.md`
- This guide is a routing index, not the specification
