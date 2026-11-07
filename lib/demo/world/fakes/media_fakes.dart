/// Seerr, Jellyfin and Plex on the fake network.
library;

import 'dart:convert';

import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'package:cupola/demo/world/artwork.dart';
import 'package:cupola/demo/world/fixtures.dart';
import 'package:cupola/demo/world/config_profile.dart';
import 'package:cupola/demo/world/profile_network.dart';
import 'package:cupola/demo/world/service_fakes.dart';
import 'package:cupola/demo/world/world.dart';
import 'package:cupola/demo/world/fakes/arr_fakes.dart';
import 'package:cupola/demo/world/fakes/seerr_sessions.dart';

// === Seerr =================================================================

/// Seerr, as whoever calls it sees it: the operator's admin key, or a
/// household member's own session.
///
/// Its settings know the Radarr and Sonarr servers the profile lists in
/// `seerrKnows`, whether or not Cupola has a connection to them, which is
/// the whole of the b case.
///
/// Who is calling, the sign-in routes, the sessions and the CSRF guard are in
/// `seerr_sessions.dart`; this class holds the world's data and the checks
/// each route makes on its own (a requester sees her own requests only).
class SeerrFake extends ServiceFake {
  const SeerrFake();

  /// The routes that want nobody, the one list [gate] reads: `/status`,
  /// `/status/appdata` and `/settings/public` (`security: []` in the API
  /// spec), every route under `/auth` but `GET /auth/me`, and whatever is
  /// not the API at all (`server/routes/index.ts`).
  @override
  bool isPublic(NetworkRequest r) {
    const v1 = '/api/v1/';
    if (!r.path.startsWith(v1)) return true;
    final route = r.path.substring(v1.length);
    if (route.startsWith('auth/')) {
      return !(r.method == 'GET' && route == 'auth/me');
    }
    return r.method == 'GET' &&
        const {'status', 'status/appdata', 'settings/public'}.contains(route);
  }

  // Seerr reads a key it does not know as nobody, and refuses nobody the way
  // `isAuthenticated` does.
  @override
  NetworkReply refuseKey(NetworkRequest request) => seerrEndpointRefused();

  @override
  NetworkReply refuseWrite(NetworkRequest request) => seerrEndpointRefused();

  /// A web page still answers in front of everything; otherwise Seerr's own
  /// middleware decides: the CSRF guard, then the key or the session, then
  /// the route's permission.
  @override
  NetworkReply? gate(NetworkRequest r, ServerContext c) {
    if (c.behaviour == ConnectionBehaviour.servesHtmlPage) {
      return super.gate(r, c);
    }
    return seerrGate(r, c, isPublic: isPublic);
  }

  @override
  NetworkReply finish(
    NetworkRequest request,
    ServerContext context,
    NetworkReply reply,
  ) => seerrFinish(request, reply);

  // Search and discovery are GETs; every write is a POST, PUT or DELETE.

  /// User [id] as a request, an issue or the user list names them.
  static JsonMap _user(ServerContext c, int id) {
    final user =
        SeerrSetup.of(c).userById(id) ??
        WorldSeerrUsers.household.firstWhere((u) => u.id == id);
    return {
      'id': id,
      'displayName': user.displayName,
      'username': user.displayName.toLowerCase(),
      'email': user.email,
      'permissions': user.permissions,
      'userType': user.kind.wire,
      'avatar': '/avatarproxy/$id',
      'requestCount': id == 1 ? 0 : 20,
    };
  }

  /// `(request id, title, requester, request status, age, is4k)`.
  ///
  /// Request status: 1 pending, 2 approved, 3 declined. The media's own
  /// status comes from [_mediaStatus], so a request and the title's page
  /// never disagree.
  static const _requests = [
    (1, WorldTitles.charge, 2, 1, Duration(hours: 2), false),
    (2, WorldTitles.metropolis, 3, 1, Duration(days: 1), false),
    (3, WorldTitles.spriteFright, 2, 2, Duration(days: 20), false),
    (4, WorldTitles.coffeeRun, 3, 2, Duration(days: 5), false),
    (5, WorldTitles.sintel, 2, 2, Duration(days: 9), false),
    (6, WorldTitles.tearsOfSteel, 2, 2, Duration(days: 30), true),
    (7, WorldTitles.cosmosLaundromat, 2, 2, Duration(days: 60), false),
    // A series' next season, asked for and waiting.
    (8, WorldTitles.nightShift, 3, 1, Duration(hours: 5), false),
  ];

  /// What Seerr knows of each title: `(status, status4k)`, Seerr's media
  /// status: 1 unknown, 2 pending, 3 processing, 4 partially available,
  /// 5 available. Null for a title Seerr has no media row for.
  static (int, int)? _mediaStatus(WorldTitle t) => switch (t.key) {
    'spriteFright' || 'bigBuckBunny' => (3, 1),
    'coffeeRun' => (5, 1),
    'sintel' || 'elephantsDream' => (5, 3),
    'tearsOfSteel' => (5, 5),
    'spring' => (1, 5),
    'charge' || 'metropolis' => (2, 1),
    'cosmosLaundromat' || 'nightShift' => (4, 1),
    _ => null,
  };

  /// The requests as the world stands: as written, or, once it lives, as the
  /// demo left them.
  static List<(int, WorldTitle, int, int, Duration, bool)> _requestsOf(
    ServerContext c,
  ) {
    final live = _live(c);
    if (live == null) return _requests;
    return [
      for (final q in live)
        (
          q.id,
          q.title,
          q.requester,
          q.status,
          c.now.difference(q.created),
          q.is4k,
        ),
    ];
  }

  /// The living world's requests, read from the written ones the first time.
  static List<LiveSeerrRequest>? _live(ServerContext c) {
    if (c.life == null) return null;
    return seerrStateOf(c.network, c.server.id).liveRequests ??= [
      for (final (id, title, by, status, age, is4k) in _requests)
        LiveSeerrRequest(
          id: id,
          title: title,
          requester: by,
          status: status,
          created: c.now.subtract(age),
          is4k: is4k,
          fromWorld: true,
        ),
    ];
  }

  /// What Seerr knows of [t]: as written, or, once the world lives, what its
  /// arr holds and fetches and what the demo asked for.
  static (int, int)? _mediaStatusOf(ServerContext c, WorldTitle t) {
    final written = _mediaStatus(t);
    if (c.life == null) return written;
    final hd = _liveStatus(c, t, is4k: false) ?? written?.$1;
    final uhd = _liveStatus(c, t, is4k: true) ?? written?.$2;
    if (hd == null && uhd == null) return null;
    return (hd ?? 1, uhd ?? 1);
  }

  /// One copy's status as the living world says it, or null to keep the
  /// written one: on disk is available, a download under way is processing,
  /// and a request the demo made or decided waits, is processing, or, once
  /// declined, leaves the title unknown.
  static int? _liveStatus(ServerContext c, WorldTitle t, {required bool is4k}) {
    final life = c.life!;
    final arr = _arrFor(c, t, is4k);
    if (arr != null) {
      if (t.isSeries) {
        final held = life.arrs.seriesOf(arr, t);
        if (held != null && !held.seeded && held.arrivedSeasons.isNotEmpty) {
          return 5;
        }
      } else if (life.arrs.movieOf(arr, t)?.hasFile ?? false) {
        return 5;
      }
      final fetching = life.downloads.any(
        (d) =>
            d.arr == arr &&
            d.title == t &&
            d.state != DownloadState.seeding &&
            d.state != DownloadState.stopped,
      );
      if (fetching) return 3;
    }
    // Only what the demo asked for or decided speaks: the world's own
    // requests are in the written status already.
    final decided = [
      for (final q in _live(c)!)
        if (q.title == t && q.is4k == is4k && (!q.fromWorld || q.changed)) q,
    ];
    if (decided.isEmpty) return null;
    final open = decided.where((q) => q.status != 3);
    // Declined, and nothing else asked: Seerr knows nothing of it again.
    if (open.isEmpty) return 1;
    return open.any((q) => q.status == 2) ? 3 : 2;
  }

  /// The network's id of the arr Seerr sends a request for [t] to, or null
  /// when Seerr knows none this device reaches.
  static String? _arrFor(ServerContext c, WorldTitle t, bool is4k) {
    final kind = t.isSeries ? ServiceKey.sonarr : ServiceKey.radarr;
    final servers = _known(c, kind).where((s) => s.is4k == is4k).toList();
    if (servers.isEmpty) return null;
    final known =
        servers.where((s) => s.isDefault).firstOrNull ?? servers.first;
    return c.network.serverAt(Uri.parse(known.url))?.id;
  }

  /// A request approved in a living world goes to its arr, which adds the
  /// title and searches for it.
  static void _send(ServerContext c, LiveSeerrRequest q) {
    final arr = _arrFor(c, q.title, q.is4k);
    final arrs = c.life?.arrs;
    if (arr == null || arrs == null) return;
    if (q.title.isSeries) {
      arrs.addSeries(arr, q.title, search: true);
    } else {
      arrs.addMovie(arr, q.title, search: true);
    }
  }

  /// A request made in a living world: kept, and sent on at once when it is
  /// approved as it is made.
  static (int, WorldTitle, int, int, Duration, bool) _keep(
    ServerContext c, {
    required WorldTitle title,
    required int requester,
    required bool approved,
    required bool is4k,
  }) {
    final live = _live(c)!;
    final q = LiveSeerrRequest(
      id: live.fold<int>(0, (top, q) => q.id > top ? q.id : top) + 1,
      title: title,
      requester: requester,
      status: approved ? 2 : 1,
      created: c.now,
      is4k: is4k,
    );
    live.add(q);
    if (approved) _send(c, q);
    return (q.id, title, requester, q.status, Duration.zero, is4k);
  }

  /// How long ago [t] arrived on its arr in the demo, or null when it did
  /// not: the player has held it since then.
  static Duration? _arrivedInDemo(ServerContext c, WorldTitle t) {
    final arrs = c.life?.arrs;
    final arr = arrs == null ? null : _arrFor(c, t, false);
    if (arrs == null || arr == null) return null;
    final at = t.isSeries
        ? arrs.seriesOf(arr, t)?.arrived
        : arrs.movieOf(arr, t)?.arrivedLive;
    return at == null ? null : c.now.difference(at);
  }

  /// The id [t] has on the arr Seerr sends it to: the world's, or the one a
  /// living arr gave it.
  static int? _externalId(ServerContext c, WorldTitle t, {required bool is4k}) {
    final written = t.isSeries
        ? (is4k ? null : SonarrFake.idOf(t))
        : RadarrFake.idOf(t, is4k: is4k);
    final arrs = c.life?.arrs;
    final arr = arrs == null ? null : _arrFor(c, t, is4k);
    if (arrs == null || arr == null) return written;
    return t.isSeries
        ? arrs.seriesOf(arr, t)?.id ?? written
        : arrs.movieOf(arr, t)?.id ?? written;
  }

  /// The collection every Blender film belongs to: 5 of 8 on the server,
  /// 2 on the way, 1 requested.
  static const collectionId = 90101;
  static const collectionName = 'Blender Open Movies';
  static const collectionParts = [
    WorldTitles.elephantsDream,
    WorldTitles.bigBuckBunny,
    WorldTitles.sintel,
    WorldTitles.tearsOfSteel,
    WorldTitles.spring,
    WorldTitles.coffeeRun,
    WorldTitles.spriteFright,
    WorldTitles.charge,
  ];

  /// Ian Hubert: director, 3 of 4 on the server.
  static const personId = 90001;
  static const personName = 'Ian Hubert';
  static const personCredits = [
    WorldTitles.tearsOfSteel,
    WorldTitles.elephantsDream,
    WorldTitles.sintel,
    WorldTitles.charge,
  ];

  static List<SeerrKnownServer> _known(ServerContext c, ServiceKey kind) => [
    for (final s in c.profile.seerrKnows)
      if (s.service == kind) s,
  ];

  /// Seerr's id for the server a title of this kind and resolution goes to.
  static int? _serverFor(ServerContext c, WorldTitle t, bool is4k) {
    final kind = t.isSeries ? ServiceKey.sonarr : ServiceKey.radarr;
    final servers = _known(c, kind).where((s) => s.is4k == is4k).toList();
    if (servers.isEmpty) return null;
    return (servers.where((s) => s.isDefault).firstOrNull ?? servers.first)
        .seerrId;
  }

  static JsonMap? _media(ServerContext c, WorldTitle t) {
    final status = _mediaStatusOf(c, t);
    if (status == null) return null;
    final (hd, uhd) = status;
    final hdId = _externalId(c, t, is4k: false);
    final uhdId = t.isSeries ? null : _externalId(c, t, is4k: true);
    return {
      'id': t.tmdbId,
      'tmdbId': t.tmdbId,
      if (t.tvdbId != null) 'tvdbId': t.tvdbId,
      'mediaType': t.isSeries ? 'tv' : 'movie',
      'status': hd,
      'status4k': uhd,
      'serviceId': hdId == null ? null : _serverFor(c, t, false),
      'serviceId4k': uhdId == null ? null : _serverFor(c, t, true),
      'externalServiceId': hdId,
      'externalServiceId4k': uhdId,
      'externalServiceSlug': t.slug,
      // Seerr's link to the title in the player it is set up with, once it
      // is there, whole or in part.
      if (hd == 4 || hd == 5)
        'mediaUrl': '${WorldHosts.jellyfin}/web/#/details?id=jf-${t.key}',
      // When the player first held it: Coffee Run this afternoon, Sintel
      // two days ago, the rest of what is there long before.
      if (hd == 4 || hd == 5)
        'mediaAddedAt': c.ago(
          _arrivedInDemo(c, t) ??
              switch (t.key) {
                'coffeeRun' => const Duration(hours: 3),
                'sintel' => const Duration(days: 2),
                _ => const Duration(days: 25),
              },
        ),
      // A series' seasons, each with its own status. Cosmos Laundromat: the
      // first on the server, the second in part. Night Shift: the first on
      // the server, the second asked for by nobody, the third waiting.
      if (t.isSeries)
        'seasons': [
          {'seasonNumber': 1, 'status': hd >= 4 ? 5 : hd, 'status4k': 1},
          {
            'seasonNumber': 2,
            'status': t == WorldTitles.nightShift ? 1 : hd,
            'status4k': 1,
          },
        ],
      'downloadStatus': [
        for (final d in c.downloads)
          if (d.title == t &&
              (d.arr == WorldIds.radarr || d.arr == WorldIds.sonarr) &&
              d.state != DownloadState.importBlocked)
            _downloadStatus(c, d),
      ],
      'downloadStatus4k': [
        for (final d in c.downloads)
          if (d.title == t && d.arr == WorldIds.radarr4k) _downloadStatus(c, d),
      ],
      'createdAt': c.ago(const Duration(days: 60)),
      'updatedAt': c.ago(const Duration(hours: 1)),
      // Seerr's own: every request for the title, as `/movie/:id` sends it.
      'requests': [
        for (final row in _requestsOf(c))
          if (row.$2 == t) _requestRecord(c, row),
      ],
    };
  }

