@Tags(['catalog'])
library;

import 'dart:io' as io;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/domain/seerr_permission.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/features/discover/presentation/catalog_title_actions.dart';
import 'package:cupola/features/media/domain/operator_adds_via.dart';
import 'package:cupola/features/settings/data/operator_adds_via_provider.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/features/media/presentation/media_add_sheet.dart';
import 'package:cupola/features/media/presentation/media_page.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/media_watched_by.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_media_stats.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';
import 'package:cupola/features/media/presentation/media_split.dart';
import 'package:cupola/features/search/presentation/arr_add_form_provider.dart';
import 'package:cupola/features/media/presentation/media_sources_provider.dart';
import 'package:cupola/features/movies/domain/models/radarr_movie.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/media/presentation/media_episode_providers.dart';
import 'package:cupola/features/media/presentation/media_episode_sheet.dart';
import 'package:cupola/features/media/presentation/media_episodes_graph.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode_file.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

import '../test_helpers/settings_scope.dart';
import 'catalog.dart';

const _key = MediaKey.movie(653);

/// Each catalog picture's light, from the same `titleLightFromPixels` the app
/// runs. Read before the sheets: the app's own read goes through an image
/// stream and an isolate, which the sheet's fake time never finishes.
final _lights = <String, TitleLight?>{};

Future<void> _readLights() async {
  for (final (url, file) in [
    (CatalogArt.backdrop, 'backdrop'),
    (CatalogArt.poster, 'poster'),
  ]) {
    final bytes = io.File(
      'design/system/assets/Imagery/$file.jpg',
    ).readAsBytesSync();
    final codec = await ui.instantiateImageCodec(
      bytes,
      targetWidth: titleLightDecodeSize,
      targetHeight: titleLightDecodeSize,
    );
    final frame = await codec.getNextFrame();
    final rgba = (await frame.image.toByteData())!;
    _lights[url] = await titleLightFromPixels([
      for (var i = 0; i + 3 < rgba.lengthInBytes; i += 4)
        0xFF000000 |
            rgba.getUint8(i) << 16 |
            rgba.getUint8(i + 1) << 8 |
            rgba.getUint8(i + 2),
    ]);
  }
  // The same pictures where Seerr's record links them.
  _lights['https://image.tmdb.org/t/p/w1280${CatalogArt.tmdbBackdrop}'] =
      _lights[CatalogArt.backdrop];
  _lights['https://image.tmdb.org/t/p/w500${CatalogArt.tmdbPoster}'] =
      _lights[CatalogArt.poster];
}

ServiceInstance _connection(
  ServiceKey service,
  String id, {
  String label = '',
}) => ServiceInstance(
  id: id,
  service: service,
  label: label,
  url: 'http://nas.home.arpa',
  credential: 'catalog',
);

final _jellyfin = _connection(ServiceKey.jellyfin, 'jellyfin');
final _emby = _connection(ServiceKey.emby, 'emby');
final _plex = _connection(ServiceKey.plex, 'plex');
final _radarr = _connection(ServiceKey.radarr, 'radarr');
final _radarr4k = _connection(ServiceKey.radarr, 'radarr-4k', label: '4K');
final _bazarr = _connection(ServiceKey.bazarr, 'bazarr');
final _seerr = _connection(ServiceKey.seerr, 'seerr');

final _at = DateTime(2026, 10, 3, 20, 41);

MediaReading<T> _answered<T>(T value) =>
    MediaReadingAnswered(MediaAnswer(value, _at));

/// The household's copy of the catalog's title, with [images] as Radarr links
/// them (`CatalogArt`, read from disk).
RadarrMovie _movie({
  List<Object?> images = const [],
  bool uhd = false,
  bool held = true,
}) => RadarrMovie.fromJson({
  'id': 7,
  'title': 'Nosferatu',
  'sortTitle': 'nosferatu',
  'tmdbId': 653,
  'year': 1922,
  'runtime': 94,
  'status': 'released',
  'hasFile': held,
  'monitored': true,
  'isAvailable': true,
  'studio': 'Prana Film',
  'genres': ['Horror', 'Fantasy'],
  'overview':
      'Thomas Hutter travels to the Carpathians to sell a house to Count '
      'Orlok, who has seen a portrait of Hutter\'s wife, and follows the '
      'young man home by sea.',
  'images': images,
  'ratings': {
    'imdb': {'value': 7.8, 'votes': 113000},
    'tmdb': {'value': 7.6, 'votes': 2400},
    'rottenTomatoes': {'value': 97},
  },
  if (held)
    'movieFile': {
      'id': 70,
      'movieId': 7,
      'relativePath': 'Nosferatu (1922).mkv',
      'path': '/data/movies/Nosferatu (1922)/Nosferatu (1922).mkv',
      'size': uhd ? 41200000000 : 9400000000,
      'dateAdded': '2026-09-28T21:04:00Z',
      'quality': {
        'quality': {
          'id': uhd ? 19 : 7,
          'name': uhd ? 'Bluray-2160p' : 'Bluray-1080p',
          'resolution': uhd ? 2160 : 1080,
        },
      },
    },
});

const _art = [
  {'coverType': 'poster', 'remoteUrl': CatalogArt.poster},
  {'coverType': 'fanart', 'remoteUrl': CatalogArt.backdrop},
];

StreamItem _item({StreamVideo? video, int? resumeMs}) => StreamItem(
  id: 'jf-653',
  title: 'Nosferatu',
  subtitle: '1922',
  kind: StreamItemKind.movie,
  posterPath: null,
  year: 1922,
  runtimeMs: 94 * 60000,
  isPlayed: false,
  resumeOffsetMs: resumeMs,
  unplayedChildCount: null,
  video: video,
);

