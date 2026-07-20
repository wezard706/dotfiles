#!/bin/bash
set -e

# Dotfiles Installer
# This script installs:
#   - Claude Code skills, CLAUDE.md, and rules
#   - Codex AGENTS.md
# Run this script from the cloned repository directory

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/.claude"
AGENTS_SOURCE_DIR="$SCRIPT_DIR/.agents"
CLAUDE_DIR="$HOME/.claude"
SKILLS_DIR="$CLAUDE_DIR/skills"
RULES_DIR="$CLAUDE_DIR/rules"
GIT_SOURCE_DIR="$SCRIPT_DIR/git"
CODEX_DIR="$HOME/.codex"
AGENTS_DIR="$HOME/.agents"

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

# Clean and recreate rules directory; preserve existing skills
echo "🧹 Cleaning existing rule configurations..."
rm -rf "$RULES_DIR"
mkdir -p "$RULES_DIR"
mkdir -p "$SKILLS_DIR"

# Install CLAUDE.md (.agents/AGENTS.md を正本とするコピー)
echo "📝 Installing CLAUDE.md..."
cp "$AGENTS_SOURCE_DIR/AGENTS.md" "$CLAUDE_DIR/CLAUDE.md"

# Install rules
echo ""
echo "📋 Installing rules..."
for rule_file in "$AGENTS_SOURCE_DIR"/rules/*.md; do
    if [ -f "$rule_file" ]; then
        rule_name=$(basename "$rule_file")
        echo "   Installing rule: $rule_name"
        cp "$rule_file" "$RULES_DIR/$rule_name"
    fi
done

# Install skills (正本は .agents/skills)
echo ""
echo "📚 Installing skills..."
for skill_dir in "$AGENTS_SOURCE_DIR"/skills/*/; do
    if [ -d "$skill_dir" ]; then
        skill_name=$(basename "$skill_dir")
        dest_dir="$SKILLS_DIR/$skill_name"
        echo "   Installing skill: $skill_name"
        cp -r "$skill_dir" "$dest_dir"
    fi
done

# Install hooks and wire them into settings.json so they fire in every project.
# Hook スクリプトを ~/.claude/hooks/ に配置し、PostToolUse 配線を
# ~/.claude/settings.json へマージする。他キー・他フックは保全し、
# 同一コマンドの重複は除くため再実行しても冪等。
if [ -d "$SOURCE_DIR/hooks" ]; then
    echo ""
    echo "🪝 Installing hooks..."
    HOOKS_DIR="$CLAUDE_DIR/hooks"
    mkdir -p "$HOOKS_DIR"
    SETTINGS_FILE="$CLAUDE_DIR/settings.json"
    [ -f "$SETTINGS_FILE" ] || echo '{}' > "$SETTINGS_FILE"
    for hook_file in "$SOURCE_DIR"/hooks/*.rb; do
        [ -f "$hook_file" ] || continue
        hook_name=$(basename "$hook_file")
        echo "   Installing hook: $hook_name"
        cp "$hook_file" "$HOOKS_DIR/$hook_name"
        chmod +x "$HOOKS_DIR/$hook_name"
        hook_cmd="ruby \"$HOOKS_DIR/$hook_name\""
        jq --arg cmd "$hook_cmd" '
          .hooks //= {} |
          .hooks.PostToolUse //= [] |
          .hooks.PostToolUse |= (
            map(select((.hooks // []) | any(.command == $cmd) | not))
            + [{"matcher": "Edit|Write|MultiEdit", "hooks": [{"type": "command", "command": $cmd}]}]
          )
        ' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE"
    done
fi

# Install Codex configuration.
# ~/.codex/config.toml はローカル状態（認証・trust・marketplaceパス等）を含むため
# このスクリプトでは一切触らない。
echo ""
echo "🤖 Installing Codex configuration..."
mkdir -p "$CODEX_DIR"

# AGENTS.md は .agents/AGENTS.md をヘッダに .agents/rules/*.md を連結して生成する。
# rules の paths frontmatter は Codex に相当機構がないため、
# 先頭見出し直後の「このセクションは〜に適用する」文へ変換する。
{
    cat "$AGENTS_SOURCE_DIR/AGENTS.md"
    for rule_file in "$AGENTS_SOURCE_DIR"/rules/*.md; do
        [ -f "$rule_file" ] || continue
        echo ""
        awk '
            FNR == 1 && $0 == "---" { in_fm = 1; next }
            in_fm && $0 == "---" { in_fm = 0; next }
            in_fm {
                if (match($0, /"[^"]+"/)) {
                    pat = substr($0, RSTART + 1, RLENGTH - 2)
                    pats = pats (pats == "" ? "" : ", ") "`" pat "`"
                }
                next
            }
            !scope_done && /^# / {
                print
                if (pats != "") {
                    print ""
                    print "このセクションは " pats " に該当するファイルを扱うときに適用する。"
                }
                scope_done = 1
                next
            }
            { print }
        ' "$rule_file"
    done
} > "$CODEX_DIR/AGENTS.md"
echo "   Generated AGENTS.md"

# 共有スキルを ~/.agents/skills/ へ配置する。Codex はこのディレクトリを
# スキル探索パスとして読むが Claude Code は読まないため、Claude 向けには
# 上の skills セクションで ~/.claude/skills/ へも配置している。
# skills CLI 等で導入済みの他スキルを保全するため、スキル単位で上書きコピーする。
mkdir -p "$AGENTS_DIR/skills"
for skill_dir in "$AGENTS_SOURCE_DIR"/skills/*/; do
    if [ -d "$skill_dir" ]; then
        skill_name=$(basename "$skill_dir")
        echo "   Installing shared skill: $skill_name"
        cp -r "$skill_dir" "$AGENTS_DIR/skills/$skill_name"
    fi
done

echo ""
echo "Installation complete!"
echo ""
echo "Installed files:"
echo "  - $HOME/.gitconfig.aliases"
echo "  - $CLAUDE_DIR/CLAUDE.md"
echo "  - $CODEX_DIR/AGENTS.md"
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
