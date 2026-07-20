# dotfiles

Claude Code と Codex の設定を管理するリポジトリ。`./install.sh` で配置する（冪等・再実行可能）。

## 構成

- `.agents/` — Claude / Codex 共有ソースの正本
  - `AGENTS.md` — 行動原則・コミュニケーション（ツール中立の表現。`~/.claude/CLAUDE.md` と `~/.codex/AGENTS.md` の共通ヘッダ）
  - `rules/` — 共有ルール（design-proposal / terminology / development-principles / rails-principles）
  - `skills/` — 共有スキル
- `.claude/` — Claude Code 専用（hooks・CLAUDE.local.md）
- `git/` — git エイリアス

## install.sh の配置先

| ソース | 配置先 | 方式 |
|---|---|---|
| `.agents/AGENTS.md` | `~/.claude/CLAUDE.md` | コピー |
| `.agents/rules/*.md` | `~/.claude/rules/` | コピー（ディレクトリをクリーン再作成） |
| `.agents/AGENTS.md` + `.agents/rules/*.md` | `~/.codex/AGENTS.md` | 連結して生成 |
| `.agents/skills/` | `~/.claude/skills/` | スキル単位で上書きコピー（管理外スキルは保全） |
| `.agents/skills/` | `~/.agents/skills/` | スキル単位で上書きコピー（skills CLI 導入分は保全） |
| `.claude/hooks/*.rb` | `~/.claude/hooks/` | コピー + `~/.claude/settings.json` の PostToolUse へマージ |
| `git/.gitconfig.aliases` | `~/.gitconfig.aliases` | コピー + `~/.gitconfig` へ include 追記 |

## Codex 設定（AGENTS.md）

`~/.codex/AGENTS.md` は `.agents/AGENTS.md` をヘッダに `.agents/rules/*.md` を連結して生成される。直接編集せず、dotfiles リポジトリ側を編集して `./install.sh` を再実行すること。rules の paths frontmatter は Codex に相当機構がないため、生成時に「このセクションは〜に適用する」という自然文へ変換される。

プロジェクトの AGENTS.md と矛盾する指示がある場合、Codex の連結仕様により作業ディレクトリに近い側（プロジェクト側）が優先される。

## スキルの編集先

スキルの正本は `.agents/skills/`（Claude / Codex 両方へ配置される）。配置先（`~/.claude/skills/` 等）を直接編集せず、リポジトリ側を編集して `./install.sh` を再実行する。

スキル探索パスの実測: Codex は `~/.codex/skills/` と `~/.agents/skills/` の両方を読む。Claude Code は `~/.claude/skills/` のみを読む。

## dotfiles で管理しないもの

- `~/.codex/config.toml` — 認証・trust・marketplace 等のローカル状態を含むため install.sh では一切触らない
- `~/.codex/rules/`（Codex の permission）— 手動管理
- `~/.claude/settings.json` — 手動管理（install.sh は hooks の配線マージのみ行う）