/// The full household: Jellyfin part-way through, Plex silent since the
/// evening with its last answer, two Radarr copies, Bazarr wanting German,
/// and no Seerr.
List<MediaRow> _household({List<Object?> images = _art}) => [
  MediaConnectionRow<MediaStreamCopy>(
    _jellyfin,
    _answered(
      MediaStreamCopy.found(
        _item(
          video: const StreamVideo(width: 3840, height: 2160, range: 'HDR10'),
          resumeMs: 31 * 60000,
        ),
      ),
    ),
  ),
  MediaConnectionRow<MediaStreamCopy>(
    _plex,
    MediaReadingFailed(
      ServiceFailureReason.unreachable,
      lastKnown: MediaAnswer(
        MediaStreamCopy.found(
          _item(video: const StreamVideo(width: 1920, height: 1080)),
        ),
        DateTime(2026, 10, 3, 18, 12),
      ),
    ),
  ),
  MediaConnectionRow<MediaRadarrCopy>(
    _radarr,
    _answered(
      MediaRadarrCopy(
        movie: _movie(images: images),
        queue: ArrQueueSnapshot.empty,
      ),
    ),
  ),
  MediaConnectionRow<MediaRadarrCopy>(
    _radarr4k,
    _answered(
      MediaRadarrCopy(
        movie: _movie(images: images, uhd: true),
        queue: ArrQueueSnapshot.empty,
      ),
    ),
  ),
  MediaConnectionRow<MediaBazarrCopy?>(
    _bazarr,
    _answered(
      const MediaBazarrCopy(
        arrConnectionId: 'radarr',
        movie: BazarrMovie(
          radarrId: 7,
          monitored: true,
          presentLanguages: [
            BazarrSubtitleLanguage(name: 'English', code2: 'en'),
          ],
          missingLanguages: [
            BazarrSubtitleLanguage(name: 'German', code2: 'de'),
          ],
        ),
      ),
    ),
  ),
  const MediaNotSetUpRow(ServiceKey.seerr),
];

/// The household with Seerr in place of its setup row: TMDB's record names
/// the title, and the collection it belongs to.
List<MediaRow> _withSeerr({
  Map<String, dynamic> mediaInfo = const {'status': 5},
}) => [
  ..._household().where((row) => row is! MediaNotSetUpRow),
  MediaConnectionRow<MediaSeerrRecord>(
    _seerr,
    _answered(
      MediaSeerrRecord(
        details: {
          'id': 653,
          'title': 'Nosferatu',
          'releaseDate': '1922-02-16',
          'runtime': 94,
          'genres': [
            {'id': 27, 'name': 'Horror'},
          ],
          'overview':
              'Thomas Hutter travels to the Carpathians to sell a house to '
              'Count Orlok, and the count follows him home by sea.',
          'posterPath': CatalogArt.tmdbPoster,
          'backdropPath': CatalogArt.tmdbBackdrop,
          'voteAverage': 7.6,
          'credits': {
            'crew': [
              {'id': 1, 'name': 'F. W. Murnau', 'job': 'Director'},
            ],
          },
          'collection': {
            'id': 1,
            'name': 'Silent Horror',
            'backdropPath': CatalogArt.tmdbBackdrop,
          },
          'watchProviders': _watchProviders,
          'releases': _releases,
          'mediaInfo': mediaInfo,
        },
      ),
    ),
  ),
];

/// No media server in Cupola: Seerr says Nosferatu is on its [server], and
/// its link opens it there.
List<MediaRow> _throughSeerr({ServiceKey server = ServiceKey.jellyfin}) => [
  MediaServerThroughSeerrRow(
    seerr: _seerr,
    server: server,
    mediaInfo: const {'status': 5},
    url: Uri.parse(
      server == ServiceKey.emby
          ? 'http://emby.local:8096/web/index.html#!/item?id=653'
          : 'http://jellyfin.local:8096/web/#/details?id=jf-653',
    ),
  ),
  ..._withSeerr().where((row) => row is! MediaConnectionRow<MediaStreamCopy>),
];

/// An Emby in Cupola holding the title, unplayed, beside Radarr's copy: the
/// lead plays it there, and the server's row is a fact, not Seerr's word.
List<MediaRow> _onEmby() => [
  MediaConnectionRow<MediaStreamCopy>(
    _emby,
    _answered(
      MediaStreamCopy.found(
        _item(video: const StreamVideo(width: 1920, height: 1080)),
      ),
    ),
  ),
  ..._household().whereType<MediaConnectionRow<MediaRadarrCopy>>().take(1),
];

/// The household with the 4K Radarr holding nothing yet, and Seerr on an
/// account whose session ended.
List<MediaRow> _copyToAdd() => [
  for (final row in _household())
    if (row is MediaNotSetUpRow)
      MediaConnectionRow<MediaSeerrRecord>(
        _seerr,
        const MediaReadingFailed(ServiceFailureReason.sessionEnded),
      )
    else if (row is MediaConnectionRow && row.connection.id == _radarr4k.id)
      MediaConnectionRow<MediaRadarrCopy>(
        _radarr4k,
        _answered(
          const MediaRadarrCopy(movie: null, queue: ArrQueueSnapshot.empty),
        ),
      )
    else
      row,
];

