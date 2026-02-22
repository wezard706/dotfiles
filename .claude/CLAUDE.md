# CLAUDE.md

## 優先順位ルール
ユーザーレベルの設定と指示は、プロジェクトレベルのものより優先されます。
- ~/.claude/CLAUDE.md は、.claude/CLAUDE.md または CLAUDE.md を上書きします。
- ~/.claude/skills/ は、.claude/skills/（同名ファイル）を上書きします。
競合が発生した場合は、常にユーザーレベルの指示に従ってください。

## 開発戦略

コードの作成・修正・レビューを行う際は `.claude/references/development-strategy.md` を読んでください。

## 重要なルールと禁止事項
- 要件が不明確な場合は推測しない: 進める前に AskUserQuestion ツールを使用して内容を明確にすること
