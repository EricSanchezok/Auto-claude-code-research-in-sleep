---
name: auto-review-loop
description: Autonomous multi-round research review loop. Repeatedly reviews, implements fixes, and re-reviews until positive assessment or max rounds reached. Use when user says "auto review loop", "review until it passes", or wants autonomous iterative improvement.
argument-hint: [topic-or-scope]
allowed-tools: Bash(*), Read, Grep, Glob, Write, Edit, Skill, Task
---

# Auto Review Loop: Autonomous Research Improvement

Autonomously iterate: review → implement fixes → re-review, until the external reviewer gives a positive assessment or MAX_ROUNDS is reached.

## Context: $ARGUMENTS

## Constants

- MAX_ROUNDS = 5
- POSITIVE_THRESHOLD: score >= 6/10, or verdict contains "accept", "sufficient", "ready for submission"
- REVIEW_DOC: `review-stage/AUTO_REVIEW.md` (cumulative log) *(fall back to `./AUTO_REVIEW.md` for legacy projects)*
- **OUTPUT_DIR = `review-stage/`** — All review-stage outputs go here. Create the directory if it doesn't exist.
- See `shared-references/reviewer-routing.md` for routing options.
- **HUMAN_CHECKPOINT = false** — When `true`, pause after each round's review (Phase B) and present the score + weaknesses to the user. Wait for user input before proceeding to Phase C. The user can: approve the suggested fixes, provide custom modification instructions, skip specific fixes, or stop the loop early. When `false` (default), the loop runs fully autonomously.
- **COMPACT = false** — When `true`, (1) read `EXPERIMENT_LOG.md` and `findings.md` instead of parsing full logs on session recovery, (2) append key findings to `findings.md` after each round.
- **REVIEWER_DIFFICULTY = medium** — Controls how adversarial the reviewer is. Three levels:
  - `medium` (default): Current behavior — the executor delegates review to a reviewer agent via `task()`.
  - `hard`: Adds **Reviewer Memory** (the reviewer tracks its own suspicions across rounds) + **Debate Protocol** (the executor can rebut, the reviewer rules).
  - `nightmare`: Everything in `hard` + **the reviewer reads the repo directly** via `task(subagent_type="auditor", category="most-capable")` (the executor cannot filter what the reviewer sees) + **Adversarial Verification** (the reviewer independently checks if code matches claims).

> 💡 Override: `/auto-review-loop "topic" — compact: true, human checkpoint: true, difficulty: hard`

## DAG Orchestration

The review loop is a repeating DAG per round. Below is the structure in `dagwrite` syntax. **Without DAG support, the linear workflow below still works identically** — the DAG is an optional parallelization overlay.

```
dag auto_review_loop {
  // ── Round N ──────────────────────────────────────────
  node round_N_review        { phase: "A"   desc: "Delegate review to reviewer/auditor" }
  node round_N_parse         { phase: "B"   desc: "Extract score, verdict, action items" }
  node round_N_memory_update { phase: "B.5" desc: "Update REVIEWER_MEMORY.md"  mode: "hard,nightmare" }
  node round_N_debate_rebut  { phase: "B.6" desc: "Executor writes rebuttal"   mode: "hard,nightmare" }
  node round_N_debate_rule   { phase: "B.6" desc: "Reviewer rules on rebuttal" mode: "hard,nightmare" }
  node round_N_implement     { phase: "C"   desc: "Implement fixes (may fan-out)" }
  node round_N_wait          { phase: "D"   desc: "Wait for experiment results" }
  node round_N_document      { phase: "E"   desc: "Append to AUTO_REVIEW.md + write state" }

  // Sequential backbone
  edge round_N_review  → round_N_parse
  edge round_N_parse   → round_N_implement
  edge round_N_implement → round_N_wait
  edge round_N_wait    → round_N_document

  // hard/nightmare: memory update + debate branch (parallel with each other, after parse)
  edge round_N_parse         → round_N_memory_update
  edge round_N_parse         → round_N_debate_rebut
  edge round_N_memory_update → round_N_debate_rebut   // memory must be saved before debate
  edge round_N_debate_rebut  → round_N_debate_rule
  edge round_N_debate_rule   → round_N_implement       // ruling adjusts action items

  // Phase C fan-out: independent fixes run in parallel
  fanout round_N_implement → [fix_1, fix_2, fix_3]
  fanin  [fix_1, fix_2, fix_3] → round_N_wait

  // Round boundary
  edge round_N_document → round_N+1_review
}
```

