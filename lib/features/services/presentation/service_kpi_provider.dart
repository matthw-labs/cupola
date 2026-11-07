import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderOrFamily;

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/capability/capability_scope.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/platform/device_time_zone.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/dockge/domain/models/dockge_stack.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/music/domain/models/lidarr_artist.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/emby/presentation/emby_provider.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_capability.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/movies/presentation/movies_provider.dart';
import 'package:cupola/features/music/presentation/music_provider.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/prowlarr/domain/models/prowlarr_models.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/nzbget/domain/models/nzbget_models.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/readarr/domain/models/readarr_models.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/domain/torrent_list_order.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/features/services/domain/download_client_faults.dart';
import 'package:cupola/features/services/domain/kpi_aggregate.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_provider.dart';
import 'package:cupola/features/transmission/domain/models/transmission_models.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_media_stats.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';
import 'package:cupola/features/truenas/presentation/truenas_provider.dart';
import 'package:cupola/features/truenas/domain/models/dashboard.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';
import 'package:cupola/features/unraid/domain/unraid_alerts.dart';
import 'package:cupola/features/unraid/presentation/unraid_provider.dart';

/// A download client's Queue tab rail: [serviceKpiProvider] as read, with its
/// rates `—` while the page's stale band is up ([withRatesNotUpdating]).
///
/// Not `whenData`: a stale page's rail is reloading behind a read that does
/// not come back, and `whenData` drops a reload's previous figures, which
/// put the rail back to its skeleton.
AsyncValue<List<ServiceKpi>> queueRailOf(
  AsyncValue<List<ServiceKpi>> kpis, {
  required bool stale,
}) => stale && kpis.hasValue && !kpis.hasError
    ? AsyncData(withRatesNotUpdating(kpis.requireValue))
    : kpis;

/// KPIs shown in the [ServiceKpiPeek] at the top of each service page.
///
/// Derives metrics from the same sources the pages load, so the figures agree
/// with the lists. A page that already watches a live stream derives its rail
/// from that watch (Dockge does); this provider then serves the dashboard
/// card's snapshot.
final serviceKpiProvider = FutureProvider.autoDispose
    .family<List<ServiceKpi>, ServiceKey>((ref, service) async {
      switch (service) {
        case ServiceKey.radarr:
          return _radarrKpis(ref);
        case ServiceKey.sonarr:
          return _sonarrKpis(ref);
        case ServiceKey.lidarr:
          return _lidarrKpis(ref);
        case ServiceKey.qbittorrent:
          return _qbittorrentKpis(ref);
        case ServiceKey.seerr:
          return _seerrKpis(ref);
        case ServiceKey.bazarr:
          return _bazarrKpis(ref);
        case ServiceKey.truenas:
          return _truenasKpis(ref);
        case ServiceKey.dockge:
          return _dockgeKpis(ref);
        case ServiceKey.prowlarr:
          return _prowlarrKpis(ref);
        case ServiceKey.readarr:
          return _readarrKpis(ref);
        case ServiceKey.sabnzbd:
          return _sabnzbdKpis(ref);
        case ServiceKey.nzbget:
          return _nzbgetKpis(ref);
        case ServiceKey.unraid:
          return _unraidKpis(ref);
        case ServiceKey.transmission:
          return _transmissionKpis(ref);
        case ServiceKey.nginxProxyManager:
          return _npmKpis(ref);
        case ServiceKey.tracearr:
          return _tracearrKpis(ref);
        // Providers, not the clients directly: the figures need a failure that
        // survives the fetch, and the provider layer is what makes that
        // shareable with the Overview, invalidatable with the rest and
        // overridable by name in a test. The sessions are the very read the
        // room's Now playing and its light take, so the figure cannot say
        // `1 stream` over a list that has moved on (or the other way round).
        //
        // What a refusal means is asked through the container, captured now:
        // the answer is needed after the reads, past an `await`, where this
        // `autoDispose` provider's `ref` must not be used.
        case ServiceKey.jellyfin || ServiceKey.emby:
          final container = ref.container;
          final providers = mediaBrowserProvidersOf(service);
          return _mediaBrowserKpis(
            ref.watch(providers.sessions.future),
            ref.watch(providers.strictLibraries.future),
            kind: () => container.read(providers.credentialKind.future),
          );
        case ServiceKey.plex:
          final container = ref.container;
          return _plexKpis(
            ref.watch(plexSessionsProvider.future),
            ref.watch(plexStrictLibrariesProvider.future),
            probe: () => container.read(
              connectionCapabilityProvider(
                container.read(activeInstanceProvider(ServiceKey.plex))?.id ??
                    '',
              ).future,
            ),
          );
      }
    }, retry: noProviderRetry);

/// Every provider [serviceKpiProvider] reads for [service]: the sources, not
/// the folds.
///
/// A pull that invalidates only [serviceKpiProvider] re-folds the same cached
/// answers: most of these are plain `FutureProvider`s that live as long as the
/// app, so the Dashboard's refresh redrew thirteen stack cards from figures it
/// never re-asked for, and a source that had failed stayed failed however many
/// times it was pulled. Kept beside the switch above and exhaustive over
/// [ServiceKey], so a service added there cannot be missing here.
///
/// The per-connection readers behind [serviceKpiForProvider] ask their client
/// directly, except the arrs' libraries, which are read once a session per
/// connection ([moviesForProvider] and its siblings) and listed here with the
/// lens's.
List<ProviderOrFamily> serviceKpiSources(ServiceKey service) =>
    switch (service) {
      // The family behind the snapshot, not the lens wrapper alone: that one
      // only resolves the lens and re-watches its family member, which keeps
      // the answer it already had.
      ServiceKey.radarr => [
        radarrKpiLibraryProvider,
        moviesForProvider,
        radarrQueueSnapshotProvider,
        radarrQueueSnapshotForProvider,
      ],
      ServiceKey.sonarr => [sonarrKpiLibraryProvider, seriesForProvider],
      ServiceKey.lidarr => [
        lidarrKpiLibraryProvider,
        musicForProvider,
        lidarrAlbumKeysForProvider,
      ],
      ServiceKey.readarr => [
        readarrKpiLibraryProvider,
        readarrAuthorsForProvider,
        readarrQueueProvider,
      ],
      ServiceKey.qbittorrent => [allTorrentsProvider],
      ServiceKey.seerr => [requestRowsProvider],
      // Both halves of [_bazarrKpis]: the provider statuses live as long as
      // the app, so a failure left in them outlasts every pull that skips them.
      ServiceKey.bazarr => [
        bazarrBadgesProvider,
        bazarrProviderStatusesProvider,
      ],
      ServiceKey.truenas => [truenasDashboardProvider],
      ServiceKey.dockge => [dockgeStackListProvider],
      ServiceKey.prowlarr => [
        prowlarrIndexersProvider,
        prowlarrIndexerStatsProvider,
      ],
      ServiceKey.sabnzbd => [sabnzbdQueueProvider, sabnzbdServerStatsProvider],
      ServiceKey.nzbget => [nzbgetStatusProvider, nzbgetQueueProvider],
      ServiceKey.unraid => [unraidArrayProvider, unraidDockerProvider],
      ServiceKey.transmission => [
        transmissionStatsProvider,
        transmissionTorrentsProvider,
      ],
      ServiceKey.nginxProxyManager => [
        npmProxyHostsProvider,
        npmCertificatesProvider,
      ],
      ServiceKey.jellyfin => [
        jellyfinSessionsProvider,
        jellyfinStrictLibrariesProvider,
      ],
      ServiceKey.emby => [embySessionsProvider, embyStrictLibrariesProvider],
      ServiceKey.tracearr => [
        tracearrLiveProvider,
        tracearrTodayProvider,
        tracearrUnseenViolationsProvider,
        tracearrServersProvider,
      ],
      ServiceKey.plex => [plexSessionsProvider, plexStrictLibrariesProvider],
    };

/// The [serviceKpiSources] that download a whole library: the arrs' `GET /movie`,
/// `/series`, `/artist`, `/album` and `/author`, the heaviest answers the app
/// asks for, behind figures that change a few times a day.
///
/// A silent return to Stack skips these until they are old enough to be worth
/// the download; a pull or a re-tap reads them like everything else.
List<ProviderOrFamily> serviceKpiLibrarySources(ServiceKey service) =>
    switch (service) {
      ServiceKey.radarr => [radarrKpiLibraryProvider, moviesForProvider],
      ServiceKey.sonarr => [sonarrKpiLibraryProvider, seriesForProvider],
      ServiceKey.lidarr => [
        lidarrKpiLibraryProvider,
        musicForProvider,
        lidarrAlbumKeysForProvider,
      ],
      ServiceKey.readarr => [
        readarrKpiLibraryProvider,
        readarrAuthorsForProvider,
      ],
      _ => const [],
    };

