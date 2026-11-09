import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/side_pane_route.dart';
import 'package:cupola/features/activity/domain/download_page.dart'
    show downloadPageKey;
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_split.dart';
import 'package:cupola/features/services/presentation/services_provider.dart'
    show ServiceQueueItem;
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart'
    show streamClientForProvider;

/// Opening a title's page from the page the user is on: under that page's
/// tab, so the poster flies and the tab keeps it (`ServiceRoutes.media`).
extension OpenMedia on BuildContext {
  /// Where the user is: the location the router is showing.
  String get _here => GoRouter.of(this).state.uri.path;

  /// Whether the pane beside this page shows [key]'s page: the row that
  /// opens it marks itself while it does, as a poster wears its ring.
  bool paneShows(MediaKey key) => SidePaneScope.selectedOf(this) == key;

  /// Whether the pane beside this page shows the person [id]'s page.
  bool paneShowsPerson(int id) =>
      SidePaneScope.selectedOf(this) == MediaPanePerson(id: id).selected;

  /// Whether the pane beside this page shows the download [key]'s page.
  bool paneShowsDownload(String key) =>
      SidePaneScope.selectedOf(this) == MediaPaneDownload.selectedFor(key);

  /// Pushes [item]'s own page (`ServiceRoutes.activityDownload`), and on a
  /// tablet beside the list as a title is.
  Future<void> openDownload(ServiceQueueItem item) =>
      openDownloadAt(instanceId: item.instanceId, key: downloadPageKey(item));

  /// Pushes the page of the download the address `?i=[instanceId]&id=[key]`
  /// names, for a caller that holds the two and not the queue's row: an
  /// Overview that read a torrent or a queue record of its own service.
  /// [key] is the client's id for the transfer (`downloadPageKey`).
  Future<void> openDownloadAt({
    required String instanceId,
    required String key,
  }) => _openBeside(
    ServiceRoutes.activityDownload(instanceId: instanceId, key: key),
  );

  /// Pushes [key]'s page under the tab the user is on.
  Future<void> openMedia(
    MediaKey key, {
    String? focus,
    int? season,
    String? heroTag,
    String? posterUrl,
  }) => _openBeside(
    ServiceRoutes.media(
      key,
      from: _here,
      focus: focus,
      season: season,
      heroTag: heroTag,
      posterUrl: posterUrl,
    ),
  );

  /// Pushes [location], a page the pane can draw: a title's, a person's or
  /// a collection's (`MediaSplit.pageOf`). On a tablet with one open beside
  /// the list, one chosen from the list takes its place, with the pane's own
  /// history; one opened from inside the pane is pushed on it, so Back in the
  /// pane returns to the page before.
  Future<void> _openBeside(String location, {Object? extra}) {
    final router = GoRouter.of(this);
    if (MediaPane.maybeOf(this) == null &&
        SidePaneScope.selectedOf(this) != null) {
      while (MediaSplit.pageOf(router.state.uri) != null && router.canPop()) {
        router.pop();
      }
    }
    return router.push(location, extra: extra);
  }

  /// Opens a title Seerr names on its own page, under the tab the user is
  /// on: [mediaType] is Seerr's `movie` or `tv`, [id] TMDB's.
  Future<void> openSeerrTitle({
    required String mediaType,
    required int id,
    String? heroTag,
    String? posterUrl,
  }) => openMedia(
    mediaType == 'tv' ? MediaKey.tv(id) : MediaKey.movie(id),
    heroTag: heroTag,
    posterUrl: posterUrl,
  );

  /// Opens an item a media server listed: a movie or a series on its own
  /// page, with the copy of the connection that listed it leading (the
  /// service's lens); a season or an episode on its series' page, on that
  /// season; anything else on the server's own page.
  ///
  /// [instanceId] is the connection that listed the item: it leads in place of
  /// the lens, and rides the server's page as `?i=`, so opening a row from one
  /// connection never moves the lens.
  ///
  /// A season or an episode names its series by the server's own id
  /// (`StreamItem.seriesId`), and the page is keyed by the ids the server
  /// holds for it, so the tap reads them first: one read of the series
  /// through the connection's own client (`StreamServerClient.getSeriesKey`).
  /// While it is out the tap shows what any press shows, and nothing else: no
  /// page in between. A series the server holds no ids for, a read that failed
  /// or ran out ([_keyLookupLimit]), and an item that names no series (an
  /// album, a track, an episode the server filed under none) open the server's
  /// own page as they always did: the tap never ends nowhere, and never says
  /// that a lookup it did for itself failed.
  Future<void> openStreamItem(
    ServiceKey service,
    StreamItem item, {
    String instanceId = '',
  }) async {
    final container = ProviderScope.containerOf(this, listen: false);
    final focus = instanceId.isNotEmpty
        ? instanceId
        : container.read(activeInstanceProvider(service))?.id;
    if (MediaKey.ofStreamItem(item) case final key?) {
      return openMedia(key, focus: focus);
    }
    if (item.seriesId case final seriesId?
        when item.kind == StreamItemKind.season ||
            item.kind == StreamItemKind.episode) {
      final asked = '${service.name}/$instanceId/${item.id}';
      // A second tap while the first is out would open the page twice.
      if (!_askedKeys.add(asked)) return;
      final MediaKey? series;
      try {
        series = await _serverKeyOf(
          container,
          service,
          instanceId,
          (client, cancelToken) =>
              client.getSeriesKey(seriesId, cancelToken: cancelToken),
        );
      } finally {
        _askedKeys.remove(asked);
      }
      // The tile went away while the read was out: nobody is left to open it.
      if (!mounted) return;
      if (series != null) {
        return openMedia(series, focus: focus, season: item.seasonNumber);
      }
    }
    await push(
      ServiceRoutes.streamItem(service, item.id, instanceId: instanceId),
    );
  }

