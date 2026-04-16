---
name: training-check
description: Periodically check WandB metrics during training to catch problems early (NaN, loss divergence, idle GPUs). Avoids wasting GPU hours on broken runs. Use when training is running and you want automated health checks.
argument-hint: [wandb-run-path]
allowed-tools: Bash(*), Read, Grep, Glob, Write, Edit, Task
---

# Training Check

Periodically read WandB metrics during training to catch problems early. Do not wait until training finishes to discover it was a waste of GPU time.

## Context: $ARGUMENTS

## Constants

- WANDB_ENTITY and WANDB_PROJECT: read from CLAUDE.md or passed as argument (format: `entity/project/run_id`)
- CHECK_INTERVAL: starts at 10 minutes, then gradually increases if consistently healthy: 10 min → 20 min → 30 min → 60 min (cap)
- REVIEWER_MODEL — used via reviewer task for ambiguous cases only

## When to Use

- After training is confirmed running (session alive, loss decreasing for first few steps)
- Set up via agenda watch/every trigger to fire periodically during training
- **This skill checks training QUALITY, not process HEALTH.** Process health (session alive, GPU utilization) is [watchdog.py](../../tools/watchdog.py)'s job.

## Workflow

### Step 1: Read WandB Metrics

```python
import wandb
api = wandb.Api()
run = api.run("<entity>/<project>/<run_id>")
history = run.history()
```

If WandB is unreachable (API error, network issue), fall back to reading the log file directly via SSH:
```bash
ssh server "tail -100 /path/to/training.log"
```

Check these signals:
- **Loss trend**: Is training loss decreasing over the last N steps?
- **Eval metrics**: Are evaluation metrics improving (or at least not degrading)?
- **NaN / Inf**: Any NaN or Inf values in loss or gradients?
- **Spikes**: Sudden large jumps in loss (>10x normal variance)?
- **Learning rate**: Is the schedule behaving as expected?
- **Gradient norm**: Exploding or vanishing?

### Step 2: Judgment

| Signal | Judgment | Action |
|--------|----------|--------|
| NaN/Inf in loss | **Clearly bad** | Stop training, investigate |
| Loss diverging (increasing for >N steps) | **Clearly bad** | Stop training, investigate |
| Eval metrics significantly worse than baseline | **Clearly bad** | Stop training, investigate |
| Loss decreasing, metrics improving | **Clearly fine** | Continue, increase check interval |
| Loss flat but not diverging | **Unsure** | → Step 3 (reviewer judgment) |
| Metrics noisy, can't tell trend | **Unsure** | → Step 3 (reviewer judgment) |
| Slightly worse than baseline but still early | **Unsure** | → Step 3 (reviewer judgment) |

### Step 3: Reviewer Judgment (only when unsure)

Only escalate to the reviewer when the signal is ambiguous. For clearly good or clearly bad signals, act directly.

```
task(subagent_type="reviewer", category="most-capable"):
  prompt: |
    TRAINING HEALTH CHECK — need your judgment on ambiguous metrics.

    Run: <entity>/<project>/<run_id>
    Current epoch/step: X / Y total
    Training loss (last 10 checkpoints): [values]
    Eval metrics (last 3 evals): [values]
    Baseline reference: [numbers from paper/reproduction]

    What I'm unsure about: [specific concern]

    Please respond with exactly one of:
    - STOP: clearly problematic, should kill training
    - CONTINUE: looks fine, check again next interval
    - WAIT: not enough data to judge, check again sooner
```

### Step 4: Act