**Parallelization opportunities:**
- **Phase B.5 + B.6**: In hard/nightmare, memory update (B.5) and debate rebuttal drafting (B.6 step 1) can proceed concurrently — the rebuttal doesn't depend on the memory file being saved first, but the reviewer ruling call (B.6 step 2) must wait for both.
- **Phase C**: Independent fixes (different files, different experiments) can be dispatched as parallel `task()` calls. Aggregate all results before proceeding to Phase D.
- **Cross-round**: No parallelism — each round depends on the previous round's documented state.

## State Persistence (Compact Recovery)

Long-running loops may hit the context window limit, triggering automatic compaction. To survive this, persist state to `review-stage/REVIEW_STATE.json` after each round:

```json
{
  "round": 2,
  "status": "in_progress",
  "difficulty": "medium",
  "last_score": 5.0,
  "last_verdict": "not ready",
  "pending_experiments": ["screen_name_1"],
  "timestamp": "2026-03-13T21:00:00"
}
```

**Write this file at the end of every Phase E** (after documenting the round). Overwrite each time — only the latest state matters.

**On completion** (positive assessment or max rounds), set `"status": "completed"` so future invocations don't accidentally resume a finished loop.

## Output Protocols

> Follow these shared protocols for all output files:
> - **[Output Versioning Protocol](../shared-references/output-versioning.md)** — write timestamped file first, then copy to fixed name
> - **[Output Manifest Protocol](../shared-references/output-manifest.md)** — log every output to MANIFEST.md
> - **[Output Language Protocol](../shared-references/output-language.md)** — respect the project's language setting

## Workflow

### Initialization

1. **Check for `review-stage/REVIEW_STATE.json`** *(fall back to `./REVIEW_STATE.json` if not found — legacy path)*:
   - If neither path exists: **fresh start** (normal case, identical to behavior before this feature existed)
   - If it exists AND `status` is `"completed"`: **fresh start** (previous loop finished normally)
   - If it exists AND `status` is `"in_progress"` AND `timestamp` is older than 24 hours: **fresh start** (stale state from a killed/abandoned run — delete the file and start over)
    - If it exists AND `status` is `"in_progress"` AND `timestamp` is within 24 hours: **resume**
      - Read the state file to recover `round`, `last_score`, `pending_experiments`
     - Read `review-stage/AUTO_REVIEW.md` to restore full context of prior rounds *(fall back to `./AUTO_REVIEW.md`)*
     - If `pending_experiments` is non-empty, check if they have completed (e.g., check screen sessions)
     - Resume from the next round (round = saved round + 1)
     - Log: "Recovered from context compaction. Resuming at Round N."
2. Read project narrative documents, memory files, and any prior review documents. **When `COMPACT = true` and compact files exist**: read `findings.md` + `EXPERIMENT_LOG.md` instead of full `review-stage/AUTO_REVIEW.md` and raw logs — saves context window.
3. Read recent experiment results (check output directories, logs)
4. Identify current weaknesses and open TODOs from prior reviews
5. Initialize round counter = 1 (unless recovered from state file)
6. Create/update `review-stage/AUTO_REVIEW.md` with header and timestamp

### Loop (repeat up to MAX_ROUNDS)

#### Phase A: Review

**Route by REVIEWER_DIFFICULTY:**

##### Medium (default) — Reviewer Task

Send comprehensive context to the external reviewer:

```
task(
  subagent_type="reviewer",
  category="most-capable",
  prompt="""
    [Round N/MAX_ROUNDS of autonomous review loop]

    [Full research context: claims, methods, results, known weaknesses]
    [Changes since last round, if any]

    Please act as a senior ML reviewer (NeurIPS/ICML level).

    1. Score this work 1-10 for a top venue
    2. List remaining critical weaknesses (ranked by severity)
    3. For each weakness, specify the MINIMUM fix (experiment, analysis, or reframing)
    4. State clearly: is this READY for submission? Yes/No/Almost

    Be brutally honest. If the work is ready, say so clearly.
  """
)
```

