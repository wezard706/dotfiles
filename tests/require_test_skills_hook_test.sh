#!/bin/bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT_DIR/.claude/hooks/require-test-skills.rb"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# フックは exit 0 / exit 2 と stderr で結果を返すため、両方を捕まえて検証する。
run_hook() {
  hook_stderr=$(printf '%s' "$1" | ruby "$HOOK" 2>&1 >/dev/null)
  hook_status=$?
}

assert_allowed() {
  run_hook "$2"
  [ "$hook_status" -eq 0 ] || fail "$1: expected exit 0, got $hook_status ($hook_stderr)"
}

assert_blocked() {
  run_hook "$2"
  [ "$hook_status" -eq 2 ] || fail "$1: expected exit 2, got $hook_status"
  grep -Fq "$3" <<<"$hook_stderr" || fail "$1: expected stderr to contain '$3', got: $hook_stderr"
}

transcript() {
  path="$TEST_ROOT/$1.jsonl"
  shift
  : > "$path"
  for line in "$@"; do
    printf '%s\n' "$line" >> "$path"
  done
  printf '%s' "$path"
}

skill_call() {
  printf '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"%s"}}]}}' "$1"
}

slash_call() {
  printf '{"type":"user","message":{"content":[{"type":"text","text":"<command-name>/%s</command-name>"}]}}' "$1"
}

payload() {
  ruby -rjson -e 'puts JSON.generate({
    "tool_name" => ARGV[0], "transcript_path" => ARGV[1],
    "tool_input" => JSON.parse(ARGV[2])
  })' "$@"
}

SPEC_BODY='RSpec.describe User do\n  it "returns a name" do\n    expect(user.name).to eq("a")\n  end\nend\n'
NO_SKILLS=$(transcript empty '{"type":"user","message":{"content":"テストを書いて"}}')
BOTH_SKILLS=$(transcript both "$(skill_call test-design)" "$(skill_call test-implementation)")
SLASH_SKILLS=$(transcript slash "$(slash_call test-design)" "$(slash_call test-implementation)")
DESIGN_ONLY=$(transcript design "$(skill_call test-design)")

echo "== spec への新規テストケース追加はスキル未経由ならブロックされる =="
assert_blocked "Write without skills" \
  "$(payload Write "$NO_SKILLS" "$(ruby -rjson -e 'puts JSON.generate({"file_path" => "/r/spec/models/user_spec.rb", "content" => ARGV[0].gsub("\\n", "\n")})' "$SPEC_BODY")")" \
  "test-design, test-implementation"

echo "== 両スキル発火後は通る（Skill ツール経由） =="
assert_allowed "Write after both skills" \
  "$(payload Write "$BOTH_SKILLS" "$(ruby -rjson -e 'puts JSON.generate({"file_path" => "/r/spec/models/user_spec.rb", "content" => ARGV[0].gsub("\\n", "\n")})' "$SPEC_BODY")")"

echo "== 両スキル発火後は通る（スラッシュコマンド経由） =="
assert_allowed "Write after slash commands" \
  "$(payload Write "$SLASH_SKILLS" "$(ruby -rjson -e 'puts JSON.generate({"file_path" => "/r/spec/models/user_spec.rb", "content" => ARGV[0].gsub("\\n", "\n")})' "$SPEC_BODY")")"

echo "== 片方だけの発火では未発火スキルのみを指摘してブロックする =="
run_hook "$(payload Write "$DESIGN_ONLY" "$(ruby -rjson -e 'puts JSON.generate({"file_path" => "/r/spec/models/user_spec.rb", "content" => ARGV[0].gsub("\\n", "\n")})' "$SPEC_BODY")")"
[ "$hook_status" -eq 2 ] || fail "design only: expected exit 2, got $hook_status"
grep -Fq "未発火のスキルがある: test-implementation" <<<"$hook_stderr" \
  || fail "design only: expected only test-implementation to be reported, got: $hook_stderr"

echo "== spec 以外のファイルは対象外 =="
assert_allowed "non-spec file" \
  "$(payload Write "$NO_SKILLS" '{"file_path":"/r/app/models/user.rb","content":"class User\nend\n"}')"

echo "== テストケース行を増やさない Edit は対象外 =="
assert_allowed "edit without new cases" \
  "$(payload Edit "$NO_SKILLS" '{"file_path":"/r/spec/models/user_spec.rb","old_string":"let(:user) { build(:user) }","new_string":"let(:user) { create(:user) }"}')"

echo "== 既存テストケース行の移動は新規追加として数えない =="
assert_allowed "moved case lines" \
  "$(payload Edit "$NO_SKILLS" "$(ruby -rjson -e 'puts JSON.generate({"file_path" => "/r/spec/models/user_spec.rb", "old_string" => "  it \"works\" do\n    x\n  end", "new_string" => "  it \"works\" do\n    y\n  end"})')")"

echo "== MultiEdit でのテストケース追加もブロックされる =="
assert_blocked "multiedit adds case" \
  "$(payload MultiEdit "$NO_SKILLS" "$(ruby -rjson -e 'puts JSON.generate({"file_path" => "/r/spec/models/user_spec.rb", "edits" => [{"old_string" => "end", "new_string" => "  it \"is added\" do\n  end\nend"}]})')")" \
  "test-design"

echo "== フック自身の警告文が転写されても発火判定を満たさない =="
SELF_ECHO=$(transcript self_echo "$(ruby -rjson -e 'puts JSON.generate({"type" => "user", "message" => {"content" => "[テストスキル必須] user_spec.rb に 1 件のテストケースを追加しようとしたが、未発火のスキルがある: test-design, test-implementation。Skill ツールで test-design → test-implementation を順に起動せよ"}})')")
assert_blocked "self-echoed warning" \
  "$(payload Write "$SELF_ECHO" "$(ruby -rjson -e 'puts JSON.generate({"file_path" => "/r/spec/models/user_spec.rb", "content" => ARGV[0].gsub("\\n", "\n")})' "$SPEC_BODY")")" \
  "test-design, test-implementation"

echo "== トランスクリプトが壊れた行を含んでも落ちない =="
BROKEN=$(transcript broken 'not json at all' "$(skill_call test-design)" "$(skill_call test-implementation)")
assert_allowed "broken transcript line" \
  "$(payload Write "$BROKEN" "$(ruby -rjson -e 'puts JSON.generate({"file_path" => "/r/spec/models/user_spec.rb", "content" => ARGV[0].gsub("\\n", "\n")})' "$SPEC_BODY")")"

echo "== トランスクリプトが存在しない場合はブロック側に倒す =="
assert_blocked "missing transcript" \
  "$(payload Write "$TEST_ROOT/does-not-exist.jsonl" "$(ruby -rjson -e 'puts JSON.generate({"file_path" => "/r/spec/models/user_spec.rb", "content" => ARGV[0].gsub("\\n", "\n")})' "$SPEC_BODY")")" \
  "test-design, test-implementation"

echo "PASS: require-test-skills hook"
