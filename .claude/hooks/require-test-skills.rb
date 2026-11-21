#!/usr/bin/env ruby
# frozen_string_literal: true

# claude_hook_event: PreToolUse
# claude_hook_matcher: Edit|Write|MultiEdit
#
# PreToolUse hook: spec ファイルへの新規テストケース追加を、test-design /
# test-implementation 未経由ならブロックする。
# スキル発火の判定は、セッション状態ファイルを持たずに済むトランスクリプト走査に寄せる。
# 既存行の移動による誤検出を避けるため、Edit では old_string に含まれる行を除外する。

require 'json'

REQUIRED_SKILLS = %w[test-design test-implementation].freeze
CASE_LINE = /^\s*(?:describe|context|it|specify|example|fit|xit)\b/.freeze

def case_lines(text)
  text.to_s.each_line.map(&:rstrip).select { |line| line =~ CASE_LINE }
end

def skills_from_tool_use(content)
  return [] unless content.is_a?(Array)

  content.filter_map do |block|
    next unless block.is_a?(Hash) && block['type'] == 'tool_use' && block['name'] == 'Skill'

    block.dig('input', 'skill').to_s
  end
end

def skills_from_slash_command(content)
  text =
    case content
    when String then content
    when Array then content.filter_map { |b| b['text'] if b.is_a?(Hash) }.join("\n")
    else ''
    end
  text.scan(%r{<command-name>/?(?:[\w.-]+:)?([\w-]+)</command-name>}).flatten
end

def invoked_skills(transcript_path)
  return [] unless transcript_path && File.file?(transcript_path)

  File.foreach(transcript_path).with_object([]) do |line, skills|
    entry = JSON.parse(line)
    content = entry.dig('message', 'content')
    skills.concat(skills_from_tool_use(content))
    skills.concat(skills_from_slash_command(content))
  rescue JSON::ParserError
    next
  end
end

input = JSON.parse($stdin.read)
tool_input = input['tool_input'] || {}
path = tool_input['file_path'].to_s
exit 0 unless path.end_with?('_spec.rb')

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

added = pairs.flat_map { |old, new| case_lines(new) - case_lines(old) }
exit 0 if added.empty?

missing = REQUIRED_SKILLS - invoked_skills(input['transcript_path'])
exit 0 if missing.empty?

warn <<~MSG
  [テストスキル必須] #{File.basename(path)} に #{added.size} 件のテストケースを追加しようとしたが、
  未発火のスキルがある: #{missing.join(', ')}

  RSpec のテストは手書きせず、次の順でスキルを経由すること。
    1. test-design スキル — 何をテストすべきかを設計し、describe/context/it のアウトラインを作る
    2. test-implementation スキル — そのアウトラインを RSpec コードに落とす

  Skill ツールで #{missing.join(' → ')} を順に起動し、各スキルの手順に従って書き直せ。
  今回の書き込みは破棄された。スキルを経由した書き込みは通る。
MSG
exit 2
