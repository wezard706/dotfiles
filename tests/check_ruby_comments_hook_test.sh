#!/bin/bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT_DIR/.claude/hooks/check-ruby-comments.rb"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# フックは書き込み後のファイルを読んで宣言を解析するため、payload と同じ内容を
# 実ファイルとして用意してから起動する。
write_case() {
  case_path="$TEST_ROOT/$1"
  mkdir -p "$(dirname "$case_path")"
  printf '%s' "$2" > "$case_path"
}

run_write() {
  write_case "$1" "$2"
  payload=$(ruby -rjson -e 'puts JSON.generate({"tool_name" => "Write", "tool_input" => {"file_path" => ARGV[0], "content" => ARGV[1]}})' "$case_path" "$2")
  hook_stderr=$(printf '%s' "$payload" | ruby "$HOOK" 2>&1 >/dev/null)
  hook_status=$?
}

run_edit() {
  write_case "$1" "$2"
  payload=$(ruby -rjson -e 'puts JSON.generate({"tool_name" => "Edit", "tool_input" => {"file_path" => ARGV[0], "old_string" => ARGV[1], "new_string" => ARGV[2]}})' "$case_path" "$3" "$4")
  hook_stderr=$(printf '%s' "$payload" | ruby "$HOOK" 2>&1 >/dev/null)
  hook_status=$?
}

assert_ok() {
  [ "$hook_status" -eq 0 ] || fail "$1: expected exit 0, got $hook_status: $hook_stderr"
}

assert_flagged() {
  label="$1"
  shift
  [ "$hook_status" -eq 2 ] || fail "$label: expected exit 2, got $hook_status"
  for expected in "$@"; do
    grep -Fq "$expected" <<<"$hook_stderr" || fail "$label: expected stderr to contain '$expected', got: $hook_stderr"
  done
}

assert_absent() {
  if grep -Fq "$2" <<<"$hook_stderr"; then
    fail "$1: stderr should not contain '$2', got: $hook_stderr"
  fi
}

echo "== メソッド: YARD タグが無ければ @param と @return を指摘 =="
run_write bare.rb '# 予約の重複検知と成立判定を担う
class Reservation
  def book(coach)
    coach
  end
end
'
assert_flagged "method bare" "宣言系コメントの欠落" "@param（coach）" "@return"

echo "== メソッド: WHY が無ければ散文なしでも通る =="
run_write tags_only.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # @param coach [Coach] 担当コーチ
  # @return [Reservation] 成立した予約
  def book(coach)
    coach
  end
end
'
assert_ok "tags without prose"

echo "== メソッド: 散文だけでタグが無ければ指摘 =="
run_write prose_only.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # 二重予約の検知を DB のユニーク制約に委ねず、ここで判定する。
  # 制約違反の例外を UI に出さないため
  def book(coach)
    coach
  end
end
'
assert_flagged "prose only" "@param（coach）" "@return"

echo "== メソッド: WHY の散文とタグが揃えば通る =="
run_write complete.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # 二重予約の検知を DB のユニーク制約に委ねず、ここで判定する。
  # 制約違反の例外を UI に出さないため
  #
  # @param coach [Coach] 担当コーチ
  # @return [Reservation] 成立した予約
  # @raise [Conflict] 重複する予約がある場合
  def book(coach)
    coach
  end
end
'
assert_ok "prose with tags"

echo "== @param [Type] name の語順も認める =="
run_write param_order.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # @param [Coach] coach 担当コーチ
  # @return [Reservation] 成立した予約
  def book(coach)
    coach
  end
end
'
assert_ok "param type-first order"

echo "== 複数引数: 書き漏らした引数だけを指摘 =="
run_write partial_params.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # @param coach [Coach] 担当コーチ
  # @return [Reservation] 成立した予約
  def book(coach, starts_at, notify: false)
    coach
  end
end
'
assert_flagged "partial params" "@param（starts_at, notify）"
assert_absent "partial params" "@param（coach"

echo "== ブロック引数には @param を要求しない =="
run_write block_param.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # @return [void]
  def each(&block)
    block
  end
end
'
assert_ok "block parameter"

echo "== private メソッドにもタグを要求する =="
run_write private_bare.rb '# 予約の重複検知と成立判定を担う
class Reservation
  private

  def slot_available?
    true
  end
end
'
assert_flagged "private bare" "@return"

echo "== private メソッド: タグが揃えば通る =="
run_write private_ok.rb '# 予約の重複検知と成立判定を担う
class Reservation
  private

  # @return [Boolean]
  def slot_available?
    true
  end
end
'
assert_ok "private with tags"

echo "== private def 形式も宣言として拾う =="
run_write private_inline.rb '# 予約の重複検知と成立判定を担う
class Reservation
  private def slot_available?
    true
  end
end
'
assert_flagged "private def form" "@return"

echo "== initialize とセッターには @return を要求しない =="
run_write no_return_tag.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # @param starts_at [Time] 予約開始時刻
  def initialize(starts_at)
    @starts_at = starts_at
  end

  # @param value [Time] 新しい開始時刻
  def starts_at=(value)
    @starts_at = value
  end
