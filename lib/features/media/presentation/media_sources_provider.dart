import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/models/media_preview.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/bazarr_provider.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/seerr_numbering.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/domain/seerr_media_copy.dart';
import 'package:cupola/features/media/domain/media_collection.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/presentation/series_provider.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';

/// One source of a Media page: a title, read through one connection.
///
/// A record, so a family keyed on it compares structurally.
typedef MediaSource = ({MediaKey key, String connectionId});

/// The connections of [service] that are set up enough to ask, in the order
/// the settings keep them.
List<ServiceInstance> _configured(Ref ref, ServiceKey service) => ref
    .watch(currentSettingsProvider)
    .instancesOf(service)
    .where((instance) => instance.isConfigured)
    .toList(growable: false);

/// The arr that holds titles of [key]'s kind.
ServiceKey _arrOf(MediaKey key) =>
    key.isMovie ? ServiceKey.radarr : ServiceKey.sonarr;

/// What the Radarr [MediaSource.connectionId] holds of the film: one
/// `movie?tmdbId=` read, and that Radarr's own queue.
///
/// A failure travels (`RadarrService.getMovieByTmdbId`): a Radarr that did
/// not answer is never a film it does not hold. The queue never fails the
/// copy: a queue that did not answer is a snapshot that says so, and the badge
/// waits for it.
final mediaRadarrCopyProvider = FutureProvider.autoDispose
    .family<MediaAnswer<MediaRadarrCopy>, MediaSource>((ref, source) async {
      final tmdbId = source.key.tmdbId;
      if (!source.key.isMovie || tmdbId == null) {
        throw ArgumentError.value(source.key, 'key', 'not a movie');
      }
      final radarr = ref.watch(radarrServiceForProvider(source.connectionId));
      // Subscribed before the first await, like everything this build reads:
      // a ref used after one may belong to a build disposed meanwhile. The
      // queue is the connection's, shared and kept, and never fails.
      final queue = ref.watch(
        radarrQueueSnapshotForProvider(source.connectionId).future,
      );
      final movie = await radarr.getMovieByTmdbId(tmdbId);
      return MediaAnswer(
        MediaRadarrCopy(
          movie: movie,
          queue: movie == null ? ArrQueueSnapshot.empty : await queue,
        ),
        DateTime.now(),
      );
    }, retry: noProviderRetry);

/// TVDB's id of the series [MediaKey] names: what Sonarr is asked by.
///
/// The key's own, else the first Seerr that answers with TMDB's record of the
/// series, else the first Sonarr whose library carries the TMDB id (Sonarr v4
/// records it; v3 does not, and a v3 Sonarr then cannot be matched without a
/// Seerr). Null when nobody can say.
///
/// The library is the one the app already holds for that connection
/// ([seriesForProvider], read once a session), never a download of its own:
/// this runs on every opening of a series page.
final mediaTvdbIdProvider = FutureProvider.autoDispose.family<int?, MediaKey>((
  ref,
  key,
) async {
  if (key.isMovie) return null;
  final own = key.tvdbId;
  if (own != null) return own;
  for (final seerr in _configured(ref, ServiceKey.seerr)) {
    try {
      final record = await ref.watch(
        mediaSeerrRecordProvider((key: key, connectionId: seerr.id)).future,
      );
      final tvdb = record.value.tvdbId;
      if (tvdb != null) return tvdb;
    } catch (_) {
      // That Seerr's failure is on its own row; another may still say.
    }
  }
  for (final sonarr in _configured(ref, ServiceKey.sonarr)) {
    try {
      final library = await ref.watch(seriesForProvider(sonarr.id).future);
      for (final series in library) {
        if (series.tmdbId == key.tmdbId && series.tvdbId > 0) {
          return series.tvdbId;
        }
      }
    } catch (_) {
      // That Sonarr's failure is on its own row.
    }
  }
  return null;
}, retry: noProviderRetry);

