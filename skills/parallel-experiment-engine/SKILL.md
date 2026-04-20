---
name: parallel-experiment-engine
description: "Unified parallel experiment scheduling across all compute backends. Automatically selects the optimal parallel strategy based on experiment scale and available backend (SSH remote, 启智 GPU/HPC, Vast.ai, Modal, local). Replaces serial /run-experiment calls when multiple independent experiments need deployment. Use when user says '并行跑实验', 'parallel experiments', 'run all experiments', 'batch deploy', or when /experiment-bridge would otherwise deploy sequentially."
argument-hint: [experiment-list-or-plan-path]
allowed-tools: Bash(*), Read, Write, Edit, Grep, Glob, Task, Skill(run-experiment), Skill(experiment-queue), Skill(serverless-modal), Skill(vast-gpu), inspire_status, inspire_submit, inspire_stop, inspire_jobs, inspire_job_detail
---

# Parallel Experiment Engine: Multi-Backend Scheduling

Deploy experiments in parallel: **$ARGUMENTS**

## Why This Exists

`/experiment-bridge` deploys experiments by calling `/run-experiment` one at a time — serial execution even when multiple GPUs or backend slots are available. Each compute backend has its own parallel mechanism, but no skill unifies them:

| Backend | Parallel Mechanism | Current Problem |
|---------|-------------------|-----------------|
| SSH remote | `/experiment-queue` scheduler | Not auto-invoked by pipeline |
| 启智 GPU | `inspire_submit` (loop per experiment) | Not integrated into experiment-bridge |
| 启智 HPC/CPU | `inspire_submit_hpc` | Not integrated into experiment-bridge |
| Vast.ai | Rent multiple instances | Only 1 instance at a time |
| Modal | `@modal.function .map()` | Only single launcher per call |
| Local | Multi-process, CUDA_VISIBLE_DEVICES | Only 1 GPU at a time |

This skill provides a unified scheduling layer that detects the backend, estimates parallel capacity, and dispatches experiments using the most efficient mechanism for that backend.

## Constants

- **SERIAL_THRESHOLD = 3** — Use serial `/run-experiment` when total jobs ≤ this number. Override via `$ARGUMENTS`.
- **AUTO_DETECT_BACKEND = true** — When `true`, read `CLAUDE.md` to determine backend. When `false`, use the `backend` specified in arguments.
- **ESTIMATE_ONLY = false** — When `true`, generate the deployment plan without executing. Useful for preview before committing GPU hours.

> 💡 Override: `/parallel-experiment-engine "plan" — serial_threshold: 10, backend: inspire, estimate_only: true`

## Workflow

### Phase 1: Parse Experiment List

Read the experiment list from one of:

1. **`refine-logs/EXPERIMENT_PLAN.md`** — extract all experiment blocks with their configs
2. **`refine-logs/EXPERIMENT_TRACKER.md`** — extract TODO runs
3. **Ablation plan** from `/ablation-planner` output
4. **Direct argument** — user provides a list or grid spec

Build an **experiment manifest** — a structured list of all experiments to run:

```json
{
  "experiments": [
    {
      "id": "R001",
      "name": "baseline_wikitext",
      "command": "python train.py --model baseline --dataset wikitext103 --seed 42",
      "milestone": "M1",
      "priority": "MUST-RUN",
      "depends_on": [],
      "estimated_hours": 2.0
    },
    {
      "id": "R002",
      "name": "method_wikitext_s42",
      "command": "python train.py --model our_method --dataset wikitext103 --seed 42",
      "milestone": "M2",
      "priority": "MUST-RUN",
      "depends_on": ["R001"],
      "estimated_hours": 3.0
    }
  ]
}
```

Key fields:
- **`depends_on`**: experiment IDs that must complete first (e.g., method runs after baseline, student after teacher)
- **`priority`**: MUST-RUN experiments are scheduled first; NICE-TO-HAVE fill remaining slots
- **`estimated_hours`**: used for cost estimation and scheduling

### Phase 2: Detect Backend and Capacity

If `AUTO_DETECT_BACKEND = true`, read `CLAUDE.md`:

| CLAUDE.md Setting | Backend | Capacity Detection |
|-------------------|---------|-------------------|
| `gpu: local` | local | `nvidia-smi` GPU count, or MPS |
| `gpu: remote` + SSH alias | ssh | `ssh <server> nvidia-smi` — count free GPUs |
| `gpu: vast` | vast | Read `vast-instances.json` or rent new instances |
| `gpu: modal` | modal | Modal auto-scales — capacity = number of experiments |
| `sii.enable=true` or `启智` mentioned | inspire | `inspire_status` — check free GPUs per compute group |
| HPC/CPU section | inspire-hpc | `inspire_status` — check HPC nodes |

