# ARIS Skill Update: 同步、自定义与冲突解决

更新、自定义和修复 ARIS 科研 skill 集合。

## 上下文: $ARGUMENTS

## 架构概览

```
/root/.synergy/config/skills/<skill>/  ← Synergy 加载 skill 的目录
        ↓ (symlink)
/root/.synergy/aris/skills/<skill>/    ← git repo 里的实际文件
/root/.synergy/aris/                   ← git clone of EricSanchezok/Auto-claude-code-research-in-sleep
```

**关键事实**: 所有 skill 都通过 symlink 指向 aris repo。因此 `git pull` 就能更新，无需重新 install。

## 已知的本地自定义

| Skill | 改动内容 | 状态 |
|-------|---------|------|
| `paper-illustration` | Gemini API → SII 代理 (`apicz.boyuerichdata.com`), `GEMINI_API_KEY` → `SII_API_KEY`, URL param auth → `x-goog-api-key` header | ✅ 已 commit + push |
| `paper-writing` | 仍引用 `GEMINI_API_KEY`（第 32、162 行，仅为文档说明） | ⏸️ 暂未改，无功能影响 |

### paper-illustration 改动细节

```
# 3 处 API 调用全部修改:
1. Layout optimization (gemini-3-pro-preview)
2. Style verification (gemini-3-pro-preview)
3. Image generation (gemini-3-pro-image-preview)

# 每处修改模式相同:
- API_KEY="${GEMINI_API_KEY}"  →  API_KEY="${SII_API_KEY}"
- URL="https://generativelanguage.googleapis.com/v1beta/models/...?key=$API_KEY"
  → URL="https://apicz.boyuerichdata.com/v1beta/models/..."
- 新增 header: -H "x-goog-api-key: $API_KEY"
- URL 参数中的 ?key=$API_KEY 移除
```

## 工作流

### 步骤 1: 检查当前状态

```bash
# 检查 aris repo 状态
cd /root/.synergy/aris
git status
git branch -v

# 检查 symlink 健康状态
total=$(ls -d /root/.synergy/config/skills/*/ 2>/dev/null | wc -l)
symlinks=$(find /root/.synergy/config/skills/ -maxdepth 1 -type l | wc -l)
echo "Skills: $total, Symlinks: $symlinks"

# 检查是否有非 symlink 的 skill（说明 symlink 损坏）
for d in /root/.synergy/config/skills/*/; do
  [ ! -L "$d" ] && echo "BROKEN (not symlink): $(basename $d)"
done

# 检查本地未提交的修改
git diff --name-only
```

### 步骤 2: 拉取上游更新

```bash
cd /root/.synergy/aris
git fetch origin
git pull origin main
```

**如果无冲突**: 直接完成，skill 已更新（因为 symlink）。

**如果有冲突**: 进入步骤 3。

### 步骤 3: 解决冲突

上游可能更新了我们自定义过的 `paper-illustration/SKILL.md`，此时会产生 merge conflict。

**冲突解决原则**:
- **保留 SII 代理配置**: `SII_API_KEY`、`apicz.boyuerichdata.com`、`x-goog-api-key` header
- **采纳上游其他改进**: 新的 prompt 模板、新的质量检查步骤等
- 每次解决后验证所有 3 处 API 调用都仍是 SII 代理

```bash
# 查看冲突文件
git diff --name-only --diff-filter=U

# 解决冲突后
git add -A
git commit -m "merge: upstream updates with SII proxy preserved"
git push origin main
```

**冲突解决验证**:
```bash
# 确认 SII 代理配置完整
grep -c "SII_API_KEY" skills/paper-illustration/SKILL.md     # 应 ≥ 3
grep -c "apicz.boyuerichdata.com" skills/paper-illustration/SKILL.md  # 应 ≥ 3
grep -c "x-goog-api-key" skills/paper-illustration/SKILL.md  # 应 ≥ 3
grep -c "GEMINI_API_KEY" skills/paper-illustration/SKILL.md   # 应 = 0
```

### 步骤 4: 应用新的本地自定义

如果需要新增或修改其他 skill 走 SII 代理:

```bash
# 编辑 skill（因为 symlink，直接改的就是 aris 目录里的文件）
vim /root/.synergy/aris/skills/<skill>/SKILL.md

# 提交并推送
cd /root/.synergy/aris
git add -A
git commit -m "feat: <描述改动>"
git push origin main
```

