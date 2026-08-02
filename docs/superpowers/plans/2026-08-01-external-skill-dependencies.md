# External Skill Dependencies Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `install.sh`実行時に、commit SHAで固定した3つの外部成果物をCodex用とClaude Code用のスキルとして再現可能かつ安全にインストールする。

**Architecture:** `.agents/skill-dependencies.json`を入力に、`scripts/install_external_skills.sh`が内製スキル、アダプター、外部成果物から一時的なスキルバンドルを構築する。`install.sh`はバンドルの構築がすべて成功した後に、管理対象スキルだけを`~/.agents/skills`と`~/.claude/skills`へスキル単位で置換する。

**Tech Stack:** Bash 3.2互換シェル、Git、jq、Agent Skills形式の`SKILL.md`

## Global Constraints

- 外部依存は40桁の完全なcommit SHAで固定し、ブランチ名またはタグをインストール時に解決しない。
- `vercel-labs/agent-skills`は`7c180d9044c9ae2b442b567aad4e42a28dd5ed62`に固定する。
- `jasim/layered-rails-skills`は`1328ef71675315a658fdbd494db4b2fd488c0ec8`に固定する。
- `vladikk/modularity`はCC BY-NC-SA 4.0と商用利用用途が整合しないため対象に含めない。
- インストール先は`~/.agents/skills`と`~/.claude/skills`の両方とする。
- 管理対象外のインストール済みスキルを削除または変更しない。
- 外部依存の取得または検証が一つでも失敗した場合は、インストール先を変更せず非0で終了する。
- テストと検証では利用者の実際の`HOME`を変更しない。
- Ruby、TypeScript、JavaScriptファイルは追加しない。

---

## File Structure

- Create: `.agents/skill-dependencies.json` — 外部リポジトリ、固定SHA、sourceとdestinationの宣言
- Create: `.agents/external-skill-adapters/layered-rails-review/SKILL.md` — `review.md`をAgent Skills形式で利用するローカルアダプター
- Create: `scripts/install_external_skills.sh` — 依存定義を検証し、一時スキルバンドルを構築する処理
- Create: `tests/install_external_skills_test.sh` — ローカルfixture Gitリポジトリを使うネットワーク非依存テスト
- Modify: `install.sh` — バンドル構築と両インストール先への安全な反映を統合
- Modify: `README.md` — 外部依存、固定方法、更新方法、必要コマンドの説明

### Task 1: 外部スキルバンドル構築処理

**Files:**
- Create: `scripts/install_external_skills.sh`
- Create: `tests/install_external_skills_test.sh`

**Interfaces:**
- Consumes: `scripts/install_external_skills.sh MANIFEST LOCAL_SKILLS_DIR ADAPTERS_DIR OUTPUT_DIR`
- Consumes: manifest schema `{"repositories":[{"url":string,"revision":string,"artifacts":[{"source":string,"destination":string}]}]}`
- Produces: `OUTPUT_DIR`直下の各スキルディレクトリに`SKILL.md`を含む検証済みスキルバンドル
- Produces: リポジトリごとに一度だけ`Fetching URL@REVISION`という形式の標準出力
- Failure: エラー理由を標準エラーへ出し、`OUTPUT_DIR`の既存内容を変更せず非0で終了

- [ ] **Step 1: 正常系fixtureと失敗系テストを書く**

`tests/install_external_skills_test.sh`に、終了時に一時ディレクトリを削除する最小テストハーネスを作る。

```bash
#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_file() {
  [ -f "$1" ] || fail "expected file: $1"
}

assert_not_exists() {
  [ ! -e "$1" ] || fail "expected path not to exist: $1"
}

assert_contains() {
  grep -Fq "$2" "$1" || fail "expected $1 to contain: $2"
}

create_fixture_repository() {
  fixture_repo="$TEST_ROOT/upstream"
  mkdir -p "$fixture_repo/skills/first" "$fixture_repo/skills/second" \
    "$fixture_repo/skills/no-skill-md" \
    "$fixture_repo/layered-rails/commands"
  printf '%s\n' '---' 'name: first' 'description: First fixture skill.' '---' > "$fixture_repo/skills/first/SKILL.md"
  printf '%s\n' '---' 'name: second' 'description: Second fixture skill.' '---' > "$fixture_repo/skills/second/SKILL.md"
  printf '%s\n' 'Fixture without SKILL.md.' > "$fixture_repo/skills/no-skill-md/README.md"
  printf '%s\n' '# /layers:review' 'Fixture review instructions.' > "$fixture_repo/layered-rails/commands/review.md"
  git -C "$fixture_repo" init -q
  git -C "$fixture_repo" add .
  git -C "$fixture_repo" -c user.name=Test -c user.email=test@example.com commit -qm fixture
  fixture_revision="$(git -C "$fixture_repo" rev-parse HEAD)"
}
```

