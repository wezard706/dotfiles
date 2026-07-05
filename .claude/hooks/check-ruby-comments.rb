#!/usr/bin/env ruby
# frozen_string_literal: true

# PostToolUse hook (Edit/Write/MultiEdit):
# .rb ファイルに新規追加されたコメント行を検出し、コードコメント規約
# （~/.claude/rules/development-principles.md）への自己レビューを促す。
# 既存行の移動による誤検出を避けるため、Edit では old_string に含まれる行を除外する。

require 'json'

BOILERPLATE = /frozen_string_literal|rubocop:|^#!|shareable_constant_value|typed:|encoding:/.freeze

def comment_lines(text)
  text.to_s.each_line.map(&:rstrip).select { |l| l.lstrip.start_with?('#') }
     .reject { |l| l.lstrip =~ BOILERPLATE }
end

input = JSON.parse($stdin.read)
tool_input = input['tool_input'] || {}
path = tool_input['file_path'].to_s
exit 0 unless path.end_with?('.rb')

pairs =
  case input['tool_name']
  when 'Edit'
    [[tool_input['old_string'], tool_input['new_string']]]
  when 'MultiEdit'
    (tool_input['edits'] || []).map { |e| [e['old_string'], e['new_string']] }
  when 'Write'
    [[nil, tool_input['content']]]
  else
    exit 0
  end

added = pairs.flat_map do |old, new|
  comment_lines(new) - comment_lines(old)
end

exit 0 if added.empty?

warn <<~MSG
  [コメント規約チェック] 追加コードに #{added.size} 件のコメントを検出:
  #{added.map { |c| "    #{c.strip}" }.join("\n")}

  ~/.claude/rules/development-principles.md の「コードコメント規約」を Read で参照し、
  各コメントが「記述してよいコメント」に該当するか検証せよ。
  該当しないものは Edit で削除すること。該当するものはそのまま残してよい。
MSG
exit 2