  static JsonMap _downloadStatus(ServerContext c, WorldDownload d) => {
    'externalId': d.title == null
        ? null
        : d.title!.isSeries
        ? SonarrFake.idOf(d.title!)
        : RadarrFake.idOf(d.title!, is4k: d.arr == WorldIds.radarr4k),
    'mediaType': d.title?.isSeries == true ? 'tv' : 'movie',
    'size': d.size,
    'sizeLeft': d.sizeLeft,
    'status': switch (d.state) {
      DownloadState.queued => 'queued',
      DownloadState.stuck => 'warning',
      _ => 'downloading',
    },
    if (d.eta != null)
      'timeLeft': '00:${d.eta!.inMinutes.toString().padLeft(2, '0')}:00',
    if (d.eta != null) 'estimatedCompletionTime': c.ahead(d.eta!),
    'title': d.release,
    'downloadId': d.id.toUpperCase(),
  };

  static JsonMap _request(
    ServerContext c,
    (int, WorldTitle, int, int, Duration, bool) row,
  ) => {..._requestRecord(c, row), 'media': _media(c, row.$2)};

  /// A request without its media, as the title's own record lists it.
  static JsonMap _requestRecord(
    ServerContext c,
    (int, WorldTitle, int, int, Duration, bool) row,
  ) {
    final (id, title, by, status, age, is4k) = row;
    final edited = seerrStateOf(c.network, c.server.id).requestEdits[id];
    // A request still waiting names no profile and no folder of its own, as
    // Seerr keeps one asked for without the advanced options: the server's
    // go with it. One that was handed on carries what it went with.
    final waiting = status == 1;
    return {
      'id': id,
      'status': status,
      'type': title.isSeries ? 'tv' : 'movie',
      'is4k': is4k,
      'serverId': edited != null ? edited.serverId : _serverFor(c, title, is4k),
      'profileId': edited != null
          ? edited.profileId
          : waiting
          ? null
          : 1,
      if (edited == null && !waiting)
        'profileName': is4k ? 'Ultra-HD' : 'HD-1080p',
      'rootFolder': edited != null
          ? edited.rootFolder
          : waiting
          ? null
          : is4k
          ? '/mnt/tank/media/films-4k'
          : '/mnt/tank/media/films',
      // Charge carries a tag, which an edit has to send back.
      if (id == 1) 'tags': const [2],
      'createdAt': c.ago(age),
      'updatedAt': c.ago(age),
      'canRemove': true,
      'requestedBy': _user(c, by),
      if (status != 1) 'modifiedBy': _user(c, 1),
      // A waiting request asks for the season nobody has asked for yet.
      'seasons': !title.isSeries
          ? const <Object?>[]
          : status == 1
          ? [
              {'id': 3, 'seasonNumber': 3, 'status': 1},
            ]
          : [
              {'id': 1, 'seasonNumber': 1, 'status': 5},
              {'id': 2, 'seasonNumber': 2, 'status': 3},
              // And the third, not out yet: the requester's calendar dates
              // its episodes.
              if (title == WorldTitles.cosmosLaundromat)
                {'id': 4, 'seasonNumber': 3, 'status': 2},
            ],
    };
  }

  static JsonMap _details(ServerContext c, WorldTitle t) {
    final media = _media(c, t);
    return {
      'id': t.tmdbId,
      if (t.isSeries) 'name': t.title else 'title': t.title,
      'posterPath': ?WorldArtwork.posterPath(t),
      'backdropPath': ?WorldArtwork.backdropPath(t),
      if (t.isSeries)
        'firstAirDate': '${t.year}-05-01'
      else
        'releaseDate': '${t.year}-04-10',
      'overview': 'A Blender open ${t.isSeries ? 'series' : 'movie'}.',
      'voteAverage': 7.4,
      'genres': const [
        {'id': 16, 'name': 'Animation'},
      ],
      'externalIds': {
        if (t.imdbId != null) 'imdbId': t.imdbId,
        if (t.tvdbId != null) 'tvdbId': t.tvdbId,
      },
      if (t.imdbId != null) 'imdbId': t.imdbId,
      if (t.isSeries) 'numberOfSeasons': 3,
      if (t.isSeries) 'status': 'Returning Series',
      // The third season's premiere, as TMDB dates it: a day, no hour.
      if (t == WorldTitles.cosmosLaundromat)
        'nextEpisodeToAir': {
          'name': 'Episode 1',
          'airDate': c.ahead(const Duration(days: 3)).substring(0, 10),
          'seasonNumber': 3,
          'episodeNumber': 1,
        },
      if (t.isSeries)
        'seasons': [
          for (var s = 1; s <= 3; s++)
            {'id': s, 'seasonNumber': s, 'episodeCount': s == 3 ? 8 : 10},
        ],
      if (collectionParts.contains(t))
        'collection': {'id': collectionId, 'name': collectionName},
      'watchProviders': [
        {
          'iso_3166_1': 'IT',
          'flatrate': [
            {'id': 8, 'name': 'Netflix'},
            {'id': 119, 'name': 'Prime Video'},
          ],
          'buy': [
            {'id': 2, 'name': 'Apple TV'},
          ],
        },
        {
          'iso_3166_1': 'US',
          'flatrate': [
            {'id': 15, 'name': 'Hulu'},
          ],
        },
      ],
      if (!t.isSeries) ...{
        'releases': {
          'results': [
            {
              'iso_3166_1': 'IT',
              'release_dates': [
                {'type': 3, 'release_date': '${t.year}-09-26T00:00:00.000Z'},
                // Sprite Fright is out on digital today and on disc in
                // thirteen days, as Radarr dates it.
                if (t == WorldTitles.spriteFright) ...[
                  {
                    'type': 4,
                    'release_date': c.agoToday(const Duration(hours: 6)),
                  },
                  {
                    'type': 5,
                    'release_date': c.ahead(const Duration(days: 13)),
                  },
                ] else
                  {'type': 4, 'release_date': '${t.year}-11-12T00:00:00.000Z'},
              ],
            },
          ],
        },
      },
      'credits': {
        'cast': const <Object?>[],
        'crew': [
          if (personCredits.contains(t))
            {
              'id': personId,
              'name': personName,
              'job': 'Director',
              'department': 'Directing',
            },
        ],
      },
      'relatedVideos': const <Object?>[],
      'mediaInfo': ?media,
    };
  }

  /// What the review sites say of the world's own films, `(critics,
  /// audience, IMDb)`; any other film with an IMDb id gets scores worked out
  /// from its TMDB id, so a title page always reads the same.
  static const _filmScores = <String, (int, int, double)>{
    'sintel': (92, 88, 7.5),
    'metropolis': (98, 95, 8.3),
    'tearsOfSteel': (74, 70, 6.8),
    'spriteFright': (68, 72, 5.9),
  };

  static (int, int, double) _scoresOf(WorldTitle t) =>
      _filmScores[t.key] ??
      (
        55 + t.tmdbId % 41,
        60 + t.tmdbId * 7 % 36,
        double.parse((5.5 + t.tmdbId % 30 / 10).toStringAsFixed(1)),
      );

  /// Seerr's `RTRating` for a film, null when Rotten Tomatoes has none: it
  /// rates the films that have an IMDb id here, which leaves Coffee Run,
  /// Spring and Charge without a score.
  static JsonMap? _tomatoes(WorldTitle t) {
    if (t.imdbId == null) return null;
    final (critics, audience, _) = _scoresOf(t);
    return {
      'title': t.title,
      'url': 'https://www.rottentomatoes.com/m/${t.slug.replaceAll('-', '_')}',
      'criticsRating': critics >= 75
          ? 'Certified Fresh'
          : critics >= 60
          ? 'Fresh'
          : 'Rotten',
      'criticsScore': critics,
      'audienceRating': audience >= 60 ? 'Upright' : 'Spilled',
      'audienceScore': audience,
      'year': t.year,
    };
  }

  /// Seerr's `IMDBRating` for a film, null when it has no IMDb id.
  static JsonMap? _imdb(WorldTitle t) {
    if (t.imdbId == null) return null;
    return {
      'title': t.title,
      'url': 'https://www.imdb.com/title/${t.imdbId}',
      'criticsScore': _scoresOf(t).$3,
      'criticsScoreCount': 1000 + t.tmdbId % 9000,
      'year': t.year,
    };
  }

  static JsonMap _credit(ServerContext c, WorldTitle t) => {
    'id': t.tmdbId,
    'mediaType': t.isSeries ? 'tv' : 'movie',
    if (t.isSeries) 'name': t.title else 'title': t.title,
    'posterPath': ?WorldArtwork.posterPath(t),
    if (!t.isSeries) 'releaseDate': '${t.year}-04-10',
    'job': 'Director',
    'department': 'Directing',
    'voteAverage': 7.4,
    'mediaInfo': ?_media(c, t),
  };

  static JsonMap _page(NetworkRequest r, List<JsonMap> items) {
    final take = int.tryParse(r.query['take'] ?? '') ?? 20;
    final skip = int.tryParse(r.query['skip'] ?? '') ?? 0;
    final start = skip.clamp(0, items.length);
    final end = (start + take).clamp(0, items.length);
    return {
      'pageInfo': {
        'pages': (items.length / take).ceil(),
        'pageSize': take,
        'results': items.length,
        'page': take == 0 ? 1 : skip ~/ take + 1,
      },
      'results': items.sublist(start, end),
    };
  }

  /// A person among the trending titles, as TMDB's `/trending/all` sends one
  /// through Seerr: `mediaType: person`, a name and what she is known for.
  static const JsonMap _trendingPerson = {
    'id': 1234567,
    'mediaType': 'person',
    'name': 'Elena Varga',
    'profilePath': null,
    'adult': false,
    'popularity': 88.2,
    'knownFor': <Object?>[],
  };

  static JsonMap _discoverPage(List<WorldTitle> titles) => {
    'page': 1,
    'totalPages': 1,
    'totalResults': titles.length,
    'results': [
      for (final t in titles)
        {
          'id': t.tmdbId,
          'mediaType': t.isSeries ? 'tv' : 'movie',
          if (t.isSeries) 'name': t.title else 'title': t.title,
          if (!t.isSeries) 'releaseDate': '${t.year}-04-10',
          'voteAverage': 7.4,
          'posterPath': ?WorldArtwork.posterPath(t),
          'backdropPath': ?WorldArtwork.backdropPath(t),
        },
    ],
  };

  /// One server as `GET /settings/radarr|sonarr` sends it: Seerr's
  /// `RadarrSettings` or `SonarrSettings` (`server/lib/settings/index.ts`),
  /// the key in the clear, as the route returns `settings.radarr` whole.
  ///
  /// The address is where Seerr reaches the server: its container under
  /// `withDockerHostnames`, and then `externalUrl` holds the address a
  /// browser opens it at, as an admin of such a stack sets it.
  static JsonMap _knownSettings(SeerrKnownServer s, ServerContext c) {
    final docker = c.profile.dockerHostnames && s.containerUrl != null;
    final uri = s.seenBySeerr(dockerHostnames: docker);
    return {
      'id': s.seerrId,
      'name': s.name,
      'hostname': uri.host,
      'port': uri.port,
      'apiKey': s.apiKey,
      'useSsl': uri.scheme == 'https',
      'baseUrl': '',
      'activeProfileId': s.activeProfileId,
      'activeProfileName': s.activeProfileName,
      'activeDirectory': s.activeDirectory,
      'tags': const <Object?>[],
      'is4k': s.is4k,
      'isDefault': s.isDefault,
      'externalUrl': docker ? s.url : '',
      'syncEnabled': true,
      'preventSearch': false,
      'tagRequests': false,
      'overrideRule': const <Object?>[],
      if (s.service == ServiceKey.radarr) 'minimumAvailability': 'released',
      if (s.service == ServiceKey.sonarr) ...{
        'seriesType': 'standard',
        'animeSeriesType': 'anime',
        'activeAnimeProfileId': s.activeProfileId,
        'enableSeasonFolders': true,
        'monitorNewItems': 'all',
      },
    };
  }