/// Where Nosferatu streams in the catalog's region, as TMDB lists it.
const _watchProviders = [
  {
    'iso_3166_1': 'US',
    'flatrate': [
      {'id': 283, 'name': 'Crunchyroll'},
      {'id': 191, 'name': 'Kanopy'},
    ],
    'buy': [
      {'id': 2, 'name': 'Apple TV'},
      {'id': 3, 'name': 'Google Play Movies'},
    ],
  },
];

/// Its dates there: in cinemas, then digital and on disc decades later.
const _releases = {
  'results': [
    {
      'iso_3166_1': 'US',
      'release_dates': [
        {'type': 3, 'release_date': '1929-06-03T00:00:00.000Z'},
        {'type': 4, 'release_date': '2013-10-29T00:00:00.000Z'},
        {'type': 5, 'release_date': '2007-04-17T00:00:00.000Z'},
      ],
    },
  ],
};

/// A film nobody holds that Anna asked for two hours ago: the request
/// waits on the operator.
List<MediaRow> _askedFor() => [
  ..._notHeld().where((row) => row is! MediaNotSetUpRow),
  MediaConnectionRow<MediaSeerrRecord>(
    _seerr,
    _answered(
      MediaSeerrRecord(
        details: {
          'id': 653,
          'title': 'Nosferatu',
          'releaseDate': '1922-02-16',
          'runtime': 94,
          'genres': const [
            {'id': 27, 'name': 'Horror'},
          ],
          'overview':
              'Thomas Hutter travels to the Carpathians to sell a house to '
              'Count Orlok, and the count follows him home by sea.',
          'posterPath': CatalogArt.tmdbPoster,
          'backdropPath': CatalogArt.tmdbBackdrop,
          'voteAverage': 7.6,
          'credits': const {
            'crew': [
              {'id': 1, 'name': 'F. W. Murnau', 'job': 'Director'},
            ],
          },
          'watchProviders': _watchProviders,
          'releases': _releases,
          'mediaInfo': {
            'status': 2,
            'status4k': 1,
            'requests': [
              {
                'id': 41,
                'status': 1,
                'type': 'movie',
                'is4k': false,
                'createdAt': catalogNow
                    .subtract(const Duration(hours: 2))
                    .toUtc()
                    .toIso8601String(),
                'requestedBy': const {'id': 2, 'displayName': 'Anna'},
              },
            ],
          },
        },
      ),
    ),
  ),
];

/// Nosferatu's download as Radarr's queue lists it, stalled at 47%.
const _stuckRecord = {
  'id': 2,
  'movieId': 7,
  'title': 'Nosferatu.1922.1080p.BluRay',
  'downloadClient': 'qBittorrent',
  'size': 2400000000,
  'sizeleft': 1272000000,
  'status': 'warning',
  'trackedDownloadStatus': 'warning',
  'trackedDownloadState': 'downloading',
  'statusMessages': [
    {
      'title': 'Nosferatu.1922.1080p.BluRay',
      'messages': ['The download is stalled with no connections'],
    },
  ],
};

/// Radarr tracks the film and holds no file, with [queue]; Jellyfin has
/// none.
List<MediaRow> _wanted(ArrQueueSnapshot queue) => [
  MediaConnectionRow<MediaStreamCopy>(
    _jellyfin,
    _answered(const MediaStreamCopy.notInLibrary()),
  ),
  MediaConnectionRow<MediaRadarrCopy>(
    _radarr,
    _answered(
      MediaRadarrCopy(
        movie: _movie(images: _art, held: false),
        queue: queue,
      ),
    ),
  ),
  const MediaNotSetUpRow(ServiceKey.seerr),
];

/// What the requester's household holds of a film nobody asked for: her
/// Jellyfin has none, and Seerr knows the title and nothing of it.
List<MediaRow> _notAskedFor() => [
  MediaConnectionRow<MediaStreamCopy>(
    _jellyfin,
    _answered(const MediaStreamCopy.notInLibrary()),
  ),
  MediaConnectionRow<MediaSeerrRecord>(
    _seerr,
    _answered(
      const MediaSeerrRecord(
        details: {
          'id': 653,
          'title': 'Nosferatu',
          'releaseDate': '1922-02-16',
          'runtime': 94,
          'genres': [
            {'id': 27, 'name': 'Horror'},
          ],
          'overview':
              'Thomas Hutter travels to the Carpathians to sell a house to '
              'Count Orlok, and the count follows him home by sea.',
          'posterPath': CatalogArt.tmdbPoster,
          'backdropPath': CatalogArt.tmdbBackdrop,
          'voteAverage': 7.6,
          'credits': {
            'crew': [
              {'id': 1, 'name': 'F. W. Murnau', 'job': 'Director'},
            ],
          },
        },
      ),
    ),
  ),
];

/// A film nobody holds: Jellyfin has none, neither Radarr tracks it.
List<MediaRow> _notHeld() => [
  MediaConnectionRow<MediaStreamCopy>(
    _jellyfin,
    _answered(const MediaStreamCopy.notInLibrary()),
  ),
  for (final radarr in [_radarr, _radarr4k])
    MediaConnectionRow<MediaRadarrCopy>(
      radarr,
      _answered(
        const MediaRadarrCopy(movie: null, queue: ArrQueueSnapshot.empty),
      ),
    ),
  const MediaNotSetUpRow(ServiceKey.seerr),
];

/// The operator who asks Seerr first, as the app does by default.
class _AddsViaSeerr extends OperatorAddsViaNotifier {
  @override
  OperatorAddsVia build() => OperatorAddsVia.seerr;
}

/// The add form as a Radarr answers it: two profiles, one folder, fourteen
/// indexers.
class _CatalogAddForm extends ArrAddFormNotifier {
  _CatalogAddForm(super.arg);

