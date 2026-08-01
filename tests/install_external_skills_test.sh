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

test_readme_documents_external_skills() {
  assert_contains "$ROOT_DIR/README.md" '.agents/skill-dependencies.json'
  assert_contains "$ROOT_DIR/README.md" 'commit SHA'
  assert_contains "$ROOT_DIR/README.md" 'composition-patterns'
  assert_contains "$ROOT_DIR/README.md" 'react-best-practices'
  assert_contains "$ROOT_DIR/README.md" 'layered-rails-review'
}

test_install_sh_replaces_managed_skills_in_both_targets() {
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

test_install_sh_preserves_existing_skills_when_bundle_build_fails() {
  case_root="$TEST_ROOT/install-sh-failure"
  test_home="$case_root/home"
  mkdir -p "$test_home/.agents/skills/first" "$test_home/.claude/skills/first"
  printf '%s\n' original > "$test_home/.agents/skills/first/original"
  printf '%s\n' original > "$test_home/.claude/skills/first/original"
  write_manifest "$case_root/valid.json" "$fixture_revision"
  jq '.repositories[0].revision = "0000000000000000000000000000000000000000"' \
    "$case_root/valid.json" > "$case_root/invalid.json"

  if HOME="$test_home" SKILL_DEPENDENCIES_FILE="$case_root/invalid.json" \
    bash "$ROOT_DIR/install.sh" > "$case_root/stdout.log" 2> "$case_root/stderr.log"; then
    fail 'expected install.sh to fail when the external skill bundle cannot be built'
  fi

  assert_file "$test_home/.agents/skills/first/original"
  assert_file "$test_home/.claude/skills/first/original"
  assert_not_exists "$test_home/.agents/skills/first/SKILL.md"
  assert_not_exists "$test_home/.claude/skills/first/SKILL.md"
}

create_fixture_repository
test_builds_complete_bundle
test_rejected_manifest non-commit-revision '.repositories[0].revision = "main"'
test_rejected_manifest missing-source '.repositories[0].artifacts[0].source = "skills/missing"'
test_rejected_manifest missing-skill-md '.repositories[0].artifacts[0].source = "skills/no-skill-md"'
test_rejected_manifest unsafe-source '.repositories[0].artifacts[0].source = "../outside"'
test_rejected_manifest absolute-destination '.repositories[0].artifacts[0].destination = "/absolute"'
test_rejected_manifest unsafe-destination '.repositories[0].artifacts[0].destination = "../outside"'
test_rejected_manifest duplicate-destination '.repositories[0].artifacts[1].destination = "first"'
test_repository_manifest
test_layered_rails_adapter
test_readme_documents_external_skills
test_install_sh_replaces_managed_skills_in_both_targets
test_install_sh_preserves_existing_skills_when_bundle_build_fails
echo 'All external skill installer tests passed.'
