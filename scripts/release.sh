#!/usr/bin/env bash

set -euo pipefail

TARGET="${1:-all}"
APP_NAME="Cupola"
APP_SLUG="cupola"
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

case "$TARGET" in
  android|ios|testflight|macos|web|windows|linux|all)
    ;;
  *)
    printf 'Usage: scripts/release.sh [android|ios|testflight|macos|web|windows|linux|all]\n' >&2
    exit 1
    ;;
esac

VERSION=$(grep '^version:' "$ROOT_DIR/pubspec.yaml" | sed 's/version: *//;s/+.*//')

if [[ -z "$VERSION" ]]; then
  printf 'Failed to read version from pubspec.yaml\n' >&2
  exit 1
fi

# The version reaches an AppleScript heredoc and `rm -rf "$DIST_DIR"`. A branch
# whose `version:` was edited to carry quotes or `..` must fail here, before
# either interpreter sees it.
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$ ]] ||
  [[ "$VERSION" == *..* ]]; then
  printf 'Refusing a version that is not a release version: %s\n' "$VERSION" >&2
  exit 1
fi

# A prerelease keeps pubspec.yaml's three numbers (App Store Connect refuses
# anything else) and carries its suffix in the package names and the tag only:
# CUPOLA_PRERELEASE=beta.1 packages `cupola-1.0.0-beta.1.*` for `v1.0.0-beta.1`.
RELEASE="$VERSION"
if [[ -n "${CUPOLA_PRERELEASE:-}" ]]; then
  if [[ ! "$CUPOLA_PRERELEASE" =~ ^[0-9A-Za-z]+(\.[0-9A-Za-z]+)*$ ]]; then
    printf 'Refusing a prerelease suffix that is not dot-separated words: %s\n' "$CUPOLA_PRERELEASE" >&2
    exit 1
  fi
  RELEASE="${VERSION}-${CUPOLA_PRERELEASE}"
fi

cd "$ROOT_DIR"

# A release is the production identity (AGENTS.md, App identities). Flutter
# hands every FLUTTER_XCODE_* variable to xcodebuild as a build setting, so a
# shell left over from scripts/run_dev.sh or the testlab would ship a suffixed
# bundle id or isolated entitlements.
if env | grep -q '^FLUTTER_XCODE_'; then
  printf 'Refusing to release with FLUTTER_XCODE_* set: %s\n' \
    "$(env | grep '^FLUTTER_XCODE_' | cut -d= -f1 | tr '\n' ' ')" >&2
  exit 1
fi

# The macOS app ships exported for Developer ID (macos/ExportOptions.plist):
# signed with the team's Developer ID certificate, carrying a Developer ID
# profile that opens on any Mac and keeps the data protection keychain, then
# notarized and stapled. CUPOLA_NOTARY_PROFILE names the credentials saved once
# with `xcrun notarytool store-credentials`.
if [[ ("$TARGET" == "macos" || "$TARGET" == "all") && "$(uname -s)" == "Darwin" ]]; then
  if [[ -z "${CUPOLA_NOTARY_PROFILE:-}" ]]; then
    printf 'Set CUPOLA_NOTARY_PROFILE to notarize the macOS app\n' >&2
    exit 1
  fi
  MACOS_TEAM_ID=$(/usr/libexec/PlistBuddy -c 'Print :teamID' macos/ExportOptions.plist)
  MACOS_SIGN_IDENTITY=$(security find-identity -v -p codesigning \
    | awk -v team="($MACOS_TEAM_ID)" '/"Developer ID Application: / && index($0, team) { print $2; exit }')
  if [[ -z "$MACOS_SIGN_IDENTITY" ]]; then
    printf 'No Developer ID Application certificate for team %s in the keychain\n' "$MACOS_TEAM_ID" >&2
    exit 1
  fi
fi

DIST_DIR="dist/${RELEASE}"
# An upload leaves the packages already built in place.
if [[ "$TARGET" != "testflight" ]]; then
  rm -rf "$DIST_DIR"
  mkdir -p "$DIST_DIR"
