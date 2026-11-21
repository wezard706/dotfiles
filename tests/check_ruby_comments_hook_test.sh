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

echo "== public メソッド: コメント皆無なら散文と型注釈の両方を指摘 =="
run_write bare.rb '# 予約の重複検知と成立判定を担う
class Reservation
  def book(coach)
    coach
  end
end
'
assert_flagged "public bare" "宣言系コメントの欠落" "散文コメント" "rbs-inline 型注釈"

echo "== public メソッド: 散文のみなら型注釈を指摘 =="
run_write prose_only.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # コーチを指定して予約を確定
  def book(coach)
    coach
  end
end
'
assert_flagged "prose only" "rbs-inline 型注釈"
assert_absent "prose only" "不足: 散文コメント"

echo "== public メソッド: 型注釈のみなら散文を指摘 =="
run_write annotation_only.rb '# 予約の重複検知と成立判定を担う
class Reservation
  #: (Coach) -> void
  def book(coach)
    coach
  end
end
'
assert_flagged "annotation only" "不足: 散文コメント"
assert_absent "annotation only" "rbs-inline 型注釈（#:）"

echo "== public メソッド: 散文と型注釈が揃えば通る =="
run_write complete.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # コーチを指定して予約を確定
  #: (Coach) -> void
  def book(coach)
    coach
  end
end
'
assert_ok "complete"

echo "== private メソッド: 型注釈のみで通る =="
run_write private_ok.rb '# 予約の重複検知と成立判定を担う
class Reservation
  private

  #: () -> bool
  def slot_available?
    true
  end
end
'
assert_ok "private with annotation"

echo "== private メソッド: 型注釈が無ければ指摘し、散文は求めない =="
run_write private_bare.rb '# 予約の重複検知と成立判定を担う
class Reservation
  private

  def slot_available?
    true
  end
end
'
assert_flagged "private bare" "rbs-inline 型注釈"
assert_absent "private bare" "不足: 散文コメント"

echo "== private def 形式も private と判定する =="
run_write private_inline.rb '# 予約の重複検知と成立判定を担う
class Reservation
  #: () -> bool
  private def slot_available?
    true
  end
end
'
assert_ok "private def form"

echo "== private :foo 形式も private と判定する =="
run_write private_symbol.rb '# 予約の重複検知と成立判定を担う
class Reservation
  #: () -> bool
  def slot_available?
    true
  end

  private :slot_available?
end
'
assert_ok "private symbol form"

echo "== 入れ子クラスの public メソッドにも散文を要求する =="
run_write nested.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # 予約枠の空き状況を表す
  class Slot
    #: () -> bool
    def open?
      true
    end
  end
end
'
assert_flagged "nested public" "不足: 散文コメント"

echo "== class: 責務の散文が無ければ指摘 =="
run_write class_bare.rb 'class Reservation
end
'
assert_flagged "class bare" "責務を述べる散文コメント"

echo "== attr_reader: 行末の型注釈が無ければ指摘 =="
run_write attr_bare.rb '# 予約の重複検知と成立判定を担う
class Reservation
  attr_reader :starts_at
end
'
assert_flagged "attr bare" "行末の型注釈"

echo "== attr_reader: 行末注釈があれば通る =="
run_write attr_ok.rb '# 予約の重複検知と成立判定を担う
class Reservation
  attr_reader :starts_at #: Time
end
'
assert_ok "attr annotated"

echo "== def 行末の型注釈も認める =="
run_write trailing_def.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # 人間可読の表現を返す
  def to_s #: String
    ""
  end
end
'
assert_ok "trailing def annotation"

echo "== 宣言に付く散文は実装内コメントとして指摘されない =="
run_write doc_not_suppressed.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # コーチを指定して予約を確定
  #: (Coach) -> void
  def book(coach)
    coach
  end
end
'
assert_ok "declaration comments not suppressed"

echo "== メソッド本体内のコメントは従来どおり指摘 =="
run_write body_comment.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # コーチを指定して予約を確定
  #: (Coach) -> void
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

  # コーチを指定して予約を確定
  #: (Coach) -> void
  def book(coach)
    coach
  end
end
'
assert_flagged "detached comment" "実装内コメントの確認" "宣言から離れた見出しコメント"

echo "== boilerplate と rbs_inline マジックコメントは抑制対象外 =="
run_write boilerplate.rb '# frozen_string_literal: true
# rbs_inline: enabled

# 予約の重複検知と成立判定を担う
class Reservation
end
'
assert_ok "boilerplate and magic comment"

echo "== 本体だけの変更では宣言の欠落を指摘しない =="
run_edit body_only.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # コーチを指定して予約を確定
  #: (Coach) -> void
  def book(coach)
    coach.reload
  end
end
' '    coach' '    coach.reload'
assert_ok "body-only edit"

echo "== 注釈の無い既存メソッドは、触っていなければ指摘しない =="
run_edit untouched.rb '# 予約の重複検知と成立判定を担う
class Reservation
  def legacy_method
    1
  end

  # コーチを指定して予約を確定
  #: (Coach) -> void
  def book(coach)
    coach
  end
end
' '' '  # コーチを指定して予約を確定
  #: (Coach) -> void
  def book(coach)
    coach
  end
'
assert_ok "untouched legacy method"

echo "== ヒアドキュメントの式展開をコメントと誤認しない =="
run_write heredoc.rb '# 予約の重複検知と成立判定を担う
class Reservation
  # 通知文面を組み立てる
  #: (String) -> String
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
