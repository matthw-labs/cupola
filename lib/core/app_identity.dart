/// Who this app says it is: name, version, licence.
///
/// Three consts and no plugin, deliberately. The obvious way to get a version
/// into the UI is `package_info_plus`, and this project refuses it by name:
/// `kPlexProductVersion` in `features/plex/data/plex_client.dart` carries the
/// refusal and the reason: *the project takes no new dependencies*. That is not
/// squeamishness about one package. The version string is wanted in exactly two
/// places (a settings footer and a header a media server records in its
/// authorised-devices list), both of which are reached before any async work is
/// allowed to happen, and `package_info_plus` answers over a platform channel:
/// so a const string is not the cheap approximation of the plugin, it is the
/// better shape: no `Future`, no `MissingPluginException` on a platform whose
/// implementation is missing, nothing to mock in a widget test.
///
/// The cost is that these track `pubspec.yaml` by hand. That cost is real and it
/// is the whole reason they are in *one* file: before this, the only version
/// literal in the app was the Plex header, which had drifted to `0.8.0` while
/// the pubspec said 1.0.0; one copy is a thing you forget to update, and two
/// copies are a thing you update inconsistently.
library;

/// The product name, as a person reads it: window strips, breadcrumbs,
/// footers, and the name a media server files this client under.
///
/// Not derived from the package name (`cupola`) or the bundle id: those are
/// identifiers that happen to look like the name today, and the app was called
/// Seekarr until recently.
const String kAppName = 'Cupola';

/// The user-facing version, mirroring `pubspec.yaml`'s `version:` with the
/// build number dropped.
///
/// The build number is deliberately absent: `1.0.0+1` is what a store needs to
/// order two uploads of the same release, and a settings footer reading
/// "Cupola 1.0.0+1" prints an increment that means nothing to the person
/// reading it.
const String kAppVersion = '1.1.0';

/// The prerelease this build is, without its dash (`beta`), or empty for a
/// stable release.
///
/// It lives here and not in `pubspec.yaml` because App Store Connect refuses a
/// version that is not three numbers, so the pubspec cannot carry it. It is the
/// one source of the suffix: `scripts/release_label.sh` reads it for the
/// package names, the tag and the CI's desktop builds, so the footer, the
/// packages and the release page always name the same beta.
const String kAppPrerelease = 'beta';

/// The release as a person reads it, suffix included: `1.1.0-beta`.
///
/// The suffix is a word, never numbered: a version has one beta at most, and
/// the next beta moves the version itself (`1.1.1-beta`), so the footer of
/// every build a person can hold names a different release.
const String kAppRelease = kAppPrerelease == ''
    ? kAppVersion
    : '$kAppVersion-$kAppPrerelease';

/// The licence, by SPDX identifier.
///
/// Apache-2.0 rather than MIT, and the distinction is load-bearing rather than
/// decorative: the relicense landed on this branch only, so a footer that
/// hardcoded "MIT" would be making a legal claim about the wrong tree. SPDX
/// short form because that is what the `LICENSE` file at the root is, and a
/// footer is not the place to spell out "Apache License, Version 2.0".
const String kAppLicence = 'Apache-2.0';

/// The one line a settings footer prints: `Cupola 1.1.0-beta · Apache-2.0`.
///
/// Assembled here rather than at the call site so the separator, the spacing and
/// the order are decided once. A middot with hair spaces around it is the app's
/// separator everywhere else a readout joins two facts, and a second surface
/// wanting this line must print the same one rather than an em dash version of
/// it.
const String kAppIdentityLine = '$kAppName $kAppRelease\u00A0· $kAppLicence';
