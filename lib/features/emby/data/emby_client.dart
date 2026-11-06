import 'package:cupola/features/emby/data/emby_dialect.dart';
import 'package:cupola/features/jellyfin/data/media_browser_client.dart';

/// Emby's client: [MediaBrowserClient] speaking [EmbyDialect].
///
/// The sibling of `JellyfinClient`, and like it a subclass so that every place
/// naming an Emby connection (providers, tests, the probe) keeps a type of its
/// own and no caller picks a dialect.
///
/// It takes no device labels: an API key behind `X-Emby-Token` registers no
/// device, so there is nothing for a client name or a device id to decorate.
class EmbyClient extends MediaBrowserClient {
  /// See [MediaBrowserClient.new] for what each argument is. [now] is for a
  /// test that needs a captured session list not to go stale.
  EmbyClient({
    required super.baseUrl,
    required super.apiKey,
    super.userId,
    super.pinnedCertFingerprint,
    super.accessHeaders,
    super.onlyAtHome,
    DateTime Function()? now,
  }) : super(dialect: EmbyDialect(now: now ?? DateTime.now));
}
