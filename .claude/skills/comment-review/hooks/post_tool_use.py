#!/usr/bin/env python3
"""PostToolUse フック: Edit/Write/MultiEdit でコメントを追加・変更したとき、
本体エージェントに comment-review スキルでの自己レビューを促す。

毎回の編集で発火するため、変更テキストにコメントが含まれない場合は
何も出力せず終了し、ノイズを抑える。判定を誤っても代償は小さい
（偽陽性 = 不要な自己レビューが1回、偽陰性 = レビュー漏れ）ので、
取りこぼしを避ける方向にやや広めの判定にしてある。

フックが落ちてユーザーの編集を妨げないよう、想定外は常に exit 0 で握りつぶす。
"""
import json
import re
import sys

# 言語非依存にコメント構文を広めに拾う。偽陽性は許容、取りこぼしは避ける。
COMMENT_PATTERNS = [
    re.compile(r"(^|\s)#(?!\{)"),      # Ruby/Python/shell/YAML（#{ 補間は除外）
    re.compile(r"(?<!:)//"),           # C系//（:// のURLは除外）
    re.compile(r"/\*"),                # C系ブロックコメント開始
    re.compile(r"^\s*\*( |/|\*|$)"),   # JSDoc/Javadoc 本文行（* で始まる）
    re.compile(r"<!--"),               # HTML/XML/Markdown
    re.compile(r'"""|\'\'\''),         # Python docstring
    re.compile(r"(^|\s)-- "),          # SQL/Lua/Haskell
]


def extract_new_text(tool_name, tool_input):
    """ツール入力から「新しく書かれたテキスト」を取り出す。"""
    if tool_name == "Write":
        return tool_input.get("content", "") or ""
    if tool_name == "Edit":
        return tool_input.get("new_string", "") or ""
    if tool_name == "MultiEdit":
        return "\n".join(
            (e.get("new_string", "") or "") for e in tool_input.get("edits", [])
        )
    return ""


def contains_comment(text):
    return any(p.search(line) for line in text.splitlines() for p in COMMENT_PATTERNS)


def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return  # 入力が壊れていても編集は妨げない

    tool_name = data.get("tool_name", "")
    tool_input = data.get("tool_input", {}) or {}
    new_text = extract_new_text(tool_name, tool_input)
    if not new_text or not contains_comment(new_text):
        return  # コメントを含まない編集はスルー

    file_path = tool_input.get("file_path", "(不明なファイル)")
    message = (
        f"直前の {tool_name} でファイル `{file_path}` のコメントを追加・変更しました。"
        "comment-review スキルを使い、変更したコメントが規約に従っているか自己レビューし、"
        "違反があれば修正してください。問題がなければ何もする必要はありません。"
    )
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PostToolUse",
            "additionalContext": message,
        }
    }))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # フックの失敗で編集フローを壊さない
    sys.exit(0)