  static JsonMap _knownService(SeerrKnownServer s) => {
    'id': s.seerrId,
    'name': s.name,
    'is4k': s.is4k,
    'isDefault': s.isDefault,
    'activeDirectory': s.activeDirectory,
    'activeProfileId': s.activeProfileId,
    'activeTags': const <Object?>[],
  };

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    final auth = seerrAuthAnswer(r, c) ?? seerrUserSettingsAnswer(r, c);
    if (auth != null) return auth;
    final path = r.path;
    final setup = SeerrSetup.of(c);
    // The gate let nobody through to a route that wants a caller; the
    // public routes do not read it.
    final caller = seerrCallerOf(r, c);
    final everyone = caller?.seesEveryone ?? false;
    if (r.method == 'GET') {
      switch (path) {
        case '/api/v1/status':
          return NetworkReply.json({
            'version': setup.release.version,
            'commitTag': setup.release.commitTag,
            'updateAvailable': false,
            'commitsBehind': 0,
            'restartRequired': false,
          });
        case '/api/v1/settings/public':
          return NetworkReply.json(setup.publicSettings);
        case '/api/v1/request':
          // `request.ts:147-162`: without MANAGE_REQUESTS or REQUEST_VIEW the
          // list filters itself to the caller's own.
          final requestedBy = int.tryParse(r.query['requestedBy'] ?? '');
          if (!everyone &&
              requestedBy != null &&
              requestedBy != caller?.user.id) {
            return seerrError(
              403,
              "You do not have permission to view this user's requests.",
            );
          }
          final by = everyone ? requestedBy : caller?.user.id;
          final rows = [
            for (final row in _requestsOf(c))
              if (by == null || row.$3 == by) _request(c, row),
          ];
          final filter = r.query['filter'];
          int? mediaStatus(JsonMap q) =>
              (q['media'] as JsonMap?)?['status'] as int?;
          // The status of the copy the request asked for: a 4K request
          // reads the title's 4K status, as Seerr's own filter does.
          int? requestedStatus(JsonMap q) =>
              (q['media'] as JsonMap?)?[q['is4k'] == true
                      ? 'status4k'
                      : 'status']
                  as int?;
          final filtered = switch (filter) {
            'pending' => rows.where((q) => q['status'] == 1).toList(),
            'approved' => rows.where((q) => q['status'] == 2).toList(),
            // Seerr's own reading: approved, and the title not yet
            // available (unknown, pending, processing, partly available).
            'processing' =>
              rows
                  .where(
                    (q) =>
                        q['status'] == 2 &&
                        const {null, 1, 2, 3, 4}.contains(requestedStatus(q)),
                  )
                  .toList(),
            'available' => rows.where((q) => mediaStatus(q) == 5).toList(),
            'failed' => rows.where((q) => q['status'] == 4).toList(),
            _ => rows,
          };
          return NetworkReply.json(_page(r, filtered));
        case '/api/v1/request/count':
          final pending = _requestsOf(c).where((q) => q.$4 == 1).length;
          return NetworkReply.json({
            'total': _requestsOf(c).length,
            'movie': _requestsOf(c).where((q) => !q.$2.isSeries).length,
            'tv': _requestsOf(c).where((q) => q.$2.isSeries).length,
            'pending': pending,
            'approved': _requestsOf(c).where((q) => q.$4 == 2).length,
            'declined': _requestsOf(c).where((q) => q.$4 == 3).length,
            'processing': _requestsOf(
              c,
            ).where((q) => _mediaStatusOf(c, q.$2)?.$1 == 3).length,
            'available': _requestsOf(
              c,
            ).where((q) => _mediaStatusOf(c, q.$2)?.$1 == 5).length,
          });
        case '/api/v1/user':
          // `user/index.ts:160-163`: the email only for MANAGE_USERS.
          final full = caller?.has(SeerrPermission.manageUsers) ?? false;
          return NetworkReply.json(
            _page(r, [
              for (final u in setup.users)
                if (full) _user(c, u.id) else _user(c, u.id)..remove('email'),
            ]),
          );
        case '/api/v1/issue':
          return NetworkReply.json(
            _page(r, [
              {
                'id': 1,
                'issueType': 2,
                'status': 1,
                'problemSeason': 0,
                'problemEpisode': 0,
                'createdAt': c.ago(const Duration(days: 3)),
                'updatedAt': c.ago(const Duration(days: 2)),
                'createdBy': _user(c, 2),
                // The issue's media names its title, as the app reads it.
                'media': {
                  ..._media(c, WorldTitles.tearsOfSteel)!,
                  'title': WorldTitles.tearsOfSteel.title,
                },
                'comments': [
                  {
                    'id': 1,
                    'message': 'Audio drifts out of sync after about 8 minutes',
                    'user': _user(c, 2),
                    'createdAt': c.ago(const Duration(days: 3)),
                  },
                  {
                    'id': 2,
                    'message': 'Which device?',
                    'user': _user(c, 1),
                    'createdAt': c.ago(const Duration(days: 2, hours: 5)),
                  },
                  {
                    'id': 3,
                    'message': 'Living room TV',
                    'user': _user(c, 2),
                    'createdAt': c.ago(const Duration(days: 2)),
                  },
                ],
              },
            ]),
          );
        case '/api/v1/issue/count':
          return NetworkReply.json({
            'total': 1,
            'video': 0,
            'audio': 1,
            'subtitles': 0,
            'others': 0,
            'open': 1,
            'closed': 0,
          });
        case '/api/v1/settings/radarr':
          return NetworkReply.json([
            for (final s in _known(c, ServiceKey.radarr)) _knownSettings(s, c),
          ]);
        case '/api/v1/settings/sonarr':
          return NetworkReply.json([
            for (final s in _known(c, ServiceKey.sonarr)) _knownSettings(s, c),
          ]);
        case '/api/v1/service/radarr':
          return NetworkReply.json([
            for (final s in _known(c, ServiceKey.radarr)) _knownService(s),
          ]);
        case '/api/v1/service/sonarr':
          return NetworkReply.json([
            for (final s in _known(c, ServiceKey.sonarr)) _knownService(s),
          ]);
        case '/api/v1/discover/trending':
          // TMDB's trending, which Seerr relays, mixes people in with the
          // titles: one leads the list, as she does when she is in the news.
          final page = _discoverPage([
            for (final t in WorldTitles.all)
              if (!t.isSeries) t,
          ]);
          return NetworkReply.json({
            ...page,
            'results': [_trendingPerson, ...page['results']! as List],
          });
        case '/api/v1/discover/movies':
        case '/api/v1/discover/movies/upcoming':
          return NetworkReply.json(
            _discoverPage([
              for (final t in WorldTitles.all)
                if (!t.isSeries) t,
            ]),
          );
        case '/api/v1/discover/tv':
        case '/api/v1/discover/tv/upcoming':
          return NetworkReply.json(
            _discoverPage([
              for (final t in WorldTitles.all)
                if (t.isSeries) t,
            ]),
          );
        case '/api/v1/search':
          final query = (r.query['query'] ?? '').toLowerCase();
          return NetworkReply.json(
            _discoverPage([
              for (final t in WorldTitles.all)
                if (query.isNotEmpty && t.title.toLowerCase().contains(query))
                  t,
            ]),
          );
        // The rail's own route, as Seerr 3.4.1 answers it: each genre with
        // the backdrops of a few of its titles, which a profile leaves empty
        // because it carries no artwork (see the README). `/genres/{movie,tv}`
        // exists too, but nothing in the app reads it.
        case '/api/v1/discover/genreslider/movie':
        case '/api/v1/discover/genreslider/tv':
          return NetworkReply.json(const [
            {'id': 16, 'name': 'Animation', 'backdrops': <String>[]},
          ]);
      }
      final service = RegExp(
        r'^/api/v1/service/(radarr|sonarr)/(\d+)$',
      ).firstMatch(path);
      if (service != null) {
        final kind = service.group(1)!;
        final id = int.parse(service.group(2)!);
        final known = _known(
          c,
          kind == 'radarr' ? ServiceKey.radarr : ServiceKey.sonarr,
        ).where((s) => s.seerrId == id).firstOrNull;
        if (known == null) {
          return NetworkReply.json({'message': 'Not found'}, status: 404);
        }
        return NetworkReply.json({
          'server': _knownService(known),
          'profiles': [
            for (final profile in known.profiles)
              {'id': profile.id, 'name': profile.name},
          ],
          'rootFolders': [
            for (final (i, folder) in known.rootFolders.indexed)
              {'id': i + 1, 'path': folder.path, 'freeSpace': folder.freeSpace},
          ],
          'tags': const <Object?>[],
        });
      }
      final quota = RegExp(r'^/api/v1/user/(\d+)/quota$').firstMatch(path);
      if (quota != null && caller != null) {
        final id = int.parse(quota.group(1)!);
        // `user/index.ts:804-834`: one's own, or MANAGE_USERS and
        // MANAGE_REQUESTS for anybody's.
        if (id != caller.user.id &&
            !(caller.has(SeerrPermission.manageUsers) &&
                caller.has(SeerrPermission.manageRequests))) {
          return seerrError(
            403,
            "You do not have permission to view this user's request limits.",
          );
        }
        final user = setup.userById(id);
        // Upstream relays TypeORM's own "could not find" sentence here; only
        // the 404 is modelled.
        if (user == null) return seerrError(404, 'User not found.');
        return NetworkReply.json(seerrQuotaOf(user, full: setup.quotaReached));
      }
      final one = RegExp(r'^/api/v1/request/(\d+)$').firstMatch(path);
      if (one != null) {
        final id = int.parse(one.group(1)!);
        final row = _requestsOf(c).where((q) => q.$1 == id).firstOrNull;
        if (row == null) {
          return NetworkReply.json({
            'message': 'Request not found.',
          }, status: 404);
        }
        // `request.ts:434-463`.
        if (!everyone && row.$3 != caller?.user.id) {
          return seerrError(
            403,
            'You do not have permission to view this request.',
          );
        }
        return NetworkReply.json(_request(c, row));
      }
      // A season as TMDB keeps it: Cosmos Laundromat's votes, a few of the
      // second season's from fewer than twenty people, the third not out.
      final season = RegExp(
        r'^/api/v1/tv/(\d+)/season/(\d+)$',
      ).firstMatch(path);
      if (season != null) {
        final number = int.parse(season.group(2)!);
        final votes = switch (number) {
          1 => const [7.2, 7.5, 7.9, 8.1, 7.4, 8.3, 7.0, 7.7, 8.0, 8.6],
          2 => const [8.2, 8.4, 8.1, 7.6, 7.9, 8.9, 7.3, 8.0, 8.5, 8.7],
          _ => const <double>[0, 0, 0, 0, 0, 0, 0, 0],
        };
        return NetworkReply.json({
          'id': number,
          'seasonNumber': number,
          'episodes': [
            for (final (i, vote) in votes.indexed)
              {
                'id': number * 100 + i + 1,
                'seasonNumber': number,
                'episodeNumber': i + 1,
                'name': switch ((number, i + 1)) {
                  (2, 3) => 'The Second Cycle',
                  (2, 6) => 'The Seventh Cycle',
                  _ => 'Episode ${i + 1}',
                },
                // The third season weekly from its premiere, three days on.
                'airDate': number == 3
                    ? c.ahead(Duration(days: 3 + 7 * i)).substring(0, 10)
                    : '2025-0${number + 1}-${(i + 1).toString().padLeft(2, '0')}',
                'overview': number == 2 && i == 2
                    ? 'Franck wakes up in the second life Tachyon sold him.'
                    : '',
                // No still: a picture needs the disk cache tests have not got.
                'voteAverage': vote,
                'voteCount': vote == 0
                    ? 0
                    : number == 2 && const {4, 6, 7, 8}.contains(i)
                    ? 12
                    : number == 2 && i == 5
                    ? 31
                    : 37,
              },
          ],
        });
      }
      // Rotten Tomatoes' word on a series, which TMDB's record lacks.
      if (RegExp(r'^/api/v1/tv/\d+/ratings$').hasMatch(path)) {
        return NetworkReply.json({
          'title': WorldTitles.cosmosLaundromat.title,
          'criticsScore': 88,
          'criticsRating': 'Fresh',
        });
      }
      // Rotten Tomatoes' and IMDb's word on a film, which TMDB's record
      // lacks: `/ratings` is Rotten Tomatoes alone, `/ratingscombined` both.
      final scores = RegExp(
        r'^/api/v1/movie/(\d+)/(ratings|ratingscombined)$',
      ).firstMatch(path);
      if (scores != null) {
        final id = int.parse(scores.group(1)!);
        final film = (c.life == null ? WorldTitles.all : WorldTitles.catalogue)
            .where((t) => t.tmdbId == id && !t.isSeries)
            .firstOrNull;
        if (film == null) {
          return NetworkReply.json({'message': 'Not found'}, status: 404);
        }
        final rt = _tomatoes(film);
        if (scores.group(2) == 'ratings') {
          // Seerr answers 404 for a film Rotten Tomatoes does not rate.
          return rt == null
              ? NetworkReply.json({
                  'message': 'Unable to retrieve movie ratings.',
                }, status: 404)
              : NetworkReply.json(rt);
        }
        return NetworkReply.json({'rt': rt, 'imdb': _imdb(film)});
      }
      final detail = RegExp(r'^/api/v1/(movie|tv)/(\d+)$').firstMatch(path);
      if (detail != null) {
        final id = int.parse(detail.group(2)!);
        // A living world opens every title its search finds.
        final title = (c.life == null ? WorldTitles.all : WorldTitles.catalogue)
            .where(
              (t) => t.tmdbId == id && t.isSeries == (detail.group(1) == 'tv'),
            )
            .firstOrNull;
        if (title == null) {
          return NetworkReply.json({'message': 'Not found'}, status: 404);
        }
        return NetworkReply.json(_details(c, title));
      }
      if (path == '/api/v1/person/$personId') {
        return NetworkReply.json({
          'id': personId,
          'name': personName,
          'knownForDepartment': 'Directing',
          'biography': 'Director of Blender open movies.',
          'placeOfBirth': 'Seattle, Washington, USA',
        });
      }
      if (path == '/api/v1/person/$personId/combined_credits') {
        return NetworkReply.json({
          'id': personId,
          'cast': const <Object?>[],
          'crew': [for (final t in personCredits) _credit(c, t)],
        });
      }
      if (path == '/api/v1/collection/$collectionId') {
        return NetworkReply.json({
          'id': collectionId,
          'name': collectionName,
          'overview': 'The open movies of the Blender Studio.',
          'parts': [
            for (final t in collectionParts)
              {
                'id': t.tmdbId,
                'mediaType': 'movie',
                'title': t.title,
                'releaseDate': '${t.year}-04-10',
                'voteAverage': 7.4,
                'posterPath': ?WorldArtwork.posterPath(t),
                'mediaInfo': ?_media(c, t),
              },
          ],
        });
      }
      final rail = RegExp(
        r'^/api/v1/(movie|tv)/\d+/(recommendations|similar)$',
      ).firstMatch(path);
      // The household watched Tears of Steel: what TMDB recommends after it
      // is the atrium's Because you watched.
      if (rail != null) {
        return NetworkReply.json(
          _discoverPage(
            path ==
                    '/api/v1/movie/${WorldTitles.tearsOfSteel.tmdbId}/recommendations'
                ? const [
                    WorldTitles.sintel,
                    WorldTitles.elephantsDream,
                    WorldTitles.charge,
                  ]
                : const [],
          ),
        );
      }
      if (path.startsWith('/api/v1/discover/')) {
        return NetworkReply.json(_discoverPage(const []));
      }
    }
    // An edit before an approval, as Seerr's route takes it: only a request
    // still waiting, `mediaType` required, and a series with its seasons.
    final edit = RegExp(r'^/api/v1/request/(\d+)$').firstMatch(path);
    if (r.method == 'PUT' && edit != null) {
      final id = int.parse(edit.group(1)!);
      final row = _requestsOf(c).where((q) => q.$1 == id).firstOrNull;
      if (row == null) {
        return NetworkReply.json({
          'message': 'Request not found.',
        }, status: 404);
      }
      // `request.ts:484-494`: one's own, and a series or REQUEST_ADVANCED; or
      // MANAGE_REQUESTS.
      final mine = row.$3 == caller?.user.id;
      final advanced = caller?.has(SeerrPermission.requestAdvanced) ?? false;
      if (!(caller?.has(SeerrPermission.manageRequests) ?? false) &&
          !(mine && (row.$2.isSeries || advanced))) {
        return seerrError(
          403,
          'You do not have permission to modify this request.',
        );
      }
      if (row.$4 != 1 ||
          seerrStateOf(c.network, c.server.id).decidedElsewhere.contains(id)) {
        return NetworkReply.json({
          'message': 'Only pending requests can be modified.',
        }, status: 409);
      }
      final body = r.json;
      if (body is! Map || body['mediaType'] == null) {
        return NetworkReply.json({
          'message': "request/body must have required property 'mediaType'",
        }, status: 400);
      }
      final seasons = body['seasons'];
      if (body['mediaType'] == 'tv' && (seasons is! List || seasons.isEmpty)) {
        return NetworkReply.json({
          'message':
              'Missing seasons. If you want to cancel a series request, use '
              'the DELETE method.',
        }, status: 500);
      }
      // The route writes every field from the body: one left out is
      // written as missing.
      seerrStateOf(c.network, c.server.id).requestEdits[id] = (
        serverId: body['serverId'],
        profileId: body['profileId'],
        rootFolder: body['rootFolder'],
      );
      return NetworkReply.json(_request(c, row));
    }
    if (r.method == 'POST' &&
        RegExp(r'^/api/v1/request/\d+/(approve|decline)$').hasMatch(path)) {
      final id = int.parse(path.split('/')[4]);
      final row = _requestsOf(c).where((q) => q.$1 == id).firstOrNull;
      if (row == null) {
        return NetworkReply.json({'message': 'Not found'}, status: 404);
      }
      // A living world keeps the decision, and an approval goes to the arr.
      final live = _live(c)?.where((q) => q.id == id).firstOrNull;
      if (live != null && live.status == 1) {
        final approve = path.endsWith('/approve');
        live
          ..status = approve ? 2 : 3
          ..changed = true;
        if (approve) _send(c, live);
        return NetworkReply.json(
          _request(c, _requestsOf(c).firstWhere((q) => q.$1 == id)),
        );
      }
      return NetworkReply.json(_request(c, row));
    }
    // A title put on the watchlist: Seerr answers with the item. The world
    // keeps no watchlist.
    if (r.method == 'POST' && path == '/api/v1/watchlist') {
      final body = r.json;
      return NetworkReply.json({
        if (body is Map) ...body.cast<String, Object?>(),
        'ratingKey': '',
      }, status: 201);
    }
    if (r.method == 'POST' && path == '/api/v1/request') {
      // The operator's answer is the world's first row, as it always was:
      // the request sheet's tests read it.
      if (caller == null || caller.byKey) {
        // A living world keeps what the operator asked for: an admin's
        // request is approved as it is made, and goes to the arr.
        final title = c.life == null ? null : _titleAsked(r);
        if (title != null) {
          final body = r.json as Map;
          return NetworkReply.json(
            _request(
              c,
              _keep(
                c,
                title: title,
                requester: WorldSeerrUsers.admin.id,
                approved: true,
                is4k: body['is4k'] == true,
              ),
            ),
            status: 201,
          );
        }
        return NetworkReply.json(
          _request(c, _requestsOf(c).first),
          status: 201,
        );
      }
      return _newRequest(r, c, caller, setup);
    }
    final cancel = RegExp(r'^/api/v1/request/(\d+)$').firstMatch(path);
    if (r.method == 'DELETE' && cancel != null && caller != null) {
      final id = int.parse(cancel.group(1)!);
      final row = _requestsOf(c).where((q) => q.$1 == id).firstOrNull;
      if (row == null) return seerrError(404, 'Request not found.');
      // `request.ts:706-737`: a 401, not a 403, for a request that is not
      // one's own or no longer waits.
      if (!caller.has(SeerrPermission.manageRequests) &&
          (row.$3 != caller.user.id || row.$4 != 1)) {
        return seerrError(
          401,
          'You do not have permission to delete this request.',
        );
      }
      _live(c)?.removeWhere((q) => q.id == id);
      return const NetworkReply(204);
    }
    // `issue.ts:326-372`: past the route's MANAGE_ISSUES or CREATE_ISSUES
    // (`_needOf` in `seerr_sessions.dart`), anybody else's issue wants MANAGE_ISSUES, else a 401.
    // The world has one issue, Anna's.
    final status = RegExp(
      r'^/api/v1/issue/(\d+)/(open|resolved)$',
    ).firstMatch(path);
    if (r.method == 'POST' && status != null) {
      if (status.group(1) != '1') return seerrError(404, 'Issue not found.');
      if (caller != null &&
          !caller.byKey &&
          !caller.has(SeerrPermission.manageIssues) &&
          caller.user.id != WorldSeerrUsers.anna.id) {
        return seerrError(
          401,
          'You do not have permission to modify this issue.',
        );
      }
      return NetworkReply.json({
        'id': 1,
        'status': status.group(2) == 'resolved' ? 2 : 1,
      });
    }
    if (r.method == 'DELETE' && path.startsWith('/api/v1/')) {
      return const NetworkReply(204);
    }
    return null;
  }

  /// The title `POST /api/v1/request` asks for, by its TMDB id and kind,
  /// from everything the world's Seerr can find.
  static WorldTitle? _titleAsked(NetworkRequest r) {
    final body = r.json;
    if (body is! Map) return null;
    final series = body['mediaType'] == 'tv';
    return WorldTitles.catalogue
        .where((t) => t.tmdbId == body['mediaId'] && t.isSeries == series)
        .firstOrNull;
  }

  /// `POST /api/v1/request` by a household member's own account: the
  /// permission and quota checks of `MediaRequest.request`, then a request of
  /// theirs, waiting unless the account is auto-approved.
  static NetworkReply _newRequest(
    NetworkRequest r,
    ServerContext c,
    SeerrCaller caller,
    SeerrSetup setup,
  ) {
    final json = r.json;
    final body = json is Map ? json : const <String, Object?>{};
    final kind = body['mediaType'];
    final is4k = body['is4k'] == true;
    final refusal = seerrRequestRefusal(
      caller,
      kind: kind is String ? kind : null,
      is4k: is4k,
      ignoreQuota: body['ignoreQuota'] == true,
      quotaReached: setup.quotaReached,
    );
    if (refusal != null) return refusal;
    final series = kind == 'tv';
    final title =
        WorldTitles.all
            .where((t) => t.tmdbId == body['mediaId'] && t.isSeries == series)
            .firstOrNull ??
        WorldTitles.all.firstWhere((t) => t.isSeries == series);
    final approved = seerrAutoApproves(caller, movie: !series, is4k: is4k);
    if (c.life != null) {
      return NetworkReply.json(
        _request(
          c,
          _keep(
            c,
            title: _titleAsked(r) ?? title,
            requester: caller.user.id,
            approved: approved,
            is4k: is4k,
          ),
        ),
        status: 201,
      );
    }
    return NetworkReply.json(
      _request(c, (
        100 + c.network.requestsTo(c.server.id).length,
        title,
        caller.user.id,
        approved ? 2 : 1,
        Duration.zero,
        is4k,
      )),
      status: 201,
    );
  }
}

