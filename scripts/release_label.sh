#!/usr/bin/env bash

# Prints the release this tree is, as its packages and its tag name it:
# `1.1.0` or `1.1.0-beta`. The three numbers come from pubspec.yaml (App
# Store Connect accepts nothing else there); the suffix comes from
# kAppPrerelease in lib/core/app_identity.dart, the one place it is written, so
# the Settings footer, the package names, the tag and the CI's desktop builds
# always name the same release.
#
#   scripts/release_label.sh            # 1.1.0-beta
#   scripts/release_label.sh --version  # 1.1.0

set -euo pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

VERSION=$(grep '^version:' "$ROOT_DIR/pubspec.yaml" | sed 's/version: *//;s/+.*//')
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  printf 'pubspec.yaml version is not three numbers: %s\n' "$VERSION" >&2
  exit 1
fi

IDENTITY="$ROOT_DIR/lib/core/app_identity.dart"
APP_VERSION=$(sed -n "s/^const String kAppVersion = '\(.*\)';$/\1/p" "$IDENTITY")
if [[ "$APP_VERSION" != "$VERSION" ]]; then
  printf 'kAppVersion (%s) does not match pubspec.yaml (%s)\n' "$APP_VERSION" "$VERSION" >&2
  exit 1
fi

if ! grep -q "^const String kAppPrerelease = '.*';$" "$IDENTITY"; then
  printf 'No kAppPrerelease in %s\n' "$IDENTITY" >&2
  exit 1
fi
PRERELEASE=$(sed -n "s/^const String kAppPrerelease = '\(.*\)';$/\1/p" "$IDENTITY")
if [[ -n "$PRERELEASE" && ! "$PRERELEASE" =~ ^[0-9A-Za-z]+(\.[0-9A-Za-z]+)*$ ]]; then
  printf 'kAppPrerelease is not dot-separated words: %s\n' "$PRERELEASE" >&2
  exit 1
fi

if [[ "${1:-}" == "--version" ]]; then
  printf '%s\n' "$VERSION"
elif [[ -n "$PRERELEASE" ]]; then
  printf '%s-%s\n' "$VERSION" "$PRERELEASE"
else
  printf '%s\n' "$VERSION"
fi
