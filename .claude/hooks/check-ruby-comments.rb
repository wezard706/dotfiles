#!/usr/bin/env ruby
# frozen_string_literal: true

# claude_hook_event: PostToolUse
# claude_hook_matcher: Edit|Write|MultiEdit
#
# .rb の追加差分をコードコメント規約（~/.claude/rules/development-principles.md）に
# 照らし、宣言系コメントの欠落と実装内コメントの過剰を指摘する。
# 宣言系と実装系で規約の既定が逆（書く / 書かない）なため、コメントは位置で分類する。
# 散文の要否は WHY の有無で決まり機械判定できないため、フックは YARD タグの欠落だけを見る。
# 既存行の移動による誤検出を避けるため、Edit では old_string に含まれる行を除外する。
# 宣言の解析には prism を使い、不在環境では実装内コメントの検査だけに縮退する。

require 'json'

YARD_TAG = /\A#\s*@\w+/.freeze
YARD_PARAM = /\A#\s*@param\s+(?:\[[^\]]*\]\s*)?(\S+)/.freeze
YARD_RETURN = /\A#\s*@return\b/.freeze
BOILERPLATE = /frozen_string_literal|rubocop:|\A#!|shareable_constant_value|typed:|encoding:/.freeze
EXCLUDED_PATH = %r{_spec\.rb\z|/db/migrate/}.freeze
DECLARATION = /
  \A\s*(?:(?:private|protected|public)\s+)?(?:class|module|def)\b
  |\A\s*attr_(?:reader|writer|accessor)\b
/x.freeze

Declaration = Struct.new(:kind, :line, :name, :parameters)

# ヒアドキュメント内の式展開 `#{...}` は行頭に `#` が来るため、コメントと区別する。
def comment?(line)
  stripped = line.to_s.lstrip
  stripped.start_with?('#') && !stripped.start_with?('#{')
end

def comment_lines(text)
  text.to_s.each_line.map(&:rstrip).select { |line| comment?(line) }
end

# 直後の非コメント行が宣言であれば、そのコメントは宣言に付随するものと見なす。
# 空行で隔てられている場合は付随しない。
def declaration_comment?(lines, index)
  ((index + 1)...lines.size).each do |i|
    next if comment?(lines[i])
    return false if lines[i].strip.empty?

    return !(lines[i] =~ DECLARATION).nil?
  end
  false
end

def comment_block_above(lines, line_number)
  index = line_number - 2
  block = []
  while index >= 0 && comment?(lines[index])
    block.unshift(lines[index].strip)
    index -= 1
  end
  block
end

def statements_of(node)
  body = node.is_a?(Prism::ProgramNode) ? node.statements : node.body
  body.is_a?(Prism::StatementsNode) ? body.body : []
end

# ブロック引数は @yield 系で書く流儀もあるため @param を要求しない。
def parameter_names(def_node)
  params = def_node.parameters
  return [] if params.nil?

  nodes = params.requireds + params.optionals + params.posts + params.keywords
  nodes += [params.rest, params.keyword_rest].compact
  nodes.filter_map { |node| node.name&.to_s if node.respond_to?(:name) }
end

# クラス・モジュールの外にある def は公開APIの面を持たないため対象外にする
# （スクリプトのトップレベル定義が該当する）。
def scan_scope(statements, out, inside_type: false)
  statements.each do |stmt|
    case stmt
    when Prism::ClassNode, Prism::ModuleNode
      out << Declaration.new(:type, stmt.location.start_line, nil, [])
      scan_scope(statements_of(stmt), out, inside_type: true)
    when Prism::SingletonClassNode
      scan_scope(statements_of(stmt), out, inside_type: inside_type)
    when Prism::DefNode
      next unless inside_type

      out << Declaration.new(:method, stmt.location.start_line, stmt.name.to_s, parameter_names(stmt))
    when Prism::CallNode
      next unless inside_type

      case stmt.name
      when :private, :protected, :public
        (stmt.arguments&.arguments || []).each do |arg|
          next unless arg.is_a?(Prism::DefNode)

          out << Declaration.new(:method, arg.location.start_line, arg.name.to_s, parameter_names(arg))
        end
      when :attr_reader, :attr_writer, :attr_accessor
        out << Declaration.new(:attr, stmt.location.start_line, nil, [])
      end
    end
  end
