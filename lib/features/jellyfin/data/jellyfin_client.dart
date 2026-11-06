import 'package:cupola/features/jellyfin/data/media_browser_client.dart';
import 'package:cupola/features/jellyfin/data/media_browser_dialect.dart';

// Everything that used to be declared here (the constants, the header builder,
// the device id, the search bands, the viewer-required exception) lives with
// the shared client now, and is re-exported so the import path every caller and
// test already uses keeps naming all of it.
export 'package:cupola/features/jellyfin/data/media_browser_client.dart';
export 'package:cupola/features/jellyfin/data/media_browser_dialect.dart';

/// Jellyfin's client: [MediaBrowserClient] speaking [JellyfinDialect].
///
/// A subclass rather than an alias so that every place that names a Jellyfin
/// connection (providers, tests, the probe) keeps its type, and so the
/// constructor is the one it has always had: no caller picks a dialect.
class JellyfinClient extends MediaBrowserClient {
  /// See [MediaBrowserClient.new] for what each argument is.
  JellyfinClient({
    required super.baseUrl,
    required super.apiKey,
    super.userId,
    super.clientName,
    super.deviceName,
    super.deviceId,
    super.appVersion,
    super.pinnedCertFingerprint,
    super.accessHeaders,
    super.onlyAtHome,
  }) : super(dialect: const JellyfinDialect());

  /// How far back a session counts as "active"; see
  /// [JellyfinDialect.activeWithinSeconds].
  static const int kActiveWithinSeconds = JellyfinDialect.activeWithinSeconds;
}