/// What the Sonarr [MediaSource.connectionId] holds of the series: one
/// `series?tvdbId=` read, its episodes, and that Sonarr's own queue by series
/// and by episode. The episodes are the same Sonarr's answer: a read of them
/// that fails fails the copy, rather than a series with no episodes.
///
/// A series whose TVDB id nobody can name reads as one this Sonarr does not
/// track ([mediaTvdbIdProvider] says when that is honest).
final mediaSonarrCopyProvider = FutureProvider.autoDispose
    .family<MediaAnswer<MediaSonarrCopy>, MediaSource>((ref, source) async {
      if (source.key.isMovie) {
        throw ArgumentError.value(source.key, 'key', 'not a series');
      }
      final sonarr = ref.watch(sonarrServiceForProvider(source.connectionId));
      // Subscribed before the first await, as the Radarr copy does.
      final queuesRead = ref.watch(
        sonarrQueueSnapshotsForProvider(source.connectionId).future,
      );
      final tvdbId = await ref.watch(mediaTvdbIdProvider(source.key).future);
      final series = tvdbId == null
          ? null
          : await sonarr.getSeriesByTvdbId(tvdbId);
      if (series == null) {
        return MediaAnswer(
          const MediaSonarrCopy(series: null, queue: ArrQueueSnapshot.empty),
          DateTime.now(),
        );
      }
      final episodes = await sonarr.getEpisodes(series.id);
      final queues = await queuesRead;
      return MediaAnswer(
        MediaSonarrCopy(
          series: series,
          queue: queues.bySeries,
          episodes: episodes,
          episodeQueue: queues.byEpisode,
        ),
        DateTime.now(),
      );
    }, retry: noProviderRetry);

/// What the media server [MediaSource.connectionId] answers about the title,
/// looked up by its ids and checked again here, as `streamAvailabilityProvider`
/// does: a client that forgets to verify cannot put a wrong Play on the page.
final mediaStreamCopyProvider = FutureProvider.autoDispose
    .family<MediaAnswer<MediaStreamCopy>, MediaSource>((ref, source) async {
      // Which server the connection is, and nothing else of the settings: a
      // write elsewhere (the region, another connection) asks nothing again.
      // Its address and access reach the client through its own route.
      final service = ref.watch(
        currentSettingsProvider.select(
          (settings) => settings.instanceById(source.connectionId)?.service,
        ),
      );
      final client = switch (service) {
        final media? when media.isMediaServer => ref.watch(
          streamBackendOf(media).clientFor(source.connectionId),
        ),
        _ => throw ArgumentError.value(
          source.connectionId,
          'connectionId',
          'not a media server',
        ),
      };
      final key = source.key;
      final query = StreamExternalQuery(
        tmdbId: key.tmdbId?.toString(),
        tvdbId: key.tvdbId?.toString(),
        kind: key.isMovie ? StreamItemKind.movie : StreamItemKind.series,
      );
      final cancelToken = CancelToken();
      ref.onDispose(cancelToken.cancel);
      final lookup = await client.lookupByExternalId(
        tmdbId: query.tmdbId,
        tvdbId: query.tvdbId,
        kind: query.kind,
        cancelToken: cancelToken,
      );
      final item = lookup.item;
      final copy = switch (lookup.outcome) {
        StreamLookupOutcome.found
            when item != null &&
                streamExternalMatchScore(item, query) != null =>
          MediaStreamCopy.found(
            item,
            // At the hero poster's largest box, on a dense screen.
            poster: switch (item.posterPath) {
              final path? when path.isNotEmpty => client.imageFor(
                path,
                width: 400,
              ),
              _ => null,
            },
            episodes: key.isMovie
                ? null
                : await _streamEpisodes(client, item.id, cancelToken),
          ),
        StreamLookupOutcome.notInLibrary =>
          const MediaStreamCopy.notInLibrary(),
        _ => const MediaStreamCopy.notVerified(),
      };
      return MediaAnswer(copy, DateTime.now());
    }, retry: noProviderRetry);

/// A series' episodes on a media server, or null when the read of them did
/// not answer: the copy itself is still a fact, and its episodes are then
/// unknown, never absent.
Future<List<StreamItem>?> _streamEpisodes(
  StreamServerClient client,
  String seriesId,
  CancelToken cancelToken,
) async {
  try {
    return await client.getEpisodes(seriesId, cancelToken: cancelToken);
  } catch (_) {
    return null;
  }
}