// === Jellyfin ==============================================================

/// Jellyfin with three users; the operator is "this is me".
///
/// [ConnectionBehaviour.readOnly] models a non-admin user's token: the P2+J
/// variant, Anna signing in with her own account: admin reads (other users,
/// devices, tasks, the activity log, the full system info) are refused, and
/// only her own sessions are listed.
/// What the household's players were told by remote control, per server and
/// session: a player that announced media control obeys a Pause, a Resume
/// and a Stop, and the session list says so on its next read.
final _remote = Expando<Map<String, ({bool paused, bool stopped})>>(
  'remote control',
);

final _command = RegExp(r'^/Sessions/([^/]+)/Playing/(Pause|Unpause|Stop)$');

/// Applies a remote-control [path] (already without Emby's `/emby`) sent to
/// [c]'s server.
void _obeyRemote(ServerContext c, String path) {
  final match = _command.firstMatch(path);
  if (match == null) return;
  final states = _remote[c.network] ??= {};
  final key = '${c.server.id}/${match.group(1)}';
  final was = states[key] ?? (paused: false, stopped: false);
  states[key] = switch (match.group(2)) {
    'Pause' => (paused: true, stopped: was.stopped),
    'Unpause' => (paused: false, stopped: was.stopped),
    _ => (paused: was.paused, stopped: true),
  };
}

/// [session] as its player stands after what it was told: paused, or no
/// longer playing anything.
JsonMap _asObeyed(ServerContext c, JsonMap session) {
  final state = _remote[c.network]?['${c.server.id}/${session['Id']}'];
  if (state == null) return session;
  if (state.stopped) {
    return {...session}..remove('NowPlayingItem');
  }
  final playState = session['PlayState'];
  return {
    ...session,
    'PlayState': {
      if (playState is Map) ...playState.cast<String, Object?>(),
      'IsPaused': state.paused,
    },
  };
}

class JellyfinFake extends ServiceFake {
  const JellyfinFake();

  static const operatorId = '0a1b2c3d4e5f60718293a4b5c6d7e8f9';
  static const annaId = '1a1b2c3d4e5f60718293a4b5c6d7e8f9';
  static const lucaId = '2a1b2c3d4e5f60718293a4b5c6d7e8f9';
  static const serverId = '9f2c1b7e4a3d4f0e8b6c5a1d2e3f4a5b';

  @override
  bool isPublic(NetworkRequest request) =>
      request.method == 'GET' &&
      (request.path == '/System/Info/Public' || request.path == '/System/Ping');

  @override
  NetworkReply refuseKey(NetworkRequest request) => const NetworkReply(401);

  @override
  bool isAdminRead(NetworkRequest request) =>
      request.method == 'GET' &&
      (request.path == '/System/Info' ||
          request.path == '/Users' ||
          request.path == '/Devices' ||
          request.path == '/ScheduledTasks' ||
          request.path == '/System/ActivityLog/Entries' ||
          request.path == '/Library/VirtualFolders');

  // Playback reporting and session commands are POSTs a non-admin may send
  // for its own sessions, so only the admin writes count here.
  @override
  bool isWrite(NetworkRequest request) =>
      request.method != 'GET' &&
      (request.path.startsWith('/Library/') ||
          request.path.startsWith('/ScheduledTasks/') ||
          request.path.startsWith('/Items/') &&
              request.path.endsWith('/Refresh'));

  static JsonMap _item(ServerContext c, WorldTitle t, {String? type}) {
    final unverified = c.profile.unverifiedMatches.contains(t.key);
    return {
      'Name': t.title,
      'Id': 'jf-${t.key}',
      'ServerId': serverId,
      'Type': type ?? (t.isSeries ? 'Series' : 'Movie'),
      'ProductionYear': t.year,
      'RunTimeTicks': 7200000000,
      // Case f: the item is there, but under another TMDB id, so the app's
      // own match refuses it.
      'ProviderIds': {
        'Tmdb': unverified ? '${t.tmdbId + 1000000}' : '${t.tmdbId}',
        if (t.imdbId != null && !unverified) 'Imdb': t.imdbId,
        if (t.tvdbId != null) 'Tvdb': '${t.tvdbId}',
      },
      'UserData': {
        'Played': t == WorldTitles.tearsOfSteel,
        if (t == WorldTitles.tearsOfSteel)
          'LastPlayedDate': c.ago(const Duration(days: 1)),
        'PlaybackPositionTicks': 0,
        'IsFavorite': false,
      },
      'ImageTags': const <String, Object?>{},
      'DateCreated': c.ago(const Duration(days: 30)),
      // The picture: Tears of Steel is the household's 4K HDR copy.
      if (!t.isSeries)
        'MediaStreams': [
          if (t == WorldTitles.tearsOfSteel)
            {
              'Type': 'Video',
              'Width': 3840,
              'Height': 1714,
              'VideoRange': 'HDR',
              'VideoRangeType': 'HDR10',
            }
          else
            {
              'Type': 'Video',
              'Width': 1920,
              'Height': 1080,
              'VideoRange': 'SDR',
              'VideoRangeType': 'SDR',
            },
          {'Type': 'Audio', 'Language': 'eng'},
        ],
    };
  }

  static List<WorldTitle> _library() => const [
    WorldTitles.coffeeRun,
    WorldTitles.sintel,
    WorldTitles.tearsOfSteel,
    WorldTitles.elephantsDream,
    WorldTitles.spring,
    WorldTitles.cosmosLaundromat,
  ];

  static JsonMap _user(String id, String name, {required bool admin}) => {
    'Id': id,
    'Name': name,
    'ServerId': serverId,
    'HasPassword': true,
    'Policy': {'IsAdministrator': admin, 'IsDisabled': false},
    'LastActivityDate': '2026-09-29T18:40:00.0000000Z',
  };

  /// Anna's Sintel on the living-room TV, as the session list holds it.
  static JsonMap _sessionOf(ServerContext c) => {
    'Id': 'session-anna-livingroom',
    'UserId': annaId,
    'UserName': WorldPeople.anna,
    'Client': 'Jellyfin Android TV',
    'DeviceName': 'Living room TV',
    'DeviceId': 'living-room-tv',
    'DeviceType': 'TV',
    'IsActive': true,
    'SupportsMediaControl': true,
    'SupportsRemoteControl': true,
    // What a TV client announces: it can be paused, stopped and shown a
    // message, so the room draws all three.
    'SupportedCommands': ['DisplayMessage', 'SetVolume', 'Mute'],
    'LastActivityDate': c.ago(const Duration(minutes: 1)),
    'PlayState': {
      'PositionTicks': 18000000000,
      'IsPaused': false,
      'PlayMethod': 'DirectPlay',
      'CanSeek': true,
    },
    'NowPlayingItem': {
      ..._item(c, WorldTitles.sintel),
      'RunTimeTicks': 40800000000,
    },
  };