/// What a service page's pull-to-refresh has to re-ask: its reachability probe
/// and every source its KPI rail reads.
///
/// [serviceSummaryProvider] only delegates to [instanceSummaryProvider], which
/// is not `autoDispose`; invalidating the wrapper alone redrew the identity
/// band from the probe already in the cache, so a pull never asked the server
/// whether it was up. And [serviceKpiProvider] folds sources that live as long
/// as the app: see [serviceKpiSources].
void invalidateServiceReadout(WidgetRef ref, ServiceKey service) {
  ref.invalidate(serviceSummaryProvider(service));
  for (final instance
      in ref.read(currentSettingsProvider).configuredInstancesOf(service)) {
    ref.invalidate(
      instanceSummaryProvider((service: service, instanceId: instance.id)),
    );
  }
  ref.invalidate(serviceKpiProvider(service));
  for (final source in serviceKpiSources(service)) {
    ref.invalidate(source);
  }
}

/// The same KPIs, for one **named connection** rather than for the lens.
///
/// The Dashboard's stack card needs this: a service with two connections draws
/// `×2` and the fleet's figures, and there is no fleet figure to compute while
/// the only thing the app can ask is "what does the lens say". Keyed on
/// [InstanceRef] and not on a bare id, for the reason that record already
/// carries, a probe for a connection that has since been removed still has to
/// know what kind of thing it was.
///
/// The lens's own id collapses back onto [serviceKpiProvider] rather than
/// fetching the same server twice, which is the same collapse
/// `requestsForProvider` and the `*ServiceFor` families make, and what keeps an
/// override of the plain provider from being bypassed in tests.
///
/// **Null means this connection cannot be read on its own yet**, which is not
/// the same as having no figures. Every currently registered service has a
/// keyed reader; keeping the nullable result makes the contract explicit for
/// a future service whose KPI set cannot be addressed per connection. A fold
/// that guessed would print the lens's rate as the fleet's, which is the bug
/// this provider exists to end.
final serviceKpiForProvider = FutureProvider.autoDispose
    .family<List<ServiceKpi>?, InstanceRef>((ref, key) async {
      final lens = ref.watch(activeInstanceProvider(key.service))?.id ?? '';
      if (key.instanceId.isEmpty || key.instanceId == lens) {
        return ref.watch(serviceKpiProvider(key.service).future);
      }
      return switch (key.service) {
        ServiceKey.radarr => await _radarrKpisFor(ref, key.instanceId),
        ServiceKey.sonarr => await _sonarrKpisFor(ref, key.instanceId),
        ServiceKey.lidarr => await _lidarrKpisFor(ref, key.instanceId),
        ServiceKey.seerr => await _seerrKpisFor(ref, key.instanceId),
        ServiceKey.qbittorrent => await _qbittorrentKpisFor(
          ref,
          key.instanceId,
        ),
        ServiceKey.bazarr => await _bazarrKpisFor(ref, key.instanceId),
        ServiceKey.truenas => await _truenasKpisFor(ref, key.instanceId),
        ServiceKey.dockge => await _dockgeKpisFor(ref, key.instanceId),
        ServiceKey.prowlarr => await _prowlarrKpisFor(ref, key.instanceId),
        ServiceKey.readarr => await _readarrKpisFor(ref, key.instanceId),
        ServiceKey.sabnzbd => await _sabnzbdKpisFor(ref, key.instanceId),
        ServiceKey.nzbget => await _nzbgetKpisFor(ref, key.instanceId),
        ServiceKey.unraid => await _unraidKpisFor(ref, key.instanceId),
        ServiceKey.transmission => await _transmissionKpisFor(
          ref,
          key.instanceId,
        ),
        ServiceKey.nginxProxyManager => await _npmKpisFor(ref, key.instanceId),
        ServiceKey.jellyfin || ServiceKey.emby => await _mediaBrowserKpisFor(
          ref,
          key.service,
          key.instanceId,
        ),
        ServiceKey.plex => await _plexKpisFor(ref, key.instanceId),
        ServiceKey.tracearr => await _tracearrKpisFor(ref, key.instanceId),
      };
      // `noProviderRetry`, like the provider above it. The lens path awaits
      // `serviceKpiProvider(...).future`, which settles into a stable error
      // and stops; retrying *here* re-ran it behind an exponential backoff and
      // put the whole storm back one level up, with pending timers that
      // outlive a widget test.
    }, retry: noProviderRetry);

/// The whole service's figures, folded across every connection it has.
///
/// Null when there is no aggregate to show, and the three reasons are all the
/// same refusal:
///
///  * **a connection is dark.** Gated on `offline == 0` before anything is
///    fetched: the fold is never partial, because a sum missing a term looks
///    exactly like a sum.
///  * **a connection cannot be read per connection**: see
///    [serviceKpiForProvider].
///  * **the figures do not fold**: see [aggregateServiceKpis], which is where
///    the arithmetic and, more importantly, the refusals live.
///
/// A single-connection service folds to itself, so the card does not have to
/// know whether it is looking at one server or six.
final foldedServiceKpisProvider = FutureProvider.autoDispose
    .family<List<ServiceKpi>?, ServiceKey>((ref, service) async {
      final settings = ref.watch(currentSettingsProvider);
      final connections = settings.configuredInstancesOf(service);
      if (connections.isEmpty) return null;

      // Lens first. `aggregateServiceKpis` falls back to the head of this list
      // for every figure whose unit cannot be added: a percentage, a ratio, a
      // state word, and the lens is the connection the rest of the app is
      // already pointed at, so it is the only defensible one to keep.
      final lens = ref.watch(activeInstanceProvider(service))?.id;
      final ordered = [
        for (final connection in connections)
          if (connection.id == lens) connection,
        for (final connection in connections)
          if (connection.id != lens) connection,
      ];

      // Reachability first, and **awaited**. Reading the synchronous fold
      // instead was the bug this line replaces: on a cold open every probe is
      // still in flight, so `offline` is zero, the gate opens, and the fold
      // publishes a sum over however many servers happened to have answered.
      // The figure has to wait for every connection to have said something,
      // because that is the whole claim it makes.
      final answers = await Future.wait([
        for (final connection in ordered)
          _connectionAnswers(ref, (
            service: service,
            instanceId: connection.id,
          )),
      ]);
      if (answers.contains(false)) return null;

      final perConnection = await Future.wait([
        for (final connection in ordered)
          ref.watch(
            serviceKpiForProvider((
              service: service,
              instanceId: connection.id,
            )).future,
          ),
      ]);
      // Lidarr's albums are counted off its artists, which name none of
      // them, so the albums each connection holds are read for the fold
      // alone, and only when there is a second connection to fold.
      if (service == ServiceKey.lidarr && ordered.length > 1) {
        return aggregateServiceKpis(
          await _withLidarrAlbums(ref, ordered, perConnection),
        );
      }
      return aggregateServiceKpis(perConnection);
      // Derived from [serviceKpiForProvider], so it carries the flag for the
      // reason that one does.
    }, retry: noProviderRetry);

/// The albums one Lidarr connection holds, by MusicBrainz release group id
/// (`foreignAlbumId`): what lets a fold across two Lidarr count an album
/// both hold once. An album with no id stands for itself.
final lidarrAlbumKeysForProvider = FutureProvider.autoDispose
    .family<Set<Object>, String>((ref, instanceId) async {
      final albums = await ref
          .watch(lidarrServiceForProvider(instanceId))
          .getAllAlbumsOrThrow();
      return {
        for (final album in albums) _titleKey(album, album.foreignAlbumId),
      };
    }, retry: noProviderRetry);

/// Each connection's figures with its albums named, for the fold.
///
/// A connection whose albums could not be read takes the album figure to
/// `—`, as any term that did not answer does: a sum standing in for the
/// union would be a count of copies stated as a count of albums.
Future<List<List<ServiceKpi>?>> _withLidarrAlbums(
  Ref ref,
  List<ServiceInstance> connections,
  List<List<ServiceKpi>?> perConnection,
) async {
  final keys = await Future.wait([
    for (final connection in connections)
      ref
          .watch(lidarrAlbumKeysForProvider(connection.id).future)
          .then<Set<Object>?>((keys) => keys, onError: (_) => null),
  ]);
  return [
    for (var i = 0; i < perConnection.length; i++)
      perConnection[i]
          ?.map((kpi) {
            if (kpi.label != 'Albums' || kpi.isUnavailable) return kpi;
            final albums = keys[i];
            return albums == null
                ? ServiceKpi.unavailable(label: kpi.label, icon: kpi.icon)
                : ServiceKpi(
                    label: kpi.label,
                    value: kpi.value,
                    icon: kpi.icon,
                    tone: kpi.tone,
                    note: kpi.note,
                    members: albums,
                  );
          })
          .toList(growable: false),
  ];
}

/// Whether one connection answered, with a probe that threw counted as a no.
///
/// `instanceSummaryProvider` normally reports an unreachable server as an
/// offline summary rather than by throwing, but the fold must not be the place
/// that finds out otherwise: an error escaping here would take the card into
/// `AsyncError` and lose the reading for every connection that *was* fine.
Future<bool> _connectionAnswers(Ref ref, InstanceRef key) async {
  try {
    return (await ref.watch(instanceSummaryProvider(key).future)).isOnline;
  } catch (_) {
    return false;
  }
}

/// The single live figure a service contributes to the stack matrix on
/// `/services`.
///
int _statInt(Map<String, dynamic>? stats, String key) =>
    (stats?[key] as num?)?.toInt() ?? 0;

