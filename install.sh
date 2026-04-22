#!/bin/bash

# Claude Code Skills & Commands Installer (Linux/Mac)
#
# Usage:
#   ./install.sh                            # Global install (symlinks to ~/.claude/)
#   ./install.sh --project                  # Per-project install (copies to ./.claude/, gitignored by default)
#   ./install.sh --project /path/to/repo    # Per-project install into a specific dir
#   ./install.sh --project --no-gitignore   # Per-project install WITHOUT gitignoring (commit & share with team)
#   ./install.sh --project --symlink        # Per-project install using symlinks (solo dev only; implies --no-gitignore-relevant-only)
#
# Global install is shared across every project and updates live via `git pull`.
# Per-project install copies files into the project's `.claude/` folder and
# automatically adds .claude/skills/ and .claude/commands/ to .gitignore so
# they don't end up in the project's git history. Pass --no-gitignore to keep
# them out of .gitignore (e.g., if you want to commit them to share with a team).

set -e

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Parse args ---
MODE="global"
TARGET_DIR=""
USE_SYMLINK=false
ADD_GITIGNORE=true   # default ON for --project

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project|--local)
            MODE="project"
            shift
            ;;
        --symlink)
            USE_SYMLINK=true
            shift
            ;;
        --no-gitignore)
            ADD_GITIGNORE=false
            shift
            ;;
        --gitignore)
            # Back-compat — was required in the first version, now the default
            ADD_GITIGNORE=true
            shift
            ;;
        --global)
            MODE="global"
            shift
            ;;
        -h|--help)
            sed -n '3,16p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        -*)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
        *)
            TARGET_DIR="$1"
            shift
            ;;
    esac
done

# --- Resolve install target ---
if [ "$MODE" = "project" ]; then
    if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$(pwd)"
    fi
    TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
    SKILLS_DIR="$TARGET_DIR/.claude/skills"
    COMMANDS_DIR="$TARGET_DIR/.claude/commands"
    LOCATION_LABEL="project ($TARGET_DIR)"
else
    SKILLS_DIR="$HOME/.claude/skills"
    COMMANDS_DIR="$HOME/.claude/commands"
    LOCATION_LABEL="global (~/.claude)"
    USE_SYMLINK=true  # Global install always uses symlinks (for git pull updates)
fi

echo "📦 Claude Code Skills & Commands Installer"
echo "   From:    $REPO_DIR"
echo "   To:      $LOCATION_LABEL"
echo "   Method:  $([ "$USE_SYMLINK" = true ] && echo "symlink" || echo "copy")"
echo ""

if [ "$MODE" = "project" ] && [ "$TARGET_DIR" = "$REPO_DIR" ]; then
    echo "⚠️  Refusing to install into the skills repo itself."
    echo "   Run this from inside your project, or pass the project path:"
    echo "     $0 --project /path/to/your/project"
    exit 1
fi

mkdir -p "$SKILLS_DIR"
mkdir -p "$COMMANDS_DIR"

install_item() {
    # install_item <source> <target>
    local source="$1"
    local target="$2"

    # Remove existing target (symlink, file, or directory) so we can replace it
    if [ -L "$target" ]; then
        rm "$target"
    elif [ -e "$target" ]; then
        if [ "$USE_SYMLINK" = true ]; then
            echo "⚠️  Exists and is not a symlink — skipping: $target" >&2
            return 1
        fi
        # Copy mode — safe to overwrite
        rm -rf "$target"
    fi

    if [ "$USE_SYMLINK" = true ]; then
        ln -s "$source" "$target"
    else
        cp -R "$source" "$target"
    fi
}

# --- Install skills ---
installed_skills=0
if [ -d "$REPO_DIR/skills" ]; then
    for skill_path in "$REPO_DIR"/skills/*/SKILL.md; do
        [ -e "$skill_path" ] || { echo "⚠️  No skills found in skills/"; break; }
        skill=$(basename "$(dirname "$skill_path")")
        [[ "$skill" == .* ]] && continue

        if install_item "$REPO_DIR/skills/$skill" "$SKILLS_DIR/$skill"; then
            echo "✅ Installed skill: $skill"
            installed_skills=$((installed_skills + 1))
        fi
    done
fi

# --- Install commands ---
installed_commands=0
if [ -d "$REPO_DIR/commands" ]; then
    for command_file in "$REPO_DIR"/commands/*.md; do
        [ -e "$command_file" ] || { echo "⚠️  No commands found in commands/"; break; }
        command=$(basename "$command_file")

        if install_item "$REPO_DIR/commands/$command" "$COMMANDS_DIR/$command"; then
            echo "✅ Installed command: ${command%.md}"
            installed_commands=$((installed_commands + 1))
        fi
    done
fi

echo ""
echo "📝 Installation complete:"
echo "   - $installed_skills skill(s) installed to $SKILLS_DIR"
echo "   - $installed_commands command(s) installed to $COMMANDS_DIR"
echo ""

if [ "$MODE" = "project" ]; then
    # Add to .gitignore by default (opt out with --no-gitignore)
    if [ "$ADD_GITIGNORE" = true ]; then
        gitignore="$TARGET_DIR/.gitignore"
        marker="# Claude Code skills and commands (installed locally)"
        if [ -f "$gitignore" ] && grep -qF "$marker" "$gitignore"; then
            echo "ℹ️  .gitignore already has entries for .claude/skills and .claude/commands"
        else
            {
                echo ""
                echo "$marker"
                echo ".claude/skills/"
                echo ".claude/commands/"
            } >> "$gitignore"
            echo "✅ Added .claude/skills/ and .claude/commands/ to .gitignore"
        fi
    fi

    echo ""
    echo "Next steps:"
    echo "  - Skills and commands are available inside: $TARGET_DIR"
    if [ "$ADD_GITIGNORE" = true ]; then
        echo "  - .claude/skills/ and .claude/commands/ are gitignored — not committed to this repo"
        echo "  - Teammates will need to run this install themselves"
        echo "  - To share with the team via git instead: re-run with --no-gitignore and commit the folders"
    else
        echo "  - .claude/skills/ and .claude/commands/ are NOT gitignored — commit them to share with teammates:"
        echo "      git add .claude/skills .claude/commands && git commit -m \"chore: add Claude Code skills and commands\""
    fi
    echo "  - For agile-board: python $REPO_DIR/skills/agile-board/scripts/setup.py"
    if [ "$USE_SYMLINK" = false ]; then
        echo "  - To update: re-run this script after 'git pull' in $REPO_DIR"
    else
        echo "  - To update: git pull in $REPO_DIR (symlinks track automatically)"
    fi
else
    echo "Next steps:"
    echo "  - Skills and commands are now available globally for all projects"
    echo "  - For agile-board: python $REPO_DIR/skills/agile-board/scripts/setup.py  (run inside each project)"
    echo "  - To update: git pull in $REPO_DIR  (symlinks track automatically)"
fi