  /// The household's devices as `GET /Devices` lists them (`DeviceInfoDto`):
  /// the living-room TV Anna is watching on, the operator's phone and
  /// browser, and Luca's tablet.
  static List<JsonMap> _devices(ServerContext c) {
    JsonMap device(
      String id,
      String name,
      String app,
      String version,
      String userId,
      String user,
      Duration lastSeen,
    ) => {
      'Id': id,
      'Name': name,
      'AppName': app,
      'AppVersion': version,
      'LastUserId': userId,
      'LastUserName': user,
      'DateLastActivity': c.ago(lastSeen),
    };
    return [
      device(
        'living-room-tv',
        'Living room TV',
        'Jellyfin Android TV',
        '0.19.1',
        annaId,
        WorldPeople.anna,
        const Duration(minutes: 1),
      ),
      device(
        'operator-iphone',
        'Operator iPhone',
        'Jellyfin iOS',
        '1.4.2',
        operatorId,
        'Operator',
        const Duration(hours: 3),
      ),
      device(
        'luca-ipad',
        "Luca's iPad",
        'Jellyfin iOS',
        '1.4.2',
        lucaId,
        WorldPeople.luca,
        const Duration(days: 2),
      ),
      device(
        'operator-firefox',
        'Firefox',
        'Jellyfin Web',
        '10.11.11',
        operatorId,
        'Operator',
        const Duration(days: 6),
      ),
    ];
  }

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    if (r.method == 'POST') _obeyRemote(c, r.path);
    if (r.method != 'GET') return const NetworkReply(204);
    final path = r.path;
    switch (path) {
      case '/System/Info/Public':
        return NetworkReply.json({
          ...jsonFixtureMap('jellyfin/system_info_public.json'),
          'LocalAddress': WorldHosts.jellyfin,
          'ServerName': 'nas',
        });
      case '/System/Info':
        return NetworkReply.json({
          ...jsonFixtureMap('jellyfin/system_info_public.json'),
          'LocalAddress': WorldHosts.jellyfin,
          'ServerName': 'nas',
          'HasPendingRestart': false,
          'HasUpdateAvailable': false,
        });
      case '/System/Ping':
        return NetworkReply.text('Jellyfin Server');
      case '/Users':
        return NetworkReply.json([
          _user(operatorId, 'Operator', admin: true),
          _user(annaId, WorldPeople.anna, admin: false),
          _user(lucaId, WorldPeople.luca, admin: false),
        ]);
      case '/Users/Me':
        return NetworkReply.json(
          c.behaviour == ConnectionBehaviour.readOnly
              ? _user(annaId, WorldPeople.anna, admin: false)
              : _user(operatorId, 'Operator', admin: true),
        );
      case '/Sessions':
        return NetworkReply.json([_asObeyed(c, _sessionOf(c))]);
      case '/Library/VirtualFolders':
        return NetworkReply.json([
          for (final (name, type) in const [
            ('Films', 'movies'),
            ('Films 4K', 'movies'),
            ('Series', 'tvshows'),
            ('Music', 'music'),
          ])
            {
              'Name': name,
              'CollectionType': type,
              'ItemId': 'lib-${name.toLowerCase().replaceAll(' ', '-')}',
              'Locations': ['/mnt/tank/media/${name.toLowerCase()}'],
            },
        ]);
      case '/Items/Counts':
        return NetworkReply.json({
          'MovieCount': 461,
          'SeriesCount': 86,
          'EpisodeCount': 2914,
          'AlbumCount': 1240,
          'SongCount': 14000,
        });
      case '/ScheduledTasks':
        return NetworkReply.json([
          {
            'Name': 'Scan media library',
            'State': 'Running',
            'CurrentProgressPercentage': 42.0,
            'Id': 'task-scan',
            'Category': 'Library',
            'Key': 'RefreshLibrary',
            // The run before this one, twelve hours back: the task's default
            // trigger is every twelve hours.
            'LastExecutionResult': {
              'Status': 'Completed',
              'StartTimeUtc': c.ago(const Duration(hours: 12, minutes: 6)),
              'EndTimeUtc': c.ago(const Duration(hours: 12, minutes: 2)),
              'Name': 'Scan media library',
              'Key': 'RefreshLibrary',
              'Id': 'task-scan-last',
            },
          },
        ]);
      case '/System/ActivityLog/Entries':
        return NetworkReply.json({
          'Items': [
            {
              'Id': 1,
              'Name': 'Anna started Sintel on Living room TV',
              'Type': 'VideoPlayback',
              'Date': c.ago(const Duration(minutes: 38)),
              'Severity': 'Information',
            },
            {
              'Id': 2,
              'Name': 'Coffee Run added to Films',
              'Type': 'ItemAdded',
              'Date': c.ago(const Duration(hours: 2, minutes: 13)),
              'Severity': 'Information',
            },
          ],
          'TotalRecordCount': 2,
        });
      case '/Devices':
        return NetworkReply.json({
          'Items': _devices(c),
          'TotalRecordCount': _devices(c).length,
        });
      case '/Items':
      case '/Search/Hints':
        final ids =
            r.query['AnyProviderIdEquals'] ?? r.query['anyProviderIdEquals'];
        final term = (r.query['searchTerm'] ?? r.query['SearchTerm'] ?? '')
            .toLowerCase();
        final items = [
          for (final t in _library())
            if (_wanted(t, ids, term)) _item(c, t),
        ];
        return NetworkReply.json({
          'Items': items,
          'TotalRecordCount': items.length,
          'StartIndex': 0,
        });
      case '/Shows/NextUp':
        return NetworkReply.json({
          'Items': const <Object?>[],
          'TotalRecordCount': 0,
        });
    }
    // A series' episodes, with the household viewer's watch state: Cosmos
    // Laundromat's first season and the three of the second on the server,
    // two of them watched and the third part-way.
    final episodes = RegExp(
      r'^/Shows/jf-([A-Za-z0-9]+)/Episodes$',
    ).firstMatch(path);
    if (episodes != null) {
      final cosmos = episodes.group(1) == WorldTitles.cosmosLaundromat.key;
      JsonMap episode(int season, int number, {double played = 1}) => {
        ..._item(c, WorldTitles.cosmosLaundromat, type: 'Episode'),
        'Id': 'jf-cosmos-s${season}e$number',
        'Name': season == 2 && number == 3
            ? 'The Second Cycle'
            : 'Episode $number',
        'SeriesName': WorldTitles.cosmosLaundromat.title,
        'SeriesId': 'jf-cosmosLaundromat',
        'ParentIndexNumber': season,
        'IndexNumber': number,
        'RunTimeTicks': 12000000000,
        'UserData': {
          'Played': played >= 1,
          'PlaybackPositionTicks': played > 0 && played < 1
              ? (12000000000 * played).round()
              : 0,
          if (played > 0 && played < 1) 'PlayedPercentage': played * 100,
        },
      };
      final items = cosmos
          ? [
              for (var e = 1; e <= 10; e++) episode(1, e),
              episode(2, 1),
              episode(2, 2),
              episode(2, 3, played: 0.75),
            ]
          : const <JsonMap>[];
      return NetworkReply.json({
        'Items': items,
        'TotalRecordCount': items.length,
      });
    }
    if (RegExp(r'^/Users/[^/]+/Items/Resume$').hasMatch(path) ||
        path == '/UserItems/Resume') {
      return NetworkReply.json({
        'Items': [
          {
            ..._item(c, WorldTitles.cosmosLaundromat, type: 'Episode'),
            'Id': 'jf-cosmos-s02e03',
            'Name': 'The Second Cycle',
            'SeriesName': WorldTitles.cosmosLaundromat.title,
            'SeriesId': 'jf-cosmosLaundromat',
            'ParentIndexNumber': 2,
            'IndexNumber': 3,
            'RunTimeTicks': 12000000000,
            'UserData': {
              'Played': false,
              'PlaybackPositionTicks': 9000000000,
              'PlayedPercentage': 75.0,
            },
          },
        ],
        'TotalRecordCount': 1,
      });
    }
    if (RegExp(r'^/Users/[^/]+/Items/Latest$').hasMatch(path) ||
        path == '/Items/Latest') {
      return NetworkReply.json([_item(c, WorldTitles.coffeeRun)]);
    }
    final one = RegExp(
      r'^/(?:Users/[^/]+/)?Items/jf-([A-Za-z0-9]+)$',
    ).firstMatch(path);
    if (one != null) {
      final title = WorldTitles.all
          .where((t) => t.key == one.group(1))
          .firstOrNull;
      if (title != null) return NetworkReply.json(_item(c, title));
    }
    return null;
  }

  static bool _wanted(WorldTitle t, String? ids, String term) {
    if (term.isNotEmpty) return t.title.toLowerCase().contains(term);
    if (ids == null || ids.isEmpty) return true;
    // Jellyfin matches any of the listed provider ids; the fake answers with
    // the item whatever id it holds, so the app's own check decides, which
    // is what case f needs.
    return ids.contains('${t.tmdbId}') ||
        (t.imdbId != null && ids.contains(t.imdbId!)) ||
        (t.tvdbId != null && ids.contains('${t.tvdbId}'));
  }
}

// === Emby ==================================================================

/// Emby, the same household as [JellyfinFake] on another server: the same
/// titles and the same people, and Emby's own routes, ids and shapes.
///
/// Built on the Jellyfin fake's data (`_item`, `_user`, `_session`) and not on
/// its routes, because the two servers part exactly there: everything sits
/// under `/emby`, the user list is `/Users/Query`, the libraries
/// `/Library/VirtualFolders/Query`, a user's resume row
/// `/Users/{id}/Items/Resume`, one item `/Users/{id}/Items/{id}` (or
/// `/Items?Ids=`), item ids are short numbers, and there is no `/Users/Me`.
/// The public answer carries no `ProductName` and a `LocalAddresses` list, as
/// a real 4.10 does (`test/fixtures/emby/`).
///
/// [ConnectionBehaviour.readOnly] models a household member's token: it is
/// refused the user list, the devices, the tasks and the activity log, and
/// still reads the libraries, the server's info and the sessions, as
/// measured.
class EmbyFake extends ServiceFake {
  const EmbyFake();

  static const operatorId = 'e0a1b2c3d4e5f60718293a4b5c6d7e8f';
  static const annaId = 'e1a1b2c3d4e5f60718293a4b5c6d7e8f';
  static const lucaId = 'e2a1b2c3d4e5f60718293a4b5c6d7e8f';
  static const serverId = 'b7e4c1a9d2f84e60a5b3c8d1e2f3a4b5';

  static const _prefix = '/emby';

  /// [path] without the `/emby` the API sits under. The root answers the same
  /// routes (measured on 4.10.2), which is what lets a Jellyfin's address be
  /// found to be an Emby's: a client that does not know the prefix still
  /// reaches it.
  static String _bare(String path) =>
      path.startsWith('$_prefix/') ? path.substring(_prefix.length) : path;

  @override
  bool isPublic(NetworkRequest request) =>
      request.method == 'GET' &&
      (_bare(request.path) == '/System/Info/Public' ||
          _bare(request.path) == '/System/Ping');

  @override
  NetworkReply refuseKey(NetworkRequest request) => const NetworkReply(401);

  @override
  bool isAdminRead(NetworkRequest request) {
    final path = _bare(request.path);
    return request.method == 'GET' &&
        (path == '/Users/Query' ||
            path == '/Users' ||
            path == '/Devices' ||
            path == '/ScheduledTasks' ||
            path == '/System/ActivityLog/Entries');
  }

  @override
  bool isWrite(NetworkRequest request) {
    final path = _bare(request.path);
    return request.method != 'GET' &&
        (path.startsWith('/Library/') ||
            path.startsWith('/ScheduledTasks/') ||
            path.startsWith('/Items/') && path.endsWith('/Refresh'));
  }

  /// The id Emby gives [t]: a number, as every Emby item has.
  static String _id(WorldTitle t) => '${100 + WorldTitles.all.indexOf(t)}';

  static JsonMap _item(ServerContext c, WorldTitle t, {String? type}) => {
    ...JellyfinFake._item(c, t, type: type),
    'Id': _id(t),
    'ServerId': serverId,
  };

  static JsonMap _user(String id, String name, {required bool admin}) => {
    ...JellyfinFake._user(id, name, admin: admin),
    'ServerId': serverId,
  };

  /// How many episodes each of Cosmos Laundromat's two seasons holds on this
  /// server: the whole first season, and three of the second.
  static const _episodesOfSeason = {1: 10, 2: 3};

  /// The id of one season, a number like every Emby id.
  static String _seasonId(int season) => '${300 + season}';

  /// One season of Cosmos Laundromat, as `/Shows/{id}/Seasons` lists it.
  static JsonMap _season(ServerContext c, int season) => {
    ..._item(c, WorldTitles.cosmosLaundromat, type: 'Season'),
    'Id': _seasonId(season),
    'Name': 'Season $season',
    'SeriesName': WorldTitles.cosmosLaundromat.title,
    'SeriesId': _id(WorldTitles.cosmosLaundromat),
    'IndexNumber': season,
    'ChildCount': _episodesOfSeason[season],
    'RunTimeTicks': null,
    'UserData': {
      'Played': false,
      'PlaybackPositionTicks': 0,
      'UnplayedItemCount': season == 2 ? 1 : 0,
    },
  };

  /// Anna's Sintel on the living-room TV, and the API key's own row, which
  /// Emby lists as a session with no user and nothing playing.
  static List<JsonMap> _sessions(ServerContext c) => [
    {
      ...JellyfinFake._sessionOf(c),
      'Id': 'emby-session-anna-livingroom',
      'UserId': annaId,
      'Client': 'Emby for Android TV',
      'NowPlayingItem': {
        ..._item(c, WorldTitles.sintel),
        'RunTimeTicks': 40800000000,
      },
    },
    {
      'Id': 'emby-session-api-key',
      'Client': 'Cupola',
      'DeviceName': 'nas',
      'DeviceId': serverId,
      'LastActivityDate': c.ago(const Duration(seconds: 20)),
      'PlayState': {'IsPaused': false},
    },
  ];

  static List<JsonMap> _devices(ServerContext c) {
    JsonMap device(
      String id,
      String name,
      String app,
      String version,
      String userId,
      String user,
      Duration lastSeen,
    ) => {
      'Id': id,
      'Name': name,
      'AppName': app,
      'AppVersion': version,
      'LastUserId': userId,
      'LastUserName': user,
      'DateLastActivity': c.ago(lastSeen),
    };
    return [
      device(
        '3',
        'Living room TV',
        'Emby for Android TV',
        '3.4.12',
        annaId,
        WorldPeople.anna,
        const Duration(minutes: 1),
      ),
      device(
        '2',
        "Luca's iPad",
        'Emby for iOS',
        '2.2.8',
        lucaId,
        WorldPeople.luca,
        const Duration(days: 2),
      ),
      device(
        '1',
        'Firefox',
        'Emby Web',
        '4.10.2.0',
        operatorId,
        'Operator',
        const Duration(days: 6),
      ),
    ];
  }

  /// The library as `GET /Library/VirtualFolders/Query` lists it.
  static List<JsonMap> _folders() => [
    for (final (index, (name, type)) in const [
      ('Movies', 'movies'),
      ('Series', 'tvshows'),
      ('Music', 'music'),
    ].indexed)
      {
        'Name': name,
        'CollectionType': type,
        'ItemId': '${3 + index}',
        'Id': '${3 + index}',
        'Locations': ['/mnt/tank/media/${name.toLowerCase()}'],
      },
  ];