/// Flags a metric as a **fault**: something that was meant to be working and
/// is not, and the only one of the three that earns amber.
StatusTone? _faultIf(bool condition) => condition ? StatusTone.warning : null;

/// Flags a metric as **backlog**: work that has not happened yet.
///
/// Noteworthy, because a pile of missing films is why you opened the service;
/// untoned, because it is the resting state of a media manager and not a
/// problem with one. This is the distinction the old single `_warnIf` could not
/// express, and the reason every \*arr shipped with its baseline painted in the
/// alarm colour.
StatusTone? _backlogIf(bool condition) => condition ? StatusTone.neutral : null;

/// Flags a metric as **activity** rather than as a problem: bytes are moving,
/// or somebody is watching, because the stack is doing its job.
StatusTone? _activityIf(bool condition) => condition ? StatusTone.info : null;

/// One figure, or the em dash that stands in for it.
///
/// A null [value] means *nobody answered*, which is the case every \*arr
/// builder below used to print as `0`. Routing both readings of a card through
/// one call is what keeps the label and the icon written once: the rail shows
/// the same four cards whether the server replied or not, so a reader can see
/// *which* figure is missing rather than watching the strip change shape.
ServiceKpi _figure({
  required String label,
  required IconData icon,
  required String? value,
  StatusTone? tone,
  String? note,
  Set<Object>? members,
}) => value == null
    ? ServiceKpi.unavailable(label: label, icon: icon, note: note)
    : ServiceKpi(
        label: label,
        value: value,
        icon: icon,
        tone: tone,
        members: members,
      );

/// The identity a title is counted by across connections: [key] when the
/// service gave one, else the title itself, which merges with nothing.
Object _titleKey(Object title, Object? key) =>
    key == null || key == 0 || key == '' ? title : key;

/// What an unanswered figure says instead of a number.
///
/// Carried by the **first** card only. The note replaces the label on the card
/// that holds it (the rail is two lines tall by construction), so putting it on
/// all four would leave a strip of four identical reasons and no way to tell
/// which absence is which.
///
/// In the classified words, never a guess: "Radarr not answering" was printed
/// for a refused key too, under a header that had just said Answering. A read
/// that failed without saying why is `Did not complete`, not silence.
String _notAnswering(ServiceKey service, Object? error) =>
    '${service.title}\u00A0· '
    '${failureLabel(classifyConnectionFailure(error), credential: refusedCredentialOf(service), gateway: accessGatewayOf(error))}';

/// The shared KPI set for a media server, identical for Jellyfin, Emby and Plex.
///
/// Three metrics, and the order is load-bearing in two ways that
/// `resolveServiceSignalPair` depends on.
///
/// **`Streams` is first, so it is the resting fallback.** With nothing flagged
/// the matrix cell shows `kpis.first`, and `0 streams` is both true and live:
/// unlike a library total, which DESIGN.md rightly calls the least live thing you
/// could put on a control-room screen.
///
/// **`Streams` is only flagged while nothing is transcoding.** The cell shows the
/// *first* flagged KPI, so gating it this way lets the more urgent fact win
/// without teaching the resolver about precedence: idle reads `0 streams` in
/// neutral, a healthy stream reads `2 streaming` in info blue, and the moment the
/// box starts re-encoding it reads `1 transcode` in warning amber. One rule, three
/// correct readings, no special-casing in the shared resolver.
///
/// **There is no aggregate bitrate metric, deliberately.** Neither server reports
/// measured outbound throughput: Jellyfin only carries a bitrate while
/// transcoding, and Plex's `Session.bandwidth` is a reservation. Summing those
/// would add two different units together and present the result as the box's
/// egress: a fabricated number. Per-session bitrate is shown on the board, where
/// `StreamSession.bitrateIsNominal` can say what it actually is.
///
/// **A null future is a read this token may not make**, and its figures read
/// `—` with [sessionsNote] or [librariesNote] saying why: a shared account's
/// Plex token is refused who is watching, a household member's Jellyfin token
/// the library list. Both are configuration, not faults, so the rest of the
/// rail still says what the token could read.
///
/// [sessionsNote] on sessions that did answer says whose they are: a
/// household member's Jellyfin token sees only its own playback, and a count
/// of it must not read as the server's.
Future<List<ServiceKpi>> _streamKpis(
  Future<List<StreamSession>>? sessionsFuture,
  Future<List<StreamLibrary>>? librariesFuture, {
  String? sessionsNote,
  String? librariesNote,
}) async {
  // Both reads are started by the caller so the rail does not wait for one
  // endpoint before asking the other. `Future.wait` is important here rather
  // than two sequential awaits: when an unreachable server rejects both
  // requests, it observes both failures while still propagating the first one
  // to `serviceKpiProvider`.
  final results = await Future.wait<Object?>([
    sessionsFuture ?? Future<Object?>.value(),
    librariesFuture ?? Future<Object?>.value(),
  ]);
  final sessions = results[0] as List<StreamSession>?;
  final libraries = results[1] as List<StreamLibrary>?;
  final transcodes = sessions?.where((s) => s.playMethod.isTranscode).length;

  return [
    sessions == null
        ? ServiceKpi.unavailable(
            label: 'Streams',
            icon: Icons.play_circle_outline_rounded,
            note: sessionsNote,
          )
        : ServiceKpi(
            label: 'Streams',
            value: '${sessions.length}',
            icon: Icons.play_circle_outline_rounded,
            tone: _activityIf(sessions.isNotEmpty && transcodes == 0),
            note: sessionsNote,
          ),
    _figure(
      label: 'Transcodes',
      value: transcodes == null ? null : '$transcodes',
      icon: Icons.memory_rounded,
      tone: transcodes == null ? null : _faultIf(transcodes > 0),
      // The reason rides on the first card of the two it empties, as every
      // unanswered rail carries it: two identical notes side by side would
      // hide which figure each one stands in for.
    ),
    _figure(
      label: 'Libraries',
      value: libraries == null ? null : '${libraries.length}',
      icon: Icons.video_library_outlined,
      note: librariesNote,
    ),
  ];
}

/// What a figure out of a shared account's Plex token's reach says.
const _ownerOnlyNote = 'owner only';

/// What a figure out of a household member's Jellyfin token's reach says.
const _adminOnlyNote = 'admin only';

/// What a count of only a household member's own playback says.
const _yoursOnlyNote = 'yours only';

/// What a failed read failed with, or null when it answered.
Future<Object?> _failureOf(Future<Object?> read) =>
    read.then<Object?>((_) => null, onError: (Object error) => error);

/// Plex's figures.
///
/// A sessions read refused while the libraries still read is, when [probe]
/// confirms it, a shared account's token: its streams and transcodes read `—`
/// and its libraries still count. Any other failure takes the rail, as before.
Future<List<ServiceKpi>> _plexKpis(
  Future<List<StreamSession>> sessions,
  Future<List<StreamLibrary>> libraries, {
  required Future<CapabilityGrant> Function() probe,
}) async {
  try {
    return await _streamKpis(sessions, libraries);
  } catch (_) {
    final refusal = await _failureOf(sessions);
    if (refusal == null ||
        await _failureOf(libraries) != null ||
        !await plexSessionsOwnerOnly(probe, refusal)) {
      rethrow;
    }
    return _streamKpis(null, libraries, sessionsNote: _ownerOnlyNote);
  }
}

/// The figures of a MediaBrowser server, Jellyfin or Emby.
///
/// A library list refused to a household member's token, which [kind] says
/// it is, reads `—`; its own playback still counts, and says it is its own,
/// as its Now playing does.
/// Any other failure takes the rail, as before.
Future<List<ServiceKpi>> _mediaBrowserKpis(
  Future<List<StreamSession>> sessions,
  Future<List<StreamLibrary>> libraries, {
  required Future<JellyfinCredentialKind> Function() kind,
}) async {
  try {
    return await _streamKpis(sessions, libraries);
  } catch (_) {
    if (await _failureOf(libraries) == null ||
        await _failureOf(sessions) != null) {
      rethrow;
    }
    bool member;
    try {
      member = (await kind()).lacksAdministrator;
    } catch (_) {
      member = false;
    }
    if (!member) rethrow;
    return _streamKpis(
      sessions,
      null,
      sessionsNote: _yoursOnlyNote,
      librariesNote: _adminOnlyNote,
    );
  }
}

Future<List<ServiceKpi>> _mediaBrowserKpisFor(
  Ref ref,
  ServiceKey service,
  String instanceId,
) {
  final providers = mediaBrowserProvidersOf(service);
  final client = ref.watch(providers.client.forConnection(instanceId));
  final container = ref.container;
  return _mediaBrowserKpis(
    ref.watch(
      streamSessionsForProvider((
        service: service,
        instanceId: instanceId,
      )).future,
    ),
    client.getLibrariesOrThrow(),
    kind: () => container.read(providers.credentialKindFor(instanceId).future),
  );
}

