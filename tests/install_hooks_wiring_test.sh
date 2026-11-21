#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_jq() {
  actual=$(jq -r "$2" "$1")
  [ "$actual" = "$3" ] || fail "$4: expected '$3', got '$actual' (query: $2)"
}

# install.sh 全体はスキル取得まで走るため、フック配線ブロックだけを install.sh の
# 本文から切り出して実行する（配線ロジックの複製を避ける）。
extract_hooks_block() {
  start=$(grep -n '^# Install hooks and wire them' "$ROOT_DIR/install.sh" | cut -d: -f1)
  [ -n "$start" ] || fail "hooks block not found in install.sh"
  end=$(awk -v s="$start" 'NR > s && /^fi$/ { print NR; exit }' "$ROOT_DIR/install.sh")
  [ -n "$end" ] || fail "hooks block terminator not found in install.sh"
  sed -n "${start},${end}p" "$ROOT_DIR/install.sh"
}

run_wiring() {
  CLAUDE_DIR="$1" SOURCE_DIR="$2" bash -c "set -euo pipefail
    CLAUDE_DIR=\"\$CLAUDE_DIR\"
    SOURCE_DIR=\"\$SOURCE_DIR\"
    $(extract_hooks_block)" > /dev/null
}

CLAUDE_HOME="$TEST_ROOT/claude"
mkdir -p "$CLAUDE_HOME"
SETTINGS="$CLAUDE_HOME/settings.json"

# 他キー・既存フックを保全することを確かめるため、先行設定を置いてから実行する。
cat > "$SETTINGS" <<'JSON'
{
  "model": "opus",
  "hooks": {
    "PostToolUse": [
      {"matcher": "Bash", "hooks": [{"type": "command", "command": "echo foreign"}]}
    ]
  }
}
JSON

echo "== 実リポジトリのフックがイベント別に配線される =="
run_wiring "$CLAUDE_HOME" "$ROOT_DIR/.claude"
assert_jq "$SETTINGS" '[.hooks.PreToolUse[].hooks[].command | select(test("require-test-skills"))] | length' '1' "PreToolUse wiring"
assert_jq "$SETTINGS" '[.hooks.PostToolUse[].hooks[].command | select(test("check-ruby-comments"))] | length' '1' "PostToolUse wiring"
assert_jq "$SETTINGS" '.hooks.PreToolUse[] | select(.hooks[].command | test("require-test-skills")) | .matcher' 'Edit|Write|MultiEdit' "PreToolUse matcher"
assert_jq "$SETTINGS" '[.hooks.PostToolUse[].hooks[].command | select(test("require-test-skills"))] | length' '0' "PreToolUse hook must not land in PostToolUse"
[ -x "$CLAUDE_HOME/hooks/require-test-skills.rb" ] || fail "hook script not installed as executable"

echo "== 他キー・無関係フックは保全される =="
assert_jq "$SETTINGS" '.model' 'opus' "unrelated key preserved"
assert_jq "$SETTINGS" '[.hooks.PostToolUse[].hooks[].command | select(. == "echo foreign")] | length' '1' "foreign hook preserved"

echo "== 再実行しても重複しない =="
run_wiring "$CLAUDE_HOME" "$ROOT_DIR/.claude"
run_wiring "$CLAUDE_HOME" "$ROOT_DIR/.claude"
assert_jq "$SETTINGS" '[.hooks.PreToolUse[].hooks[].command | select(test("require-test-skills"))] | length' '1' "idempotent PreToolUse"
assert_jq "$SETTINGS" '[.hooks.PostToolUse[].hooks[].command | select(test("check-ruby-comments"))] | length' '1' "idempotent PostToolUse"
assert_jq "$SETTINGS" '[.hooks.PostToolUse[].hooks[].command | select(. == "echo foreign")] | length' '1' "foreign hook still preserved"

echo "== イベント宣言を変えた場合は旧イベントの配線が残らない =="
FIXTURE="$TEST_ROOT/fixture/hooks"
mkdir -p "$FIXTURE"
printf '%s\n' '# claude_hook_event: PostToolUse' '# claude_hook_matcher: Write' 'exit 0' > "$FIXTURE/movable.rb"
run_wiring "$CLAUDE_HOME" "$TEST_ROOT/fixture"
assert_jq "$SETTINGS" '[.hooks.PostToolUse[].hooks[].command | select(test("movable"))] | length' '1' "fixture wired to PostToolUse"
printf '%s\n' '# claude_hook_event: PreToolUse' '# claude_hook_matcher: Write' 'exit 0' > "$FIXTURE/movable.rb"
run_wiring "$CLAUDE_HOME" "$TEST_ROOT/fixture"
assert_jq "$SETTINGS" '[.hooks.PostToolUse[].hooks[].command | select(test("movable"))] | length' '0' "old event wiring removed"
assert_jq "$SETTINGS" '[.hooks.PreToolUse[].hooks[].command | select(test("movable"))] | length' '1' "new event wiring added"

echo "== 宣言のないフックは PostToolUse / Edit|Write|MultiEdit に落ちる =="
printf '%s\n' 'exit 0' > "$FIXTURE/legacy.rb"
run_wiring "$CLAUDE_HOME" "$TEST_ROOT/fixture"
assert_jq "$SETTINGS" '.hooks.PostToolUse[] | select(.hooks[].command | test("legacy")) | .matcher' 'Edit|Write|MultiEdit' "default matcher"

echo "PASS: install.sh hook wiring"