  @override
  ArrAddFormState build() => const ArrAddFormState(
    profiles: [(id: 1, name: 'HD-1080p'), (id: 2, name: 'Any')],
    rootFolders: ['/mnt/tank/media/movies'],
    freeSpace: {'/mnt/tank/media/movies': 13600000000000},
    searchingIndexers: 14,
    profileId: 1,
    rootFolder: '/mnt/tank/media/movies',
    isLoading: false,
  );
}

/// The add sheet, open over a page that holds nothing of the film: the
/// panel drawn in place, as `AppBottomSheet`'s card draws its panels.
CatalogScene _addScene() => CatalogScene(
  'Add · over a film nobody holds: which Radarr, its profile and '
  'folder, Monitor and Search when added',
  (context) => Stack(
    fit: StackFit.expand,
    children: [
      const MediaPage(mediaKey: _key),
      const ColoredBox(color: Colors.black54),
      Align(
        alignment: Alignment.bottomCenter,
        child: AppBottomSheet(
          title: 'Add to Radarr',
          subtitle: 'Nosferatu · 1922',
          showClose: true,
          child: MediaAddSheet(
            tmdbId: 653,
            connections: [_radarr, _radarr4k],
            name: (c) => c.label.isEmpty ? 'Radarr' : 'Radarr ${c.label}',
            light: _lights[CatalogArt.backdrop],
          ),
        ),
      ),
    ],
  ),
  width: 390,
  height: 844,
  overrides: [
    mediaRowsProvider.overrideWith((ref, key) => _notHeld()),
    audienceProvider.overrideWithValue(Audience.operator),
    titleLightProvider.overrideWith((ref, url) async => null),
    arrAddFormProvider.overrideWith2(_CatalogAddForm.new),
    mediaAddLookupProvider.overrideWith(
      (ref, target) async => _movie(images: _art),
    ),
  ],
);

/// An episode's sheet over its series: the still, TMDB's score, Resume on
/// Jellyfin part-way, the synopsis, and what Sonarr holds: a 720p file below
/// the profile's 1080p, the search for it, Monitored.
CatalogScene _episodeScene() {
  final rows = _series();
  return CatalogScene(
    'Episode · its still, where it plays and how far, what Sonarr holds and '
    'the search for the quality it lacks',
    (context) => Stack(
      fit: StackFit.expand,
      children: [
        const MediaPage(mediaKey: MediaKey.tv(358332)),
        const ColoredBox(color: Colors.black54),
        Align(
          alignment: Alignment.bottomCenter,
          child: AppBottomSheet(
            child: MediaEpisodeSheet(
              seriesTitle: 'Cosmos Laundromat',
              seasons: mediaSeasonsOf(
                rows,
                audience: Audience.operator,
                now: catalogNow,
              ),
              season: 2,
              number: 3,
              operator: true,
              sonarr: (
                connection: _sonarr,
                name: 'Sonarr',
                seriesId: 1,
                profileId: 1,
              ),
              seerr: (connectionId: _seerr.id, tvId: 358332),
              server: (connection: _jellyfin, name: 'Jellyfin'),
              light: _lights[CatalogArt.backdrop],
              onPlay: (_) {},
              onChanged: () {},
            ),
          ),
        ),
      ],
    ),
    width: 390,
    height: 1240,
    overrides: [
      mediaRowsProvider.overrideWith((ref, key) => rows),
      audienceProvider.overrideWithValue(Audience.operator),
      titleLightProvider.overrideWith((ref, url) async => _lights[url]),
      mediaRecommendationsProvider.overrideWith((ref, source) async => []),
      mediaSeasonFactsProvider.overrideWith(
        (ref, source) async => [
          const MediaEpisodeFacts(
            season: 2,
            number: 3,
            name: 'The Second Cycle',
            overview:
                'Franck wakes up in the second life Tachyon sold him, and it '
                'looks better than the first. The laundry is still there.',
            stillPath: CatalogArt.tmdbBackdrop,
            voteAverage: 8.1,
            voteCount: 37,
          ),
        ],
      ),
      mediaEpisodeFilesProvider.overrideWith(
        (ref, source) async => {
          6013: SonarrEpisodeFile(
            id: 6013,
            relativePath:
                'Cosmos Laundromat - S02E03 - The Second Cycle WEBDL-720p.mkv',
            qualityName: 'WEBDL-720p',
            dateAdded: catalogNow.subtract(const Duration(hours: 2)),
            cutoffNotMet: true,
          ),
        },
      ),
      mediaSonarrCutoffProvider.overrideWith((ref, source) async => '1080p'),
    ],
  );
}

/// One Radarr copy and nothing else, with [images].
List<MediaRow> _bare(List<Object?> images) => [
  MediaConnectionRow<MediaRadarrCopy>(
    _radarr,
    _answered(
      MediaRadarrCopy(
        movie: _movie(images: images),
        queue: ArrQueueSnapshot.empty,
      ),
    ),
  ),
  const MediaNotSetUpRow(ServiceKey.seerr),
];

final _sonarr = _connection(ServiceKey.sonarr, 'sonarr');