fi

printf '==> Getting Flutter packages...\n'
flutter pub get

printf '==> Running flutter analyze...\n'
flutter analyze --fatal-infos

printf '==> Checking dart format...\n'
# The tracked files only, as CI sees them from a clean checkout: a walk of `.`
# also enters ignored state, and a container's directory there that the user
# cannot read stops the release before anything is built.
git ls-files -z -- '*.dart' | xargs -0 dart format --output=none --set-exit-if-changed

printf '==> Running the test suite...\n'
dart run tool/test_bundles/test_bundles.dart

printf '==> Verifying icon font subsetting...\n'
flutter test test/tool/material_symbols_subset_test.dart

printf '==> Verifying platform icons...\n'
bash "$ROOT_DIR/scripts/verify_icons.sh"

if [[ "$TARGET" == "android" || "$TARGET" == "all" ]]; then
  printf '==> Building Android APK...\n'
  flutter build apk --release
  cp build/app/outputs/flutter-apk/app-release.apk "$DIST_DIR/${APP_SLUG}-${RELEASE}.apk"
fi

# `web` is a compile check, not a shipped target: the README says there is no
# web client, and a browser build would keep the app's wrapping key beside its
# ciphertext in `localStorage` and lose `badCertificateCallback` entirely.
# `all` therefore packages the five native targets only; `release.sh web`
# remains for a deliberate local build.
if [[ "$TARGET" == "web" ]]; then
  printf '==> Building web release...\n'
  flutter build web --release
  cp -R build/web "$DIST_DIR/web"
fi

if [[ "$TARGET" == "windows" || "$TARGET" == "all" ]]; then
  case "$(uname -s)" in
    MINGW*|MSYS*|CYGWIN*) windows_host=true ;;
    *) windows_host=false ;;
  esac
  if [[ "$windows_host" != true ]]; then
    if [[ "$TARGET" == "windows" ]]; then
      printf 'Windows releases can only be built on a Windows host\n' >&2
      exit 1
    fi
    printf 'SKIP: Windows release requires a Windows host\n'
  else
    printf '==> Building Windows release...\n'
    flutter build windows --release
    cp -R build/windows/x64/runner/Release "$DIST_DIR/windows"
  fi
fi

if [[ "$TARGET" == "linux" || "$TARGET" == "all" ]]; then
  if [[ "$(uname -s)" != "Linux" ]]; then
    if [[ "$TARGET" == "linux" ]]; then
      printf 'Linux releases can only be built on a Linux host\n' >&2
      exit 1
    fi
    printf 'SKIP: Linux release requires a Linux host\n'
  else
    printf '==> Building Linux release...\n'
    flutter build linux --release
    cp -R build/linux/x64/release/bundle "$DIST_DIR/linux"
  fi
fi

if [[ "$TARGET" == "ios" || "$TARGET" == "all" ]]; then
  if [[ "$(uname -s)" != "Darwin" ]]; then
    if [[ "$TARGET" == "ios" ]]; then
      printf 'iOS releases can only be built on macOS\n' >&2
      exit 1
    fi
    printf 'SKIP: iOS release requires a macOS host\n'
  else
    printf '==> Building iOS IPA (unsigned, for sideloading)...\n'
    flutter build ios --release --no-codesign

    APP_PATH="build/ios/iphoneos/Runner.app"
    IPA_PATH="$DIST_DIR/${APP_SLUG}-${RELEASE}.ipa"

    if [[ ! -d "$APP_PATH" ]]; then
      printf 'Missing iOS app bundle at %s\n' "$APP_PATH" >&2
      exit 1
    fi

    IPA_WORK_DIR=$(mktemp -d)
    mkdir -p "$IPA_WORK_DIR/Payload"
    cp -r "$APP_PATH" "$IPA_WORK_DIR/Payload/"
    (cd "$IPA_WORK_DIR" && zip -qr - Payload/) > "$IPA_PATH"
    rm -rf "$IPA_WORK_DIR"

    printf '==> IPA ready for sideloading: %s\n' "$IPA_PATH"
  fi
