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
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# If running via curl, clone first
if [[ ! -f "$SCRIPT_DIR/SYNERGY_ADAPTATION.md" ]]; then
  echo "📦 Cloning ARIS for Synergy..."
  TMPDIR=$(mktemp -d)
  git clone --depth 1 https://github.com/EricSanchezok/Auto-claude-code-research-in-sleep.git "$TMPDIR/aris"
  SCRIPT_DIR="$TMPDIR/aris"
  trap 'rm -rf "$TMPDIR"' EXIT
fi

if $UNINSTALL; then
  echo "🗑️  Uninstalling ARIS skills and agents..."

  # Remove skills that came from ARIS
  if [[ -d "$SCRIPT_DIR/skills" ]]; then
    for skill_dir in "$SCRIPT_DIR/skills"/*/; do
      skill_name=$(basename "$skill_dir")
      [[ "$skill_name" == shared-references ]] && continue
      target="$SKILLS_DIR/$skill_name"
      if [[ -L "$target" ]]; then
        rm "$target"
        echo "  removed symlink: $skill_name"
      elif [[ -d "$target" ]]; then
        # Only remove if it looks like an ARIS skill (has SKILL.md)
        if [[ -f "$target/SKILL.md" ]]; then
          rm -rf "$target"
          echo "  removed: $skill_name"
        fi
      fi
    done
  fi

  # Remove shared-references
  if [[ -d "$SKILLS_DIR/shared-references" ]]; then
    rm -rf "$SKILLS_DIR/shared-references"
    echo "  removed: shared-references"
  fi

  # Remove agents
  for agent in reviewer.md auditor.md; do
    if [[ -f "$AGENTS_DIR/$agent" ]]; then
      rm "$AGENTS_DIR/$agent"
      echo "  removed agent: $agent"
    fi
  done

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
if [[ -d "$SCRIPT_DIR/skills" ]]; then
  for skill_dir in "$SCRIPT_DIR/skills"/*/; do
    skill_name=$(basename "$skill_dir")
    target="$SKILLS_DIR/$skill_name"

    if [[ -e "$target" ]] && [[ ! -L "$target" ]]; then
      echo "  ⏭️  $skill_name (already exists, skipping)"
      ((skipped++)) || true
      continue
    fi

    # Remove stale symlink
    [[ -L "$target" ]] && rm "$target"

    # Try symlink first (allows git pull to update)
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
if [[ -d "$SCRIPT_DIR/skills/shared-references" ]]; then
  target="$SKILLS_DIR/shared-references"
  [[ -L "$target" ]] && rm "$target"
  if ln -s "$SCRIPT_DIR/skills/shared-references" "$target" 2>/dev/null; then
    echo "  🔗 shared-references (symlinked)"
  else
    cp -r "$SCRIPT_DIR/skills/shared-references" "$target"
    echo "  📋 shared-references (copied)"
  fi
  ((installed++)) || true
fi

# Install agents
for agent in "$SCRIPT_DIR/agents"/*.md; do
  [[ -f "$agent" ]] || continue
  agent_name=$(basename "$agent")
  cp "$agent" "$AGENTS_DIR/$agent_name"
  echo "  🤖 $agent_name"
  ((installed++)) || true
done

echo ""
echo "✅ Installed: $installed skills/agents ($skipped skipped — already existed)"
echo ""
echo "Next steps:"
echo "  1. Reload Synergy config:  runtime_reload(target='all')"
echo "  2. Try a workflow:         /research-pipeline \"your research direction\""
echo ""
echo "To uninstall:  bash install.sh --uninstall"