Future<List<ServiceKpi>> _plexKpisFor(Ref ref, String instanceId) {
  final client = ref.watch(plexClientForProvider(instanceId));
  final container = ref.container;
  return _plexKpis(
    ref.watch(
      streamSessionsForProvider((
        service: ServiceKey.plex,
        instanceId: instanceId,
      )).future,
    ),
    client.getLibrariesOrThrow(),
    probe: () =>
        container.read(connectionCapabilityProvider(instanceId).future),
  );
}

/// The Radarr library, read so that a failure survives the fetch.
///
/// Written when [moviesProvider] still went through `fetchAllItems`, which
/// swallows every failure into `[]`: an unreachable Radarr resolved it
/// *successfully* and the rail printed `Movies 0 · Monitored 0 · Missing 0`
/// under an identity band whose own probe already read Unreachable. The wall
/// now reads `getMoviesOrThrow` too, with the same retry policy, so the two are
/// the same request made twice, kept apart so this rail's invalidation stays
/// its own. See `getMoviesOrThrow`.
///
/// Plain, not `autoDispose`, matching `moviesProvider` beside it: the library
/// is a session-scoped read, and `serviceKpiProvider` *is* `autoDispose`: a
/// disposing source under it would turn one `GET /movie` per session into one
/// per visit to the Dashboard and to every Radarr tab. Pull-to-refresh
/// invalidates it explicitly.
///
/// **`retry: noProviderRetry` is load-bearing**, not hygiene. Riverpod's
/// default retry re-runs a throwing build ten times with backoff, and a
/// `DioException` is an `Exception`, so it engages on every network failure:
/// which means `await ref.watch(...future)` inside the `catch` below does not
/// settle for some forty seconds. The `catch` exists precisely to report that
/// the server did not answer, so holding it until the retries run out is the
/// rail sitting in its skeleton state instead of saying so. Measured: the four
/// tests for this timed out at thirty seconds each before the policy went on.
/// See `lib/core/providers/provider_retry.dart`.
///
/// **[moviesProvider] itself.** The wall, this rail, Home's card and the
/// Overview each made the same `GET /movie`, the heaviest answer the app asks
/// for, and the Home paid for it at every cold open on top of the screens that
/// followed. They share one read now; all of them already carried this
/// retry policy, so nothing about how a failure settles changed.
final radarrKpiLibraryProvider = moviesProvider;

/// The Sonarr library. See [radarrKpiLibraryProvider].
///
/// Its own rather than a share of `sonarrOverviewSeriesProvider`, which reads
/// the same endpoint the same way: that one carries the default retry, on
/// purpose, because the Overview watches it as an `AsyncValue` and wants the
/// blip to heal itself. This one is *awaited* in a `catch`, and the two
/// policies cannot both hold on one provider.
///
/// **[seriesProvider] itself**, as the Radarr rail is the wall's.
final sonarrKpiLibraryProvider = seriesProvider;

/// The Lidarr library: [musicProvider] itself. See [radarrKpiLibraryProvider].
final lidarrKpiLibraryProvider = musicProvider;

/// The Readarr library: [readarrAuthorsProvider] itself. See
/// [radarrKpiLibraryProvider].
final readarrKpiLibraryProvider = readarrAuthorsProvider;

Future<List<ServiceKpi>> _radarrKpis(Ref ref) async {
  // The queue starts with the library, not after it: the snapshot never throws,
  // so a library that fails leaves nothing unhandled.
  final queue = ref.watch(radarrQueueSnapshotProvider.future);
  final List<RadarrMovie> movies;
  try {
    movies = await ref.watch(radarrKpiLibraryProvider.future);
  } catch (error) {
    // The queue figure goes too: it comes off the same server, and once the
    // library has told us the server is dark the queue has nothing to add but
    // a second note saying so.
    return _radarrKpisFrom(
      null,
      ArrQueueSnapshot.unknown,
      note: _notAnswering(ServiceKey.radarr, error),
    );
  }
  return _radarrKpisFrom(movies, await queue);
}

/// The same four figures for one **named** connection, whatever the lens is on.
///
/// Only ever called for a connection that is *not* the lens: see
/// [serviceKpiForProvider], which collapses the lens back onto the plain
/// builder so the card and the library screen keep reading one cache.
Future<List<ServiceKpi>> _radarrKpisFor(Ref ref, String instanceId) async {
  // The queue starts with the library (see [_radarrKpis]).
  final queue = ref.watch(radarrQueueSnapshotForProvider(instanceId).future);
  final List<RadarrMovie> movies;
  try {
    // The connection's one library read, cached for the session like the
    // lens's: the fold is `autoDispose` and runs again each time Home is
    // rebuilt, and read off the service it downloaded the library each time.
    movies = await ref.watch(moviesForProvider(instanceId).future);
  } catch (error) {
    return _radarrKpisFrom(
      null,
      ArrQueueSnapshot.unknown,
      note: _notAnswering(ServiceKey.radarr, error),
    );
  }
  return _radarrKpisFrom(movies, await queue);
}

/// Null means the server did not answer: see [_figure]. Never `[]`, which is
/// an answer: it says the library is there and empty.
///
/// The queue figure is the films in [queue], and only as much of a figure as
/// the snapshot can stand behind: an em dash with its own reason when the
/// queue did not answer (a library that reads fine over a queue endpoint that
/// does not used to print `Queue 0`), and a floor (`200+`) when the walk
/// stopped on a full page with no total.
List<ServiceKpi> _radarrKpisFrom(
  List<RadarrMovie>? movies,
  ArrQueueSnapshot queue, {
  String? note,
}) {
  final queued = queue.entriesById.length;
  final monitored = movies?.where((m) => m.monitored).length;
  final missing = movies?.where((m) => m.monitored && !m.hasFile).length;
  // Films by TMDB id, so a fold across an HD and a 4K Radarr counts a film
  // both hold once. Missing stays a count of files to fetch, which sums.
  Set<Object>? films(bool Function(RadarrMovie movie) where) => movies == null
      ? null
      : {
          for (final movie in movies)
            if (where(movie)) _titleKey(movie, movie.tmdbId),
        };
  return [
    _figure(
      label: 'Movies',
      value: movies == null ? null : '${movies.length}',
      icon: Icons.movie_rounded,
      note: note,
      members: films((_) => true),
    ),
    _figure(
      label: 'Monitored',
      value: monitored == null ? null : '$monitored',
      icon: Icons.visibility_rounded,
      members: films((movie) => movie.monitored),
    ),
    _figure(
      label: 'Missing',
      value: missing == null ? null : '$missing',
      icon: Icons.report_gmailerrorred_rounded,
      tone: _backlogIf(missing != null && missing > 0),
    ),
    _figure(
      label: 'Queue',
      value: !queue.answered
          ? null
          : queue.cutShort
          ? Lexicon.floor(queued)
          : '$queued',
      icon: Icons.download_rounded,
      // The library's note already says why when the whole server is dark.
      note: queue.answered || movies == null
          ? null
          : _queueNote(ServiceKey.radarr, queue.error),
    ),
  ];
}

/// Why a queue figure reads an em dash when the queue is its own fetch:
/// `Queue · Did not answer`.
String _queueNote(ServiceKey service, Object? error) =>
    'Queue\u00A0· ${failureLabel(classifyConnectionFailure(error), credential: refusedCredentialOf(service), gateway: accessGatewayOf(error))}';

Future<List<ServiceKpi>> _sonarrKpis(Ref ref) async {
  try {
    // [sonarrKpiLibraryProvider]: `seriesProvider` used to read `getSeries`,
    // which swallows its own failure into `[]`, and every figure below it was
    // a confident zero for a question nobody answered.
    return _sonarrKpisFrom(await ref.watch(sonarrKpiLibraryProvider.future));
  } catch (error) {
    return _sonarrKpisFrom(null, note: _notAnswering(ServiceKey.sonarr, error));
  }
}

/// See [_radarrKpisFor].
Future<List<ServiceKpi>> _sonarrKpisFor(Ref ref, String instanceId) async {
  try {
    return _sonarrKpisFrom(
      await ref.watch(seriesForProvider(instanceId).future),
    );
  } catch (error) {
    return _sonarrKpisFrom(null, note: _notAnswering(ServiceKey.sonarr, error));
  }
}

/// Null means the server did not answer. See [_radarrKpisFrom].
List<ServiceKpi> _sonarrKpisFrom(List<SonarrSeries>? series, {String? note}) {
  var epHave = 0;
  var epTotal = 0;
  var monitored = 0;
  for (final s in series ?? const <SonarrSeries>[]) {
    if (s.monitored) monitored++;
    epHave += _statInt(s.statistics, 'episodeFileCount');
    epTotal += _statInt(s.statistics, 'episodeCount');
  }
  final missing = (epTotal - epHave).clamp(0, epTotal);
  final answered = series != null;
  // Series by TVDB id, so two Sonarr holding one series count it once. The
  // missing episodes are files to fetch on each, and sum.
  Set<Object>? shows(bool Function(SonarrSeries show) where) => series == null
      ? null
      : {
          for (final show in series)
            if (where(show)) _titleKey(show, show.tvdbId),
        };
  return [
    _figure(
      label: 'Series',
      value: answered ? '${series.length}' : null,
      icon: Icons.tv_rounded,
      note: note,
      members: shows((_) => true),
    ),
    _figure(
      label: 'Episodes',
      value: answered ? '$epHave/$epTotal' : null,
      icon: Icons.playlist_play_rounded,
    ),
    _figure(
      label: 'Missing',
      value: answered ? '$missing' : null,
      icon: Icons.report_gmailerrorred_rounded,
      tone: _backlogIf(answered && missing > 0),
    ),
    _figure(
      label: 'Monitored',
      value: answered ? '$monitored' : null,
      icon: Icons.visibility_rounded,
      members: shows((show) => show.monitored),
    ),
  ];
}