| Decision | Action |
|----------|--------|
| **Stop** | Kill the training session. Save the WandB run URL, key metrics, and reason for stopping. Log to project notes for debugging. |
| **Continue** | Do nothing. Will be invoked again at next interval (increase interval if consistently healthy). |
| **Wait** | Do nothing but keep the current short interval (don't increase). |

## Integration with Watchdog

Training-check and [watchdog.py](../../tools/watchdog.py) operate at different levels:

| Layer | Tool | What it checks | Frequency |
|-------|------|----------------|-----------|
| Process health | watchdog.py | Session alive? GPU active? | Every 60s (continuous) |
| Training quality | training-check | Loss trend? Metrics improving? | Every 10-60 min (periodic) |

Use both together:
- Watchdog catches crashes and idle GPUs immediately
- Training-check catches subtle quality issues (loss plateau, metric degradation)

## Rules

- Do not stop training on first sign of noise — some loss spikes are normal. Look at **trends over multiple checkpoints**.
- When stopping training, always save the WandB run URL and key metrics as evidence.
- If both WandB and log files are unreachable, report the connectivity issue and try again next interval. Do not assume training is broken.
- Gradually increase check interval when healthy (10 → 20 → 30 → 60 min). Reset to 10 min after any anomaly.
- This skill is meant to be automated via agenda (see Synergy Agenda Integration below) — do not ask the user whether to set it up. Just set it.

## Synergy Agenda Integration

Instead of manually creating CronCreate jobs, use Synergy's agenda system with **watch triggers** for more reliable, context-aware monitoring.

### Why Agenda Watch Triggers

The original CronCreate pattern has several limitations:
- Requires manual creation and deletion of cron jobs
- Cannot adapt check intervals automatically
- No awareness of training completion — keeps running even after training ends

Agenda watch triggers solve this by:
- **Polling a command** on a schedule and firing only when output changes (or matches a pattern)
- **Running in project scope** — the agenda item inherits your current working directory
- **Delivering results back to your current conversation** — no need to check a separate session

### Setup via Agenda

After training is confirmed stable, create an agenda item:

```
agenda_create(
  title: "Training health check: <run_id>",
  triggers: [{
    type: "every",
    interval: "10m"           // Start at 10 min, can be adjusted
  }],
  workDirectory: "<current project directory>",
  delivery: "auto",           // Results return to THIS conversation
  prompt: """
    Run a training health check for wandb run <entity>/<project>/<run_id>.

    Steps:
    1. Pull the latest metrics from WandB (or SSH + log file fallback)
    2. Check signals: loss trend, eval metrics, NaN/Inf, spikes, gradient norm
    3. If clearly bad (NaN, divergence): report STOP with evidence, then use
       session_send(target="<SESSION_ID>", role="user",
         content="Training health check: STOP. [reason]. Action needed.")
       to wake up the originating session for follow-up action.
    4. If clearly fine: report CONTINUE, suggest increasing check interval
    5. If unsure: report WAIT with the ambiguous signals

    Report format:
    - Status: STOP / CONTINUE / WAIT
    - Key metrics (last 10 checkpoints)
    - Recommendation for next check interval

    If training has completed or the WandB run shows state=finished,
    report that the training is done and use session_send(target="<SESSION_ID>",
    role="user", content="Training complete. [summary]") to notify the session,
    then deactivate this agenda item.
  """,
  sessionRefs: [{
    sessionID: "<current session ID>",
    hint: "Training setup context, run path, and baseline reference"
  }]
)
```

### Watch Trigger Alternative (for log-file-based monitoring)

If you prefer to fire only when something changes (rather than on a fixed interval), use a watch trigger that polls the training log. The poll command depends on where training runs:

**Remote GPU server** (SSH, requires passwordless login configured):
```
command: "ssh <server> 'tail -1 /path/to/training.log'"
```

**Local machine**:
```
command: "tail -1 /path/to/training.log"
```

**启智平台 (qzcli)**:
```
command: "qzcli qz_list_jobs --running-only 2>/dev/null | grep <job-name>"
```

Full example with a remote server:

```
agenda_create(
  title: "Training log watch: <run_id>",
  triggers: [{
    type: "watch",
    watch: {
      kind: "poll",
      command: "ssh <server> 'tail -1 /path/to/training.log'",  // or local: "tail -1 /path/to/training.log", or qzcli: "qzcli qz_list_jobs --running-only 2>/dev/null | grep <job-name>"
      interval: "5m",
      trigger: "change"        // Fire when the last line changes
    }
  }],
  workDirectory: "<current project directory>",
  delivery: "auto",
  prompt: """
    The training log for <run_id> has new output. Check training health:

    1. Read the last 50 lines of the training log (SSH or local, depending on where training runs)
    2. Check for: NaN/Inf, loss divergence, abnormal spikes, stalled progress
    3. Report status: STOP / CONTINUE / WAIT
    4. If status is STOP, use session_send(target="<SESSION_ID>", role="user",
       content="Training health check: STOP. [reason]") to wake the originating session.
    5. If training has completed (final epoch reached), use session_send(target="<SESSION_ID>",
       role="user", content="Training complete. [summary]"), then deactivate this agenda item.

    Keep the report concise — just status + key numbers.
  """
)
```

### Key Agenda Configuration Details

- **`workDirectory`**: Set to your current project directory so the agenda item runs in the correct scope. This ensures file paths, SSH configs, and WandB references resolve correctly.
- **`delivery: "auto"`**: Results are sent back to the conversation where you created the agenda item. You'll see the health check reports directly in your current session.
- **`sessionRefs`**: Attach the current session so the executing agent has context about your training setup, baseline numbers, and what to watch for.
- **Interval adjustment**: To change the check interval (e.g., from 10m to 30m after consistently healthy reports), use `agenda_update` to modify the trigger. You do NOT need to delete and recreate the item.
- **Deactivation**: When training completes, the agenda item should be deactivated via `agenda_update(status: "done")` from within the task, or manually via `agenda_update(status: "done")`.

### Important: Delivery Behavior

By default, `delivery: "auto"` sends results as an **assistant** message to your session. This is informational — it does NOT wake up the session's agent to take action. If you want the health check to trigger automated responses (e.g., kill training on NaN detection), you have two options:

1. **Have the agenda task itself take action** — include instructions like "if NaN detected, kill the training process" directly in the agenda prompt. The kill command depends on your platform:
   - Remote server: `ssh <server> 'kill <pid>'`
   - Local: `kill <pid>`
   - 启智平台: `qzcli qz_stop_job --job-id <job-id>`
2. **Use `session_send` with `role: "user"`** — include in the agenda prompt: "After checking, use `session_send(target: '<your-session-ID>', role: 'user', content: '...')` to wake up this session for follow-up action." This triggers the current session's agent to process the message and respond.