For round 2+, include the full context of prior reviews and changes directly in the prompt — each `task()` call is stateless.

##### Hard — Reviewer Task + Reviewer Memory

Same as medium, but **prepend Reviewer Memory** to the prompt:

```
task(
  subagent_type="reviewer",
  category="most-capable",
  prompt="""
    [Round N/MAX_ROUNDS of autonomous review loop]

    ## Your Reviewer Memory (persistent across rounds)
    [Paste full contents of REVIEWER_MEMORY.md here]

    IMPORTANT: You have memory from prior rounds. Check whether your
    previous suspicions were genuinely addressed or merely sidestepped.
    The author (the executor) controls what context you see — be skeptical
    of convenient omissions.

    [Full research context, changes since last round...]

    Please act as a senior ML reviewer (NeurIPS/ICML level).
    1. Score this work 1-10 for a top venue
    2. List remaining critical weaknesses (ranked by severity)
    3. For each weakness, specify the MINIMUM fix
    4. State clearly: is this READY for submission? Yes/No/Almost
    5. **Memory update**: List any new suspicions, unresolved concerns,
       or patterns you want to track in future rounds.

    Be brutally honest. Actively look for things the author might be hiding.
  """
)
```

##### Nightmare — Auditor Task (reviewer reads repo directly)

**Do NOT use the standard reviewer.** Instead, let the reviewer access the repo autonomously via an auditor agent:

```
task(
  subagent_type="auditor",
  category="most-capable",
  prompt="""
    You are an adversarial senior ML reviewer (NeurIPS/ICML level).
    This is Round N/MAX_ROUNDS of an autonomous review loop.

    ## Your Reviewer Memory (persistent across rounds)
    [Paste full contents of REVIEWER_MEMORY.md]

    ## Instructions
    You have FULL READ ACCESS to this repository. The author (the executor) does NOT
    control what you see — explore freely. Your job is to find problems the
    author might hide or downplay.

    DO THE FOLLOWING:
    1. Read the experiment code, results files (JSON/CSV), and logs YOURSELF
    2. Verify that reported numbers match what's actually in the output files
    3. Check if evaluation metrics are computed correctly (ground truth, not model output)
    4. Look for cherry-picked results, missing ablations, or suspicious hyperparameter choices
    5. Read NARRATIVE_REPORT.md or review-stage/AUTO_REVIEW.md for the author's claims — then verify each against code

    OUTPUT FORMAT:
    - Score: X/10
    - Verdict: ready / almost / not ready
    - Verified claims: [which claims you independently confirmed]
    - Unverified/false claims: [which claims don't match the code or results]
    - Weaknesses (ranked): [with MINIMUM fix for each]
    - Memory update: [new suspicions and patterns to track next round]

    Be adversarial. Trust nothing the author tells you — verify everything yourself.
  """
)
```

**Key difference**: In nightmare mode, the auditor agent independently reads code, result files, and logs. The executor cannot filter or curate what the reviewer sees. This is the closest analog to a real hostile reviewer who reads your actual paper + supplementary materials.

#### Phase B: Parse Assessment

**CRITICAL: Save the FULL raw response** from the external reviewer verbatim (store in a variable for Phase E). Do NOT discard or summarize — the raw text is the primary record.

Then extract structured fields:
- **Score** (numeric 1-10)
- **Verdict** ("ready" / "almost" / "not ready")
- **Action items** (ranked list of fixes)

**STOP CONDITION**: If score >= 6 AND verdict contains "ready" or "almost" → stop loop, document final state.

**NEGATIVE RESULT DETECTION**: If round ≥ 2, compare current score against prior round scores from `REVIEW_STATE.json`. Check:

1. **Score decay**: If score has decreased or stayed the same for 2 consecutive rounds (e.g., Round 1: 4, Round 2: 3, Round 3: 3) → the method may be fundamentally weak, not just buggy.
2. **Low-score plateau**: If score has been ≤4 for 2+ consecutive rounds → the improvements being made are not moving the needle.
3. **Degrading method performance**: If experiment results show method metric getting *worse* across rounds (not just review score) → fixes are introducing regressions rather than improvements.