同じfixtureリポジトリからディレクトリ2件とファイル1件を取得するmanifestを`jq -n`で生成し、次を個別のテスト関数として記述する。

```bash
write_manifest() {
  manifest_path="$1"
  revision="$2"
  jq -n \
    --arg url "$fixture_repo" \
    --arg revision "$revision" \
    '{repositories:[{url:$url,revision:$revision,artifacts:[
      {source:"skills/first",destination:"first"},
      {source:"skills/second",destination:"second"},
      {source:"layered-rails/commands/review.md",destination:"layered-rails-review/references/upstream-review.md"}
    ]}]}' > "$manifest_path"
}

test_builds_complete_bundle() {
  case_root="$TEST_ROOT/happy"
  mkdir -p "$case_root/local/internal" "$case_root/adapters/layered-rails-review"
  printf '%s\n' '---' 'name: internal' 'description: Internal fixture skill.' '---' > "$case_root/local/internal/SKILL.md"
  printf '%s\n' '---' 'name: layered-rails-review' 'description: Review Rails layers.' '---' > "$case_root/adapters/layered-rails-review/SKILL.md"
  write_manifest "$case_root/manifest.json" "$fixture_revision"

  "$ROOT_DIR/scripts/install_external_skills.sh" \
    "$case_root/manifest.json" "$case_root/local" "$case_root/adapters" "$case_root/output" \
    > "$case_root/output.log"

  assert_file "$case_root/output/internal/SKILL.md"
  assert_file "$case_root/output/first/SKILL.md"
  assert_file "$case_root/output/second/SKILL.md"
  assert_file "$case_root/output/layered-rails-review/SKILL.md"
  assert_contains "$case_root/output/layered-rails-review/references/upstream-review.md" 'Fixture review instructions.'
  [ "$(grep -c '^Fetching ' "$case_root/output.log")" -eq 1 ] || fail 'repository must be fetched once'
}
```

以下の共通関数でmanifestの一部を変更し、コマンドが非0になること、事前に作った
`OUTPUT_DIR/sentinel`が残ること、外部artifactが追加されないことを検証する。

```bash
test_rejected_manifest() {
  case_name="$1"
  jq_filter="$2"
  case_root="$TEST_ROOT/rejected-$case_name"
  mkdir -p "$case_root/local/internal" \
    "$case_root/adapters/layered-rails-review" \
    "$case_root/output"
  printf '%s\n' '---' 'name: internal' 'description: Internal fixture skill.' '---' > "$case_root/local/internal/SKILL.md"
  printf '%s\n' '---' 'name: layered-rails-review' 'description: Review Rails layers.' '---' > "$case_root/adapters/layered-rails-review/SKILL.md"
  printf '%s\n' sentinel > "$case_root/output/sentinel"
  write_manifest "$case_root/valid.json" "$fixture_revision"
  jq "$jq_filter" "$case_root/valid.json" > "$case_root/invalid.json"

  if "$ROOT_DIR/scripts/install_external_skills.sh" \
    "$case_root/invalid.json" "$case_root/local" "$case_root/adapters" "$case_root/output" \
    > "$case_root/stdout.log" 2> "$case_root/stderr.log"; then
    fail "expected rejected manifest: $case_name"
  fi

  assert_file "$case_root/output/sentinel"
  assert_not_exists "$case_root/output/first"
}
```

各拒否条件は、次の固定した`jq` filterで実行する。

```bash
test_rejected_manifest non-commit-revision '.repositories[0].revision = "main"'
test_rejected_manifest missing-source '.repositories[0].artifacts[0].source = "skills/missing"'
test_rejected_manifest missing-skill-md '.repositories[0].artifacts[0].source = "skills/no-skill-md"'
test_rejected_manifest unsafe-source '.repositories[0].artifacts[0].source = "../outside"'
test_rejected_manifest absolute-destination '.repositories[0].artifacts[0].destination = "/absolute"'
test_rejected_manifest unsafe-destination '.repositories[0].artifacts[0].destination = "../outside"'
test_rejected_manifest duplicate-destination '.repositories[0].artifacts[1].destination = "first"'
```