end

def declarations(source)
  result = Prism.parse(source)
  return [] if result.failure?

  out = []
  scan_scope(statements_of(result.value), out)
  out
end

def prose?(block)
  block.any? do |comment|
    !(comment =~ YARD_TAG) && !(comment =~ BOILERPLATE) && comment.sub(/\A#+/, '').strip != ''
  end
end

def documented_parameters(block)
  block.filter_map { |comment| comment[YARD_PARAM, 1] }
end

# initialize とセッターは、YARD の慣習として戻り値を書かない。
def return_tag_required?(declaration)
  declaration.name != 'initialize' && !declaration.name.to_s.end_with?('=')
end

def missing_requirements(declaration, lines)
  block = comment_block_above(lines, declaration.line)
  missing = []
  case declaration.kind
  when :type
    missing << '責務を述べる散文' unless prose?(block)
  when :method
    undocumented = declaration.parameters - documented_parameters(block)
    missing << "@param（#{undocumented.join(', ')}）" unless undocumented.empty?
    missing << '@return' if return_tag_required?(declaration) && block.none? { |c| c =~ YARD_RETURN }
  when :attr
    missing << '@return' if block.none? { |c| c =~ YARD_RETURN }
  end
  missing
end

input = JSON.parse($stdin.read)
tool_input = input['tool_input'] || {}
path = tool_input['file_path'].to_s
exit 0 unless path.end_with?('.rb')
exit 0 if path =~ EXCLUDED_PATH

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

added = pairs.flat_map { |old, new| new.to_s.each_line.map(&:strip) - old.to_s.each_line.map(&:strip) }.reject(&:empty?)
added_comments = pairs.flat_map { |old, new| comment_lines(new) - comment_lines(old) }
exit 0 if added.empty?

lines = File.file?(path) ? File.read(path).lines.map(&:rstrip) : []

body_comments = added_comments.reject { |c| c =~ BOILERPLATE }.select do |comment|
  index = lines.index { |line| comment?(line) && line.strip == comment.strip }
  index.nil? || !declaration_comment?(lines, index)
end

undocumented =
  begin
    require 'prism'
    declarations(lines.join("\n")).filter_map do |declaration|
      next unless added.include?(lines[declaration.line - 1].to_s.strip)

      missing = missing_requirements(declaration, lines)
      next if missing.empty?

      "    #{path}:#{declaration.line}  #{lines[declaration.line - 1].strip}\n" \
        "        不足: #{missing.join(' / ')}"
    end
  rescue LoadError, StandardError
    # prism 不在や未知の AST 形状で全 .rb 編集を壊さないよう、宣言検査だけを落とす。
    []
  end

exit 0 if body_comments.empty? && undocumented.empty?

messages = []

unless undocumented.empty?
  messages << <<~SECTION
    [宣言系コメントの欠落] 追加した宣言に必須の YARD タグがない:
    #{undocumented.join("\n")}

    ~/.claude/rules/development-principles.md の「コードコメント規約」を Read で参照し、
    宣言系コメントの規約に従って追記せよ。形式は YARD（@param・@return・@raise）に従うこと。
    メソッドの散文は WHY だけを書く。WHAT と自明な WHY は書かないこと。
  SECTION
end

unless body_comments.empty?
  messages << <<~SECTION
    [実装内コメントの確認] 宣言に付随しないコメントを #{body_comments.size} 件検出:
    #{body_comments.map { |c| "    #{c.strip}" }.join("\n")}

    ~/.claude/rules/development-principles.md の「コードコメント規約」を Read で参照し、
    各コメントが「設計判断の根拠」「非自明な制約」のいずれかに該当するか検証せよ。
    判断が付かない場合は comment-review スキルの references/comment-conventions.md（正本）を読め。
    該当しないものは Edit で削除すること。該当するものはそのまま残してよい。
  SECTION
end

warn messages.join("\n")
exit 2