  static JsonMap _page(List<JsonMap> items) => {
    'Items': items,
    'TotalRecordCount': items.length,
  };

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    final path = _bare(r.path);
    if (r.method == 'POST') _obeyRemote(c, path);
    if (r.method != 'GET') return const NetworkReply(204);
    switch (path) {
      case '/System/Info/Public':
        return NetworkReply.json({
          ...jsonFixtureMap('emby/system_info_public.json'),
          'ServerName': 'tower',
          'Id': serverId,
        });
      case '/System/Info':
        return NetworkReply.json({
          ...jsonFixtureMap('emby/system_info.json'),
          'ServerName': 'tower',
          'Id': serverId,
          'HasPendingRestart': false,
          'HasUpdateAvailable': false,
        });
      case '/System/Ping':
        return NetworkReply.text('Emby Server');
      case '/Users/Query':
        return NetworkReply.json(
          _page([
            _user(operatorId, 'Operator', admin: true),
            _user(annaId, WorldPeople.anna, admin: false),
            _user(lucaId, WorldPeople.luca, admin: false),
          ]),
        );
      case '/Sessions':
        return NetworkReply.json([
          for (final session in _sessions(c)) _asObeyed(c, session),
        ]);
      case '/Library/VirtualFolders/Query':
        return NetworkReply.json(_page(_folders()));
      case '/Devices':
        return NetworkReply.json(_page(_devices(c)));
      case '/ScheduledTasks':
      case '/System/ActivityLog/Entries':
      case '/Items/Counts':
        // Nothing Emby-specific in them: the Jellyfin fake's own answer.
        return const JellyfinFake().answer(
          NetworkRequest(
            method: r.method,
            uri: r.uri.replace(path: path),
            headers: r.headers,
            body: r.body,
            server: r.server,
          ),
          c,
        );
      case '/Items':
        final ids =
            r.query['AnyProviderIdEquals'] ?? r.query['anyProviderIdEquals'];
        final term = (r.query['searchTerm'] ?? r.query['SearchTerm'] ?? '')
            .toLowerCase();
        final asked = (r.query['ids'] ?? r.query['Ids'] ?? '').split(',');
        // A library's page asks for its own kind: Movie in a movie library,
        // Series in a TV one.
        final types =
            (r.query['includeItemTypes'] ?? r.query['IncludeItemTypes'] ?? '')
                .split(',')
                .where((type) => type.isNotEmpty)
                .toSet();
        bool ofType(WorldTitle t) =>
            types.isEmpty || types.contains(t.isSeries ? 'Series' : 'Movie');
        return NetworkReply.json(
          _page([
            for (final t in JellyfinFake._library())
              if ((asked.first.isNotEmpty
                      ? asked.contains(_id(t))
                      : JellyfinFake._wanted(t, ids, term)) &&
                  ofType(t))
                _item(c, t),
          ]),
        );
      case '/Shows/NextUp':
        return NetworkReply.json(_page(const []));
    }
    // A series' episodes, with the viewer's watch state: Cosmos Laundromat's
    // first season and the three of the second on the server, two of them
    // watched and the third part-way, as the Jellyfin fake has them.
    final seasons = RegExp(r'^/Shows/(\d+)/Seasons$').firstMatch(path);
    if (seasons != null) {
      final cosmos = seasons.group(1) == _id(WorldTitles.cosmosLaundromat);
      return NetworkReply.json(
        _page(
          cosmos
              ? [for (final n in _episodesOfSeason.keys) _season(c, n)]
              : const [],
        ),
      );
    }
    final episodes = RegExp(r'^/Shows/(\d+)/Episodes$').firstMatch(path);
    if (episodes != null) {
      final cosmos = episodes.group(1) == _id(WorldTitles.cosmosLaundromat);
      JsonMap episode(int season, int number, {double played = 1}) => {
        ..._item(c, WorldTitles.cosmosLaundromat, type: 'Episode'),
        'Id': '${200 + season * 20 + number}',
        'Name': season == 2 && number == 3
            ? 'The Second Cycle'
            : 'Episode $number',
        'SeriesName': WorldTitles.cosmosLaundromat.title,
        'SeriesId': _id(WorldTitles.cosmosLaundromat),
        'ParentIndexNumber': season,
        'IndexNumber': number,
        'RunTimeTicks': 12000000000,
        'UserData': {
          'Played': played >= 1,
          'PlaybackPositionTicks': played > 0 && played < 1
              ? (12000000000 * played).round()
              : 0,
          if (played > 0 && played < 1) 'PlayedPercentage': played * 100,
        },
      };
      // A season's own page asks for its episodes by `seasonId`.
      final wanted = r.query['seasonId'] ?? r.query['SeasonId'];
      return NetworkReply.json(
        _page(
          cosmos
              ? [
                  for (var e = 1; e <= 10; e++) episode(1, e),
                  episode(2, 1),
                  episode(2, 2),
                  episode(2, 3, played: 0.75),
                ].where((row) {
                  if (wanted == null || wanted.isEmpty) return true;
                  return _seasonId(row['ParentIndexNumber']! as int) == wanted;
                }).toList()
              : const <JsonMap>[],
        ),
      );
    }
    if (RegExp(r'^/Users/[^/]+/Items/Resume$').hasMatch(path)) {
      return NetworkReply.json(
        _page([
          {
            ..._item(c, WorldTitles.cosmosLaundromat, type: 'Episode'),
            'Id': '${200 + 2 * 20 + 3}',
            'Name': 'The Second Cycle',
            'SeriesName': WorldTitles.cosmosLaundromat.title,
            'SeriesId': _id(WorldTitles.cosmosLaundromat),
            'ParentIndexNumber': 2,
            'IndexNumber': 3,
            'RunTimeTicks': 12000000000,
            'UserData': {
              'Played': false,
              'PlaybackPositionTicks': 9000000000,
              'PlayedPercentage': 75.0,
            },
          },
        ]),
      );
    }
    final one = RegExp(r'^/Users/[^/]+/Items/(\d+)$').firstMatch(path);
    if (one != null) {
      final title = WorldTitles.all
          .where((t) => _id(t) == one.group(1))
          .firstOrNull;
      if (title != null) return NetworkReply.json(_item(c, title));
      for (final n in _episodesOfSeason.keys) {
        if (_seasonId(n) == one.group(1)) {
          return NetworkReply.json(_season(c, n));
        }
      }
    }
    final user = RegExp(r'^/Users/([^/]+)$').firstMatch(path);
    if (user != null) {
      return switch (user.group(1)) {
        operatorId => NetworkReply.json(
          _user(operatorId, 'Operator', admin: true),
        ),
        annaId => NetworkReply.json(
          _user(annaId, WorldPeople.anna, admin: false),
        ),
        lucaId => NetworkReply.json(
          _user(lucaId, WorldPeople.luca, admin: false),
        ),
        _ => null,
      };
    }
    return null;
  }
}

// === Plex ==================================================================

/// Plex, owner token by default.
///
/// [ConnectionBehaviour.readOnly] models a shared, non-owner token (P6):
/// `/status/sessions` (what Stop needs) is refused, the library reads.
class PlexFake extends ServiceFake {
  const PlexFake();

  @override
  bool isPublic(NetworkRequest request) =>
      request.method == 'GET' && request.path == '/identity';

  @override
  NetworkReply refuseKey(NetworkRequest request) => NetworkReply.text(
    '<html><head><title>Unauthorized</title></head></html>',
    status: 401,
  );

  @override
  bool isAdminRead(NetworkRequest request) =>
      request.method == 'GET' &&
      (request.path == '/status/sessions' ||
          request.path == '/statistics/bandwidth');

  // A shared user's token is refused the owner's routes the way a bad token
  // is refused everything: 401, Plex's only word for it.
  @override
  NetworkReply refuseWrite(NetworkRequest request) => refuseKey(request);

  static JsonMap _metadata(ServerContext c, WorldTitle t, int key) {
    final unverified = c.profile.unverifiedMatches.contains(t.key);
    return {
      'ratingKey': '$key',
      'key': '/library/metadata/$key',
      'guid': 'plex://${t.isSeries ? 'show' : 'movie'}/${t.key}',
      'type': t.isSeries ? 'show' : 'movie',
      'title': t.title,
      'year': t.year,
      'addedAt':
          c.now.subtract(const Duration(days: 30)).millisecondsSinceEpoch ~/
          1000,
      // The household watched Tears of Steel on Plex too, a day before
      // Jellyfin.
      if (t == WorldTitles.tearsOfSteel)
        'lastViewedAt':
            c.now.subtract(const Duration(days: 2)).millisecondsSinceEpoch ~/
            1000,
      'Guid': [
        {'id': 'tmdb://${unverified ? t.tmdbId + 1000000 : t.tmdbId}'},
        if (t.imdbId != null && !unverified) {'id': 'imdb://${t.imdbId}'},
        if (t.tvdbId != null) {'id': 'tvdb://${t.tvdbId}'},
      ],
    };
  }

  static const _library = [
    WorldTitles.coffeeRun,
    WorldTitles.sintel,
    WorldTitles.tearsOfSteel,
    WorldTitles.elephantsDream,
    WorldTitles.spring,
  ];

  static const _machineId = '9c8b7a6d5e4f3a2b1c0d9e8f7a6b5c4d3e2f1a0b';

  /// Plex's timestamps: whole seconds since the epoch, [age] before now.
  static int _epoch(ServerContext c, Duration age) =>
      c.now.subtract(age).millisecondsSinceEpoch ~/ 1000;

  /// The sections as recorded, scanned when a household's server scans: the
  /// films this morning, the series a couple of hours ago, the music last
  /// night. The photos were never scanned and say nothing.
  static JsonMap _sections(ServerContext c) {
    final json = jsonFixtureMap('plex/library_sections.json');
    final scanned = <String, Duration>{
      '1': const Duration(hours: 5),
      '2': const Duration(hours: 2),
      '3': const Duration(hours: 20),
    };
    final container = json['MediaContainer'] as Map<String, dynamic>;
    for (final section in (container['Directory'] as List).cast<JsonMap>()) {
      final age = scanned[section['key']];
      if (age != null) section['scannedAt'] = _epoch(c, age);
    }
    return json;
  }

  /// The episode the owner stopped five minutes from the end of: Jellyfin's
  /// Continue watching holds it too, at three quarters of twenty minutes.
  static JsonMap _partWatched(ServerContext c) => {
    'ratingKey': '203',
    'key': '/library/metadata/203',
    'guid': 'plex://episode/cosmosLaundromat-s02e03',
    'type': 'episode',
    'title': 'The Second Cycle',
    'summary': 'Franck wakes up in the second life Tachyon sold him.',
    'grandparentRatingKey': '200',
    'grandparentKey': '/library/metadata/200',
    'grandparentGuid': 'plex://show/cosmosLaundromat',
    'grandparentTitle': WorldTitles.cosmosLaundromat.title,
    'parentRatingKey': '202',
    'parentKey': '/library/metadata/202',
    'parentTitle': 'Season 2',
    'parentIndex': 2,
    'index': 3,
    'year': WorldTitles.cosmosLaundromat.year,
    'duration': 1200000,
    'viewOffset': 900000,
    'lastViewedAt': _epoch(c, const Duration(hours: 1)),
    'addedAt': _epoch(c, const Duration(days: 25)),
    'librarySectionID': 2,
    'librarySectionKey': '/library/sections/2',
    'librarySectionTitle': 'TV Shows',
    'source': 'server://$_machineId/com.plexapp.plugins.library',
    'Guid': [
      {'id': 'tvdb://${WorldTitles.cosmosLaundromat.tvdbId}'},
    ],
  };

  /// What is playing on the server: Luca's Elephants Dream on his iPad.
  static JsonMap _session(ServerContext c) => {
    ..._metadata(c, WorldTitles.elephantsDream, 103),
    'sessionKey': '12',
    'duration': 660000,
    'viewOffset': 240000,
    'librarySectionID': 1,
    'librarySectionKey': '/library/sections/1',
    'librarySectionTitle': 'Movies',
    'User': {'id': '2', 'title': WorldPeople.luca},
    'Player': {
      'address': '192.168.1.58',
      'device': 'iPad',
      'machineIdentifier': 'luca-ipad',
      'model': 'iPad13,4',
      'platform': 'iOS',
      'platformVersion': '18.6',
      'product': 'Plex for iOS',
      'profile': 'iOS',
      'state': 'playing',
      'title': "Luca's iPad",
      'version': '9.35.0',
      'local': true,
      'relayed': false,
      'secure': true,
      'userID': 2,
    },
    'Session': {
      'id': 'plex-session-luca',
      'bandwidth': 8000,
      'location': 'lan',
    },
  };

  /// The devices that signed in to the server, as `/devices` lists them.
  static List<JsonMap> _devices(ServerContext c) => [
    for (final (id, name, product, platform, seen) in [
      (
        1,
        'Living room TV',
        'Plex for Android (TV)',
        'Android',
        const Duration(days: 1),
      ),
      (2, 'Operator iPhone', 'Plex for iOS', 'iOS', const Duration(hours: 4)),
      (3, "Luca's iPad", 'Plex for iOS', 'iOS', const Duration(minutes: 3)),
    ])
      {
        'id': id,
        'name': name,
        'product': product,
        'platform': platform,
        'clientIdentifier': 'plex-device-$id',
        'provides': 'client,player,pubsub-player',
        'createdAt': _epoch(c, Duration(days: 300 - id * 40)),
        'lastSeenAt': _epoch(c, seen),
      },
  ];

  /// The household's one playlist: three of the films, for a film night.
  static List<JsonMap> _playlists(ServerContext c) => [
    {
      'ratingKey': '900',
      'key': '/playlists/900/items',
      'guid': 'com.plexapp.agents.none://film-night',
      'type': 'playlist',
      'title': 'Film night',
      'playlistType': 'video',
      'smart': false,
      'leafCount': 3,
      'duration': 2282000,
      'addedAt': _epoch(c, const Duration(days: 12)),
      'updatedAt': _epoch(c, const Duration(days: 4)),
    },
  ];

  static JsonMap _continueWatching(ServerContext c) => {
    'MediaContainer': {
      'size': 1,
      'Hub': [
        {
          'hubIdentifier': 'home.continue',
          'hubKey': '/hubs/continueWatching/items',
          'key': '/hubs/continueWatching/items',
          'more': false,
          'size': 1,
          'style': 'hero',
          'title': 'Continue Watching',
          'type': 'mixed',
          'Metadata': [_partWatched(c)],
        },
      ],
    },
  };