テスト末尾では全テスト関数を明示的に呼ぶ。

```bash
create_fixture_repository
test_builds_complete_bundle
test_rejected_manifest non-commit-revision '.repositories[0].revision = "main"'
test_rejected_manifest missing-source '.repositories[0].artifacts[0].source = "skills/missing"'
test_rejected_manifest missing-skill-md '.repositories[0].artifacts[0].source = "skills/no-skill-md"'
test_rejected_manifest unsafe-source '.repositories[0].artifacts[0].source = "../outside"'
test_rejected_manifest absolute-destination '.repositories[0].artifacts[0].destination = "/absolute"'
test_rejected_manifest unsafe-destination '.repositories[0].artifacts[0].destination = "../outside"'
test_rejected_manifest duplicate-destination '.repositories[0].artifacts[1].destination = "first"'
echo 'All external skill installer tests passed.'
```

- [ ] **Step 2: テストを実行して失敗を確認する**

Run: `bash tests/install_external_skills_test.sh`

Expected: FAIL with `scripts/install_external_skills.sh: No such file or directory`

- [ ] **Step 3: manifest検証とバンドル構築を実装する**

`scripts/install_external_skills.sh`をBash 3.2で動く構文だけで実装する。出力先へ直接構築せず、同じ親ディレクトリに作った一時バンドルを完成後に`OUTPUT_DIR`へ切り替える。

```bash
#!/bin/bash
set -euo pipefail

[ "$#" -eq 4 ] || {
  echo "Usage: $0 MANIFEST LOCAL_SKILLS_DIR ADAPTERS_DIR OUTPUT_DIR" >&2
  exit 64
}

MANIFEST="$1"
LOCAL_SKILLS_DIR="$2"
ADAPTERS_DIR="$3"
OUTPUT_DIR="$4"

die() {
  echo "External skill installation failed: $*" >&2
  exit 1
}

validate_relative_path() {
  value="$1"
  [ -n "$value" ] || return 1
  case "$value" in
    /*|.|..|*/./*|./*|*/.|*/../*|../*|*/..) return 1 ;;
  esac
}

command -v git >/dev/null 2>&1 || die 'git is required'
command -v jq >/dev/null 2>&1 || die 'jq is required'
[ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"

jq -e '
  .repositories | type == "array" and length > 0 and
  all(.[];
    (.url | type == "string" and length > 0) and
    (.revision | type == "string" and test("^[0-9a-fA-F]{40}$")) and
    (.artifacts | type == "array" and length > 0) and
    all(.artifacts[];
      (.source | type == "string" and length > 0) and
      (.destination | type == "string" and length > 0)))
' "$MANIFEST" >/dev/null || die 'invalid manifest schema or revision'

duplicate_destination="$(jq -r '[.repositories[].artifacts[].destination] | group_by(.)[] | select(length > 1) | .[0]' "$MANIFEST" | head -n 1)"
[ -z "$duplicate_destination" ] || die "duplicate destination: $duplicate_destination"
```

続けて、`mktemp -d`で作った作業領域へ内製スキルとアダプターをコピーする。repositoryオブジェクトは`jq -c '.repositories[]'`で一度ずつ処理し、次のGit操作で固定SHAだけを取得する。

```bash
git -c core.hooksPath=/dev/null init -q "$repository_dir"
git -c core.hooksPath=/dev/null -C "$repository_dir" remote add origin "$url"
git -c core.hooksPath=/dev/null -C "$repository_dir" fetch -q --depth 1 origin "$revision"
git -c core.hooksPath=/dev/null -C "$repository_dir" checkout -q --detach FETCH_HEAD
actual_revision="$(git -C "$repository_dir" rev-parse HEAD)"
[ "$actual_revision" = "$revision" ] || die "revision mismatch for $url: expected $revision, got $actual_revision"
```

artifactごとに`validate_relative_path`を適用する。sourceがディレクトリなら直下の
`SKILL.md`を要求し、sourceがファイルならdestinationの親ディレクトリを作って
コピーする。source配下にシンボリックリンクが一つでもあれば拒否する。destinationが
一時バンドル内に既に存在する場合は上書きせず失敗する。最後に一時バンドル直下の
全ディレクトリへ`SKILL.md`を要求する。