Future<List<ServiceKpi>> _lidarrKpis(Ref ref) async {
  try {
    // [lidarrKpiLibraryProvider], not `musicProvider`: see [_radarrKpis].
    return _lidarrKpisFrom(await ref.watch(lidarrKpiLibraryProvider.future));
  } catch (error) {
    return _lidarrKpisFrom(null, note: _notAnswering(ServiceKey.lidarr, error));
  }
}

/// See [_radarrKpisFor].
Future<List<ServiceKpi>> _lidarrKpisFor(Ref ref, String instanceId) async {
  try {
    return _lidarrKpisFrom(
      await ref.watch(musicForProvider(instanceId).future),
    );
  } catch (error) {
    return _lidarrKpisFrom(null, note: _notAnswering(ServiceKey.lidarr, error));
  }
}

/// Null means the server did not answer. See [_radarrKpisFrom].
List<ServiceKpi> _lidarrKpisFrom(List<LidarrArtist>? artists, {String? note}) {
  var albums = 0;
  var trackHave = 0;
  var trackTotal = 0;
  for (final a in artists ?? const <LidarrArtist>[]) {
    albums += a.albumCount;
    trackHave += a.trackFileCount;
    trackTotal += a.trackCount;
  }
  final missing = (trackTotal - trackHave).clamp(0, trackTotal);
  final answered = artists != null;
  return [
    _figure(
      label: 'Artists',
      value: answered ? '${artists.length}' : null,
      icon: Icons.person_rounded,
      note: note,
      // By MusicBrainz id, so two Lidarr holding one artist count them once.
      members: artists == null
          ? null
          : {
              for (final artist in artists)
                _titleKey(artist, artist.foreignArtistId),
            },
    ),
    _figure(
      label: 'Albums',
      value: answered ? '$albums' : null,
      icon: Icons.album_rounded,
    ),
    _figure(
      label: 'Tracks',
      value: answered ? '$trackHave/$trackTotal' : null,
      icon: Icons.music_note_rounded,
    ),
    _figure(
      label: 'Missing',
      value: answered ? '$missing' : null,
      icon: Icons.report_gmailerrorred_rounded,
      tone: _backlogIf(answered && missing > 0),
    ),
  ];
}

Future<List<ServiceKpi>> _qbittorrentKpis(Ref ref) async {
  final now = ref.read(stallClockProvider)();
  return _qbittorrentKpisFrom(
    await ref.watch(allTorrentsProvider.future),
    now: now,
  );
}

Future<List<ServiceKpi>> _qbittorrentKpisFor(Ref ref, String instanceId) async {
  final now = ref.read(stallClockProvider)();
  final data = await ref
      .watch(qbittorrentServiceForProvider(instanceId))
      .mainData();
  return _qbittorrentKpisFrom(
    sortTorrents(data.torrents, TorrentSort.addedOn, reverse: true),
    now: now,
  );
}

/// qBittorrent's rail. Its last figure counts the stuck torrents, by the one
/// rule a stuck download is judged by ([qbittorrentInFlight]: stalled or
/// failed), so the card is flagged when Needs you shows one.
List<ServiceKpi> _qbittorrentKpisFrom(
  List<Torrent> torrents, {
  required DateTime now,
}) {
  var active = 0;
  var downloading = 0;
  var seeding = 0;
  var stuck = 0;
  var dl = 0;
  var up = 0;
  for (final t in torrents) {
    final state = TorrentState.fromString(t.state);
    if (state.isActive) active++;
    if (state == TorrentState.downloading ||
        state == TorrentState.metaDownloading) {
      downloading++;
    }
    if (state == TorrentState.seeding) seeding++;
    if (qbittorrentInFlight(t, now: now)?.fault != null) stuck++;
    dl += t.dlSpeed;
    up += t.upSpeed;
  }
  return [
    ServiceKpi(label: 'Active', value: '$active', icon: Icons.bolt_rounded),
    // The brand book's pair, `↓ 22.4 MB/s ↑ 1.1 MB/s`: the arrow is the
    // card's glyph and the rate its figure, so the word under them names the
    // rate rather than repeating the arrow. It said `Down` and `Up`, and
    // `Down` is the one state word the lexicon bans outright.
    ServiceKpi(
      label: 'Download',
      value: formatSpeed(dl),
      icon: Icons.south_rounded,
      tone: _activityIf(dl > 0),
    ),
    ServiceKpi(
      label: 'Upload',
      value: formatSpeed(up),
      icon: Icons.north_rounded,
    ),
    ServiceKpi(label: 'Seeding', value: '$seeding', icon: Icons.upload_rounded),
    ServiceKpi(
      label: 'Downloading',
      value: '$downloading',
      icon: Icons.download_rounded,
    ),
    ServiceKpi(
      label: StateWord.stuck.label,
      value: '$stuck',
      icon: Icons.report_gmailerrorred_rounded,
      tone: _faultIf(stuck > 0),
    ),
  ];
}

Future<List<ServiceKpi>> _seerrKpis(Ref ref) async =>
    _seerrKpisFrom(await ref.watch(requestRowsProvider.future));

/// See [_radarrKpisFor]. Seerr already owned its per-connection read, because a
/// request id is per instance and a merged list cannot be acted on by id alone.
Future<List<ServiceKpi>> _seerrKpisFor(Ref ref, String instanceId) async =>
    _seerrKpisFrom(await ref.watch(requestRowsForProvider(instanceId).future));