fi

# TestFlight is never part of `all`: it uploads the iOS build and then the macOS
# one to App Store Connect, signed for the store by the team in
# ios/ExportOptions-testflight.plist and macos/ExportOptions-testflight.plist
# with the Apple ID signed in to Xcode. Both platforms share one build number,
# higher than the last upload: it defaults to the UTC minute
# (CUPOLA_BUILD_NUMBER overrides it); the version stays the one in
# pubspec.yaml. macOS goes second so a signing failure there never costs the
# iOS upload.
if [[ "$TARGET" == "testflight" ]]; then
  if [[ "$(uname -s)" != "Darwin" ]]; then
    printf 'TestFlight uploads can only be made on macOS\n' >&2
    exit 1
  fi

  BUILD_NUMBER="${CUPOLA_BUILD_NUMBER:-$(date -u +%Y%m%d%H%M)}"
  printf '==> Archiving iOS %s (%s) for App Store Connect...\n' "$VERSION" "$BUILD_NUMBER"
  flutter build ios --release --config-only --build-number "$BUILD_NUMBER"
  IOS_ARCHIVE="build/ios/${APP_NAME}.xcarchive"
  rm -rf "$IOS_ARCHIVE"
  xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner -configuration Release \
    -destination 'generic/platform=iOS' -archivePath "$IOS_ARCHIVE" -allowProvisioningUpdates -quiet archive

  printf '==> Uploading to TestFlight...\n'
  xcodebuild -exportArchive -archivePath "$IOS_ARCHIVE" -exportOptionsPlist ios/ExportOptions-testflight.plist \
    -exportPath "build/ios/testflight" -allowProvisioningUpdates

  printf '==> Archiving macOS %s (%s) for App Store Connect...\n' "$VERSION" "$BUILD_NUMBER"
  flutter build macos --release --config-only --build-number "$BUILD_NUMBER"
  MACOS_TF_ARCHIVE="build/macos/${APP_NAME}-testflight.xcarchive"
  rm -rf "$MACOS_TF_ARCHIVE"
  xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
    -archivePath "$MACOS_TF_ARCHIVE" -allowProvisioningUpdates -quiet archive

  printf '==> Uploading macOS to TestFlight...\n'
  xcodebuild -exportArchive -archivePath "$MACOS_TF_ARCHIVE" \
    -exportOptionsPlist macos/ExportOptions-testflight.plist \
    -exportPath "build/macos/testflight" -allowProvisioningUpdates
fi