完成した一時バンドルは次の切替処理で`OUTPUT_DIR`へ反映する。切替に失敗した場合は
backupを元へ戻し、既存出力を保全する。

```bash
incoming_dir="$(dirname "$OUTPUT_DIR")/.skill-bundle.incoming.$$"
backup_dir="$(dirname "$OUTPUT_DIR")/.skill-bundle.backup.$$"
rm -rf "$incoming_dir" "$backup_dir"
mv "$bundle_dir" "$incoming_dir"
if [ -e "$OUTPUT_DIR" ]; then
  mv "$OUTPUT_DIR" "$backup_dir"
fi
if mv "$incoming_dir" "$OUTPUT_DIR"; then
  rm -rf "$backup_dir"
else
  rm -rf "$incoming_dir"
  [ ! -e "$backup_dir" ] || mv "$backup_dir" "$OUTPUT_DIR"
  die "could not replace output directory: $OUTPUT_DIR"
fi
```

- [ ] **Step 4: 正常系と失敗系テストを通す**

Run: `bash tests/install_external_skills_test.sh`

Expected: PASS and final line `All external skill installer tests passed.`

Run: `bash -n scripts/install_external_skills.sh tests/install_external_skills_test.sh`

Expected: exit 0 with no output

- [ ] **Step 5: Task 1をコミットする**

```bash
git add scripts/install_external_skills.sh tests/install_external_skills_test.sh
git commit -m "feat: 外部スキルバンドル構築処理を追加"
```

### Task 2: 固定依存定義とLayered Railsアダプター

**Files:**
- Create: `.agents/skill-dependencies.json`
- Create: `.agents/external-skill-adapters/layered-rails-review/SKILL.md`
- Modify: `tests/install_external_skills_test.sh`

**Interfaces:**
- Consumes: Task 1のmanifest schemaと`install_external_skills.sh` CLI
- Produces: `composition-patterns`、`react-best-practices`、`layered-rails-review`の完成バンドル
- Produces: `$layered-rails-review`の明示呼び出し、およびRails差分レビュー要求に対する暗黙呼び出し

- [ ] **Step 1: 実manifestとアダプターの構造テストを書く**

`tests/install_external_skills_test.sh`へ次を追加する。

```bash
test_repository_manifest() {
  manifest="$ROOT_DIR/.agents/skill-dependencies.json"
  jq -e '
    [.repositories[].revision] == [
      "7c180d9044c9ae2b442b567aad4e42a28dd5ed62",
      "1328ef71675315a658fdbd494db4b2fd488c0ec8"
    ] and
    [.repositories[].artifacts[].destination] == [
      "composition-patterns",
      "react-best-practices",
      "layered-rails-review/references/upstream-review.md"
    ]
  ' "$manifest" >/dev/null || fail 'unexpected external skill manifest'
}

test_layered_rails_adapter() {
  adapter="$ROOT_DIR/.agents/external-skill-adapters/layered-rails-review/SKILL.md"
  assert_file "$adapter"
  assert_contains "$adapter" 'name: layered-rails-review'
  assert_contains "$adapter" 'references/upstream-review.md'
}
```

末尾の呼び出し一覧へ`test_repository_manifest`と`test_layered_rails_adapter`を加える。

- [ ] **Step 2: 構造テストを実行して失敗を確認する**

Run: `bash tests/install_external_skills_test.sh`

Expected: FAIL with `.agents/skill-dependencies.json` or adapter `SKILL.md` not found

- [ ] **Step 3: 依存定義とアダプタースキルを追加する**

このStepでは`superpowers:writing-skills`を読み、スキル記述と検証の規約を適用する。

`.agents/skill-dependencies.json`へ次を記録する。

```json
{
  "repositories": [
    {
      "url": "https://github.com/vercel-labs/agent-skills.git",
      "revision": "7c180d9044c9ae2b442b567aad4e42a28dd5ed62",
      "artifacts": [
        {
          "source": "skills/composition-patterns",
          "destination": "composition-patterns"
        },
        {
          "source": "skills/react-best-practices",
          "destination": "react-best-practices"
        }
      ]
    },
    {
      "url": "https://github.com/jasim/layered-rails-skills.git",
      "revision": "1328ef71675315a658fdbd494db4b2fd488c0ec8",
      "artifacts": [
        {
          "source": "layered-rails/commands/review.md",
          "destination": "layered-rails-review/references/upstream-review.md"
        }
      ]
    }
  ]
}
```