Write capacity to the manifest:

```json
{
  "backend": "inspire",
  "capacity": {
    "compute_group": "lcg-xxx",
    "total_nodes": 8,
    "free_nodes": 5,
    "max_parallel": 5
  }
}
```

### Phase 3: Build Execution Plan

Group experiments into **waves** based on dependencies and capacity:

```
Wave 1 (no dependencies, max_parallel = 5):
  R001: baseline_wikitext        → slot 0
  R003: baseline_penntreebank    → slot 1
  R005: ablation_no_attention    → slot 2
  R007: ablation_no_residual     → slot 3
  R009: seed_sweep_s42           → slot 4

Wave 2 (depends on R001):
  R002: method_wikitext_s42      → slot 0 (after R001)
  R004: method_penntreebank_s42  → slot 1 (after R003)
  ...

Wave 3 (depends on Wave 2):
  ...
```

**Scheduling rules:**

1. Experiments with `depends_on: []` go to Wave 1
2. An experiment goes to Wave N+1 only if all its `depends_on` experiments are in Wave N or earlier
3. Within a wave, schedule up to `max_parallel` experiments simultaneously
4. MUST-RUN experiments take priority over NICE-TO-HAVE within the same wave
5. If total jobs ≤ `SERIAL_THRESHOLD`, flatten to a single wave (simpler execution)

Write the plan to `refine-logs/PARALLEL_PLAN.md`:

```markdown
# Parallel Execution Plan

**Backend**: [backend type]
**Capacity**: [N] parallel slots
**Total experiments**: [M]
**Waves**: [K]

## Wave 1 (experiments: 5, parallel: 5)
| Slot | ID | Name | Est. Hours |
|------|----|------|------------|
| 0 | R001 | baseline_wikitext | 2.0 |
| 1 | R003 | baseline_penntreebank | 1.5 |
| ... |

## Wave 2 (experiments: 3, parallel: 3, waits for: R001, R003)
...

## Estimated Timeline
- Wave 1: 0h → ~2h (slowest experiment)
- Wave 2: ~2h → ~5h
- Total: ~Xh wall-clock (vs ~Yh if serial)
```

### Phase 4: Dispatch

Execute the plan using the appropriate backend mechanism:

#### Backend: `inspire` (启智 GPU)

Loop `inspire_submit` for each experiment in the wave:

```
for each experiment in wave:
  inspire_submit(
    name: "wave1-{experiment_id}",
    command: "{experiment_command}",
    workspace: "{workspace}",
    compute_group: "{compute_group}",
    image: "{image}",
  )
```

Track submitted jobs via `inspire_jobs(status="running")`.

#### Backend: `inspire-hpc` (启智 HPC/CPU)

For CPU-bound experiments:

```
inspire_submit_hpc(
  name: "eval-wave-N",
  entrypoint: "cd /path && bash run_wave_N.sh",
  workspace: "高性能计算",
)
```

#### Backend: `ssh` (Remote server)

Use `/experiment-queue` for proper scheduling:

```bash
# Generate manifest for experiment-queue
cat > experiment_queue/manifest.json << 'EOF'
{
  "project": "research",
  "cwd": "/home/user/experiments",
  "conda": "research",
  "ssh": "gpu-server",
  "gpus": [0, 1, 2, 3],
  "max_parallel": 4,
  "jobs": [
    {"id": "R001", "args": {"model": "baseline", "seed": 42}},
    ...
  ]
}
EOF
```

Delegate to `/experiment-queue` for wave management, OOM retry, and stale screen cleanup.

#### Backend: `modal`

Generate a single launcher that runs experiments in parallel:

```python
@app.function(image=image, gpu="A100-80GB", timeout=3600*6)
def run_experiment(config: dict) -> dict:
    # Run one experiment
    subprocess.run(["python", "train.py"] + config["args"], check=True)
    # Parse and return results
    return results

@app.local_entrypoint()
def main():
    configs = [...]  # All experiments in current wave
    results = list(run_experiment.map(configs))  # Parallel via Modal
```

#### Backend: `vast`

Rent multiple instances if needed:

```bash
# For N parallel slots, rent N instances (or use multi-GPU instance)
for i in $(seq 1 $N); do
  /vast-gpu rent <offer_id>
done

# Deploy one experiment per instance via /run-experiment
```

#### Backend: `local`

Use CUDA_VISIBLE_DEVICES to partition GPUs:

```bash
# GPU 0
CUDA_VISIBLE_DEVICES=0 python train.py --model baseline --seed 42 &

# GPU 1
CUDA_VISIBLE_DEVICES=1 python train.py --model baseline --seed 42 --dataset ptb &

# Wait for all
wait
```