**新增 SII 代理的标准模式**:
```bash
# 在 SKILL.md 中替换以下内容:
# 1. 环境变量
API_KEY="${GEMINI_API_KEY}"  →  API_KEY="${SII_API_KEY}"

# 2. API URL (移除 ?key= 参数)
URL="https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent?key=$API_KEY"
→ URL="https://apicz.boyuerichdata.com/v1beta/models/<model>:generateContent"

# 3. curl 调用 (添加 header，移除 URL 中的 key)
curl -s -X POST "$URL" \
  -H 'Content-Type: application/json' \
  -H "x-goog-api-key: $API_KEY" \    # 新增此行
  -d @/tmp/request.json

# 4. 环境变量检查
if [ -z "$GEMINI_API_KEY" ]  →  if [ -z "$SII_API_KEY" ]
```

### 步骤 5: 修复损坏的 Symlink

如果某些 skill 变成了独立副本而非 symlink（比如手动创建了目录），需要修复:

```bash
# 1. 找到损坏的 skill
for d in /root/.synergy/config/skills/*/; do
  [ ! -L "$d" ] && echo "NOT symlink: $(basename $d)"
done

# 2. 对每个损坏的 skill，先检查本地是否有未提交的修改
# （比较与 aris 目录的差异）
diff -rq /root/.synergy/config/skills/<skill>/ /root/.synergy/aris/skills/<skill>/

# 3. 如果有本地修改，先同步到 aris
cp -r /root/.synergy/config/skills/<skill>/* /root/.synergy/aris/skills/<skill>/
cd /root/.synergy/aris && git add -A && git commit -m "preserve local changes for <skill>"

# 4. 删除副本，重建 symlink
rm -rf /root/.synergy/config/skills/<skill>
ln -s /root/.synergy/aris/skills/<skill> /root/.synergy/config/skills/<skill>

# 5. 验证
ls -la /root/.synergy/config/skills/<skill>
readlink -f /root/.synergy/config/skills/<skill>
# 应输出: /root/.synergy/aris/skills/<skill>
```

### 步骤 6: 完全重装（最后手段）

仅在 symlink 大面积损坏或目录结构异常时使用:

```bash
# ⚠️ 这会覆盖所有本地修改！先确保已 commit
cd /root/.synergy/aris
git status  # 确认无未提交修改

# 删除所有 skill 目录（symlink 和副本都删）
rm -rf /root/.synergy/config/skills/*

# 重新安装
bash /root/.synergy/aris/install.sh
```

### 步骤 7: 重新加载 Synergy Runtime

更新 skill 文件后，需要让 Synergy 重新加载才能生效:

```
runtime_reload(target: "skill")
```

## 快速参考

| 场景 | 命令 |
|------|------|
| 日常更新 | `cd /root/.synergy/aris && git pull origin main` |
| 查看本地修改 | `cd /root/.synergy/aris && git diff --name-only` |
| 提交本地自定义 | `cd /root/.synergy/aris && git add -A && git commit -m "feat: xxx" && git push` |
| 检查 symlink 健康 | `find /root/.synergy/config/skills/ -maxdepth 1 ! -type l -type d` |
| 修复单个 symlink | `rm -rf /root/.synergy/config/skills/<name> && ln -s /root/.synergy/aris/skills/<name> /root/.synergy/config/skills/<name>` |
| 完全重装 | `rm -rf /root/.synergy/config/skills/* && bash /root/.synergy/aris/install.sh` |
| 重载 Synergy | `runtime_reload(target: "skill")` |

## 关键规则

- **永远不要在 `/root/.synergy/config/skills/` 里直接改文件** — 改的是 `/root/.synergy/aris/skills/`（因为 symlink 指向那里）
- **每次 git pull 后检查冲突** — 尤其是自定义过的 `paper-illustration`
- **冲突解决优先保留 SII 代理配置** — 上游用的是直连 Gemini，我们需要走代理
- **commit 前 grep 验证** — 确保 SII 代理配置完整无遗漏
- **不要运行 install.sh 除非 symlink 损坏** — install.sh 会 skip 已存在的目录，可能产生混乱
