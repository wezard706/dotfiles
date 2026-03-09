#!/bin/bash
set -e

# Dotfiles Installer
# This script installs:
#   - Claude Code skills, CLAUDE.md, rules, and settings.json
# Run this script from the cloned repository directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/.claude"
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
RULES_DIR="$CLAUDE_DIR/rules"
GIT_SOURCE_DIR="$SCRIPT_DIR/git"

echo "Installing dotfiles..."
echo ""

# Install git aliases
echo "🔧 Installing git aliases..."
cp "$GIT_SOURCE_DIR/.gitconfig.aliases" "$HOME/.gitconfig.aliases"
if ! grep -q 'path = ~/.gitconfig.aliases' "$HOME/.gitconfig" 2>/dev/null; then
    printf '\n[include]\n\tpath = ~/.gitconfig.aliases\n' >> "$HOME/.gitconfig"
fi
echo ""

# Check if source directory exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "❌ Error: .claude directory not found in $SCRIPT_DIR"
    echo "Please run this script from the dotfiles repository directory."
    exit 1
fi

# Clean and recreate directories
echo "🧹 Cleaning existing configurations..."
rm -rf "$SKILLS_DIR"
mkdir -p "$SKILLS_DIR"
rm -rf "$RULES_DIR"
mkdir -p "$RULES_DIR"

# Install CLAUDE.md
echo "📝 Installing CLAUDE.md..."
cp "$SOURCE_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

# Install settings.json
echo "⚙️  Installing settings.json..."
cp "$SOURCE_DIR/settings.json" "$CLAUDE_DIR/settings.json"

# Install rules
echo ""
echo "📋 Installing rules..."
for rule_file in "$SOURCE_DIR"/rules/*.md; do
    if [ -f "$rule_file" ]; then
        rule_name=$(basename "$rule_file")
        echo "   Installing rule: $rule_name"
        cp "$rule_file" "$RULES_DIR/$rule_name"
    fi
done

# Install skills
echo ""
echo "📚 Installing skills..."
for skill_dir in "$SOURCE_DIR"/skills/*/; do
    if [ -d "$skill_dir" ]; then
        skill_name=$(basename "$skill_dir")
        dest_dir="$SKILLS_DIR/$skill_name"
        echo "   Installing skill: $skill_name"
        cp -r "$skill_dir" "$dest_dir"
    fi
done

echo ""
echo "Installation complete!"
echo ""
echo "Installed files:"
echo "  - $HOME/.gitconfig.aliases"
echo "  - $CLAUDE_DIR/CLAUDE.md"
echo "  - $CLAUDE_DIR/settings.json"
for rule_file in "$RULES_DIR"/*.md; do
    if [ -f "$rule_file" ]; then
        echo "  - $rule_file"
    fi
done
for skill_dir in "$SKILLS_DIR"/*/; do
    if [ -d "$skill_dir" ]; then
        echo "  - $skill_dir"
    fi
done
echo ""
echo "Claude Code skills:"
for skill_dir in "$SKILLS_DIR"/*/; do
    if [ -d "$skill_dir" ]; then
        skill_name=$(basename "$skill_dir")
        skill_file="$skill_dir/SKILL.md"
        if [ -f "$skill_file" ]; then
            description=$(grep -m1 "^description:" "$skill_file" | sed 's/^description:[[:space:]]*//')
            printf "  %-18s - %s\n" "$skill_name" "$description"
        fi
    fi
done