  /// Opens the title a live playback plays, on the connection [instanceId]
  /// of [service] (empty: the lens): the page its source already named
  /// (`StreamSession.titleKey`), else the page the server's ids for the title
  /// name (`StreamServerClient.getTitleKey`), the movie's or for an episode
  /// its series', else the server's own page of the title. A session that
  /// names no title ([canOpenStreamSession] false) opens nothing.
  Future<void> openStreamSession(
    ServiceKey service,
    StreamSession session, {
    String instanceId = '',
  }) async {
    final container = ProviderScope.containerOf(this, listen: false);
    final focus = instanceId.isNotEmpty
        ? instanceId
        : container.read(activeInstanceProvider(service))?.id;
    if (session.titleKey case final key?) return openMedia(key, focus: focus);
    final titleId = session.titleId;
    if (titleId == null || titleId.isEmpty) return;
    final asked = '${service.name}/$instanceId/title/$titleId';
    if (!_askedKeys.add(asked)) return;
    final MediaKey? key;
    try {
      key = await _serverKeyOf(
        container,
        service,
        instanceId,
        (client, cancelToken) =>
            client.getTitleKey(titleId, cancelToken: cancelToken),
      );
    } finally {
      _askedKeys.remove(asked);
    }
    if (!mounted) return;
    if (key != null) return openMedia(key, focus: focus);
    await push(
      ServiceRoutes.streamItem(service, titleId, instanceId: instanceId),
    );
  }

  /// Pushes a person's page under the tab the user is on, as a title opened
  /// here would be (`ServiceRoutes.person`), and on a tablet beside the list
  /// as a title is.
  Future<void> openPerson(int id, {String? heroTag, String? posterUrl}) =>
      _openBeside(
        ServiceRoutes.person(
          id,
          from: _here,
          heroTag: heroTag,
          posterUrl: posterUrl,
        ),
      );

  /// Pushes a collection's page under the tab the user is on, and on a
  /// tablet beside the list as a title is.
  Future<void> openCollection(int id, {String? heroTag}) =>
      _openBeside(ServiceRoutes.collection(id, from: _here, heroTag: heroTag));

  /// Pushes [location], a title's page in root form moved under the tab the
  /// user is on (`ServiceRoutes.mounted`); any other location as it is.
  Future<void> pushMounted(String location, {Object? extra}) {
    final mounted = ServiceRoutes.mounted(location, from: _here);
    return MediaSplit.pageOf(Uri.parse(mounted)) == null
        ? push(mounted, extra: extra)
        : _openBeside(mounted, extra: extra);
  }
}

/// How long a tap waits for the title's ids before it opens the server's own
/// page instead: a server that is slow to say is not worth a tap that does
/// nothing.
const _keyLookupLimit = Duration(seconds: 4);

/// The taps whose page key is being read (a season's or an episode's series,
/// a playback's title): a tap on one of them is not taken twice.
final _askedKeys = <String>{};

/// Whether [session] names a title its card can open
/// (`OpenMedia.openStreamSession`).
bool canOpenStreamSession(StreamSession session) =>
    session.titleKey != null || (session.titleId?.isNotEmpty ?? false);

/// The page key [read] answers through the connection [instanceId] of
/// [service] (empty: the lens), or null for any reason it cannot be had: the
/// connection is gone, the server did not answer in [_keyLookupLimit] or
/// holds no id for the title.
Future<MediaKey?> _serverKeyOf(
  ProviderContainer container,
  ServiceKey service,
  String instanceId,
  Future<MediaKey?> Function(StreamServerClient client, CancelToken cancelToken)
  read,
) async {
  final cancelToken = CancelToken();
  try {
    // Through the connection's own client, so its address, access and pin
    // follow the route it is reached by.
    final client = container.read(
      streamClientForProvider((service: service, instanceId: instanceId)),
    );
    return await read(client, cancelToken).timeout(_keyLookupLimit);
  } catch (_) {
    return null;
  } finally {
    // Whatever ended the wait, a read still out is not wanted.
    cancelToken.cancel();
  }
}
