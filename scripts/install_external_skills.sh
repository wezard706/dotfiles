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
WORK_DIR=""

die() {
  echo "External skill installation failed: $*" >&2
  exit 1
}

cleanup() {
  [ -z "$WORK_DIR" ] || rm -rf "$WORK_DIR"
}

validate_relative_path() {
  value="$1"
  [ -n "$value" ] || return 1
  case "$value" in
    /*|.|..|*/./*|./*|*/.|*/../*|../*|*/..) return 1 ;;
  esac
}

copy_skill_directories() {
  source_dir="$1"
  [ -d "$source_dir" ] || die "skill directory not found: $source_dir"
  cp -R "$source_dir"/. "$BUNDLE_DIR"
}

reject_symlinks() {
  source_path="$1"
  [ ! -L "$source_path" ] || die "symbolic link artifact source: $2"
  if find "$source_path" -type l -print -quit | grep -q .; then
    die "symbolic link within artifact source: $2"
  fi
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

[ -d "$LOCAL_SKILLS_DIR" ] || die "local skills directory not found: $LOCAL_SKILLS_DIR"
[ -d "$ADAPTERS_DIR" ] || die "adapters directory not found: $ADAPTERS_DIR"

OUTPUT_PARENT="$(dirname "$OUTPUT_DIR")"
[ -d "$OUTPUT_PARENT" ] || die "output parent directory not found: $OUTPUT_PARENT"

WORK_DIR="$(mktemp -d)"
trap cleanup EXIT
BUNDLE_DIR="$WORK_DIR/bundle"
mkdir "$BUNDLE_DIR"

copy_skill_directories "$LOCAL_SKILLS_DIR"
copy_skill_directories "$ADAPTERS_DIR"

jq -c '.repositories[]' "$MANIFEST" | while IFS= read -r repository; do
  url="$(printf '%s' "$repository" | jq -r '.url')"
  revision="$(printf '%s' "$repository" | jq -r '.revision')"
  repository_dir="$(mktemp -d "$WORK_DIR/repository.XXXXXX")"

  echo "Fetching $url@$revision"
  git -c core.hooksPath=/dev/null init -q "$repository_dir"
  git -c core.hooksPath=/dev/null -C "$repository_dir" remote add origin "$url"
  git -c core.hooksPath=/dev/null -C "$repository_dir" fetch -q --depth 1 origin "$revision"
  git -c core.hooksPath=/dev/null -C "$repository_dir" checkout -q --detach FETCH_HEAD
  actual_revision="$(git -C "$repository_dir" rev-parse HEAD)"
  [ "$actual_revision" = "$revision" ] || die "revision mismatch for $url: expected $revision, got $actual_revision"

  printf '%s' "$repository" | jq -c '.artifacts[]' | while IFS= read -r artifact; do
    source="$(printf '%s' "$artifact" | jq -r '.source')"
    destination="$(printf '%s' "$artifact" | jq -r '.destination')"
    validate_relative_path "$source" || die "unsafe source path: $source"
    validate_relative_path "$destination" || die "unsafe destination path: $destination"

    source_path="$repository_dir/$source"
    destination_path="$BUNDLE_DIR/$destination"
    [ -e "$source_path" ] || die "artifact source not found: $source"
    [ ! -e "$destination_path" ] || die "artifact destination already exists: $destination"
    reject_symlinks "$source_path" "$source"

    if [ -d "$source_path" ]; then
      [ -f "$source_path/SKILL.md" ] || die "artifact skill is missing SKILL.md: $source"
      cp -R "$source_path" "$destination_path"
    elif [ -f "$source_path" ]; then
      mkdir -p "$(dirname "$destination_path")"
      cp "$source_path" "$destination_path"
    else
      die "unsupported artifact source: $source"
    fi
  done
done

if ! find "$BUNDLE_DIR" -mindepth 1 -maxdepth 1 -type d -print | while IFS= read -r skill_dir; do
  [ -f "$skill_dir/SKILL.md" ] || {
    echo "External skill installation failed: bundle skill is missing SKILL.md: $skill_dir" >&2
    exit 1
  }
done; then
  exit 1
fi

incoming_dir="$OUTPUT_PARENT/.skill-bundle.incoming.$$"
backup_dir="$OUTPUT_PARENT/.skill-bundle.backup.$$"
rm -rf "$incoming_dir" "$backup_dir"
mv "$BUNDLE_DIR" "$incoming_dir"
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