if [[ "$TARGET" == "macos" || "$TARGET" == "all" ]]; then
  if [[ "$(uname -s)" != "Darwin" ]]; then
    if [[ "$TARGET" == "macos" ]]; then
      printf 'macOS releases can only be built on macOS\n' >&2
      exit 1
    fi
    printf 'SKIP: macOS release requires a macOS host\n'
  else
    printf '==> Building macOS release...\n'
    flutter build macos --release --config-only
    MACOS_ARCHIVE="build/macos/${APP_NAME}.xcarchive"
    MACOS_EXPORT="build/macos/export"
    rm -rf "$MACOS_ARCHIVE" "$MACOS_EXPORT"
    xcodebuild -workspace macos/Runner.xcworkspace -scheme Runner -configuration Release \
      -archivePath "$MACOS_ARCHIVE" -allowProvisioningUpdates -quiet archive
    xcodebuild -exportArchive -archivePath "$MACOS_ARCHIVE" -exportOptionsPlist macos/ExportOptions.plist \
      -exportPath "$MACOS_EXPORT" -allowProvisioningUpdates

    APP_PATH="$MACOS_EXPORT/${APP_NAME}.app"
    DMG_STEM="$DIST_DIR/${APP_SLUG}-${RELEASE}"
    DMG_PATH="${DMG_STEM}.dmg"
    DMG_WORK_DIR=$(mktemp -d)
    DMG_STAGING_DIR="$DMG_WORK_DIR/staging"
    DMG_RW_PATH="$DMG_WORK_DIR/${APP_SLUG}-${VERSION}-rw.dmg"
    DMG_DEVICE=""
    DMG_MOUNT_DIR=""
    DMG_VOLUME_NAME=""
    VOLUME_NAME="${APP_NAME} ${RELEASE}"

    cleanup() {
      if [[ -n "$DMG_DEVICE" ]]; then
        hdiutil detach "$DMG_DEVICE" -quiet || true
      fi

      rm -rf "$DMG_WORK_DIR"
    }

    trap cleanup EXIT

    if [[ ! -d "$APP_PATH" ]]; then
      printf 'Missing macOS app bundle at %s\n' "$APP_PATH" >&2
      exit 1
    fi

    codesign --verify --deep --strict "$APP_PATH"

    # The app carries its own ticket too, so a copy dragged out of the .dmg
    # opens on a Mac that is offline the first time.
    printf '==> Notarizing macOS app...\n'
    APP_ZIP="$DMG_WORK_DIR/${APP_SLUG}-${VERSION}.zip"
    ditto -c -k --keepParent "$APP_PATH" "$APP_ZIP"
    xcrun notarytool submit "$APP_ZIP" --keychain-profile "$CUPOLA_NOTARY_PROFILE" --wait
    xcrun stapler staple "$APP_PATH"
    spctl --assess --type execute --verbose "$APP_PATH"

    mkdir -p "$DMG_STAGING_DIR"
    ditto "$APP_PATH" "$DMG_STAGING_DIR/${APP_NAME}.app"
    ln -s /Applications "$DMG_STAGING_DIR/Applications"

    printf '==> Creating writable DMG...\n'
    hdiutil create -quiet -fs HFS+ -volname "$VOLUME_NAME" -srcfolder "$DMG_STAGING_DIR" -ov -format UDRW "$DMG_RW_PATH"

    printf '==> Customizing DMG window...\n'
    ATTACH_OUTPUT=$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_RW_PATH")
    DMG_DEVICE=$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_HFS/ { print $1; exit }')
    DMG_MOUNT_DIR=$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/Apple_HFS/ { sub(/^.*Apple_HFS[[:space:]]*/, ""); print; exit }')
    DMG_VOLUME_NAME=$(basename "$DMG_MOUNT_DIR")
    sleep 1

    if ! osascript <<EOF
tell application "Finder"
  tell disk "${DMG_VOLUME_NAME}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set bounds of container window to {120, 120, 660, 420}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 128
    set text size of viewOptions to 14
    set background color of viewOptions to {7967, 12079, 16705}
    set position of item "${APP_NAME}.app" of container window to {170, 170}
    set position of item "Applications" of container window to {430, 170}
    close
    open
    update without registering applications
    delay 2
  end tell
end tell
EOF
    then
      printf 'Warning: Finder customization failed, continuing with default DMG layout\n' >&2
    fi

    bless --folder "$DMG_MOUNT_DIR" --openfolder "$DMG_MOUNT_DIR" >/dev/null 2>&1 || true
    sync
    hdiutil detach "$DMG_DEVICE" -quiet
    DMG_DEVICE=""

    printf '==> Compressing DMG...\n'
    hdiutil convert "$DMG_RW_PATH" -quiet -format UDZO -o "$DMG_STEM"
    codesign --force --timestamp --sign "$MACOS_SIGN_IDENTITY" "$DMG_PATH"

    printf '==> Notarizing DMG...\n'
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$CUPOLA_NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    spctl --assess --type open --context context:primary-signature --verbose "$DMG_PATH"
  fi
fi

if [[ "$TARGET" != "testflight" ]]; then
  printf '\n==> Release artifacts for v%s:\n' "$RELEASE"
  ls -lh "$DIST_DIR/"
fi