/// What the Seerr [MediaSource.connectionId] knows of the title: its record
/// and, when the connection may read them, the servers of the arr that holds
/// this kind of title.
final mediaSeerrRecordProvider = FutureProvider.autoDispose
    .family<MediaAnswer<MediaSeerrRecord>, MediaSource>((ref, source) async {
      final tmdbId = source.key.tmdbId;
      if (tmdbId == null) {
        throw ArgumentError.value(source.key, 'key', 'Seerr needs a TMDB id');
      }
      final seerr = ref.watch(seerrServiceForProvider(source.connectionId));
      // Four reads that need nothing from one another, started together: the
      // page waits for the slowest, not for the sum, and the scores, which
      // Seerr goes outside to fetch, no longer hold the title back. Every one
      // but the record is answered with null where it is started, not where
      // it is awaited: a read failing before its turn at `await` would be an
      // error nobody is listening for.
      final detailsRead = source.key.isMovie
          ? seerr.getMovie(tmdbId)
          : seerr.getTv(tmdbId);
      // An account without ADMIN may not read the servers, and a failed read
      // is no list either: no copy is bound, and nothing is claimed.
      final serversRead = _orNull(
        () => seerr.getArrServers(_arrOf(source.key)),
      );
      // A score that did not answer reads `—`: never the record's failure.
      final scoresRead = _orNull<({int? rottenTomatoes, double? imdb})>(
        () async {
          if (source.key.isMovie) return seerr.getMovieScores(tmdbId);
          return (
            rottenTomatoes: await seerr.getTvCriticsScore(tmdbId),
            imdb: null,
          );
        },
      );
      // Asked of a public route, once per connection; a silence leaves the
      // codes that differ undecoded.
      final numberingRead = _orNull(seerr.numbering);

      final details = await detailsRead;
      final servers = await serversRead;
      final scores = await scoresRead;
      return MediaAnswer(
        MediaSeerrRecord(
          details: details,
          arrServers: servers,
          rottenTomatoes: scores?.rottenTomatoes,
          imdb: scores?.imdb,
          numbering: await numberingRead,
        ),
        DateTime.now(),
      );
    }, retry: noProviderRetry);

/// [read]'s answer, or null when it threw, whether on the spot or later.
///
/// The read starts as this is called and the returned future never fails, so
/// it can be started early and awaited at leisure.
Future<T?> _orNull<T>(Future<T?> Function() read) async {
  try {
    return await read();
  } catch (_) {
    return null;
  }
}

/// Whether [path], [title] and [year] Bazarr holds name the same copy as the
/// arr's: the same path, or the same title and year.
bool _sameCopy({
  required String? bazarrPath,
  required String? bazarrTitle,
  required int? bazarrYear,
  required String? path,
  required String title,
  required int year,
}) {
  if ((bazarrPath ?? '').isNotEmpty && bazarrPath == path) return true;
  final normalised = normaliseStreamTitle(bazarrTitle);
  return normalised != null &&
      normalised == normaliseStreamTitle(title) &&
      bazarrYear == year;
}

/// What Bazarr checks an arr's copy against: its id, and its path, or its
/// title and year.
typedef _ArrCopyFacts = ({int id, String? path, String title, int year});

/// The arr copy at [source], as the facts Bazarr is checked against; null when
/// that arr holds no copy. Its one `watch` runs before its first await.
Future<_ArrCopyFacts?> _arrCopyFacts(Ref ref, MediaSource source) async {
  if (source.key.isMovie) {
    final movie = (await ref.watch(
      mediaRadarrCopyProvider(source).future,
    )).value.movie;
    return movie == null
        ? null
        : (
            id: movie.id,
            path: movie.path,
            title: movie.title,
            year: movie.year,
          );
  }
  final series = (await ref.watch(
    mediaSonarrCopyProvider(source).future,
  )).value.series;
  return series == null
      ? null
      : (
          id: series.id,
          path: series.path,
          title: series.title,
          year: series.year,
        );
}

