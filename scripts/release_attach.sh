#!/usr/bin/env bash

# Attaches the packages built on the Mac to the draft release that
# .github/workflows/desktop.yml opened for a tag, then rewrites SHA256SUMS over
# every file the draft now carries. The digests are taken from copies
# downloaded back from GitHub, so they describe what a reader gets, not what
# sits in dist/. The release stays a draft: publishing it is a person's call.
#
#   scripts/release.sh all
#   scripts/release_attach.sh v$(scripts/release_label.sh)

set -euo pipefail

APP_SLUG="cupola"
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TAG="${1:-}"

if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z]+(\.[0-9A-Za-z]+)*)?$ ]]; then
  printf 'Usage: scripts/release_attach.sh vX.Y.Z[-suffix]\n' >&2
  exit 1
fi

RELEASE="${TAG#v}"
EXPECTED=$("$ROOT_DIR/scripts/release_label.sh")
if [[ "$RELEASE" != "$EXPECTED" ]]; then
  printf 'Tag %s does not name this tree, which is %s (pubspec.yaml and kAppPrerelease)\n' "$TAG" "$EXPECTED" >&2
  exit 1
fi

DIST_DIR="$ROOT_DIR/dist/${RELEASE}"
if [[ ! -d "$DIST_DIR" ]]; then
  printf 'No packages in %s: run scripts/release.sh first\n' "$DIST_DIR" >&2
  exit 1
fi

# A published release has readers and digests someone may already have
# checked: only a draft is ever changed here.
STATE=$(gh release view "$TAG" --json isDraft,isPrerelease --jq '"\(.isDraft) \(.isPrerelease)"')
if [[ "$STATE" != true* ]]; then
  printf 'Release %s is not a draft: refusing to change it\n' "$TAG" >&2
  exit 1
fi
if [[ "$RELEASE" == *-* && "$STATE" != *" true" ]]; then
  printf 'Release %s has a suffix but is not marked as a prerelease\n' "$TAG" >&2
  exit 1
fi

PACKAGES=()
for ext in apk ipa dmg; do
  file="$DIST_DIR/${APP_SLUG}-${RELEASE}.${ext}"
  if [[ -f "$file" ]]; then
    PACKAGES+=("$file")
  else
    printf 'SKIP: no %s\n' "$(basename "$file")"
  fi
done
if [[ ${#PACKAGES[@]} -eq 0 ]]; then
  printf 'No packages to attach in %s\n' "$DIST_DIR" >&2
  exit 1
fi

printf '==> Attaching %d packages to %s...\n' "${#PACKAGES[@]}" "$TAG"
gh release upload "$TAG" "${PACKAGES[@]}" --clobber

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

printf '==> Downloading the draft back to take its digests...\n'
gh release download "$TAG" --dir "$WORK_DIR"
rm -f "$WORK_DIR/SHA256SUMS"

for file in "$WORK_DIR"/*; do
  case "$(basename "$file")" in
    "${APP_SLUG}-${RELEASE}".* | "${APP_SLUG}-${RELEASE}"-*) ;;
    *)
      printf 'Draft %s carries %s, which is not a %s package\n' "$TAG" "$(basename "$file")" "$RELEASE" >&2
      exit 1
      ;;
  esac
done

for archive in linux-x64.tar.gz windows-x64.zip; do
  if [[ ! -f "$WORK_DIR/${APP_SLUG}-${RELEASE}-${archive}" ]]; then
    printf 'Warning: the draft has no %s-%s-%s yet\n' "$APP_SLUG" "$RELEASE" "$archive" >&2
  fi
done

(cd "$WORK_DIR" && shasum -a 256 -- * > SHA256SUMS)
gh release upload "$TAG" "$WORK_DIR/SHA256SUMS" --clobber

printf '\n==> SHA256SUMS on %s:\n' "$TAG"
cat "$WORK_DIR/SHA256SUMS"
printf '\nThe release is still a draft: review and publish it on GitHub.\n'