  /// What Plex's matcher (the dialog of Fix Match) answers for an external
  /// id, `tmdb-603`, asked through an item of a section whose agent is
  /// `tv.plex.agents.movie` or `.series`: the title it knows, under Plex's
  /// own guid, the one its items carry.
  static JsonMap _matches(NetworkRequest r) {
    final series = (r.query['agent'] ?? '').endsWith('.series');
    final ask = RegExp(
      r'^(tmdb|tvdb|imdb)-(.+)$',
    ).firstMatch(r.query['title'] ?? '');
    final found = ask == null
        ? null
        : WorldTitles.catalogue.where((t) {
            if (t.isSeries != series) return false;
            return switch (ask.group(1)) {
              'tmdb' => '${t.tmdbId}' == ask.group(2),
              'tvdb' => t.tvdbId != null && '${t.tvdbId}' == ask.group(2),
              _ => t.imdbId == ask.group(2),
            };
          }).firstOrNull;
    return {
      'MediaContainer': {
        'size': found == null ? 0 : 1,
        'identifier': 'com.plexapp.plugins.library',
        if (found != null)
          'SearchResult': [
            {
              'guid': 'plex://${series ? 'show' : 'movie'}/${found.key}',
              'name': found.title,
              'year': found.year,
              'score': 100,
              'lifespanEnded': false,
            },
          ],
      },
    };
  }

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    if (r.method != 'GET') return const NetworkReply(200);
    switch (r.path) {
      case '/identity':
        return NetworkReply.json(jsonFixtureMap('plex/identity.json'));
      case '/':
        return NetworkReply.json(jsonFixtureMap('plex/capabilities.json'));
      case '/status/sessions':
        return NetworkReply.json({
          'MediaContainer': {
            'size': 1,
            'Metadata': [_session(c)],
          },
        });
      case '/library/sections':
        return NetworkReply.json(_sections(c));
      case '/devices':
        return NetworkReply.json({
          'MediaContainer': {'size': _devices(c).length, 'Device': _devices(c)},
        });
      case '/playlists':
        return NetworkReply.json({
          'MediaContainer': {
            'size': _playlists(c).length,
            'Metadata': _playlists(c),
          },
        });
      case '/hubs/continueWatching':
      case '/hubs/home/continueWatching':
        return NetworkReply.json(_continueWatching(c));
      case '/library/onDeck':
        return NetworkReply.json({
          'MediaContainer': {
            'size': 1,
            'Metadata': [_partWatched(c)],
          },
        });
      case '/library/recentlyAdded':
        // The library again, newest first, as the server's own shelf lists
        // what its scans brought in.
        final added = [
          for (final (i, t) in _library.indexed) _metadata(c, t, 100 + i),
        ]..sort((a, b) => (b['addedAt'] as int).compareTo(a['addedAt'] as int));
        return NetworkReply.json({
          'MediaContainer': {'size': added.length, 'Metadata': added},
        });
      case '/hubs/search':
      case '/library/all':
        // Plex ignores provider filters (P6's f): it answers the whole
        // library and leaves the match to the client.
        return NetworkReply.json({
          'MediaContainer': {
            'size': _library.length,
            'Metadata': [
              for (final (i, t) in _library.indexed) _metadata(c, t, 100 + i),
            ],
          },
        });
    }
    if (RegExp(r'^/library/metadata/[^/]+/matches$').hasMatch(r.path)) {
      return NetworkReply.json(_matches(r));
    }
    // One item by its key: a film of the library, or the episode on deck.
    final item = RegExp(r'^/library/metadata/(\d+)$').firstMatch(r.path);
    if (item != null) {
      final key = int.parse(item.group(1)!);
      final metadata = key == 203
          ? _partWatched(c)
          : key >= 100 && key < 100 + _library.length
          ? _metadata(c, _library[key - 100], key)
          : null;
      return metadata == null
          ? NetworkReply.json({
              'MediaContainer': {'size': 0},
            }, status: 404)
          : NetworkReply.json({
              'MediaContainer': {
                'size': 1,
                'Metadata': [metadata],
              },
            });
    }
    if (RegExp(r'^/library/sections/\d+/all$').hasMatch(r.path)) {
      return NetworkReply.json({
        'MediaContainer': {
          'size': _library.length,
          'totalSize': _library.length,
          'offset': 0,
          'Metadata': [
            for (final (i, t) in _library.indexed) _metadata(c, t, 100 + i),
          ],
        },
      });
    }
    return null;
  }
}

// === Tracearr ==============================================================

/// Tracearr on `tower`, watching the household's three media servers.
///
/// Its people and its titles are the ones the three servers' own fakes
/// already play: Anna's Sintel on the living-room TV through Jellyfin and
/// through Emby, and Luca's Elephants Dream on his iPad through Plex, each with
/// the id the server itself gives the item, so the Now playing that merges
/// Tracearr's streams with the servers' own finds the same session twice and
/// says it once. Its rows are the recorded 3.1.4 rows (`tracearr/real_*.json`)
/// with the household written into them.
///
/// Public: `/health`, the keyless answer. Everything else wants the bearer key,
/// which the world's behaviours refuse as every other service's (a refused key
/// is `401` with Tracearr's own envelope).
class TracearrFake extends ServiceFake {
  const TracearrFake();

  static const version = 'v3.1.4';

  /// The servers Tracearr watches, by the id it gives each.
  static const jellyfinServerId = '3b1f7a52-0c1e-4e8a-9a41-7f6c2e0b5f11';
  static const plexServerId = '6c2e8b63-1e2e-4f9b-8b52-8e7f3f1c6a22';
  static const embyServerId = '9e3f9c74-2e3f-4a0c-9c63-9f8e4a2f7b33';

  /// The people, one Tracearr user across the three servers.
  static const annaId = 'a0a1b2c3-e4e5-4f60-8718-293a4b5c6e71';
  static const lucaId = 'b0a1b2c3-e4e5-4f60-8718-293a4b5c6e72';

  @override
  bool isPublic(NetworkRequest request) =>
      request.method == 'GET' && request.path == '/health';

  @override
  NetworkReply refuseKey(NetworkRequest request) => NetworkReply.json({
    'statusCode': 401,
    'error': 'UnauthorizedError',
    'message': 'Missing or invalid Authorization header',
  }, status: 401);

  static const _servers = [
    (
      id: jellyfinServerId,
      name: 'nas',
      type: 'jellyfin',
      streams: 1,
      version: '10.10.7',
    ),
    (
      id: plexServerId,
      name: 'basement-nas',
      type: 'plex',
      streams: 1,
      version: '1.41.6',
    ),
    (
      id: embyServerId,
      name: 'tower',
      type: 'emby',
      streams: 1,
      version: '4.10.2',
    ),
  ];

  /// What the three streams are: person, server, title, the item id the
  /// server itself gives it, and the player.
  static List<
    ({
      String id,
      String serverId,
      String serverName,
      String serverType,
      String person,
      String personId,
      WorldTitle title,
      String ratingKey,
      String device,
      String player,
      String product,
      String platform,
      int bitrate,
      int progressMinutes,
    })
  >
  _playing() => [
    (
      id: 'stream-jellyfin-anna',
      serverId: jellyfinServerId,
      serverName: 'nas',
      serverType: 'jellyfin',
      person: WorldPeople.anna,
      personId: annaId,
      title: WorldTitles.sintel,
      ratingKey: 'jf-${WorldTitles.sintel.key}',
      device: 'Living room TV',
      player: 'Living room TV',
      product: 'Jellyfin Android TV',
      platform: 'Android TV',
      bitrate: 4200,
      progressMinutes: 30,
    ),
    (
      id: 'stream-plex-luca',
      serverId: plexServerId,
      serverName: 'basement-nas',
      serverType: 'plex',
      person: WorldPeople.luca,
      personId: lucaId,
      title: WorldTitles.elephantsDream,
      ratingKey: '103',
      device: "Luca's iPad",
      player: 'iPad',
      product: 'Plex for iOS',
      platform: 'iOS',
      bitrate: 8000,
      progressMinutes: 4,
    ),
    (
      id: 'stream-emby-anna',
      serverId: embyServerId,
      serverName: 'tower',
      serverType: 'emby',
      person: WorldPeople.anna,
      personId: annaId,
      title: WorldTitles.sintel,
      ratingKey: EmbyFake._id(WorldTitles.sintel),
      device: 'Living room TV',
      player: 'Living room TV',
      product: 'Emby for Android TV',
      platform: 'Android TV',
      bitrate: 3100,
      progressMinutes: 12,
    ),
  ];

  static JsonMap _streamRow(ServerContext c, int index) {
    final p = _playing()[index];
    final template =
        (jsonFixtureMap('tracearr/real_streams_live.json')['data'] as List)
                .first
            as Map<String, dynamic>;
    final runtime = Duration(minutes: p.title == WorldTitles.sintel ? 14 : 11);
    return {
      ...template,
      'id': p.id,
      'server_id': p.serverId,
      'server_name': p.serverName,
      'server_type': p.serverType,
      'username': p.person,
      'media_title': p.title.title,
      'media_type': 'movie',
      'year': p.title.year,
      'duration_ms': runtime.inMilliseconds,
      'state': 'playing',
      'progress_ms': Duration(minutes: p.progressMinutes).inMilliseconds,
      'started_at': c.ago(Duration(minutes: p.progressMinutes)),
      'bitrate': p.bitrate,
      'device': p.device,
      'player': p.player,
      'product': p.product,
      'platform': p.platform,
      'media_id': 'media-${p.title.key}',
      'tmdb_id': p.title.tmdbId,
      'imdb_id': p.title.imdbId,
      'rating_key': p.ratingKey,
    };
  }

  static String _bitrate(int kbps) => kbps >= 1000
      ? withUnit((kbps / 1000).toStringAsFixed(1), 'Mbps')
      : withUnit(kbps, 'kbps');

  static JsonMap _streams(ServerContext c, String? serverId) {
    final playing = _playing();
    final rows = [
      for (final (i, p) in playing.indexed)
        if (serverId == null || p.serverId == serverId) _streamRow(c, i),
    ];
    final kept = [
      for (final p in playing)
        if (serverId == null || p.serverId == serverId) p,
    ];
    JsonMap summary(Iterable<dynamic> of, {String? id, String? name}) => {
      'server_id': ?id,
      'server_name': ?name,
      'total': of.length,
      'transcodes': 0,
      'audio_transcodes': 0,
      'direct_streams': 0,
      'direct_plays': of.length,
      'total_bitrate': of.isEmpty
          ? '—'
          : _bitrate(of.fold<int>(0, (sum, p) => sum + (p.bitrate as int))),
    };
    return {
      'data': rows,
      'summary': {
        ...summary(kept),
        'by_server': [
          for (final s in _servers)
            if (serverId == null || s.id == serverId)
              summary(
                kept.where((p) => p.serverId == s.id),
                id: s.id,
                name: s.name,
              ),
        ],
      },
    };
  }

  /// A page of [rows] by the `cursor` (an offset) and `pageSize` asked.
  static JsonMap _paged(NetworkRequest r, List<JsonMap> rows) {
    final size = int.tryParse(r.query['pageSize'] ?? '') ?? 25;
    final start = (int.tryParse(r.query['cursor'] ?? '') ?? 0).clamp(
      0,
      rows.length,
    );
    final end = (start + size).clamp(0, rows.length);
    return {
      'data': rows.sublist(start, end),
      'meta': {
        'nextCursor': end < rows.length ? '$end' : null,
        'pageSize': size,
      },
    };
  }

  /// Who watched what, newest first: the day's streams are in
  /// [_streams]; these are the ones that ended.
  static List<JsonMap> _history(ServerContext c) {
    final template =
        (jsonFixtureMap('tracearr/real_history.json')['data'] as List).first
            as Map<String, dynamic>;
    JsonMap row(
      int n,
      WorldTitle t,
      ({String id, String name, String type}) server,
      String person,
      String personId,
      String ratingKey,
      Duration ago,
      Duration length, {
      bool watched = true,
      String device = 'Living room TV',
      String product = 'Android TV',
    }) => {
      ...template,
      'id': 'history-$n',
      'reference_id': 'history-$n',
      'server_id': server.id,
      'server_name': server.name,
      'server_type': server.type,
      'media_title': t.title,
      'media_type': 'movie',
      'year': t.year,
      'state': 'stopped',
      'started_at': c.ago(ago + length),
      'stopped_at': c.ago(ago),
      'duration_ms': length.inMilliseconds,
      'progress_ms': '${(length.inMilliseconds * (watched ? 1 : 0.4)).round()}',
      'total_duration_ms': '${length.inMilliseconds}',
      'percent_complete': watched ? 100 : 40,
      'watched': watched,
      'segment_count': 1,
      'device': device,
      'player': device,
      'product': product,
      'media_id': 'media-${t.key}',
      'tmdb_id': t.tmdbId,
      'imdb_id': t.imdbId,
      'rating_key': ratingKey,
      'user': {
        'id': personId,
        'server_user_id': 'account-$person-${server.type}',
        'username': person,
        'thumb_url': null,
        'avatar_url': null,
      },
    };
    const jf = (id: jellyfinServerId, name: 'nas', type: 'jellyfin');
    const plex = (id: plexServerId, name: 'basement-nas', type: 'plex');
    const emby = (id: embyServerId, name: 'tower', type: 'emby');
    return [
      row(
        1,
        WorldTitles.tearsOfSteel,
        jf,
        WorldPeople.anna,
        annaId,
        'jf-${WorldTitles.tearsOfSteel.key}',
        const Duration(hours: 5),
        const Duration(minutes: 12),
      ),
      row(
        2,
        WorldTitles.coffeeRun,
        plex,
        WorldPeople.luca,
        lucaId,
        '100',
        const Duration(hours: 20),
        const Duration(minutes: 10),
        watched: false,
        device: "Luca's iPad",
        product: 'Plex for iOS',
      ),
      row(
        3,
        WorldTitles.bigBuckBunny,
        emby,
        WorldPeople.anna,
        annaId,
        EmbyFake._id(WorldTitles.bigBuckBunny),
        const Duration(days: 1, hours: 2),
        const Duration(minutes: 10),
        device: 'Emby Web',
        product: 'Emby Web',
      ),
      row(
        4,
        WorldTitles.sintel,
        jf,
        WorldPeople.luca,
        lucaId,
        'jf-${WorldTitles.sintel.key}',
        const Duration(days: 3),
        const Duration(minutes: 14),
        device: "Luca's iPad",
        product: 'Jellyfin iOS',
      ),
    ];
  }