/// What the Bazarr [MediaSource.connectionId] holds of the title: the one arr
/// copy it follows, checked against that copy's path, or its title and year.
///
/// Bazarr follows one Radarr and one Sonarr and speaks in their ids, so every
/// tracked copy is asked by its id and the answer verified; the first that
/// matches is the copy Bazarr covers. A copy whose arr did not answer is
/// skipped: it is the arr's failure, already on the arr's own row.
final mediaBazarrCopyProvider = FutureProvider.autoDispose
    .family<MediaAnswer<MediaBazarrCopy?>, MediaSource>((ref, source) async {
      final bazarr = ref.watch(bazarrServiceForProvider(source.connectionId));
      final key = source.key;
      // Every arr's copy is subscribed before the first await (a ref used
      // after one may belong to a build disposed meanwhile). The page's rows
      // read the same copies, so this asks nothing more of the arrs. One that
      // fails is awaited below or never: `ignore` keeps it from being an
      // uncaught error when an earlier copy already matched.
      final arrCopies = [
        for (final arr in _configured(ref, _arrOf(key)))
          (
            arr: arr,
            copy: _arrCopyFacts(ref, (key: key, connectionId: arr.id))
              ..ignore(),
          ),
      ];
      for (final (:arr, copy: copyRead) in arrCopies) {
        // The arr's copy, or nothing to ask Bazarr about. The arr's failure is
        // on its own row and skips the copy here; Bazarr's own fails this one.
        final _ArrCopyFacts? copy;
        try {
          copy = await copyRead;
        } catch (_) {
          continue;
        }
        if (copy == null) continue;
        if (key.isMovie) {
          final followed = await bazarr.getMovieById(copy.id);
          if (followed != null &&
              _sameCopy(
                bazarrPath: followed.path,
                bazarrTitle: followed.title,
                bazarrYear: followed.year,
                path: copy.path,
                title: copy.title,
                year: copy.year,
              )) {
            return MediaAnswer(
              MediaBazarrCopy(arrConnectionId: arr.id, movie: followed),
              DateTime.now(),
            );
          }
        } else {
          final followed = await bazarr.getSeriesById(copy.id);
          if (followed != null &&
              _sameCopy(
                bazarrPath: followed.path,
                bazarrTitle: followed.title,
                bazarrYear: followed.year,
                path: copy.path,
                title: copy.title,
                year: copy.year,
              )) {
            List<BazarrEpisode>? episodes;
            try {
              episodes = await bazarr.getEpisodes(copy.id);
            } catch (_) {
              // The row counts what is wanted instead.
            }
            return MediaAnswer(
              MediaBazarrCopy(
                arrConnectionId: arr.id,
                series: followed,
                episodes: episodes,
              ),
              DateTime.now(),
            );
          }
        }
      }
      return MediaAnswer<MediaBazarrCopy?>(null, DateTime.now());
    }, retry: noProviderRetry);

/// The "On your server" rows of a title, one per fact, in the page's order:
/// the media servers, the arr copies (or Seerr's claims about them), Bazarr,
/// Seerr.
///
/// Every connection is read on its own, and no row waits for another: a
/// connection that did not answer costs its own row, never the page (rule 1).
/// What is not set up is decided from the settings alone, before anything is
/// asked (rule 3). A media server's unverified match draws nothing (rule 7).
final mediaRowsProvider = Provider.autoDispose.family<List<MediaRow>, MediaKey>(
  (ref, key) {
    final rows = <MediaRow>[];
    MediaSource sourceOf(ServiceInstance connection) =>
        (key: key, connectionId: connection.id);

    for (final service in mediaServers) {
      for (final connection in _configured(ref, service)) {
        final reading = MediaReading.of(
          ref.watch(mediaStreamCopyProvider(sourceOf(connection))),
        );
        if (reading case MediaReadingAnswered(
          :final answer,
        ) when answer.value.outcome == StreamLookupOutcome.notVerified) {
          continue;
        }
        rows.add(MediaConnectionRow<MediaStreamCopy>(connection, reading));
      }
    }

    // Seerr needs TMDB's id: a series known only by TVDB's is not asked.
    final seerrs = key.tmdbId == null
        ? const <ServiceInstance>[]
        : _configured(ref, ServiceKey.seerr);
    final seerrReadings = [
      for (final seerr in seerrs)
        (
          connection: seerr,
          reading: MediaReading.of(
            ref.watch(mediaSeerrRecordProvider(sourceOf(seerr))),
          ),
        ),
    ];

    // With no media server of Cupola's own, Seerr's word that the title is
    // on the one Seerr is set up with, and its link to it there (rule 9).
    final players = [
      for (final service in mediaServers) ..._configured(ref, service),
    ];
    if (players.isEmpty) {
      for (final seerr in seerrReadings) {
        // Asked beside the record, so the server is usually named by the
        // time the record says the title is there.
        ref.watch(seerrServerFactsProvider(seerr.connection.id));
        if (seerr.reading case MediaReadingAnswered(:final answer)) {
          if (_playerClaim(ref, seerr.connection, answer.value)
              case final claim?) {
            rows.add(claim);
            break;
          }
        }
      }
    }

    final arr = _arrOf(key);
    final arrs = _configured(ref, arr);
    for (final connection in arrs) {
      rows.add(
        key.isMovie
            ? MediaConnectionRow<MediaRadarrCopy>(
                connection,
                MediaReading.of(
                  ref.watch(mediaRadarrCopyProvider(sourceOf(connection))),
                ),
              )
            : MediaConnectionRow<MediaSonarrCopy>(
                connection,
                MediaReading.of(
                  ref.watch(mediaSonarrCopyProvider(sourceOf(connection))),
                ),
              ),
      );
    }
    final claims = [
      for (final seerr in seerrReadings)
        if (seerr.reading case MediaReadingAnswered(:final answer))
          for (final copy in answer.value.copies)
            if (SeerrBoundCopy.of(
                  copy,
                  arr: arr,
                  servers: answer.value.arrServers,
                  connections: arrs,
                )
                case final bound when bound.isKnownOnlyToSeerr)
              MediaThroughSeerrRow(
                seerr: seerr.connection,
                copy: bound,
                mediaInfo: answer.value.mediaInfo,
              ),
    ];
    rows.addAll(claims);
    if (arrs.isEmpty && claims.isEmpty) rows.add(MediaNotSetUpRow(arr));

    for (final connection in _configured(ref, ServiceKey.bazarr)) {
      rows.add(
        MediaConnectionRow<MediaBazarrCopy?>(
          connection,
          MediaReading.of(
            ref.watch(mediaBazarrCopyProvider(sourceOf(connection))),
          ),
        ),
      );
    }

    for (final seerr in seerrReadings) {
      rows.add(
        MediaConnectionRow<MediaSeerrRecord>(seerr.connection, seerr.reading),
      );
    }
    // A Seerr account with no session is signed out, never not set up: its
    // row says so with the way to sign in again, and nothing is asked of it.
    final signedOut = ref
        .watch(currentSettingsProvider)
        .instancesOf(ServiceKey.seerr)
        .where((instance) => instance.isSignedOut);
    for (final seerr in signedOut) {
      rows.add(
        MediaConnectionRow<MediaSeerrRecord>(
          seerr,
          const MediaReadingFailed(ServiceFailureReason.sessionEnded),
        ),
      );
    }
    if (_configured(ref, ServiceKey.seerr).isEmpty && signedOut.isEmpty) {
      rows.add(const MediaNotSetUpRow(ServiceKey.seerr));
    }
    return rows;
  },
);

