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