/// A series as its page draws it: the first season and three of the second on
/// Jellyfin (two watched, the third part-way), two downloading, five aired
/// and missing, ten upgrades waiting on an import, and a third season
/// starting in three days.
List<MediaRow> _series() {
  final now = catalogNow;
  var id = 1000;
  final episodes = [
    for (final (season, count) in [(1, 10), (2, 10), (3, 10)])
      for (var number = 1; number <= count; number++)
        SonarrEpisode(
          id: ++id,
          seasonNumber: season,
          episodeNumber: number,
          title: switch ((season, number)) {
            (2, 3) => 'The Second Cycle',
            (2, 6) => 'The Seventh Cycle',
            _ => 'Episode $number',
          },
          hasFile: season == 1 || (season == 2 && number <= 3),
          episodeFileId: season == 1 || (season == 2 && number <= 3)
              ? id + 5000
              : null,
          monitored: true,
          // S3 E9 and E10 are announced without a date: Sonarr's `TBA`.
          airDateUtc: season == 3 && number > 8
              ? null
              : (season == 3
                        ? now.add(
                            Duration(days: 3 + (number - 1) * 7, hours: 1),
                          )
                        : now.subtract(
                            Duration(days: 400 - season * 60 + number),
                          ))
                    .toUtc()
                    .toIso8601String(),
        ),
  ];
  Map<String, Object?> record(
    int episodeId, {
    double? left,
    bool blocked = false,
  }) => {
    'seriesId': 1,
    'episodeId': episodeId,
    'size': 1000,
    'sizeleft': left == null ? 0 : (left * 1000).round(),
    'status': blocked ? 'completed' : 'downloading',
    'trackedDownloadStatus': blocked ? 'warning' : 'ok',
    'trackedDownloadState': blocked ? 'importBlocked' : 'downloading',
  };
  final queue = [
    record(1014, left: 0.12),
    record(1015, left: 0.91),
    for (var e = 1001; e <= 1010; e++) record(e, blocked: true),
  ];
  StreamItem episode(int season, int number, {double played = 1}) => StreamItem(
    id: 'jf-$season-$number',
    title: season == 2 && number == 3 ? 'The Second Cycle' : 'Episode $number',
    subtitle: null,
    kind: StreamItemKind.episode,
    posterPath: null,
    year: null,
    runtimeMs: 20 * 60000,
    isPlayed: played >= 1,
    resumeOffsetMs: played < 1 ? (20 * 60000 * played).round() : null,
    unplayedChildCount: null,
    seasonNumber: season,
    episodeNumber: number,
  );
  return [
    MediaConnectionRow<MediaStreamCopy>(
      _jellyfin,
      _answered(
        MediaStreamCopy.found(
          const StreamItem(
            id: 'jf-cosmos',
            title: 'Cosmos Laundromat',
            subtitle: null,
            kind: StreamItemKind.series,
            posterPath: null,
            year: 2015,
            runtimeMs: null,
            isPlayed: false,
            resumeOffsetMs: null,
            unplayedChildCount: 7,
          ),
          episodes: [
            for (var e = 1; e <= 10; e++) episode(1, e),
            episode(2, 1),
            episode(2, 2),
            episode(2, 3, played: 0.75),
          ],
        ),
      ),
    ),
    MediaConnectionRow<MediaSonarrCopy>(
      _sonarr,
      _answered(
        MediaSonarrCopy(
          series: SonarrSeries.fromJson({
            'id': 1,
            'title': 'Cosmos Laundromat',
            'tvdbId': 300001,
            'tmdbId': 358332,
            'year': 2015,
            'status': 'continuing',
            'monitored': true,
            'images': _art,
            'genres': ['Animation'],
            'seasons': [
              for (final season in [1, 2, 3])
                {'seasonNumber': season, 'monitored': true},
            ],
          }),
          queue: ArrQueueSnapshot.empty,
          episodes: episodes,
          episodeQueue: ArrQueueSnapshot.fromQueueItems(
            queue,
            idsFor: (item) => [item['episodeId'] as int],
          ),
        ),
      ),
    ),
    MediaConnectionRow<MediaSeerrRecord>(
      _seerr,
      _answered(
        const MediaSeerrRecord(
          details: {
            'id': 358332,
            'name': 'Cosmos Laundromat',
            'firstAirDate': '2015-08-10',
            'status': 'Returning Series',
            'numberOfSeasons': 3,
            'seasons': [
              {'id': 1, 'seasonNumber': 1, 'episodeCount': 10},
              {'id': 2, 'seasonNumber': 2, 'episodeCount': 10},
              {'id': 3, 'seasonNumber': 3, 'episodeCount': 8},
            ],
            'genres': [
              {'id': 16, 'name': 'Animation'},
              {'id': 10765, 'name': 'Sci-Fi & Fantasy'},
            ],
            'overview':
                'Franck, a suicidal sheep, meets Tachyon, a salesman who '
                'offers him the gift of a lifetime.',
            'posterPath': CatalogArt.tmdbPoster,
            'backdropPath': CatalogArt.tmdbBackdrop,
            'voteAverage': 8.0,
            'mediaInfo': {'status': 4},
          },
          rottenTomatoes: 88,
        ),
      ),
    ),
  ];
}

/// TMDB's votes for the series, as the graph reads them: the second season
/// stronger, four of its episodes voted by few, the third not out.
Future<List<MediaEpisodeFacts>> _seasonFacts(int season) async {
  final votes = switch (season) {
    1 => const [7.2, 7.5, 7.9, 8.1, 7.4, 8.3, 7.0, 7.7, 8.0, 8.6],
    2 => const [8.2, 8.4, 8.1, 7.6, 7.9, 8.9, 7.3, 8.0, 8.5, 8.7],
    _ => const <double>[0, 0, 0, 0, 0, 0, 0, 0],
  };
  return [
    for (final (i, vote) in votes.indexed)
      MediaEpisodeFacts(
        season: season,
        number: i + 1,
        name: switch ((season, i + 1)) {
          (2, 3) => 'The Second Cycle',
          (2, 6) => 'The Seventh Cycle',
          _ => 'Episode ${i + 1}',
        },
        voteAverage: vote == 0 ? null : vote,
        voteCount: vote == 0
            ? 0
            : season == 2 && const {4, 6, 7, 8}.contains(i)
            ? 12
            : season == 2 && i == 5
            ? 31
            : 37,
      ),
  ];
}