### Phase 5: Wave Orchestration

For multi-wave plans, enforce wave ordering:

1. Deploy Wave 1 experiments
2. Poll for completion (backend-specific):
   - `inspire`: `inspire_jobs(status="running")` or agenda watch with `kind="tool"`
   - `ssh`: read `queue_state.json` from `/experiment-queue`
   - `modal`: `modal app list`
   - `vast`: `ssh` + `screen -ls`
   - `local`: process exit
3. When all Wave N experiments complete:
   - Check results (parse output files)
   - Verify no unexpected failures
   - Deploy Wave N+1
4. Repeat until all waves complete

**Wave transition check:**
- If any MUST-RUN experiment in Wave N **failed** (not OOM-retried, but actually failed) → pause and report before continuing
- If only NICE-TO-HAVE experiments failed → log and continue

### Phase 6: Collect Results

After all waves complete:

1. Parse all result files (JSON/CSV)
2. **Training health check** — for each completed experiment, verify training was healthy:
   - **Check training logs** (stdout, log files, or W&B API) for:
     - NaN/Inf in loss or metrics → mark experiment `unhealthy:nan`
     - Loss spike (>10x increase in a single step after convergence) → mark `unhealthy:spike`
     - Gradient explosion (norm > 1e5) → mark `unhealthy:grad_explode`
     - Loss never decreased (flat line from start to end) → mark `unhealthy:no_learning`
   - **Auto-retry unhealthy experiments** (one attempt each):
     - `nan` or `grad_explode` → reduce learning rate 10x, add gradient clipping (max_norm=1.0), re-run
     - `spike` → add gradient clipping + learning rate warmup, re-run
     - `no_learning` → check if optimizer is stepping, check if requires_grad is set, re-run with higher LR
   - If retry still unhealthy → mark `failed_unhealthy` and log the diagnosis
   - If W&B is configured, also invoke `/training-check` for detailed curve analysis
3. Build the results comparison table
4. Update `refine-logs/EXPERIMENT_TRACKER.md` with final status
5. Write summary:

```markdown
# Parallel Execution Summary

**Backend**: [backend]
**Total experiments**: [M]
**Waves**: [K]
**Wall-clock time**: [X]h (estimated serial: [Y]h, speedup: [Z]x)

## Results
| ID | Name | Metric | Status |
|----|------|--------|--------|
| R001 | baseline_wikitext | 20.5 PPL | ✅ done |
| R002 | method_wikitext_s42 | 18.3 PPL | ✅ done |
| ... | ... | ... | ❌ failed |

## Failed Experiments (if any)
- [R005]: [reason]
```

## Integration with Other Skills

### Called by `/experiment-bridge` (Phase 4)

```
/experiment-bridge
  Phase 2:   Implement code
  Phase 2.5: Code review
  Phase 3:   Sanity check
  Phase 3.5: /baseline-alignment
  Phase 4:   /parallel-experiment-engine  ← replaces /run-experiment
  Phase 5:   Collect results
```

### Called after `/ablation-planner`

When ablation experiments are designed, dispatch them via this skill instead of serial `/run-experiment`.

### Reads from `/baseline-alignment`

If `refine-logs/BASELINE_ALIGNMENT.json` exists and status is `blocked`, **refuse to deploy** — return with a message pointing to the alignment report.

### Read by `/monitor-experiment`

The monitor skill can check parallel execution progress by reading `refine-logs/PARALLEL_PLAN.md` and the backend-specific state.

## Key Rules

- **Always prefer parallel over serial when jobs are independent.** If two experiments don't depend on each other, they should run concurrently.
- **Respect dependency ordering.** Never launch Wave N+1 before all Wave N dependencies are satisfied.
- **Backend-appropriate dispatch.** Don't try to use `screen` sessions on 启智 or `inspire_submit` on a remote SSH server. Each backend has its own natural mechanism — use it.
- **Capacity-aware scheduling.** Don't launch 8 parallel jobs on a 4-GPU server. Detect capacity first, then schedule.
- **MUST-RUN experiments are never skipped.** If a MUST-RUN fails, pause the pipeline and report. NICE-TO-HAVE failures are logged but don't block.
- **Cost awareness.** Before dispatching, show estimated total cost (especially for Vast.ai and Modal). Warn if approaching budget limits.
- **No partial deployment on blocked alignment.** If `/baseline-alignment` says the gate is blocked, do not deploy any experiments. Fix the bug first.
- **Fail fast.** If the first wave's results are catastrophically wrong (all experiments at 10% on a 60% baseline), stop subsequent waves and flag the issue.