/// Seerr [seerr]'s claim that the title is on the media server it is set up
/// with: where [record] says it is there, in part or whole, with a link to
/// it. The server comes from Seerr's public settings: a claim with none
/// while they are out, and no claim when they failed or name a server Cupola
/// cannot set up (Emby).
MediaServerThroughSeerrRow? _playerClaim(
  Ref ref,
  ServiceInstance seerr,
  MediaSeerrRecord record,
) {
  final mediaInfo = record.mediaInfo;
  bool there(Object? code) => code == 4 || code == 5;
  if (!there(mediaInfo?['status']) && !there(mediaInfo?['status4k'])) {
    return null;
  }
  final url = Uri.tryParse(
    stringOrNull(mediaInfo?['mediaUrl']) ??
        stringOrNull(mediaInfo?['mediaUrl4k']) ??
        '',
  );
  if (url == null || !url.hasScheme) return null;
  final facts = ref.watch(seerrServerFactsProvider(seerr.id));
  final ServiceKey? server;
  if (facts.isLoading && !facts.hasValue) {
    server = null;
  } else {
    switch (facts.value?.mediaServer) {
      case SeerrMediaServer.jellyfin:
        server = ServiceKey.jellyfin;
      case SeerrMediaServer.plex:
        server = ServiceKey.plex;
      default:
        return null;
    }
  }
  return MediaServerThroughSeerrRow(
    seerr: seerr,
    server: server,
    mediaInfo: mediaInfo,
    url: url,
  );
}

/// "More like this": TMDB's recommendations through the Seerr
/// [MediaSource.connectionId], read when the page asks for them.
final mediaRecommendationsProvider = FutureProvider.autoDispose
    .family<List<MediaPreview>, MediaSource>((ref, source) async {
      final tmdbId = source.key.tmdbId;
      if (tmdbId == null) return const [];
      return ref
          .watch(seerrServiceForProvider(source.connectionId))
          .getRecommendations(source.key.isMovie ? 'movie' : 'tv', tmdbId);
    }, retry: noProviderRetry);

/// The collection a title belongs to, counted on the household's server
/// through the Seerr [connectionId]; null when Seerr has no such collection.
final mediaCollectionHeldProvider = FutureProvider.autoDispose
    .family<MediaCollectionHeld?, ({String connectionId, int collectionId})>((
      ref,
      collection,
    ) async {
      final seerr = ref.watch(seerrServiceForProvider(collection.connectionId));
      final json = await seerr.getCollection(collection.collectionId);
      return mediaCollectionHeld(json, numbering: await seerr.numbering());
    }, retry: noProviderRetry);