`.agents/external-skill-adapters/layered-rails-review/SKILL.md`は、上流文書を正本として必ず全文読んでからレビューし、重要度付きでファイルと行を示すよう定義する。

```markdown
---
name: layered-rails-review
description: Review Rails code changes for layered architecture violations, callback health, concern health, service boundaries, and anemic domain models. Use for Rails architecture reviews and layered design checks.
---

# Layered Rails Review

1. Read `references/upstream-review.md` completely before reviewing code.
2. Determine the requested diff or file scope. If none is specified, review uncommitted changes.
3. Apply the upstream process, checklist, severity levels, and output format.
4. Report only findings supported by the reviewed code. Include the file path and tight line range for every finding.
5. If no violations are found, state that explicitly and identify any testing or inspection gaps.
```

- [ ] **Step 4: manifestとアダプターのテストを通す**

Run: `jq empty .agents/skill-dependencies.json && bash tests/install_external_skills_test.sh`

Expected: PASS and final line `All external skill installer tests passed.`

- [ ] **Step 5: Task 2をコミットする**

```bash
git add .agents/skill-dependencies.json .agents/external-skill-adapters/layered-rails-review/SKILL.md tests/install_external_skills_test.sh
git commit -m "feat: 外部スキル依存定義とRailsレビューを追加"
```

### Task 3: `install.sh`への安全な統合

**Files:**
- Modify: `install.sh:8-18`
- Modify: `install.sh:49-75`
- Modify: `install.sh:133-147`
- Modify: `tests/install_external_skills_test.sh`

**Interfaces:**
- Consumes: Task 1の`install_external_skills.sh MANIFEST LOCAL_SKILLS_DIR ADAPTERS_DIR OUTPUT_DIR`
- Consumes: 任意のテスト用override `SKILL_DEPENDENCIES_FILE`; 未指定時は`.agents/skill-dependencies.json`
- Produces: `install_managed_skills BUNDLE_DIR TARGET_SKILLS_DIR`
- Produces: Codex用とClaude Code用に同一の管理対象スキル集合

- [ ] **Step 1: 一時HOMEを使うend-to-endテストを書く**

fixture repositoryとmanifestを再利用し、`HOME`だけを一時ディレクトリへ差し替えて`install.sh`を実行するテストを追加する。

```bash
test_install_sh_installs_both_targets() {
  case_root="$TEST_ROOT/install-sh"
  test_home="$case_root/home"
  mkdir -p "$test_home/.agents/skills/unmanaged" \
    "$test_home/.claude/skills/unmanaged" \
    "$test_home/.agents/skills/first" \
    "$test_home/.claude/skills/first"
  printf '%s\n' keep > "$test_home/.agents/skills/unmanaged/marker"
  printf '%s\n' keep > "$test_home/.claude/skills/unmanaged/marker"
  printf '%s\n' stale > "$test_home/.agents/skills/first/stale"
  printf '%s\n' stale > "$test_home/.claude/skills/first/stale"
  write_manifest "$case_root/manifest.json" "$fixture_revision"

  HOME="$test_home" SKILL_DEPENDENCIES_FILE="$case_root/manifest.json" \
    bash "$ROOT_DIR/install.sh" > "$case_root/install.log"

  assert_file "$test_home/.agents/skills/first/SKILL.md"
  assert_file "$test_home/.claude/skills/first/SKILL.md"
  assert_file "$test_home/.agents/skills/layered-rails-review/references/upstream-review.md"
  assert_file "$test_home/.claude/skills/layered-rails-review/references/upstream-review.md"
  assert_file "$test_home/.agents/skills/unmanaged/marker"
  assert_file "$test_home/.claude/skills/unmanaged/marker"
  assert_not_exists "$test_home/.agents/skills/first/stale"
  assert_not_exists "$test_home/.claude/skills/first/stale"
}
```

失敗時非変更テストでは、不正SHAのmanifest、既存の`first/original`、存在しない`first/SKILL.md`を用意する。`install.sh`が非0で終了した後も`original`が両インストール先に残ることを確認する。