/// The episodes graph open over its series; [act] may tap it first.
CatalogScene _graphScene({
  String caption =
      'Episodes graph · TMDB\'s votes a season to a column, in the title\'s '
      'light; dashed where few voted',
  Future<void> Function(WidgetTester tester, Finder scene)? act,
}) {
  final rows = _series();
  return CatalogScene(
    caption,
    (context) => Stack(
      fit: StackFit.expand,
      children: [
        const MediaPage(mediaKey: MediaKey.tv(358332)),
        const ColoredBox(color: Colors.black54),
        Align(
          alignment: Alignment.bottomCenter,
          child: AppBottomSheet(
            title: 'Episodes graph',
            subtitle: 'Cosmos Laundromat · TMDB votes',
            showClose: true,
            child: MediaEpisodesGraphSheet(
              connectionId: _seerr.id,
              tvId: 358332,
              seasonNumbers: const [1, 2, 3],
              seasons: mediaSeasonsOf(
                rows,
                audience: Audience.operator,
                now: catalogNow,
              ),
              light: _lights[CatalogArt.backdrop],
              onOpenEpisode: (_, _) {},
            ),
          ),
        ),
      ],
    ),
    width: 390,
    height: 1000,
    act: act,
    overrides: [
      mediaRowsProvider.overrideWith((ref, key) => rows),
      audienceProvider.overrideWithValue(Audience.operator),
      titleLightProvider.overrideWith((ref, url) async => _lights[url]),
      mediaRecommendationsProvider.overrideWith((ref, source) async => []),
      mediaSeasonFactsProvider.overrideWith(
        (ref, source) => _seasonFacts(source.season),
      ),
    ],
  );
}