If any of these conditions are met:
- **Do NOT proceed to Phase C.** Jump to Termination with status `negative_result`.
- Write to findings.md: negative result analysis (what was tried, what didn't work, likely reasons).
- Log: `"NEGATIVE_RESULT: Loop terminated early — score plateau/decay detected at Round N (score: X/10)"`.

This prevents wasting GPU hours on iterative "improvements" to a method that is fundamentally not competitive. A negative result is a valid research outcome — it frees resources for the next idea.

#### Phase B.5: Reviewer Memory Update (hard + nightmare only)

**Skip entirely if `REVIEWER_DIFFICULTY = medium`.**

After parsing the assessment, update `REVIEWER_MEMORY.md` in the project root:

```markdown
# Reviewer Memory

## Round 1 — Score: X/10
- **Suspicion**: [what the reviewer flagged]
- **Unresolved**: [concerns not yet addressed]
- **Patterns**: [recurring issues the reviewer noticed]

## Round 2 — Score: X/10
- **Previous suspicions addressed?**: [yes/no for each, with reviewer's judgment]
- **New suspicions**: [...]
- **Unresolved**: [carried forward + new]
```

**Rules**:
- Append each round, never delete prior rounds (audit trail)
- If the reviewer's response includes a "Memory update" section, copy it verbatim
- This file is passed back to the reviewer in the next round's Phase A — it is the reviewer's persistent brain

#### Phase B.6: Debate Protocol (hard + nightmare only)

**Skip entirely if `REVIEWER_DIFFICULTY = medium`.**

After parsing the review, the executor (the author) gets a chance to **rebut**:

**Step 1 — Executor's Rebuttal:**

For each weakness the reviewer identified, the executor writes a structured response:

```markdown
### Rebuttal to Weakness #1: [title]
- **Accept / Partially Accept / Reject**
- **Argument**: [why this criticism is invalid, already addressed, or based on a misunderstanding]
- **Evidence**: [point to specific code, results, or prior round fixes]
```

Rules for the executor's rebuttal:
- Must be honest — do NOT fabricate evidence or misrepresent results
- Can point out factual errors in the review (reviewer misread code, wrong metric, etc.)
- Can argue a weakness is out of scope or would require unreasonable effort
- Maximum 3 rebuttals per round (pick the most impactful to contest)

**Step 2 — Reviewer Rules on Rebuttal:**

Send the executor's rebuttal back to the reviewer for a ruling:

*Hard mode:*
```
task(
  subagent_type="reviewer",
  category="most-capable",
  prompt="""
    You are a senior ML reviewer. The author rebuts your review:

    [paste executor's rebuttal]

    [Include the original review context so the reviewer can evaluate the rebuttal]

    For each rebuttal, rule:
    - SUSTAINED (author's argument is valid, withdraw this weakness)
    - OVERRULED (your original criticism stands, explain why)
    - PARTIALLY SUSTAINED (revise the weakness to a narrower scope)

    Then update your score if any weaknesses were withdrawn.
  """
)
```

*Nightmare mode:*
```
task(
  subagent_type="auditor",
  category="most-capable",
  prompt="""
    You are the same adversarial reviewer. The author rebuts your review:

    [paste executor's rebuttal]

    [Include the original review context]

    VERIFY the author's evidence claims yourself — read the files they reference.
    Do NOT take their word for it.

    For each rebuttal, rule:
    - SUSTAINED (verified and valid)
    - OVERRULED (evidence doesn't check out or argument is weak)
    - PARTIALLY SUSTAINED (partially valid, narrow the weakness)

    Update your score. Update your memory.
  """
)
```

**Step 3 — Update score and action items** based on the ruling:
- SUSTAINED weaknesses: remove from action items
- OVERRULED: keep as-is
- PARTIALLY SUSTAINED: revise scope

Append the full debate transcript to `review-stage/AUTO_REVIEW.md` under the round's entry.

#### Human Checkpoint (if enabled)

**Skip this step entirely if `HUMAN_CHECKPOINT = false`.**

When `HUMAN_CHECKPOINT = true`, present the review results and wait for user input:

```
📋 Round N/MAX_ROUNDS review complete.

Score: X/10 — [verdict]
Top weaknesses:
1. [weakness 1]
2. [weakness 2]
3. [weakness 3]

Suggested fixes:
1. [fix 1]
2. [fix 2]
3. [fix 3]

Options:
- Reply "go" or "continue" → implement all suggested fixes
- Reply with custom instructions → implement your modifications instead
- Reply "skip 2" → skip fix #2, implement the rest
- Reply "stop" → end the loop, document current state
```

Wait for the user's response. Parse their input:
- **Approval** ("go", "continue", "ok", "proceed"): proceed to Phase C with all suggested fixes
- **Custom instructions** (any other text): treat as additional/replacement guidance for Phase C. Merge with reviewer suggestions where appropriate
- **Skip specific fixes** ("skip 1,3"): remove those fixes from the action list
- **Stop** ("stop", "enough", "done"): terminate the loop, jump to Termination

#### Feishu Notification (if configured)

After parsing the score, check if the feishu notification config exists and mode is not `"off"`:
- Send a `review_scored` notification: "Round N: X/10 — [verdict]" with top 3 weaknesses
- If **interactive** mode and verdict is "almost": send as checkpoint, wait for user reply on whether to continue or stop
- If config absent or mode off: skip entirely (no-op)

#### Phase C: Implement Fixes (if not stopping)

For each action item (highest priority first):

1. **Code changes**: Write/modify experiment scripts, model code, analysis scripts
2. **Run experiments**: Deploy to GPU server via SSH + screen/tmux
3. **Analysis**: Run evaluation, collect results, update figures/tables
4. **Documentation**: Update project notes and review document

Prioritization rules:
- Skip fixes requiring excessive compute (flag for manual follow-up)
- Skip fixes requiring external data/models not available
- Prefer reframing/analysis over new experiments when both address the concern
- Always implement metric additions (cheap, high impact)

#### Phase C.5: Regression Check (before re-running experiments)

**Skip this step if no code changes were made in Phase C** (e.g., only analysis or reframing).

After implementing fixes but before deploying new experiments, verify the fixes did not introduce regressions:

1. **Read `refine-logs/BASELINE_ALIGNMENT.json`** — if it exists, it contains the verified baseline result from `/baseline-alignment`.
2. **Quick baseline re-run**: run the baseline experiment with the modified code, using the smallest configuration (single seed, small data if available). This should take 1-5 minutes.
3. **Compare**: if the new baseline result deviates >5% from the value in `BASELINE_ALIGNMENT.json`, the code changes introduced a regression.
4. **On regression detected**:
   - Revert the last code change (`git checkout -- <files>` or manual revert)
   - Try an alternative fix approach
   - Re-check before proceeding
   - If no alternative fix exists, skip this action item and move to the next
5. **On no regression**: proceed to Phase D.

This check catches the most common failure mode in review loops: fixing one bug while breaking something else. A 5-minute baseline re-run is far cheaper than a full experiment suite on broken code.

If experiments were launched:
- Monitor remote sessions for completion
- Collect results from output files and logs
- **Training quality check** — if W&B is configured, invoke `/training-check` to verify training was healthy (no NaN, no divergence, no plateau). If W&B not available, skip silently. Flag any quality issues in the next review round.

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

[Paste the COMPLETE raw response from the external reviewer here — verbatim, unedited.
This is the authoritative record. Do NOT truncate or paraphrase.]

</details>

### Debate Transcript (hard + nightmare only)

<details>
<summary>Click to expand debate</summary>

**Executor's Rebuttal:**
[paste rebuttal]

**Reviewer's Ruling:**
[paste ruling — SUSTAINED / OVERRULED / PARTIALLY SUSTAINED for each]

**Score adjustment**: X/10 → Y/10

</details>

### Actions Taken
- [what was implemented/changed]

### Results
- [experiment outcomes, if any]

### Status
- [continuing to round N+1 / stopping]
- Difficulty: [medium/hard/nightmare]
```

**Write `review-stage/REVIEW_STATE.json`** with current round, score, verdict, and any pending experiments.

**Append to `findings.md`** (when `COMPACT = true`): one-line entry per key finding this round:

```markdown
- [Round N] [positive/negative/unexpected]: [one-sentence finding] (metric: X.XX → Y.YY)
```

**Bug knowledge extraction** (when a bug was fixed in Phase C and confirmed in Phase D):

If Phase C fixed a code bug AND Phase D confirmed the fix improved results, extract the bug pattern for future projects:

```
memory_write(
  title: "Bug: [short pattern, e.g., 'eval uses model output as GT']",
  content: "Pattern: [what went wrong]. Root cause: [why]. Fix: [what was changed]. Context: [framework, dataset, task]. Found in: [round N of auto-review-loop].",
  category: "knowledge",
  recallMode: "contextual"
)
```

Only write when the fix is confirmed effective — do not write speculative or unverified fixes. This ensures the knowledge base contains reliable bug patterns, not guesses.

Increment round counter → back to Phase A.

### Termination

When loop ends (positive assessment or max rounds):

1. Update `review-stage/REVIEW_STATE.json` with `"status": "completed"`
2. Write final summary to `review-stage/AUTO_REVIEW.md`
3. Update project notes with conclusions
4. **Write method/pipeline description** to `review-stage/AUTO_REVIEW.md` under a `## Method Description` section — a concise 1-2 paragraph description of the final method, its architecture, and data flow. This serves as input for `/paper-illustration` in Workflow 3 (so it can generate architecture diagrams automatically).
5. **Generate claims from results** — invoke `/result-to-claim` to convert experiment results from `review-stage/AUTO_REVIEW.md` into structured paper claims. Output: `CLAIMS_FROM_RESULTS.md`. This bridges Workflow 2 → Workflow 3 so `/paper-plan` can directly use validated claims instead of extracting them from scratch. If `/result-to-claim` is not available, skip silently.
6. If stopped at max rounds without positive assessment:
   - List remaining blockers
   - Estimate effort needed for each
   - Suggest whether to continue manually or pivot
5. **Feishu notification** (if configured): Send `pipeline_done` with final score progression table

## Agenda Integration

For long-running loops, use Synergy's agenda system to avoid blocking on experiment waits and to enable loop continuation across sessions.

### Phase D: Watch-Based Experiment Wait

When experiments launched in Phase C take >30 min, create an agenda item with a **watch trigger** instead of polling manually:

```
agenda_create(
  title: "Review loop: wait for experiment results (Round N)",
  prompt: """
    The experiment(s) launched in Round N of the auto-review-loop have completed.
    Results are now available.

    1. Collect all output files and logs from the experiment
    2. Summarize key results and metrics
    3. Use session_send to wake up the originating session:
       session_send(target="<SESSION_ID>", role="user",
         content="Phase D complete for Round N. Results collected. Resume Phase E.")
  """,
  workDirectory: "<current project directory>",
  delivery: "auto",
  sessionRefs: [{ sessionID: "<current session ID>", hint: "Active review loop session — resume here after results arrive" }],
  triggers: [{
    type: "watch",
    watch: {
      kind: "poll",
      // Choose the right command for your platform:
      // Remote server:  "ssh <server> 'ls /path/to/results/final_metrics.json 2>/dev/null && echo DONE || echo PENDING'"
      // Local:         "ls /path/to/results/final_metrics.json 2>/dev/null && echo DONE || echo PENDING"
      // 启智平台 (Synergy native):  use kind="tool" watch: { kind: "tool", tool: "inspire_jobs", args: { status: "running" }, interval: "5m", trigger: "change" }
      command: "ssh <server> 'ls /path/to/results/final_metrics.json 2>/dev/null && echo DONE || echo PENDING'",
      interval: "5m",
      trigger: "match",
      match: "DONE"
    }
  }]
)
```

Alternative watch patterns (choose based on your platform):
- **Screen/tmux session (remote)**: `ssh <server> 'screen -ls | grep <session_name>'` → trigger on match when screen exits
- **Screen/tmux session (local)**: `screen -ls | grep <session_name>` → trigger on match when screen exits
- **W&B run status**: `curl -s "https://api.wandb.ai/..." | jq .state` → trigger when state is `"finished"`
- **启智平台 job**: use agenda watch with `{ kind: "tool", tool: "inspire_jobs", args: { status: "running" }, trigger: "change" }` → fires when job list changes (completion/failure)
- **Local file**: `{ kind: "file", glob: "results/**/*.json", event: "add" }` → trigger when result files appear

After creating the agenda item, **log it in `review-stage/REVIEW_STATE.json`** under a new `agenda_item_id` field so you can cancel it if the loop is terminated early.

### Loop Continuation After Phase D

The agenda prompt above uses `session_send` with `role: "user"` to **wake up the current session's agent** after results arrive. This is critical:

- `delivery: "auto"` sends the agenda result back as an **assistant** message, which does NOT trigger the session's agent to act
- `session_send(target, role: "user", content)` delivers a **user** message that wakes the agent, enabling automated continuation to Phase E and the next round

**Full loop continuation pattern:**

```
// Inside the agenda prompt:
session_send(
  target="<SESSION_ID>",
  role="user",
  content="Phase D complete for Round N. Results: [summary]. Resume Phase E and continue the review loop."
)
```

The session's agent picks up the message, proceeds to Phase E (document round), then loops back to Phase A for the next round — fully automated.

### Key Config Details

- **`workDirectory`**: Must be set to the current project directory for correct scope resolution
- **`delivery: "auto"`**: Sends the agenda task output back to the originating conversation as an assistant message
- **`sessionRefs`**: Attach the current session so the agenda task has context about the review loop state
- **Cleanup**: On loop termination, cancel any outstanding agenda items via `agenda_update(id, status: "cancelled")`

## Key Rules

- **Large file handling**: If the Write tool fails due to file size, immediately retry using Bash (`cat << 'EOF' > file`) to write in chunks. Do NOT ask the user for permission — just do it silently.

- **Anti-hallucination citations**: When adding references during fixes, NEVER fabricate BibTeX. Use the same DBLP → CrossRef → `[VERIFY]` chain as `/paper-write`: (1) `curl -s "https://dblp.org/search/publ/api?q=TITLE&format=json"` → get key → `curl -s "https://dblp.org/rec/{key}.bib"`, (2) if not found, `curl -sLH "Accept: application/x-bibtex" "https://doi.org/{doi}"`, (3) if both fail, mark with `% [VERIFY]`. Do NOT generate BibTeX from memory.
- Be honest — include negative results and failed experiments
- Do NOT hide weaknesses to game a positive score
- Implement fixes BEFORE re-reviewing (don't just promise to fix)
- **Exhaust before surrendering** — before marking any reviewer concern as "cannot address": (1) try at least 2 different solution paths, (2) for experiment issues, adjust hyperparameters or try an alternative baseline, (3) for theory issues, provide a weaker version of the result or an alternative argument, (4) only then concede narrowly and bound the damage. Never give up on the first attempt.
- If an experiment takes > 30 minutes, launch it and continue with other fixes while waiting
- Document EVERYTHING — the review log should be self-contained
- Update project notes after each round, not just at the end

## Prompt Template for Round 2+

Since each `task()` call is stateless, include the full context of prior reviews and changes in the prompt:

```
task(
  subagent_type="reviewer",
  category="most-capable",
  prompt="""
    [Round N/MAX_ROUNDS of autonomous review loop]

    ## Previous Review Summary (Round N-1)
    - Previous Score: X/10
    - Previous Verdict: [ready/almost/not ready]
    - Previous Key Weaknesses: [list]

    ## Changes Since Last Review
    1. [Action 1]: [result]
    2. [Action 2]: [result]
    3. [Action 3]: [result]

    Updated results table:
    [paste metrics]

    Please re-score and re-assess. Are the remaining concerns addressed?
    Same format: Score, Verdict, Remaining Weaknesses, Minimum Fixes.
  """
)
```

## Review Tracing

After each `task(subagent_type="reviewer", category="most-capable")` or `task(subagent_type="auditor", category="most-capable")` call, save the trace following `shared-references/review-tracing.md`. Use `tools/save_trace.sh` or write files directly to `.aris/traces/<skill>/<date>_run<NN>/`. Respect the `--- trace:` parameter (default: `full`).
