---
name: monitor-experiment
description: Monitor running experiments, check progress, collect results. Use when user says "check results", "is it done", "monitor", or wants experiment output.
argument-hint: [server-alias or screen-name]
allowed-tools: Bash(ssh *), Bash(echo *), Read, Write, Edit
---

# Monitor Experiment Results

Monitor: $ARGUMENTS

## Workflow

### Step 1: Check What's Running

**SSH server:**
```bash
ssh <server> "screen -ls"
```

**Vast.ai instance** (read `ssh_host`, `ssh_port` from `vast-instances.json`):
```bash
ssh -p <PORT> root@<HOST> "screen -ls"
```

Also check vast.ai instance status:
```bash
vastai show instances
```

**Modal** (when `gpu: modal` in CLAUDE.md):
```bash
modal app list         # List running/recent apps
modal app logs <app>   # Stream logs from a running app
```
Modal apps auto-terminate when done — if it's not in the list, it already finished. Check results via `modal volume ls <volume>` or local output.

### Step 2: Collect Output from Each Screen
For each screen session, capture the last N lines:
```bash
ssh <server> "screen -S <name> -X hardcopy /tmp/screen_<name>.txt && tail -50 /tmp/screen_<name>.txt"
```

If hardcopy fails, check for log files or tee output.

### Step 3: Check for JSON Result Files
```bash
ssh <server> "ls -lt <results_dir>/*.json 2>/dev/null | head -20"
```

If JSON results exist, fetch and parse them:
```bash
ssh <server> "cat <results_dir>/<latest>.json"
```

### Step 3.5: Pull W&B Metrics (when `wandb: true` in CLAUDE.md)

**Skip this step entirely if `wandb` is not set or is `false` in CLAUDE.md.**

Pull training curves and metrics from Weights & Biases via Python API:

```bash
# List recent runs in the project
ssh <server> "python3 -c \"
import wandb
api = wandb.Api()
runs = api.runs('<entity>/<project>', per_page=10)
for r in runs:
    print(f'{r.id}  {r.state}  {r.name}  {r.summary.get(\"eval/loss\", \"N/A\")}')
\""

# Pull specific metrics from a run (last 50 steps)
ssh <server> "python3 -c \"
import wandb, json
api = wandb.Api()
run = api.run('<entity>/<project>/<run_id>')
history = list(run.scan_history(keys=['train/loss', 'eval/loss', 'eval/ppl', 'train/lr'], page_size=50))
print(json.dumps(history[-10:], indent=2))
\""

# Pull run summary (final metrics)
ssh <server> "python3 -c \"
import wandb, json
api = wandb.Api()
run = api.run('<entity>/<project>/<run_id>')
print(json.dumps(dict(run.summary), indent=2, default=str))
\""
```

**What to extract:**
- **Training loss curve** — is it converging? diverging? plateauing?
- **Eval metrics** — loss, PPL, accuracy at latest checkpoint
- **Learning rate** — is the schedule behaving as expected?
- **GPU memory** — any OOM risk?
- **Run status** — running / finished / crashed?

**W&B dashboard link** (include in summary for user):
```
https://wandb.ai/<entity>/<project>/runs/<run_id>
```

> This gives the auto-review-loop richer signal than just screen output — training dynamics, loss curves, and metric trends over time.

### Step 4: Summarize Results

Present results in a comparison table:
```
| Experiment | Metric | Delta vs Baseline | Status |
|-----------|--------|-------------------|--------|
| Baseline  | X.XX   | —                 | done   |
| Method A  | X.XX   | +Y.Y              | done   |
```

### Step 5: Interpret
- Compare against known baselines
- Flag unexpected results (negative delta, NaN, divergence)
- Suggest next steps based on findings

### Step 6: Feishu Notification (if configured)

After results are collected, check the feishu notification config:
- Send `experiment_done` notification: results summary table, delta vs baseline
- If config absent or mode `"off"`: skip entirely (no-op)

## Synergy Agenda Integration

Instead of manually checking experiments, use Synergy's agenda system with **watch triggers** for automated monitoring.

### Why Agenda Watch Triggers

Manual experiment monitoring requires you to repeatedly run SSH commands or check screen sessions. Agenda watch triggers automate this by:

- **Polling a command** on a schedule and firing only when output changes
- **Running in project scope** — the agenda item inherits your current working directory
- **Delivering results back to your current conversation** — you see updates where you're already working

### Setup via Agenda

After launching experiments, create an agenda item to monitor them. The poll command depends on where experiments run:

```
agenda_create(
  title: "Experiment monitor: <server-alias>",
  triggers: [{
    type: "watch",
    watch: {
      kind: "poll",
      // Choose the right command for your platform:
      // Remote server:  "ssh <server> 'screen -ls 2>/dev/null; ls -lt <results_dir>/*.json 2>/dev/null | head -5'"
      // Local:         "screen -ls 2>/dev/null; ls -lt <results_dir>/*.json 2>/dev/null | head -5"
      // 启智平台:       "qzcli qz_list_jobs --running-only 2>/dev/null; ls -lt <results_dir>/*.json 2>/dev/null | head -5"
      command: "ssh <server> 'screen -ls 2>/dev/null; ls -lt <results_dir>/*.json 2>/dev/null | head -5'",
      interval: "5m",
      trigger: "change"          // Fire when screen sessions or result files change
    }
  }],
  workDirectory: "<current project directory>",
  delivery: "auto",             // Results return to THIS conversation
  prompt: """
    Check experiment status on <server>.

    Steps:
    1. Check running sessions (screen/tmux on remote, or qzcli jobs on 启智)
    2. Check for new JSON result files in <results_dir>
    3. For each completed experiment, fetch and parse the result JSON
    4. Present results in a comparison table:

    | Experiment | Metric | Delta vs Baseline | Status |
    |-----------|--------|-------------------|--------|

    5. If ALL experiments are complete (no running screens/jobs, all results collected):
       - Present the final comparison table
       - Note any unexpected results or missing baselines
       - Use session_send(target="<SESSION_ID>", role="user",
         content="All experiments complete. [summary table]") to wake the originating session
       - Then deactivate this agenda item
    6. If experiments are still running, report progress briefly
  """,
  sessionRefs: [{
    sessionID: "<current session ID>",
    hint: "Experiment setup context, server alias, baseline numbers, and expected metrics"
  }]
)
```

### Watch Trigger for Result File Changes

For a more targeted trigger that fires only when new result files appear:

```
agenda_create(
  title: "Result file watch: <server>",
  triggers: [{
    type: "watch",
    watch: {
      kind: "poll",
      // Choose the right command for your platform:
      // Remote server:  "ssh <server> 'find <results_dir> -name \"*.json\" -newer <results_dir>/.last_check -print 2>/dev/null; touch <results_dir>/.last_check'"
      // Local:         "find <results_dir> -name '*.json' -newer <results_dir>/.last_check -print 2>/dev/null; touch <results_dir>/.last_check"
      // 启智平台:       "qzcli qz_list_jobs --running-only 2>/dev/null; find <results_dir> -name '*.json' -newer <results_dir>/.last_check -print 2>/dev/null; touch <results_dir>/.last_check"
      command: "ssh <server> 'find <results_dir> -name \"*.json\" -newer <results_dir>/.last_check -print 2>/dev/null; touch <results_dir>/.last_check'",
      interval: "5m",
      trigger: "change"          // Fire when new JSON files appear
    }
  }],
  workDirectory: "<current project directory>",
  delivery: "auto",
  prompt: """
    New result files detected. Collect and summarize:

    1. List the new result files
    2. Fetch and parse each one
    3. Add to the comparison table
    4. Flag any unexpected results (negative delta, NaN, divergence)
    5. If all expected experiments now have results, use session_send(target="<SESSION_ID>",
       role="user", content="Experiment results complete. [summary]") to wake the originating session.

    Keep the report concise — just the updated table + any flags.
  """
)
```

### Key Agenda Configuration Details

- **`workDirectory`**: Set to your current project directory so the agenda item runs in the correct scope. This ensures SSH configs, result paths, and baseline references resolve correctly.
- **`delivery: "auto"`**: Results are sent back to the conversation where you created the agenda item. You'll see monitoring updates directly in your current session.
- **`sessionRefs`**: Attach the current session so the executing agent has context about your experiment setup, server aliases, and baseline numbers.
- **Deactivation**: When all experiments complete, the agenda item should be deactivated via `agenda_update(status: "done")` from within the task, or manually.

### Important: Delivery Behavior

By default, `delivery: "auto"` sends results as an **assistant** message to your session. This is informational — it does NOT wake up the session's agent to take action. If you want monitoring to trigger automated responses (e.g., start analysis when results arrive), you have two options:

1. **Have the agenda task itself take action** — include instructions like "if results are complete, proceed with result interpretation and comparison" directly in the agenda prompt.
2. **Use `session_send` with `role: "user"`** — include in the agenda prompt: "After collecting results, use `session_send(target: '<your-session-ID>', role: 'user', content: '...')` to wake up this session for follow-up action." This triggers the current session's agent to process the message and respond.

## Key Rules
- Always show raw numbers before interpretation
- Compare against the correct baseline (same config)
- Note if experiments are still running (check progress bars, iteration counts)
- If results look wrong, check training logs for errors before concluding
- **Vast.ai cost awareness**: When monitoring vast.ai instances, report the running cost (hours * $/hr from `vast-instances.json`). If all experiments on an instance are done, remind the user to run `/vast-gpu destroy <instance_id>` to stop billing
- **Modal cost awareness**: Modal auto-scales to zero — no idle billing. When reporting results from Modal runs, note the actual execution time and estimated cost (time * $/hr from the GPU tier used). No cleanup action needed