- [ ] **Step 2: end-to-endテストを実行して失敗を確認する**

Run: `bash tests/install_external_skills_test.sh`

Expected: FAIL because `install.sh` does not read `SKILL_DEPENDENCIES_FILE` and does not install fixture external skills

- [ ] **Step 3: バンドル構築を`install.sh`へ統合する**

冒頭のパス定義へ次を追加する。

```bash
EXTERNAL_SKILL_ADAPTERS_DIR="$AGENTS_SOURCE_DIR/external-skill-adapters"
SKILL_DEPENDENCIES_FILE="${SKILL_DEPENDENCIES_FILE:-$AGENTS_SOURCE_DIR/skill-dependencies.json}"
EXTERNAL_SKILL_INSTALLER="$SCRIPT_DIR/scripts/install_external_skills.sh"
SKILL_BUNDLE_ROOT="$(mktemp -d)"
trap 'rm -rf "$SKILL_BUNDLE_ROOT"' EXIT
SKILL_BUNDLE_DIR="$SKILL_BUNDLE_ROOT/skills"
```

既存のClaude Code用とCodex用の2つのコピーloopより前に、バンドルを一度だけ構築する。

```bash
"$EXTERNAL_SKILL_INSTALLER" \
  "$SKILL_DEPENDENCIES_FILE" \
  "$AGENTS_SOURCE_DIR/skills" \
  "$EXTERNAL_SKILL_ADAPTERS_DIR" \
  "$SKILL_BUNDLE_DIR"
```

管理対象だけをスキル単位で置換する関数を追加する。`skill_name`はバンドル直下の実在ディレクトリ名だけから取得する。

```bash
install_managed_skills() {
  bundle_dir="$1"
  target_dir="$2"
  mkdir -p "$target_dir"

  for skill_dir in "$bundle_dir"/*/; do
    [ -d "$skill_dir" ] || continue
    skill_name="$(basename "$skill_dir")"
    incoming_dir="$target_dir/.${skill_name}.incoming.$$"
    backup_dir="$target_dir/.${skill_name}.backup.$$"
    rm -rf "$incoming_dir" "$backup_dir"
    cp -R "$skill_dir" "$incoming_dir"
    if [ -e "$target_dir/$skill_name" ]; then
      mv "$target_dir/$skill_name" "$backup_dir"
    fi
    if mv "$incoming_dir" "$target_dir/$skill_name"; then
      rm -rf "$backup_dir"
    else
      rm -rf "$incoming_dir"
      [ ! -e "$backup_dir" ] || mv "$backup_dir" "$target_dir/$skill_name"
      return 1
    fi
  done
}
```

既存の2つの`cp -r` loopを`install_managed_skills "$SKILL_BUNDLE_DIR" "$SKILLS_DIR"`と`install_managed_skills "$SKILL_BUNDLE_DIR" "$AGENTS_DIR/skills"`へ置き換える。表示用loopはインストール先を読む既存動作を維持する。

- [ ] **Step 4: end-to-endテストと構文検証を通す**

Run: `bash tests/install_external_skills_test.sh`

Expected: PASS and final line `All external skill installer tests passed.`

Run: `bash -n install.sh scripts/install_external_skills.sh tests/install_external_skills_test.sh`

Expected: exit 0 with no output

- [ ] **Step 5: Task 3をコミットする**

```bash
git add install.sh tests/install_external_skills_test.sh
git commit -m "feat: install.shに外部スキル導入を統合"
```

### Task 4: 利用手順と実GitHub依存の検証

**Files:**
- Modify: `README.md:32-40`
- Modify: `tests/install_external_skills_test.sh`

**Interfaces:**
- Consumes: 実manifestとTask 1のバンドル構築CLI
- Produces: 利用者向けの依存追加、固定SHA更新、失敗時動作の説明
- Produces: 3つの実成果物を含む検証済み一時バンドル

- [ ] **Step 1: README記載を要求する軽量テストを書く**

```bash
test_readme_documents_external_skills() {
  assert_contains "$ROOT_DIR/README.md" '.agents/skill-dependencies.json'
  assert_contains "$ROOT_DIR/README.md" 'commit SHA'
  assert_contains "$ROOT_DIR/README.md" 'composition-patterns'
  assert_contains "$ROOT_DIR/README.md" 'react-best-practices'
  assert_contains "$ROOT_DIR/README.md" 'layered-rails-review'
}
```

