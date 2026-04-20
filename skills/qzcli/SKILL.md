---
name: qzcli
description: "DEPRECATED: Use the built-in sii-inspire skill and native inspire_* tools instead. This skill is retained only for backward compatibility with existing workflows that reference /qzcli."
argument-hint: [command]
allowed-tools: inspire_status, inspire_submit, inspire_submit_hpc, inspire_stop, inspire_jobs, inspire_job_detail, inspire_config, inspire_images, inspire_image_push
---

# qzcli — DEPRECATED

> **This skill is deprecated.** The 启智平台 integration is now built into Synergy as native tools (`inspire_*`). Use the `sii-inspire` skill instead.

## Migration

| Old (qzcli CLI) | New (Synergy native) |
|------------------|---------------------|
| `qzcli login` | `synergy sii inspire login` (CLI) — or credentials auto-managed |
| `qzcli avail` | `inspire_status(workspace="分布式训练空间")` |
| `qzcli create --name X --command Y` | `inspire_submit(name="X", command="Y")` |
| `qzcli hpc --name X --entrypoint Y` | `inspire_submit_hpc(name="X", entrypoint="Y")` |
| `qzcli stop <job-id>` | `inspire_stop(job_id="...")` |
| `qzcli ls` | `inspire_jobs()` |
| `qzcli detail <job-id>` | `inspire_job_detail(job_id="...")` |
| `qzcli batch config.json` | Loop `inspire_submit` per experiment |
| `qzcli watch` | `agenda_create` with watch trigger on `inspire_jobs` |

## Setup

Enable in `synergy.jsonc`:
```jsonc
{ "sii": { "enable": true } }
```

Configure credentials:
```bash
synergy sii inspire login    # 启智平台账号
synergy sii harbor login     # Harbor 镜像仓库账号
```

Set defaults to simplify repeated use:
```
inspire_config(action="set", key="defaultProject", value="项目名")
inspire_config(action="set", key="defaultWorkspace", value="分布式训练空间")
inspire_config(action="set", key="commandPrefix", value="source /opt/conda/etc/profile.d/conda.sh && conda activate myenv && cd /inspire/hdd/project/{en_name}/code")
```

For the full guide, load the `sii-inspire` skill.
