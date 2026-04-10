# Output Versioning Protocol

When writing any output file that would overwrite an existing file, use timestamped filename + fixed-name latest copy:

1. Write output to timestamped file: `{FILENAME}_{YYYYMMDD_HHmmss}.md` (or `.json`, `.tex` as appropriate)
   - Timestamp precision to seconds to avoid same-day collisions
   - Place the timestamped file in the same directory as the fixed-name file
2. Copy the same content to the fixed-name file: `{FILENAME}.md` (overwrites the previous latest copy)
3. Downstream skills always read the fixed-name file — they do not need to know about timestamps

## Directory Structure

All ARIS output files are organized by workflow stage:

```
project/
├── CLAUDE.md                              # Dashboard (root — read by all stages)
├── findings.md                            # Cross-stage discovery log (root — append-only)
├── MANIFEST.md                            # Output tracking manifest (root)
│
├── idea-stage/                            # W1: Idea Discovery
│   ├── IDEA_REPORT.md                     # Latest copy
│   ├── IDEA_REPORT_20250615_143022.md     # Timestamped version
│   ├── IDEA_CANDIDATES.md
│   ├── REF_PAPER_SUMMARY.md
│   └── docs/
│       └── research_contract.md
│
├── refine-logs/                           # W1.5: Experiment Planning & Refinement
│   ├── EXPERIMENT_PLAN.md
│   ├── EXPERIMENT_TRACKER.md
│   ├── EXPERIMENT_RESULTS.md
│   ├── FINAL_PROPOSAL.md
│   ├── PIPELINE_SUMMARY.md
│   ├── REFINE_STATE.json
│   ├── REVIEW_SUMMARY.md
│   ├── REFINEMENT_REPORT.md
│   └── round_N_*.md
│
├── review-stage/                          # W2: Auto Review
│   ├── AUTO_REVIEW.md
│   └── REVIEW_STATE.json
│
├── paper/                                 # W3: Paper Writing
│   ├── main.tex
│   └── roundN/
│
└── research-wiki/                         # Persistent knowledge base
```

## What to Timestamp

Files that get overwritten on re-runs:
- `IDEA_REPORT.md`, `IDEA_CANDIDATES.md`, `REF_PAPER_SUMMARY.md`
- `EXPERIMENT_PLAN.md`, `EXPERIMENT_TRACKER.md`, `EXPERIMENT_RESULTS.md`
- `FINAL_PROPOSAL.md`, `PIPELINE_SUMMARY.md`
- `AUTO_REVIEW.md` (when starting a new review loop, not within a loop)
- `paper/main.tex`
- State files: `REFINE_STATE.json`, `REVIEW_STATE.json`

## What NOT to Timestamp

- **Append-only files**: `findings.md`, `research-wiki/log.md` — these accumulate entries, not overwrite
- **Per-round files**: `refine-logs/round_N_*.md` — already versioned by round number
- **Dashboard**: `CLAUDE.md` — single source of truth, always latest
- **MANIFEST.md** — append-only tracking file

Never delete timestamped files. They are the permanent history.

## Stale State Detection

Before reading a state file (`REFINE_STATE.json`, `REVIEW_STATE.json`, `DSE_STATE.json`):
1. Check the file's last modified time via `ls -la` or `stat`
2. If older than 48 hours, warn the user:
   "⚠️ State file {filename} is {N} days old. It may be from a previous research direction. Continue with this state, or start fresh?"
3. If the user chooses to start fresh, write a timestamped archive copy and proceed without the old state