末尾の呼び出し一覧へ`test_readme_documents_external_skills`を加える。

- [ ] **Step 2: READMEテストを実行して失敗を確認する**

Run: `bash tests/install_external_skills_test.sh`

Expected: FAIL because `README.md` does not mention `.agents/skill-dependencies.json`

- [ ] **Step 3: READMEへ外部スキル管理手順を追記する**

`README.md`のスキル管理セクションへ、次の事実を追記する。

```text
- 内製スキルの正本は`.agents/skills/`
- 外部スキルの取得元とcommit SHAは`.agents/skill-dependencies.json`
- 非Skill形式の適合処理は`.agents/external-skill-adapters/`
- `./install.sh`は全外部依存を検証後、CodexとClaude Codeの両方へ反映
- 更新時はライセンスと差分を確認し、40桁のcommit SHAを手動更新
- `git`または`jq`の欠如、ネットワーク障害、取得・検証失敗ではインストールを中止
```

- [ ] **Step 4: 全ローカルテストを通す**

Run: `bash tests/install_external_skills_test.sh`

Expected: PASS and final line `All external skill installer tests passed.`

Run: `bash -n install.sh scripts/install_external_skills.sh tests/install_external_skills_test.sh && jq empty .agents/skill-dependencies.json`

Expected: exit 0 with no output

- [ ] **Step 5: 実GitHub依存を一時バンドルへ取得する**

利用者の`HOME`を変更せず、実manifestから一時バンドルを構築する。

```bash
validation_root="$(mktemp -d)"
trap 'rm -rf "$validation_root"' EXIT
scripts/install_external_skills.sh \
  .agents/skill-dependencies.json \
  .agents/skills \
  .agents/external-skill-adapters \
  "$validation_root/skills"
test -f "$validation_root/skills/composition-patterns/SKILL.md"
test -f "$validation_root/skills/react-best-practices/SKILL.md"
test -f "$validation_root/skills/layered-rails-review/SKILL.md"
test -f "$validation_root/skills/layered-rails-review/references/upstream-review.md"
```

Expected: exit 0 and exactly two `Fetching` lines, one per external repository

- [ ] **Step 6: 差分とコメント規約を確認する**

Run: `git diff --check && git status --short`

Expected: no whitespace errors; only this planで指定した実装ファイルと既存のユーザー変更が表示される

新規・変更コメントがある場合は`comment-review`スキルを実行する。実装コードには処理の言い換えコメントを追加せず、非自明な安全制約だけをコメント対象とする。

- [ ] **Step 7: Task 4をコミットする**

```bash
git add README.md tests/install_external_skills_test.sh
git commit -m "docs: 外部スキル依存の管理手順を追加"
```

### Task 5: 完了前の総合検証

**Files:**
- Verify only: `install.sh`
- Verify only: `scripts/install_external_skills.sh`
- Verify only: `tests/install_external_skills_test.sh`
- Verify only: `.agents/skill-dependencies.json`
- Verify only: `.agents/external-skill-adapters/layered-rails-review/SKILL.md`
- Verify only: `README.md`

**Interfaces:**
- Consumes: Tasks 1-4の全成果物
- Produces: 実装完了を裏づけるコマンド出力

- [ ] **Step 1: `superpowers:verification-before-completion`を読む**

完了を報告する前に同スキルの検証手順を適用する。

- [ ] **Step 2: 構文、JSON、ローカルfixtureテストを再実行する**

Run: `bash -n install.sh scripts/install_external_skills.sh tests/install_external_skills_test.sh`

Expected: exit 0 with no output

Run: `jq empty .agents/skill-dependencies.json`

Expected: exit 0 with no output

Run: `bash tests/install_external_skills_test.sh`

Expected: PASS and final line `All external skill installer tests passed.`

- [ ] **Step 3: 実GitHub依存のステージング検証を再実行する**

Task 4 Step 5と同じコマンドを新しい`mktemp -d`で実行する。

Expected: exit 0、2件のリポジトリ取得、3スキルとLayered Rails参照ファイルの存在

- [ ] **Step 4: コミットと作業ツリーを確認する**

Run: `git log -5 --oneline && git status --short`

Expected: Tasks 1-4のコミットが存在する。ユーザーが作成した既存変更は残り、この実装の未コミット変更はない。