  static List<JsonMap> _users() => [
    for (final (id, name, jellyfin, plex, emby) in [
      (annaId, WorldPeople.anna, JellyfinFake.annaId, '1', EmbyFake.annaId),
      (lucaId, WorldPeople.luca, JellyfinFake.lucaId, '2', EmbyFake.lucaId),
    ])
      {
        'id': id,
        'username': name,
        'identity_name': null,
        'email': null,
        'plex_account_id': plex,
        'accounts': [
          for (final (server, type, external) in [
            (jellyfinServerId, 'jellyfin', jellyfin),
            (plexServerId, 'plex', plex),
            (embyServerId, 'emby', emby),
          ])
            {
              'server_id': server,
              'server_type': type,
              'server_user_id': 'account-$name-$type',
              'external_user_id': external,
              'username': name,
              'removed_at': null,
            },
        ],
      },
  ];

  /// Three violations with no address in them: Anna on two servers at once
  /// (unseen), a rule the owner named himself (unseen, which Cupola can say
  /// only by its name), and an old impossible journey somebody acknowledged.
  /// What Tracearr 3.x keeps in a violation's `data`: the conditions its
  /// engine weighed, grouped, each with the figure it measured (`actual`) and
  /// the one it was held to (`threshold`). The rule is told by the condition's
  /// `field`, which is how the app tells one (see `TracearrViolation`).
  static JsonMap _evidence(
    String field,
    String operator, {
    required Object threshold,
    required Object actual,
    required String rule,
    JsonMap? details,
  }) => {
    'evidence': [
      {
        'groupIndex': 0,
        'matched': true,
        'match': 'all',
        'conditions': [
          {
            'field': field,
            'operator': operator,
            'threshold': threshold,
            'actual': actual,
            'matched': true,
            'details': ?details,
          },
        ],
      },
    ],
    'relatedSessionIds': const <String>[],
    'ruleName': rule,
    'matchedGroups': const [0],
  };

  static List<JsonMap> _violations(ServerContext c) {
    JsonMap row(
      int n,
      String severity,
      String rule,
      String person,
      String personId,
      ({String id, String name, String type}) server,
      Duration ago,
      JsonMap data, {
      Duration? acknowledged,
    }) => {
      // A UUID, as every id Tracearr gives is: the screens refuse any other
      // before asking, since the server answers it with a 400.
      'id': '00000000-0000-4000-8000-00000000000$n',
      'severity': severity,
      'created_at': c.ago(ago),
      'acknowledged_at': acknowledged == null ? null : c.ago(acknowledged),
      'session_id': null,
      'rule': {'id': '00000000-0000-4000-9000-00000000000$n', 'name': rule},
      'server': {'id': server.id, 'name': server.name, 'type': server.type},
      'user': {
        'id': personId,
        'server_user_id': 'account-$person-${server.type}',
        'username': person,
        'thumb_url': null,
        'avatar_url': null,
      },
      'data': data,
    };
    return [
      row(
        1,
        'warning',
        'Concurrent streams',
        WorldPeople.anna,
        annaId,
        (id: jellyfinServerId, name: 'nas', type: 'jellyfin'),
        const Duration(minutes: 12),
        _evidence(
          'concurrent_streams',
          'gt',
          threshold: 1,
          actual: 2,
          rule: 'Concurrent streams',
        ),
      ),
      row(
        2,
        'low',
        'Unknown device',
        WorldPeople.luca,
        lucaId,
        (id: plexServerId, name: 'basement-nas', type: 'plex'),
        const Duration(hours: 9),
        _evidence(
          'is_local_network',
          'eq',
          threshold: false,
          actual: false,
          rule: 'Unknown device',
        ),
      ),
      row(
        3,
        'high',
        'Impossible travel',
        WorldPeople.luca,
        lucaId,
        (id: embyServerId, name: 'tower', type: 'emby'),
        const Duration(days: 2),
        _evidence(
          'travel_speed_kmh',
          'gt',
          threshold: 500,
          actual: 1700.0 / 1.5,
          rule: 'Impossible travel',
          details: const {
            'distance': 1700.0,
            'timeDeltaHours': 1.5,
            'previousLocation': {
              'lat': 45.07,
              'lon': 7.69,
              'city': 'Turin',
              'country': 'Italy',
            },
            'currentLocation': {
              'lat': 38.72,
              'lon': -9.14,
              'city': 'Lisbon',
              'country': 'Portugal',
            },
          },
        ),
        acknowledged: const Duration(days: 1, hours: 20),
      ),
    ];
  }

  static JsonMap _top(NetworkRequest r, ServerContext c) => {
    'data': [
      for (final row in [
        {
          'media_id': 'media-${WorldTitles.sintel.key}',
          'media_type': 'movie',
          'title': WorldTitles.sintel.title,
          'year': WorldTitles.sintel.year,
          'imdb_id': WorldTitles.sintel.imdbId,
          'tmdb_id': WorldTitles.sintel.tmdbId,
          'tvdb_id': null,
          'plays': 4,
          'watch_time_ms': 3360000,
          'unique_users': 2,
          'last_watched_day': c.ago(Duration.zero).substring(0, 10),
        },
        {
          'media_id': 'media-${WorldTitles.cosmosLaundromat.key}',
          'media_type': 'show',
          'title': WorldTitles.cosmosLaundromat.title,
          'year': WorldTitles.cosmosLaundromat.year,
          'imdb_id': null,
          'tmdb_id': WorldTitles.cosmosLaundromat.tmdbId,
          'tvdb_id': WorldTitles.cosmosLaundromat.tvdbId,
          'plays': 3,
          'watch_time_ms': 3600000,
          'unique_users': 1,
          'last_watched_day': c.ago(const Duration(days: 1)).substring(0, 10),
        },
      ])
        if (row['media_type'] == (r.query['media_type'] ?? row['media_type']))
          row,
    ],
    'meta': {'nextCursor': null, 'pageSize': 100},
  };

  /// The event stream, as the recorded 3.1.4 one starts: a `retry` hint, `ready`,
  /// then each playing stream's full row. A fake answers once and ends, so the
  /// hint is long: a client that reconnects at the end of it does so rarely.
  static NetworkReply _events(ServerContext c) {
    final frames = StringBuffer('retry: 30000\n\n')
      ..write(
        'event: ready\ndata: ${jsonEncode({'type': 'ready', 'at': c.ago(Duration.zero), 'data': {}})}\n\n',
      );
    for (final row in _streams(c, null)['data'] as List) {
      frames.write(
        'event: stream.updated\ndata: ${jsonEncode({'type': 'stream.updated', 'at': c.ago(Duration.zero), 'data': row})}\n\n',
      );
    }
    return NetworkReply(
      200,
      body: frames.toString(),
      contentType: 'text/event-stream; charset=utf-8',
    );
  }

  /// A person's figures: a few days of watching, two genres they like.
  static JsonMap _stats(String id) {
    final anna = id == annaId;
    JsonMap window(int plays, Duration time) => {
      'plays': plays,
      'watch_time_ms': time.inMilliseconds,
    };
    return {
      'user_id': id,
      'windows': {
        'last_7': window(anna ? 4 : 2, Duration(minutes: anna ? 190 : 75)),
        'last_30': window(anna ? 11 : 6, Duration(minutes: anna ? 520 : 240)),
        'all_time': window(anna ? 38 : 19, Duration(hours: anna ? 41 : 20)),
      },
      'top_genres': [
        {'genre': 'Animation', 'plays': anna ? 14 : 9},
        {'genre': 'Science Fiction', 'plays': anna ? 8 : 4},
      ],
    };
  }

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    if (r.method != 'GET') return null;
    final servers = [
      for (final s in _servers)
        {
          ...(jsonFixtureMap('tracearr/real_servers.json')['data'] as List)
                  .first
              as Map<String, dynamic>,
          'server_id': s.id,
          'server_name': s.name,
          'server_type': s.type,
          'active_streams': s.streams,
          'version': s.version,
        },
    ];
    // One violation, with what Tracearr did about it: only the single read
    // carries the actions.
    const violationPath = '/api/v2/public/violations/';
    if (r.path.startsWith(violationPath)) {
      final id = r.path.substring(violationPath.length);
      for (final v in _violations(c)) {
        if (v['id'] == id) {
          return NetworkReply.json({
            ...v,
            'actions': [
              {
                'type': 'notify',
                'success': true,
                'skipped': false,
                'skip_reason': null,
                'error_message': null,
                'executed_at': v['created_at'],
              },
            ],
          });
        }
      }
      return NetworkReply.json({
        'statusCode': 404,
        'error': 'NotFoundError',
        'message': 'Not Found',
      }, status: 404);
    }
    switch (r.path) {
      case '/health':
        return NetworkReply.json({
          'status': 'ok',
          'mode': 'ready',
          'db': true,
          'redis': true,
          'geoip': true,
          'timescale': {'enabled': true, 'healthy': true},
        });
      case '/api/v1/public/health':
        return NetworkReply.json({
          ...jsonFixtureMap('tracearr/real_health.json'),
          'version': version,
          'timestamp': c.ago(Duration.zero),
          'servers': [
            for (final s in _servers)
              {
                'id': s.id,
                'name': s.name,
                'type': s.type,
                'online': true,
                'historical': false,
                'activeStreams': s.streams,
              },
          ],
        });
      case '/api/v2/public/servers':
        return NetworkReply.json({
          'data': servers,
          'tracearr_version': version,
        });
      case '/api/v2/public/streams':
        final streams = _streams(c, r.query['server_id']);
        // As Tracearr 3.1.4 answers it: `summary=true` is the summary alone,
        // with no rows (measured on the lab).
        return NetworkReply.json(
          r.query['summary'] == 'true'
              ? {'summary': streams['summary']}
              : streams,
        );
      case '/api/v2/public/events':
        return _events(c);
      case '/api/v1/public/stats/today':
        return NetworkReply.json({
          ...jsonFixtureMap('tracearr/real_today.json'),
          'activeStreams': 3,
          'todayPlays': 4,
          'todaySessions': 5,
          'watchTimeHours': 1.5,
          'alertsLast24h': 2,
          'activeUsersToday': 2,
        });
      case '/api/v2/public/users':
        return NetworkReply.json(_paged(r, _users()));
      case '/api/v2/public/history':
        // The filters Tracearr's route takes and a screen asks, so a page
        // narrowed to a person lists that person's viewings and nobody's else.
        return NetworkReply.json(
          _paged(r, [
            for (final row in _history(c))
              if ((r.query['user_id'] == null ||
                      (row['user'] as JsonMap)['id'] == r.query['user_id']) &&
                  (r.query['server_id'] == null ||
                      row['server_id'] == r.query['server_id']) &&
                  (r.query['watched'] != 'true' || row['watched'] == true))
                row,
          ]),
        );
      case '/api/v2/public/violations':
        final unseen = r.query['acknowledged'] == 'false';
        final severity = r.query['severity'];
        final person = r.query['user_id'];
        return NetworkReply.json(
          _paged(r, [
            for (final v in _violations(c))
              if ((!unseen || v['acknowledged_at'] == null) &&
                  (severity == null || v['severity'] == severity) &&
                  (person == null || (v['user'] as JsonMap)['id'] == person))
                v,
          ]),
        );
      case '/api/v2/public/top-media':
        return NetworkReply.json(_top(r, c));
    }
    // A person, and their figures: `users/:id` and `users/:id/stats`.
    final person = RegExp(
      r'^/api/v2/public/users/([^/]+)(/stats)?$',
    ).firstMatch(r.path);
    if (person != null) {
      final id = Uri.decodeComponent(person.group(1)!);
      final user = _users().where((u) => u['id'] == id).firstOrNull;
      if (user == null) {
        return NetworkReply.json({
          'statusCode': 404,
          'error': 'NotFoundError',
          'message': 'User not found',
        }, status: 404);
      }
      return NetworkReply.json(person.group(2) == null ? user : _stats(id));
    }
    // Who watched a title: `media/:ref/watchers`, by the forms Tracearr's own
    // route parses. A title it does not hold is a `404`, which the app reads
    // as unknown and never as nobody.
    final watched = RegExp(
      r'^/api/v2/public/media/([^/]+)/watchers$',
    ).firstMatch(r.path);
    if (watched != null) {
      final rows = _watchedBy(Uri.decodeComponent(watched.group(1)!), c);
      if (rows == null) {
        return NetworkReply.json({
          'statusCode': 404,
          'error': 'NotFoundError',
          'message': 'Not Found',
        }, status: 404);
      }
      return NetworkReply.json(rows);
    }
    return null;
  }

  /// Who watched Sintel (Anna four times, Luca once, twelve days ago), the
  /// series Cosmos Laundromat (Luca, seven of its episodes), and Big Buck
  /// Bunny, which Tracearr holds and nobody has played; null for any other
  /// title.
  static JsonMap? _watchedBy(String ref, ServerContext c) {
    JsonMap watcher(
      String id,
      String name, {
      required int plays,
      required double completion,
      required int daysAgo,
      int? episodes,
    }) => {
      'user': {
        'server_user_id': 'account-$name',
        'user_id': id,
        'username': name,
        'identity_name': null,
      },
      'plays': plays,
      'watch_time_ms': plays * 600000,
      'completion_pct': completion,
      'last_watched_day': c.ago(Duration(days: daysAgo)).split('T').first,
      'distinct_episodes_watched': episodes,
    };
    JsonMap answer(String type, List<JsonMap> watchers) => {
      'media_id': 'media-$ref',
      'media_type': type,
      'window': 'all_time',
      'watchers': watchers,
    };
    if (ref == 'movie:tmdb:${WorldTitles.sintel.tmdbId}') {
      return answer('movie', [
        watcher(
          annaId,
          WorldPeople.anna,
          plays: 4,
          completion: 100,
          daysAgo: 2,
        ),
        watcher(
          lucaId,
          WorldPeople.luca,
          plays: 1,
          completion: 62,
          daysAgo: 12,
        ),
      ]);
    }
    if (ref == 'show:tmdb:${WorldTitles.cosmosLaundromat.tmdbId}' ||
        ref == 'show:tvdb:${WorldTitles.cosmosLaundromat.tvdbId}') {
      return answer('show', [
        watcher(
          lucaId,
          WorldPeople.luca,
          plays: 9,
          completion: 31.5,
          daysAgo: 1,
          episodes: 7,
        ),
      ]);
    }
    if (ref == 'movie:tmdb:${WorldTitles.bigBuckBunny.tmdbId}') {
      return answer('movie', const []);
    }
    return null;
  }
}