List<ServiceKpi> _seerrKpisFrom(List<SeerrRequest> requests) {
  var pending = 0;
  var processing = 0;
  var available = 0;
  for (final r in requests) {
    // Pending counts the requests that still need a decision, so it reads the
    // request's OWN status: the same source `request_ordering.dart` and the
    // /activity rows read, and for the same
    // documented reason. `displayStatus` answers a different question: it lets
    // the media's availability override the request, so a request still in
    // pendingApproval whose media Radarr already holds reports "Available":
    // which is how this KPI came to show "Pending 0" while /activity was
    // offering an Approve button for that very record.
    if (r.status == RequestStatus.pendingApproval) pending++;

    // The other two stay on displayStatus, which is the right source for them:
    // they describe where the media is, not what the request needs.
    switch (r.displayStatus.kind) {
      case SeerrRequestDisplayKind.approved:
      case SeerrRequestDisplayKind.processing:
        processing++;
      case SeerrRequestDisplayKind.available:
      case SeerrRequestDisplayKind.partiallyAvailable:
      case SeerrRequestDisplayKind.completed:
        available++;
      case SeerrRequestDisplayKind.pending:
      case SeerrRequestDisplayKind.declined:
      case SeerrRequestDisplayKind.failed:
      case SeerrRequestDisplayKind.blocklisted:
      case SeerrRequestDisplayKind.deleted:
      case SeerrRequestDisplayKind.unknown:
        break;
    }
  }
  return [
    ServiceKpi(
      label: 'Requests',
      value: '${requests.length}',
      icon: Icons.inbox_rounded,
    ),
    ServiceKpi(
      label: StateWord.waitingForApproval.label,
      value: '$pending',
      icon: Icons.hourglass_top_rounded,
      tone: _backlogIf(pending > 0),
    ),
    ServiceKpi(
      label: 'Processing',
      value: '$processing',
      icon: Icons.sync_rounded,
    ),
    ServiceKpi(
      label: 'Available',
      value: '$available',
      icon: Icons.check_circle_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _truenasKpis(Ref ref) async {
  return _truenasKpisFrom(await ref.watch(truenasDashboardProvider.future));
}

Future<List<ServiceKpi>> _truenasKpisFor(Ref ref, String instanceId) async {
  final dashboard = await ref
      .watch(truenasServiceForProvider(instanceId))
      .loadDashboard();
  return _truenasKpisFrom(dashboard);
}

List<ServiceKpi> _truenasKpisFrom(TrueNasDashboard dashboard) {
  final pools = dashboard.pools;
  final usedFractions = pools
      .map((p) => p.usedFraction)
      .whereType<double>()
      .toList(growable: false);
  final maxUsed = usedFractions.isEmpty
      ? null
      : usedFractions.fold<double>(0, (max, v) => v > max ? v : max);
  final activeAlerts = dashboard.activeAlerts.length;
  final running = dashboard.services.where((s) => s.running).length;
  return [
    ServiceKpi(
      label: 'Pools',
      value: '${pools.length}',
      icon: Icons.dns_rounded,
    ),
    if (maxUsed == null)
      const ServiceKpi.unavailable(
        label: 'Used',
        icon: Icons.pie_chart_rounded,
        note: 'pool capacity unavailable',
      )
    else
      ServiceKpi(
        label: 'Used',
        value: formatPercent(maxUsed * 100),
        icon: Icons.pie_chart_rounded,
        tone: _faultIf(maxUsed >= 0.8),
      ),
    ServiceKpi(
      label: 'Alerts',
      value: '$activeAlerts',
      icon: Icons.warning_amber_rounded,
      tone: _faultIf(activeAlerts > 0),
    ),
    ServiceKpi(label: 'Services', value: '$running', icon: Icons.bolt_rounded),
  ];
}

Future<List<ServiceKpi>> _dockgeKpis(Ref ref) async {
  // The rail is a snapshot, not a second listener on the live stack list:
  // reading the service keeps the figures on the same client cache without
  // tying an autoDispose provider to a stream another page owns. The pages
  // that draw the list derive their own rail from it.
  return dockgeKpisFrom(await ref.watch(dockgeServiceProvider).fetchStacks());
}

Future<List<ServiceKpi>> _dockgeKpisFor(Ref ref, String instanceId) async {
  final stacks = await ref
      .watch(dockgeServiceForProvider(instanceId))
      .fetchStacks();
  return dockgeKpisFrom(stacks);
}

/// The Dockge rail from the stack list the page is drawing.
List<ServiceKpi> dockgeKpisFrom(List<DockgeStack> stacks) {
  final running = stacks
      .where((s) => s.status == DockgeStackStatus.running)
      .length;
  final stopped = stacks
      .where((s) => s.status == DockgeStackStatus.exited)
      .length;
  return dockgeKpisFromCounts(
    total: stacks.length,
    running: running,
    stopped: stopped,
  );
}

/// The Dockge rail from three counts, so the Overview can feed it from the
/// census it already watches instead of opening a second read of the list.
///
/// The inactive count is the remainder: a status the rail has no word for
/// still counts in the total it was counted in.
List<ServiceKpi> dockgeKpisFromCounts({
  required int total,
  required int running,
  required int stopped,
}) {
  final inactive = total - running - stopped;
  return [
    ServiceKpi(label: 'Stacks', value: '$total', icon: Icons.layers_rounded),
    ServiceKpi(
      label: 'Running',
      value: '$running',
      icon: Icons.play_circle_rounded,
    ),
    // Backlog, not a fault: Dockge does not say whether a stop was intended,
    // so a stopped count is a plain count with no tone.
    ServiceKpi(
      label: 'Stopped',
      value: '$stopped',
      icon: Icons.stop_circle_rounded,
    ),
    ServiceKpi(
      label: 'Inactive',
      value: '$inactive',
      icon: Icons.pause_circle_rounded,
    ),
  ];
}

Future<List<ServiceKpi>> _bazarrKpis(Ref ref) async {
  final results = await Future.wait([
    ref.watch(bazarrBadgesProvider.future),
    ref.watch(bazarrProviderStatusesProvider.future),
  ]);
  return _bazarrKpisFrom(
    results[0] as BazarrBadges,
    results[1] as List<BazarrProviderStatus>,
  );
}

Future<List<ServiceKpi>> _bazarrKpisFor(Ref ref, String instanceId) async {
  final service = ref.watch(bazarrServiceForProvider(instanceId));
  final results = await Future.wait([
    service.getBadges(),
    service.getProviderStatuses(),
  ]);
  return _bazarrKpisFrom(
    results[0] as BazarrBadges,
    results[1] as List<BazarrProviderStatus>,
  );
}

/// Bazarr's badge of providers counts the throttled ones only, so the
/// figure is the enabled list's length, amber while Bazarr waits one out.
List<ServiceKpi> _bazarrKpisFrom(
  BazarrBadges b,
  List<BazarrProviderStatus> providers,
) {
  return [
    ServiceKpi(
      label: 'Wanted',
      value: '${b.totalWanted}',
      icon: Icons.subtitles_off_rounded,
      tone: _backlogIf(b.totalWanted > 0),
    ),
    ServiceKpi(
      label: 'Episodes',
      value: '${b.episodes}',
      icon: Icons.tv_rounded,
    ),
    ServiceKpi(
      label: 'Movies',
      value: '${b.movies}',
      icon: Icons.movie_rounded,
    ),
    ServiceKpi(
      label: 'Providers',
      value: '${providers.length}',
      icon: Icons.cloud_rounded,
      tone: providers.any((provider) => provider.throttled)
          ? StatusTone.warning
          : null,
    ),
  ];
}

Future<List<ServiceKpi>> _prowlarrKpis(Ref ref) async {
  // The two fetches are independent; run them in parallel.
  final results = await Future.wait([
    ref.watch(prowlarrIndexersProvider.future),
    ref.watch(prowlarrIndexerStatsProvider.future),
  ]);
  return _prowlarrKpisFrom(
    results[0] as List<ProwlarrIndexer>,
    results[1] as ProwlarrIndexerStats,
  );
}

Future<List<ServiceKpi>> _prowlarrKpisFor(Ref ref, String instanceId) async {
  final service = ref.watch(prowlarrServiceForProvider(instanceId));
  final now = DateTime.now().toUtc();
  final results = await Future.wait([
    service.getIndexers(),
    service.getIndexerStats(
      startDate: now.subtract(prowlarrStatsWindow).toIso8601String(),
      endDate: now.toIso8601String(),
    ),
  ]);
  return _prowlarrKpisFrom(
    results[0] as List<ProwlarrIndexer>,
    results[1] as ProwlarrIndexerStats,
  );
}

List<ServiceKpi> _prowlarrKpisFrom(
  List<ProwlarrIndexer> indexers,
  ProwlarrIndexerStats stats,
) {
  final active = indexers.where((i) => i.enable).length;
  return [
    ServiceKpi(
      label: 'Indexers',
      value: '$active',
      icon: Icons.travel_explore_rounded,
    ),
    ServiceKpi(
      label: 'Queries',
      value: '${stats.totalQueries}',
      icon: Icons.search_rounded,
    ),
    ServiceKpi(
      label: 'Grabs',
      value: '${stats.totalGrabs}',
      icon: Icons.download_rounded,
    ),
    ServiceKpi(
      label: 'Fails',
      value: '${stats.totalFailures}',
      icon: Icons.error_outline_rounded,
      tone: _faultIf(stats.totalFailures > 0),
    ),
  ];
}

Future<List<ServiceKpi>> _readarrKpis(Ref ref) async {
  // [readarrKpiLibraryProvider], not [readarrAuthorsProvider]: see
  // [_radarrKpis]. The two fetches fail independently: a library that answers
  // over a queue endpoint that does not is the ordinary case on a Readarr
  // mid-upgrade, so each figure says for itself whether it was answered.
  // Both reads start before either is awaited, as in [_readarrKpisFor].
  Object? authorsError;
  final authorsFuture = ref
      .watch(readarrKpiLibraryProvider.future)
      .then<List<ReadarrAuthor>?>(
        (value) => value,
        onError: (Object error) {
          authorsError = error;
          return null;
        },
      );
  Object? queueError;
  final queueFuture = ref
      .watch(readarrQueueProvider.future)
      .then<ArrRecordPage?>(
        (value) => value,
        onError: (Object error) {
          queueError = error;
          return null;
        },
      );
  final authors = await authorsFuture;
  final queued = await queueFuture;

  return _readarrKpisFrom(
    authors,
    queued,
    error: authorsError,
    queueError: queueError,
  );
}

Future<List<ServiceKpi>> _readarrKpisFor(Ref ref, String instanceId) async {
  final service = ref.watch(readarrServiceForProvider(instanceId));
  // Two independent reads, started together rather than in series: the fold
  // runs this once per configured connection, so a server that has stopped
  // answering costs one timeout here instead of two back to back. The fallback
  // is attached at construction, which is what keeps either failure from
  // escaping as an unhandled async error while the other is still in flight.
  Object? authorsError;
  final authorsFuture = ref
      .watch(readarrAuthorsForProvider(instanceId).future)
      .then<List<ReadarrAuthor>?>(
        (value) => value,
        onError: (Object error) {
          authorsError = error;
          return null;
        },
      );
  Object? queueError;
  final queueFuture = service.getQueuePage().then<ArrRecordPage?>(
    (value) => value,
    onError: (Object error) {
      queueError = error;
      return null;
    },
  );

  final authors = await authorsFuture;
  final queued = await queueFuture;
  return _readarrKpisFrom(
    authors,
    queued,
    error: authorsError,
    queueError: queueError,
  );
}

/// [error] is why the library read failed, for the note; null when it did not.
/// [queueError] is the same for the queue, which is its own fetch, and
/// [queued] the queue walk: the figure is [queueFigure] of it.
List<ServiceKpi> _readarrKpisFrom(
  List<ReadarrAuthor>? authors,
  ArrRecordPage? queued, {
  Object? error,
  Object? queueError,
}) {
  var books = 0;
  var have = 0;
  for (final a in authors ?? const <ReadarrAuthor>[]) {
    books += a.bookCount;
    have += a.bookFileCount;
  }
  final missing = (books - have).clamp(0, books);
  final answered = authors != null;
  return [
    _figure(
      label: 'Authors',
      value: answered ? '${authors.length}' : null,
      icon: Icons.person_rounded,
      note: answered ? null : _notAnswering(ServiceKey.readarr, error),
    ),
    _figure(
      label: 'Books',
      value: answered ? '$books' : null,
      icon: Icons.menu_book_rounded,
    ),
    _figure(
      label: 'Missing',
      value: answered ? '$missing' : null,
      icon: Icons.report_gmailerrorred_rounded,
      tone: _backlogIf(answered && missing > 0),
    ),
    _figure(
      label: 'Queue',
      value: queued == null ? null : queueFigure(queued),
      icon: Icons.download_rounded,
      // Its own reason, because it is its own fetch: a Readarr whose library
      // reads fine and whose queue endpoint is down used to print `Queue 0`:
      // an idle downloader rather than an unread one.
      note: queued == null ? _queueNote(ServiceKey.readarr, queueError) : null,
    ),
  ];
}

/// A queue walk as a figure, the rule Activity's queue tile reads it by.
///
/// The server's own count when the walk has one, even when it ran out of
/// pages before the rows did: the count stands, and only the rows are short.
/// Without one the rows are all there is to go on, and they are the whole
/// queue only when a short page ended it; a full page with no count to say
/// whether another followed is a floor, `200+`. It used to be the rows' length
/// whatever the walk said, so a proxy that drops `totalRecords` read
/// `Queue 200` for any queue longer than one page.
String queueFigure(ArrRecordPage page) {
  final total = page.total;
  if (total != null) return '$total';
  return page.cutShort
      ? Lexicon.floor(page.records.length)
      : '${page.records.length}';
}

Future<List<ServiceKpi>> _sabnzbdKpis(Ref ref) async {
  // Started together (see [_sabnzbdKpisFor]). The stats call is optional: its
  // failure is ignored, so the queue KPIs still show when it fails.
  final queueFuture = ref.watch(sabnzbdQueueProvider.future);
  final statsFuture = ref
      .watch(sabnzbdServerStatsProvider.future)
      .then<SabnzbdServerStats?>((value) => value, onError: (_) => null);
  return _sabnzbdKpisFrom(await queueFuture, await statsFuture);
}

Future<List<ServiceKpi>> _sabnzbdKpisFor(Ref ref, String instanceId) async {
  final client = ref.watch(sabnzbdClientForProvider(instanceId));
  // Independent reads, started together: see [_readarrKpisFor]. The stats call
  // stays optional, so it carries its own fallback instead of failing the pair.
  final queueFuture = client.getQueue();
  final statsFuture = client.getServerStats().then<SabnzbdServerStats?>(
    (value) => value,
    onError: (_) => null,
  );
  return _sabnzbdKpisFrom(await queueFuture, await statsFuture);
}

List<ServiceKpi> _sabnzbdKpisFrom(
  SabnzbdQueue queue,
  SabnzbdServerStats? stats,
) {
  final kpis = <ServiceKpi>[
    ServiceKpi(
      label: 'Download',
      value: queue.speedLabel,
      icon: Icons.south_rounded,
      tone: _activityIf(queue.kbPerSec > 0),
    ),
    ServiceKpi(
      // [SabnzbdQueue.jobCount], never `slots.length`: the client asks for a
      // 50-slot page, so a queue deeper than the page read `50` forever: a
      // figure that stops moving exactly when there is something to watch.
      // `jobCount` prefers the server's own `noofslots_total` and falls back to
      // the rows in hand when the payload carried no total.
      label: 'Queue',
      value: '${queue.jobCount}',
      icon: Icons.list_rounded,
    ),
    ServiceKpi(
      label: 'Remaining',
      value: queue.sizeLeftLabel,
      icon: Icons.hourglass_bottom_rounded,
    ),
    _usenetStatusKpi(
      paused: queue.paused,
      stoppedByDisk: sabnzbdQueueStoppedByDisk(queue),
    ),
  ];
  // Lifetime total is a nice-to-have; a stats failure must not drop the whole
  // KPI row, so it is fetched defensively and simply omitted on error.
  if (stats != null) {
    kpis.add(
      ServiceKpi(
        label: 'Total',
        value: stats.totalLabel,
        icon: Icons.download_done_rounded,
      ),
    );
  }
  return kpis;
}

Future<List<ServiceKpi>> _nzbgetKpis(Ref ref) async {
  final results = await Future.wait([
    ref.watch(nzbgetStatusProvider.future),
    ref.watch(nzbgetQueueProvider.future),
  ]);
  return _nzbgetKpisFrom(
    results[0] as NzbgetStatus,
    results[1] as List<NzbgetGroup>,
  );
}

Future<List<ServiceKpi>> _nzbgetKpisFor(Ref ref, String instanceId) async {
  final client = ref.watch(nzbgetClientForProvider(instanceId));
  final results = await Future.wait([client.status(), client.listGroups()]);
  return _nzbgetKpisFrom(
    results[0] as NzbgetStatus,
    results[1] as List<NzbgetGroup>,
  );
}

List<ServiceKpi> _nzbgetKpisFrom(
  NzbgetStatus status,
  List<NzbgetGroup> groups,
) {
  return [
    ServiceKpi(
      label: 'Download',
      value: status.rateLabel,
      icon: Icons.south_rounded,
      tone: _activityIf(status.downloadRateBytes > 0),
    ),
    ServiceKpi(
      label: 'Queue',
      value: '${groups.length}',
      icon: Icons.list_rounded,
    ),
    ServiceKpi(
      label: 'Remaining',
      value: status.remainingLabel,
      icon: Icons.hourglass_bottom_rounded,
    ),
    _usenetStatusKpi(
      paused: status.paused,
      stoppedByDisk: nzbgetQueueStoppedByDisk(status, groups),
      quotaReached: status.quotaReached,
    ),
  ];
}

/// A usenet client's Status figure: `Active`, `Stopped`, `Quota reached` or
/// `Disk full`.
///
/// Pausing the queue is something the user did on purpose, so it is neither
/// a fault nor a backlog: it is the client obeying. It used to be flagged
/// amber, which put "you pressed pause" in the same colour as "your disk is
/// full" (decision 15). Both clients stop on a full disk by flipping the same
/// switch, though, and that one is a fault: amber, in the word Home's
/// downloads use for it, never `Stopped` beside a Home that says the disk is
/// full. A download quota NZBGet reached stops it too, by the user's own
/// rule: neutral like a pause, and said for what it is, so it is not taken
/// for a pause nobody remembers making.
ServiceKpi _usenetStatusKpi({
  required bool paused,
  required bool stoppedByDisk,
  bool quotaReached = false,
}) => ServiceKpi(
  label: 'Status',
  value: stoppedByDisk
      ? diskFullReason
      : quotaReached
      ? 'Quota reached'
      : paused
      ? StateWord.stopped.label
      : 'Active',
  icon: stoppedByDisk
      ? Icons.storage_rounded
      : paused || quotaReached
      ? Icons.pause_circle_rounded
      : Icons.play_circle_rounded,
  tone: _faultIf(stoppedByDisk),
);

/// Transmission's rail, shaped like qBittorrent's so the two torrent clients
/// read the same way in the matrix: `Download` first, flagged while bytes are
/// actually moving, so the resting cell says "0 B/s" rather than a library
/// total.
Future<List<ServiceKpi>> _transmissionKpis(Ref ref) async {
  final results = await Future.wait([
    ref.watch(transmissionStatsProvider.future),
    ref.watch(transmissionTorrentsProvider.future),
  ]);
  return _transmissionKpisFrom(
    results[0] as TransmissionStats,
    results[1] as List<TransmissionTorrent>,
  );
}

Future<List<ServiceKpi>> _transmissionKpisFor(
  Ref ref,
  String instanceId,
) async {
  final client = ref.watch(transmissionClientForProvider(instanceId));
  final results = await Future.wait([client.stats(), client.torrents()]);
  return _transmissionKpisFrom(
    results[0] as TransmissionStats,
    results[1] as List<TransmissionTorrent>,
  );
}

List<ServiceKpi> _transmissionKpisFrom(
  TransmissionStats stats,
  List<TransmissionTorrent> torrents,
) {
  final downloading = torrents.where((t) => t.status.isIncoming).length;
  final stalled = torrents.where((t) => t.warning != null).length;

  return [
    ServiceKpi(
      label: 'Download',
      value: stats.downloadSpeedLabel,
      icon: Icons.south_rounded,
      tone: _activityIf(stats.downloadSpeed > 0),
    ),
    ServiceKpi(
      label: 'Upload',
      value: stats.uploadSpeedLabel,
      icon: Icons.north_rounded,
    ),
    ServiceKpi(
      label: 'Active',
      value: '${stats.activeTorrentCount}',
      icon: Icons.bolt_rounded,
    ),
    ServiceKpi(
      label: 'Downloading',
      value: '$downloading',
      icon: Icons.download_rounded,
    ),
    ServiceKpi(
      label: StateWord.stuck.label,
      value: '$stalled',
      icon: Icons.report_gmailerrorred_rounded,
      tone: _faultIf(stalled > 0),
    ),
  ];
}

/// Nginx Proxy Manager's rail.
///
/// `Offline` is the metric that earns its place: a reverse proxy is either
/// serving every hostname it claims or it is not, and a host that is switched on
/// while nginx has refused its configuration is invisible from every other
/// screen in the app: the site simply stops answering. Expiring certificates
/// are the second, for the same reason a day later.
Future<List<ServiceKpi>> _npmKpis(Ref ref) async {
  final results = await Future.wait([
    ref.watch(npmProxyHostsProvider.future),
    ref.watch(npmCertificatesProvider.future),
  ]);
  return _npmKpisFrom(
    results[0] as List<NpmProxyHost>,
    results[1] as List<NpmCertificate>,
    DateTime.now(),
  );
}

Future<List<ServiceKpi>> _npmKpisFor(Ref ref, String instanceId) async {
  final client = ref.watch(npmClientForProvider(instanceId));
  final results = await Future.wait([
    client.proxyHosts(),
    client.certificates(),
  ]);
  return _npmKpisFrom(
    results[0] as List<NpmProxyHost>,
    results[1] as List<NpmCertificate>,
    DateTime.now(),
  );
}

List<ServiceKpi> _npmKpisFrom(
  List<NpmProxyHost> hosts,
  List<NpmCertificate> certificates,
  DateTime now,
) {
  final broken = hosts.where((h) => h.hasConfigError).length;
  final disabled = hosts.where((h) => !h.enabled).length;
  final expiring = certificates.where((c) => c.isExpiringSoon(now)).length;

  return [
    ServiceKpi(
      label: 'Config errors',
      value: '$broken',
      icon: Icons.error_outline_rounded,
      tone: _faultIf(broken > 0),
    ),
    ServiceKpi(
      label: 'Hosts',
      value: '${hosts.length}',
      icon: Icons.alt_route_rounded,
    ),
    ServiceKpi(
      label: 'Expiring',
      value: '$expiring',
      icon: Icons.lock_clock_rounded,
      tone: _faultIf(expiring > 0),
    ),
    ServiceKpi(
      label: 'Certificates',
      value: '${certificates.length}',
      icon: Icons.lock_outline_rounded,
    ),
    ServiceKpi(
      label: 'Disabled',
      value: '$disabled',
      icon: Icons.pause_circle_rounded,
    ),
  ];
}

/// Tracearr's rail: what is playing, what was played today, what broke a rule
/// and has not been looked at, and how many of its servers it reaches.
///
/// **Each figure is its own read.** Tracearr answers four routes and a rail
/// that went to an em dash whole because one of them failed would lose the
/// three it could still say; a figure whose source did not answer reads `—`,
/// never `0`. When none answered the failure takes the rail, as every other
/// rail's does, so the page says the server did not answer once, not four
/// times. The unseen figure is a **floor** (`25+`) when more follow the first
/// page, since the API gives no total.
///
/// **Streams now counts the rows Live draws** (`tracearrLiveProvider`, the
/// list the Overview's Playing section also reads), so the rail and the section
/// cannot disagree after an event moves the list. Only the count is selected:
/// a progress tick, which moves no row, must not rebuild the rail.
Future<List<ServiceKpi>> _tracearrKpis(Ref ref) => _tracearrKpisFrom(
  ref.watch(tracearrLiveProvider.selectAsync((live) => live.streams.length)),
  ref.watch(tracearrTodayProvider.future),
  ref.watch(tracearrUnseenViolationsProvider.future),
  ref.watch(tracearrServersProvider.future),
);

Future<List<ServiceKpi>> _tracearrKpisFor(Ref ref, String instanceId) {
  final client = ref.watch(tracearrClientForProvider(instanceId));
  final zone = ref.read(deviceTimeZoneProvider);
  return _tracearrKpisFrom(
    client.getStreams().then((live) => live.streams.length),
    zone().then((zone) => client.getToday(timezone: zone)),
    client.getViolations(
      pageSize: kTracearrCountPage,
      filter: const TracearrViolationFilter.unseen(),
    ),
    client.getServers(),
  );
}

Future<List<ServiceKpi>> _tracearrKpisFrom(
  Future<int> streams,
  Future<TracearrToday> today,
  Future<TracearrPage<TracearrViolation>> unseen,
  Future<TracearrServers> servers,
) async {
  final results = await Future.wait<Object?>([
    _failureOr(streams),
    _failureOr(today),
    _failureOr(unseen),
    _failureOr(servers),
  ]);
  final failures = results.whereType<_ReadFailed>().toList();
  if (failures.length == results.length) throw failures.first.error;
  T? read<T>(int index) => switch (results[index]) {
    final T value => value,
    _ => null,
  };

  final playing = read<int>(0);
  final day = read<TracearrToday>(1);
  final unseenPage = read<TracearrPage<TracearrViolation>>(2);
  final watched = read<TracearrServers>(3);
  final unseenCount = unseenPage == null
      ? null
      : tracearrUnseenCount(unseenPage);
  // Servers kept for their history are not watched any more, so they are
  // neither of the two numbers.
  final polled = watched?.servers.where((s) => !s.historical).toList();
  final reached = polled?.where((s) => s.isUp).length;

  return [
    _figure(
      label: 'Streams now',
      value: playing == null ? null : '$playing',
      icon: Icons.play_circle_outline_rounded,
      tone: playing == null ? null : _activityIf(playing > 0),
    ),
    // Plays and the time they took, as the spec has it, for the device's own
    // day: the read carries the device's IANA zone (`deviceTimeZoneProvider`),
    // and falls back to Tracearr's UTC day only when there is none or Tracearr
    // refuses it.
    _figure(
      label: 'Today',
      value: day == null
          ? null
          : day.watchTime == Duration.zero
          ? countLabel(day.todayPlays, 'play')
          : '${countLabel(day.todayPlays, 'play')}$dotSeparator'
                '${formatTimeSpan(day.watchTime)}',
      icon: Icons.today_rounded,
    ),
    _figure(
      label: 'Unseen',
      value: unseenCount == null
          ? null
          : unseenCount.isFloor
          ? Lexicon.floor(unseenCount.count)
          : '${unseenCount.count}',
      icon: Icons.flag_outlined,
      // Information, never a fault: a rule was broken and nobody looked, which
      // is the person's to read and not something that stopped working.
      tone: unseenCount == null ? null : _activityIf(unseenCount.count > 0),
    ),
    _figure(
      label: 'Servers',
      value: polled == null ? null : '$reached of ${polled.length}',
      icon: Icons.dns_outlined,
      tone: polled == null ? null : _faultIf(reached! < polled.length),
    ),
  ];
}

/// A read that failed, carried as a value so its siblings are still awaited.
final class _ReadFailed {
  const _ReadFailed(this.error);

  final Object error;
}

Future<Object?> _failureOr(Future<Object?> read) =>
    read.then<Object?>((value) => value, onError: (Object e) => _ReadFailed(e));

Future<List<ServiceKpi>> _unraidKpis(Ref ref) async {
  final results = await Future.wait([
    ref.watch(unraidArrayProvider.future),
    ref.watch(unraidDockerProvider.future),
  ]);
  return _unraidKpisFrom(
    results[0] as UnraidArray,
    results[1] as List<UnraidDockerContainer>,
  );
}

Future<List<ServiceKpi>> _unraidKpisFor(Ref ref, String instanceId) async {
  final client = ref.watch(unraidClientForProvider(instanceId));
  final results = await Future.wait([
    client.getArray(),
    client.getDockerContainers(),
  ]);
  return _unraidKpisFrom(
    results[0] as UnraidArray,
    results[1] as List<UnraidDockerContainer>,
  );
}

List<ServiceKpi> _unraidKpisFrom(
  UnraidArray array,
  List<UnraidDockerContainer> containers,
) {
  final running = containers.where((c) => c.running).length;
  // Null when the array answered with no capacity block, which is nullable in
  // the committed SDL. `Used 0%` would read as an empty array: the one
  // conclusion a user acts on, and would contradict the Overview's Array
  // section, whose capacity clause correctly disappears for the same input.
  final usedPercent = array.usedPercent;
  return [
    ServiceKpi(
      label: 'Array',
      value: unraidArrayStateWords(array.state) ?? Lexicon.noFigure,
      icon: Icons.dns_rounded,
    ),
    if (usedPercent == null)
      const ServiceKpi.unavailable(
        label: 'Used',
        icon: Icons.pie_chart_rounded,
        note: 'no capacity reported',
      )
    else
      ServiceKpi(
        label: 'Used',
        value: formatPercent(usedPercent),
        icon: Icons.pie_chart_rounded,
        tone: _faultIf(usedPercent >= 80),
      ),
    ServiceKpi(
      label: 'Containers',
      value: '$running/${containers.length}',
      icon: Icons.widgets_rounded,
    ),
    // Same rule for the census: `disks` is nullable too, and a `0` here is an
    // assertion that the array has no drives, built out of silence.
    if (array.reportedDisks)
      ServiceKpi(
        label: 'Disks',
        // Parity and cache drives too; an empty slot holds none.
        value: '${array.drives.length}',
        icon: Icons.storage_rounded,
      )
    else
      const ServiceKpi.unavailable(
        label: 'Disks',
        icon: Icons.storage_rounded,
        note: 'no slots reported',
      ),
  ];
}