end
'
assert_ok "initialize and setter"

echo "== 入れ子クラスのメソッドにもタグを要求する =="
run_write nested.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # 予約枠の空き状況を表す
  class Slot
    def open?
      true
    end
  end
end
'
assert_flagged "nested method" "@return"

echo "== クラス・モジュール外のトップレベル def は対象外 =="
run_write toplevel.rb '# frozen_string_literal: true

def comment?(line)
  line.start_with?("#")
end

private def helper(path, mode)
  [path, mode]
end
'
assert_ok "top-level def"

echo "== モジュール内の def は対象外にしない =="
run_write module_method.rb '# コメント行の判定を提供する
module Commentable
  def comment?(line)
    line.start_with?("#")
  end
end
'
assert_flagged "module method" "@param（line）" "@return"

echo "== class: 責務の散文が無ければ指摘 =="
run_write class_bare.rb 'class Reservation
end
'
assert_flagged "class bare" "責務を述べる散文"

echo "== class: 責務の散文があれば通る =="
run_write class_documented.rb '# 予約の重複検知と成立判定を担う
class Reservation
end
'
assert_ok "class documented"

echo "== attr_reader: @return が無ければ指摘 =="
run_write attr_bare.rb '# 予約の重複検知と成立判定を担う
class Reservation
  attr_reader :starts_at
end
'
assert_flagged "attr bare" "@return"

echo "== attr_reader: @return があれば通る =="
run_write attr_ok.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # @return [Time] 予約開始時刻
  attr_reader :starts_at
end
'
assert_ok "attr documented"

echo "== 宣言に付く散文は実装内コメントとして指摘されない =="
run_write doc_not_suppressed.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # 二重予約の検知を DB のユニーク制約に委ねず、ここで判定する。
  # 制約違反の例外を UI に出さないため
  #
  # @param coach [Coach] 担当コーチ
  # @return [Reservation] 成立した予約
  def book(coach)
    coach
  end
end
'
assert_ok "declaration comments not suppressed"

echo "== メソッド本体内のコメントは従来どおり指摘 =="
run_write body_comment.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # @param coach [Coach] 担当コーチ
  # @return [Reservation] 成立した予約
  def book(coach)
    # 予約を作成する
    coach
  end
end
'
assert_flagged "body comment" "実装内コメントの確認" "予約を作成する"
assert_absent "body comment" "宣言系コメントの欠落"

echo "== 空行で隔てられたコメントは宣言系と見なさない =="
run_write detached_comment.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # 宣言から離れた見出しコメント

  # @param coach [Coach] 担当コーチ
  # @return [Reservation] 成立した予約
  def book(coach)
    coach
  end
end
'
assert_flagged "detached comment" "実装内コメントの確認" "宣言から離れた見出しコメント"

echo "== boilerplate は抑制対象外 =="
run_write boilerplate.rb '# frozen_string_literal: true

# 予約の重複検知と成立判定を担う
class Reservation
end
'
assert_ok "boilerplate"

echo "== 本体だけの変更では宣言の欠落を指摘しない =="
run_edit body_only.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # @param coach [Coach] 担当コーチ
  # @return [Reservation] 成立した予約
  def book(coach)
    coach.reload
  end
end
' '    coach' '    coach.reload'
assert_ok "body-only edit"

echo "== YARD の無い既存メソッドは、触っていなければ指摘しない =="
run_edit untouched.rb '# 予約の重複検知と成立判定を担う
class Reservation
  def legacy_method
    1
  end

  # @param coach [Coach] 担当コーチ
  # @return [Reservation] 成立した予約
  def book(coach)
    coach
  end
end
' '' '  # @param coach [Coach] 担当コーチ
  # @return [Reservation] 成立した予約
  def book(coach)
    coach
  end
'
assert_ok "untouched legacy method"

echo "== ヒアドキュメントの式展開をコメントと誤認しない =="
run_write heredoc.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # @param name [String] 宛名
  # @return [String] 本文
  def message(name)
    <<~TEXT
      #{name} 様
    TEXT
  end
end
'
assert_ok "heredoc interpolation"

echo "== spec・マイグレーション・非 .rb は対象外 =="
run_write models/user_spec.rb 'RSpec.describe User do
  it "works" do
    expect(1).to eq(1)
  end
end
'
assert_ok "spec excluded"
run_write db/migrate/20260101_create_users.rb 'class CreateUsers < ActiveRecord::Migration[7.1]
  def change
  end
end
'
assert_ok "migration excluded"
run_write notes.txt 'class Reservation
end
'
assert_ok "non-ruby excluded"

echo "== 構文エラーのファイルでは宣言検査をスキップする =="
run_write broken.rb '# 予約の重複検知と成立判定を担う
class Reservation
  def book(coach
end
'
assert_ok "unparsable file"

echo "PASS: check-ruby-comments hook"