CatalogScene _scene(
  String caption,
  List<MediaRow> rows, {
  double width = 390,
  double height = 1960,
  Audience audience = Audience.operator,
  double textScale = 1,
  MediaKey key = _key,
  int? season,
  bool paned = false,
  Future<void> Function(WidgetTester tester, Finder scene)? act,
}) => CatalogScene(
  caption,
  (_) => paned
      ? MediaPane(
          canGoBack: false,
          onBack: () {},
          child: MediaPage(mediaKey: key, season: season),
        )
      : MediaPage(mediaKey: key, season: season),
  width: width,
  height: height,
  textScale: textScale,
  act: act,
  overrides: [
    mediaRowsProvider.overrideWith((ref, key) => rows),
    audienceProvider.overrideWithValue(audience),
    titleLightProvider.overrideWith((ref, url) async => _lights[url]),
    mediaCollectionHeldProvider.overrideWith(
      (ref, collection) async => (held: 5, total: 8),
    ),
    mediaRecommendationsProvider.overrideWith((ref, source) async => []),
    mediaSeasonFactsProvider.overrideWith(
      (ref, source) => _seasonFacts(source.season),
    ),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_readLights);
  catalogCard(
    'MediaPage',
    width: 1240,
    overrides: () => settingsScopeOverrides(
      customize: (settings) => [
        _jellyfin,
        _emby,
        _plex,
        _radarr,
        _radarr4k,
        _bazarr,
        _seerr,
        _sonarr,
      ].fold(settings, (s, c) => s.copyWithInstance(c)),
    ),
    scenes: [
      _scene(
        'Operator · Resume on Jellyfin, lit by the backdrop; every row shape: '
        'a fact with its picture, a failure with its last answer, two copies, '
        'Bazarr, Seerr not set up',
        _household(),
      ),
      _scene(
        'Requester · the media servers only, no Manage',
        _household(),
        height: 1100,
        audience: Audience.requester,
      ),
      _scene(
        'No backdrop · the poster, veiled, carries the slab',
        _bare(const [
          {'coverType': 'poster', 'remoteUrl': CatalogArt.poster},
        ]),
        height: 760,
      ),
      _scene(
        'No artwork · the plate, dark in both rooms',
        _bare(const []),
        height: 760,
      ),
      _scene(
        'Media server only · no Seerr, no arr: the server names the title, '
        'with its synopsis and its poster',
        [
          MediaConnectionRow<MediaStreamCopy>(
            _jellyfin,
            _answered(
              MediaStreamCopy.found(
                StreamItem(
                  id: 'jf-653',
                  title: 'Nosferatu',
                  subtitle: '1922',
                  kind: StreamItemKind.movie,
                  posterPath: '/Items/jf-653/Images/Primary',
                  year: 1922,
                  runtimeMs: 94 * 60000,
                  isPlayed: false,
                  resumeOffsetMs: null,
                  unplayedChildCount: null,
                  overview:
                      'An estate agent travels to the Carpathians to sell a '
                      'house to a count who is never seen by day.',
                ),
                poster: (url: CatalogArt.poster, headers: null),
              ),
            ),
          ),
        ],
        height: 820,
      ),
      _scene(
        'Series · Resume the episode, the next to air, Sonarr\'s facts one '
        'row each, the episodes a season at a time',
        _series(),
        height: 2200,
        key: const MediaKey.tv(358332),
      ),
      _scene(
        'Series on a season · a season or an episode of a media server '
        'opened the page: the episodes open on that season, the first, not '
        'on the one Play continues',
        _series(),
        height: 2200,
        key: const MediaKey.tv(358332),
        season: 1,
      ),
      _scene(
        'Series on its announced season · eight episodes with a date read '
        'Not aired, the two Sonarr holds no date for read No air date, '
        'never Missing',
        _series(),
        height: 2200,
        key: const MediaKey.tv(358332),
        season: 3,
      ),
      _scene(
        'Series · Manage, Automatic search open: every season, then each '
        'season Sonarr monitors that has aired',
        _series(),
        height: 1000,
        key: const MediaKey.tv(358332),
        act: (tester, scene) async {
          // The page builds what is near its fold: scroll until Manage is
          // built, then bring the row up where it opens in view.
          final row = find.descendant(
            of: scene,
            matching: find.text('Automatic search'),
          );
          await tester.scrollUntilVisible(
            row,
            300,
            duration: Duration.zero,
            scrollable: find
                .descendant(of: scene, matching: find.byType(Scrollable))
                .first,
          );
          await Scrollable.ensureVisible(tester.element(row), alignment: 0.2);
          await tester.pump();
          // The sheet settles once the act is done: no time passes here, so
          // the scenes beside it are drawn at the same turn.
          await tester.tap(row);
        },
      ),
      _scene('Waiting · nobody has said who the title is yet', [
        MediaConnectionRow<MediaRadarrCopy>(
          _radarr,
          const MediaReadingWaiting(),
        ),
      ], height: 760),
      CatalogScene(
        'Just requested · Seerr passed it on and no Radarr has it yet: the '
        'line under Requested says what the Radarr rows say',
        (_) => const MediaPage(mediaKey: _key),
        width: 390,
        height: 1500,
        overrides: [
          mediaRowsProvider.overrideWith(
            (ref, key) => [
              ..._notHeld().where((row) => row is! MediaNotSetUpRow),
              ..._withSeerr(
                mediaInfo: const {'id': 41, 'status': 3, 'requests': []},
              ).whereType<MediaConnectionRow<MediaSeerrRecord>>(),
            ],
          ),
          audienceProvider.overrideWithValue(Audience.operator),
          operatorAddsViaProvider.overrideWith(_AddsViaSeerr.new),
          seerrSendsToProvider.overrideWith((ref, arr) async => true),
          roleGateProvider.overrideWith(
            (ref, id) => const RoleGate(
              audience: Audience.operator,
              grant: SeerrGrant.apiKey(),
            ),
          ),
          titleLightProvider.overrideWith((ref, url) async => _lights[url]),
          mediaSeerrNumberingProvider.overrideWith((ref, id) async => null),
          mediaCollectionHeldProvider.overrideWith((ref, c) async => null),
          mediaRecommendationsProvider.overrideWith((ref, source) async => []),
        ],
      ),
      _scene(
        'With Seerr · TMDB names the title, and the collection it belongs '
        'to: 5 of 8 on your server',
        _withSeerr(),
        height: 2240,
      ),
      _scene(
        'Through Seerr · no media server in Cupola: Seerr\'s link leads, '
        'and Jellyfin\'s row is Seerr\'s word with the way to add it',
        _throughSeerr(),
        height: 2240,
      ),
      _scene(
        'Through Seerr · Emby · no media server in Cupola: `Watch on Emby` '
        'leads, and Emby\'s row is Seerr\'s word with `Add Emby to Cupola`',
        _throughSeerr(server: ServiceKey.emby),
        height: 2240,
      ),
      _scene(
        'On Emby · the household\'s Emby holds the title: `Play on Emby` '
        'leads, and its row is a fact beside Radarr\'s',
        _onEmby(),
        height: 1100,
      ),
      _scene(
        'A copy to add, Seerr signed out · `+ Add to Radarr · 4K` under the '
        '4K Radarr\'s row; Seerr\'s account in blue with Sign in again, '
        'never not set up',
        _copyToAdd(),
        height: 2240,
      ),
      _scene(
        'Signed out · the requester\'s Seerr holds no session and nobody '
        'else can say who the title is: the page is the way to sign in',
        [
          MediaConnectionRow<MediaSeerrRecord>(
            _seerr,
            const MediaReadingFailed(ServiceFailureReason.sessionEnded),
          ),
        ],
        height: 760,
        audience: Audience.requester,
      ),
      _scene(
        'Tablet · beside the list: the phone column, wider, Close, the '
        "light rising from the list's side",
        _withSeerr(),
        width: 660,
        height: 2480,
        paned: true,
      ),
      _scene(
        'Desktop and an upright tablet · full screen: two tracks, the '
        'servers and Manage beside',
        _withSeerr(),
        width: 1180,
        height: 1700,
      ),
      _scene(
        'Found by Seerr · on the server and asked for by nobody: Seerr\'s '
        'row says Not requested, and Manage clears the title from Seerr '
        'after the arrs\' own rows',
        _withSeerr(mediaInfo: const {'id': 41, 'status': 5, 'requests': []}),
        width: 1180,
        height: 1700,
      ),
      CatalogScene(
        'Decision · Anna asked for it, and nobody holds it: the answer takes '
        'the lead\'s place, Approve lit by the title',
        (_) => const MediaPage(mediaKey: _key),
        width: 390,
        height: 1500,
        overrides: [
          mediaRowsProvider.overrideWith((ref, key) => _askedFor()),
          audienceProvider.overrideWithValue(Audience.operator),
          roleGateProvider.overrideWith(
            (ref, id) => const RoleGate(
              audience: Audience.operator,
              grant: SeerrGrant.apiKey(),
            ),
          ),
          titleLightProvider.overrideWith((ref, url) async => _lights[url]),
          mediaSeerrNumberingProvider.overrideWith((ref, id) async => null),
          mediaCollectionHeldProvider.overrideWith((ref, c) async => null),
          mediaRecommendationsProvider.overrideWith((ref, source) async => []),
        ],
      ),
      _addScene(),
      _episodeScene(),
      _graphScene(),
      _graphScene(
        caption:
            'Episodes graph · S2 E3 tapped: the cell ringed, the card says it',
        act: (tester, scene) async {
          final semantics = tester.ensureSemantics();
          await tester.tap(
            find.descendant(
              of: scene,
              matching: find.bySemanticsLabel(
                'Season 2 episode 3, 8.1 from 37 votes',
              ),
            ),
          );
          semantics.dispose();
        },
      ),
      CatalogScene(
        'Requester · Request, and what it means: the title is not on the '
        'server yet',
        (_) => const MediaPage(mediaKey: _key),
        width: 390,
        height: 1100,
        overrides: [
          mediaRowsProvider.overrideWith((ref, key) => _notAskedFor()),
          audienceProvider.overrideWithValue(Audience.requester),
          roleGateProvider.overrideWith(
            (ref, id) => RoleGate(
              audience: Audience.requester,
              grant: SeerrGrant.account(
                permissions: SeerrPermission.request.value,
              ),
            ),
          ),
          titleLightProvider.overrideWith((ref, url) async => _lights[url]),
          mediaSeerrNumberingProvider.overrideWith((ref, id) async => null),
          mediaCollectionHeldProvider.overrideWith((ref, c) async => null),
          mediaRecommendationsProvider.overrideWith((ref, source) async => []),
        ],
      ),
      CatalogScene(
        'Stuck · the fault leads with its remedy, and Remove '
        'download beside it',
        (_) => const MediaPage(mediaKey: _key),
        width: 390,
        height: 1240,
        overrides: [
          mediaRowsProvider.overrideWith(
            (ref, key) => _wanted(
              ArrQueueSnapshot.fromQueueItems([
                _stuckRecord,
              ], idsFor: (item) => [item['movieId'] as int]),
            ),
          ),
          titleLightProvider.overrideWith((ref, url) async => _lights[url]),
          mediaRadarrQueueProvider.overrideWith(
            (ref, copy) async => [_stuckRecord],
          ),
          mediaRadarrSearchProvider.overrideWith((ref, copy) async => null),
        ],
      ),
      CatalogScene(
        'Searching · Radarr asked its indexers, and a release can '
        'be chosen by hand',
        (_) => const MediaPage(mediaKey: _key),
        width: 390,
        height: 1100,
        overrides: [
          mediaRowsProvider.overrideWith(
            (ref, key) => _wanted(ArrQueueSnapshot.empty),
          ),
          titleLightProvider.overrideWith((ref, url) async => _lights[url]),
          mediaRadarrSearchProvider.overrideWith(
            (ref, copy) async => DateTime(2026, 10, 3, 20, 53),
          ),
        ],
      ),
      CatalogScene(
        'Watched by · a movie, from Tracearr: each person with their plays, '
        'how far they got and when they last did, the way to their page at '
        'the row\'s end',
        (_) => const MediaRoom(
          light: null,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: MediaWatchedBy(mediaKey: MediaKey.movie(45745)),
          ),
        ),
        width: 390,
        height: 330,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _withTracearr),
          tracearrWatchedByProvider.overrideWith(
            (ref, key) async => _watchers(const [
              ('anna-id', 'Anna', 4, 100.0, null, Duration(days: 2)),
              ('luca-id', 'Luca', 1, 62.0, null, Duration(days: 12)),
            ]),
          ),
        ],
      ),
      CatalogScene(
        'Watched by · a series: its distinct episodes first, then the plays; '
        'and a title Tracearr holds that nobody has played, in one line',
        (_) => const MediaRoom(
          light: null,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                MediaWatchedBy(mediaKey: MediaKey.tv(358332)),
                MediaWatchedBy(mediaKey: MediaKey.movie(10378)),
              ],
            ),
          ),
        ),
        width: 390,
        height: 420,
        overrides: [
          currentSettingsProvider.overrideWith((ref) => _withTracearr),
          tracearrWatchedByProvider.overrideWith(
            (ref, key) async => key.isMovie
                ? _watchers(const [])
                : _watchers(const [
                    ('luca-id', 'Luca', 9, 31.5, 7, Duration(days: 1)),
                  ]),
          ),
        ],
      ),
      _scene(
        'Twice the reading size',
        _household(),
        height: 2400,
        textScale: catalogTextScale,
      ),
    ],
  );
}

final _withTracearr = settingsWithServices(const [
  ServiceKey.radarr,
  ServiceKey.tracearr,
]);

/// What Tracearr says of who watched a title: a person, their plays, how
/// much they got through, the episodes for a series, and how many days ago,
/// against the clock the scene is drawn on.
TracearrMediaWatchers _watchers(
  List<(String, String, int, double, int?, Duration)> people,
) => TracearrMediaWatchers(
  watchers: [
    for (final (id, name, plays, completion, episodes, ago) in people)
      TracearrWatcher(
        userId: id,
        username: name,
        plays: plays,
        completionPct: completion,
        distinctEpisodesWatched: episodes,
        lastWatchedDay: DateTime.now().subtract(ago),
      ),
  ],
);
