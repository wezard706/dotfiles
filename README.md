# dotfiles

Claude Code の設定を管理するリポジトリ。`./install.sh` で配置する（冪等・再実行可能）。

## 構成

- `.claude/` — Claude Code 設定の正本
  - `CLAUDE.md` — 行動原則・コミュニケーション（`~/.claude/CLAUDE.md` へ配置）
  - `rules/` — ルール（design-proposal / terminology / development-principles / rails-principles / nextjs-principles）
  - `skills/` — スキル
  - `hooks/` — フック
  - `CLAUDE.local.md` — このリポジトリで作業するときの指示
- `git/` — git エイリアス

## install.sh の配置先

| ソース | 配置先 | 方式 |
|---|---|---|
| `.claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | コピー |
| `.claude/rules/*.md` | `~/.claude/rules/` | コピー（ディレクトリをクリーン再作成） |
| `.claude/skills/` | `~/.claude/skills/` | スキル単位で上書きコピー（管理外スキルは保全） |
| `.claude/hooks/*.rb` | `~/.claude/hooks/` | コピー + `~/.claude/settings.json` の PostToolUse へマージ |
| `git/.gitconfig.aliases` | `~/.gitconfig.aliases` | コピー + `~/.gitconfig` へ include 追記 |

## スキルの編集先

スキルの正本は `.claude/skills/`。配置先（`~/.claude/skills/`）を直接編集せず、リポジトリ側を編集して `./install.sh` を再実行する。

### 外部スキルの管理

- 内製スキルの正本は `.claude/skills/`
- 外部スキルの取得元と commit SHA は `.claude/skill-dependencies.json`
- 非 Skill 形式の適合処理は `.claude/external-skill-adapters/`
- `./install.sh` は全外部依存を検証後、`~/.claude/skills/` へ反映
- 配置先の `.dotfiles-managed-skills` は、dotfiles が管理するトップレベルスキル名を
  C ロケール昇順・改行区切り（1行1スキル名）で保持する inventory
- 前回の inventory にあり現在の bundle にないスキルは削除し、inventory にない管理外スキルは保全
- スキル本体・削除・inventory は一つの transaction として更新し、失敗時は復元
- 更新時はライセンスと差分を確認し、40桁の commit SHA を手動更新
- `git` または `jq` の欠如、ネットワーク障害、取得・検証失敗ではインストールを中止

現在の外部スキルは `composition-patterns`、`react-best-practices`、`layered-rails-review` である。

## dotfiles で管理しないもの

- `~/.claude/settings.json` — 手動管理（install.sh は hooks の配線マージのみ行う）
