#!/usr/bin/env bash
set -euo pipefail

# ARIS for Synergy — one-click installer
# Usage: curl -sL https://raw.githubusercontent.com/EricSanchezok/Auto-claude-code-research-in-sleep/main/install.sh | bash
#   Or:  bash install.sh [--uninstall]

UNINSTALL=false
[[ "${1:-}" == "--uninstall" ]] && UNINSTALL=true

SYNERGY_HOME="${SYNERGY_HOME:-$HOME/.synergy}"
SKILLS_DIR="$SYNERGY_HOME/config/skills"
AGENTS_DIR="$SYNERGY_HOME/config/agent"
ARIS_REPO="https://github.com/EricSanchezok/Auto-claude-code-research-in-sleep.git"
ARIS_DIR="$SYNERGY_HOME/aris"  # Persistent clone location

# Resolve script directory (works when run via curl or locally)
SCRIPT_DIR="$(cd "$(dirname "$0")" 2>/dev/null && pwd)" || true
if [[ -f "$SCRIPT_DIR/SYNERGY_ADAPTATION.md" ]]; then
  # Running from a local clone — use it directly
  ARIS_DIR="$SCRIPT_DIR"
else
  # Running via curl or from outside the repo — clone/pull to persistent location
  if [[ -d "$ARIS_DIR/.git" ]]; then
    echo "🔄 Updating ARIS (git pull)..."
    git -C "$ARIS_DIR" pull --ff-only || {
      echo "⚠️  git pull failed. Trying fresh clone..."
      rm -rf "$ARIS_DIR"
      git clone --depth 1 "$ARIS_REPO" "$ARIS_DIR"
    }
  else
    echo "📦 Cloning ARIS for Synergy..."
    rm -rf "$ARIS_DIR"
    git clone --depth 1 "$ARIS_REPO" "$ARIS_DIR"
  fi
fi

if $UNINSTALL; then
  echo "🗑️  Uninstalling ARIS skills and agents..."

  # Remove skills that came from ARIS
  for target in "$SKILLS_DIR"/*/; do
    [[ -d "$target" ]] || continue
    skill_name=$(basename "$target")
    # Check if it's an ARIS skill (exists in the repo)
    if [[ -d "$ARIS_DIR/skills/$skill_name" ]]; then
      rm -rf "$target"
      echo "  removed: $skill_name"
    fi
  done

  # Remove agents
  for agent in reviewer.md auditor.md; do
    if [[ -f "$AGENTS_DIR/$agent" ]]; then
      rm "$AGENTS_DIR/$agent"
      echo "  removed agent: $agent"
    fi
  done

  # Remove the persistent clone
  if [[ -d "$ARIS_DIR" ]] && [[ "$ARIS_DIR" != "$SCRIPT_DIR" ]]; then
    rm -rf "$ARIS_DIR"
    echo "  removed repo: $ARIS_DIR"
  fi

  echo "✅ ARIS uninstalled."
  exit 0
fi

echo "⚔️🌙 Installing ARIS for Synergy..."
echo ""

# Create directories
mkdir -p "$SKILLS_DIR" "$AGENTS_DIR"

# Install skills (symlink if possible, copy as fallback)
installed=0
skipped=0
if [[ -d "$ARIS_DIR/skills" ]]; then
  for skill_dir in "$ARIS_DIR/skills"/*/; do
    skill_name=$(basename "$skill_dir")
    target="$SKILLS_DIR/$skill_name"

    if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
      echo "  ⏭️  $skill_name (already exists, skipping)"
      ((skipped++)) || true
      continue
    fi

    # Remove stale symlink from old install
    [[ -L "$target" ]] && rm "$target"

    # Symlink — allows updates via git pull on the persistent clone
    if ln -s "$skill_dir" "$target" 2>/dev/null; then
      echo "  🔗 $skill_name (symlinked)"
    else
      cp -r "$skill_dir" "$target"
      echo "  📋 $skill_name (copied)"
    fi
    ((installed++)) || true
  done
fi

# Install shared-references
if [[ -d "$ARIS_DIR/skills/shared-references" ]]; then
  target="$SKILLS_DIR/shared-references"
  [[ -L "$target" ]] && rm "$target"
  if ln -s "$ARIS_DIR/skills/shared-references" "$target" 2>/dev/null; then
    echo "  🔗 shared-references (symlinked)"
  else
    cp -r "$ARIS_DIR/skills/shared-references" "$target"
    echo "  📋 shared-references (copied)"
  fi
  ((installed++)) || true
fi

# Install agents
for agent in "$ARIS_DIR/agents"/*.md; do
  [[ -f "$agent" ]] || continue
  agent_name=$(basename "$agent")
  cp "$agent" "$AGENTS_DIR/$agent_name"
  echo "  🤖 $agent_name"
  ((installed++)) || true
done

echo ""
echo "✅ Installed: $installed skills/agents ($skipped skipped — already existed)"
echo ""
echo "To update:  curl -sL https://raw.githubusercontent.com/EricSanchezok/Auto-claude-code-research-in-sleep/main/install.sh | bash"
echo "To remove:  curl -sL https://raw.githubusercontent.com/EricSanchezok/Auto-claude-code-research-in-sleep/main/install.sh | bash -s -- --uninstall"