/// One Radarr copy's history, read when History opens.
final mediaRadarrHistoryProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({String connectionId, int movieId})>((
      ref,
      copy,
    ) {
      return ref
          .watch(radarrServiceForProvider(copy.connectionId))
          .getMovieHistory(copy.movieId);
    }, retry: noProviderRetry);

/// A film nobody holds, as the Radarr it would be added to looks it up: what
/// the add posts back.
final mediaAddLookupProvider = FutureProvider.autoDispose
    .family<RadarrMovie, ({String connectionId, int tmdbId})>((ref, target) {
      return ref
          .watch(radarrServiceForProvider(target.connectionId))
          .lookupMovieByTmdbId(target.tmdbId);
    }, retry: noProviderRetry);

/// A series nobody holds, as the Sonarr it would be added to looks it up: by
/// TVDB's id when it is known, else by TMDB's (which Sonarr 4 reads). What
/// the add posts back. Throws when Sonarr does not answer or does not find
/// it.
final mediaSonarrAddLookupProvider = FutureProvider.autoDispose
    .family<SonarrSeries, ({String connectionId, int? tvdbId, int? tmdbId})>((
      ref,
      target,
    ) async {
      final tvdb = target.tvdbId;
      final found = await ref
          .watch(sonarrServiceForProvider(target.connectionId))
          .lookupSeries(
            tvdb != null ? 'tvdb:$tvdb' : 'tmdb:${target.tmdbId}',
            reportFailure: true,
          );
      for (final series in found) {
        if (tvdb != null
            ? series.tvdbId == tvdb
            : series.tmdbId == target.tmdbId) {
          return series;
        }
      }
      throw StateError('Sonarr found no series under that id');
    }, retry: noProviderRetry);

/// One Radarr copy's downloads, read while its panel shows one.
final mediaRadarrQueueProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, ({String connectionId, int movieId})>((
      ref,
      copy,
    ) {
      return ref
          .watch(radarrServiceForProvider(copy.connectionId))
          .getMovieQueue(copy.movieId);
    }, retry: noProviderRetry);

/// When a search for one Radarr copy was asked, while it runs; null when none
/// does. Asked again every few seconds while one does, so the panel turns from
/// searching to what Radarr found.
final mediaRadarrSearchProvider = FutureProvider.autoDispose
    .family<DateTime?, ({String connectionId, int movieId})>((ref, copy) async {
      final since = await ref
          .watch(radarrServiceForProvider(copy.connectionId))
          .searchingSince(copy.movieId);
      if (since != null) {
        final again = Timer(const Duration(seconds: 4), ref.invalidateSelf);
        ref.onDispose(again.cancel);
      }
      return since;
    }, retry: noProviderRetry);

/// One Radarr's quality profiles, by id: read when a copy's Files & quality
/// opens. Empty when Radarr did not answer.
final mediaRadarrProfilesProvider = FutureProvider.autoDispose
    .family<Map<int, String>, String>((ref, connectionId) async {
      final profiles = await ref
          .watch(radarrServiceForProvider(connectionId))
          .getQualityProfiles();
      return {
        for (final profile in profiles)
          if (profile['id'] case final int id) id: '${profile['name'] ?? ''}',
      };
    }, retry: noProviderRetry);

/// The numbering one Seerr follows for its media codes, so a request's state
/// is read as that server means it. Null until it has said.
final mediaSeerrNumberingProvider = FutureProvider.autoDispose
    .family<SeerrNumbering?, String>((ref, connectionId) {
      return ref.watch(seerrServiceForProvider(connectionId)).numbering();
    }, retry: noProviderRetry);

/// Asks [row]'s connection again, and only it: a failed row's `Retry`.
void retryMediaRow(WidgetRef ref, MediaKey key, MediaRow row) {
  if (row is! MediaConnectionRow) return;
  final source = (key: key, connectionId: row.connection.id);
  if (row.service.isMediaServer) {
    ref.invalidate(mediaStreamCopyProvider(source));
    return;
  }
  switch (row.service) {
    case ServiceKey.radarr:
      ref.invalidate(mediaRadarrCopyProvider(source));
    case ServiceKey.sonarr:
      ref.invalidate(mediaSonarrCopyProvider(source));
    case ServiceKey.bazarr:
      ref.invalidate(mediaBazarrCopyProvider(source));
    case ServiceKey.seerr:
      ref.invalidate(mediaSeerrRecordProvider(source));
    default:
      break;
  }
}
