/// Radarr, Sonarr, Lidarr, Readarr, Prowlarr and Bazarr on the fake network.
///
/// The arrs share one wire shape: `X-Api-Key`, `/api/<v>/…`, the paged
/// envelope, so they share [ArrFake]; each subclass supplies its library. A
/// server's library is chosen by which connection it is (Radarr or Radarr 4K,
/// Sonarr or Sonarr Anime), never by which profile, so the same Radarr answers
/// the same way wherever it appears.
library;

import 'package:cupola/features/settings/domain/service_key.dart';

import 'package:cupola/demo/world/arr_life.dart';
import 'package:cupola/demo/world/artwork.dart';
import 'package:cupola/demo/world/profile_network.dart';
import 'package:cupola/demo/world/service_fakes.dart';
import 'package:cupola/demo/world/world.dart';
import 'package:cupola/demo/world/fakes/media_fakes.dart' show SeerrFake;

/// The shared arr surface: status, health, queue, history, calendar, wanted,
/// profiles, root folders, commands.
abstract class ArrFake extends ServiceFake {
  const ArrFake();

  String get apiVersion;
  String get appName;
  String get version;

  String get _base => '/api/$apiVersion';

  List<JsonMap> queue(ServerContext c) => const [];
  List<JsonMap> history(ServerContext c) => const [];
  List<JsonMap> calendar(ServerContext c) => const [];
  List<JsonMap> missing(ServerContext c) => const [];

  /// `/parse?title=`: the arr reading a release name. Unread by default, the
  /// way an arr answers a name its parser cannot place: the title echoed and
  /// nothing else.
  JsonMap parse(ServerContext c, String title) => {'title': title};

  /// The world title [release] is a release of, read the way the fakes write
  /// release names (`Sprite.Fright.2021.1080p.WEB`), or null.
  static WorldTitle? titleOfRelease(String release) {
    for (final title in WorldTitles.catalogue) {
      if (release.startsWith('${title.title.replaceAll(' ', '.')}.')) {
        return title;
      }
    }
    return null;
  }

  /// The service's own routes, tried after the shared ones.
  NetworkReply? own(NetworkRequest r, ServerContext c) => null;

  /// What a command posted to `/command` does to a living world. Nothing by
  /// default; Radarr and Sonarr search, and import by hand.
  void command(ServerContext c, Map<Object?, Object?> body) {}

  /// The world title with TMDB id [tmdbId], or null.
  static WorldTitle? titleOfTmdb(Object? tmdbId) => WorldTitles.catalogue
      .where((t) => '${t.tmdbId}' == '$tmdbId')
      .firstOrNull;

  /// The world series with TVDB id [tvdbId], or null.
  static WorldTitle? titleOfTvdb(Object? tvdbId) => WorldTitles.catalogue
      .where((t) => t.isSeries && '${t.tvdbId}' == '$tvdbId')
      .firstOrNull;

  /// What `/release` finds for [title] in a living world: three releases, the
  /// first the arr would take. [target] names what was searched for
  /// (`movie-4`, `series-2-season-1`) and comes back in the guid, so a grab
  /// knows what it fetches.
  List<JsonMap> releases(
    ServerContext c,
    String target,
    WorldTitle title, {
    required int? season,
  }) {
    final is4k = c.server.is4k;
    final base = title.title.replaceAll(' ', '.');
    final tail = season == null
        ? '${title.year}'
        : 'S${season.toString().padLeft(2, '0')}';
    final names = [
      if (is4k) '$base.$tail.2160p.UHD.BluRay.x265-WORLD',
      '$base.$tail.1080p.WEB-DL.x264-WORLD',
      '$base.$tail.1080p.BluRay.x264-NORTHWIND',
      '$base.$tail.720p.WEB.h264-HARBOR',
    ].take(3);
    return [
      for (final (i, name) in names.indexed)
        {
          'guid': 'world-release/$target/$i/$name',
          'title': name,
          'indexerId': 1,
          'indexer': 'Nyaa',
          'size': name.contains('2160p')
              ? 8800000000
              : name.contains('720p')
              ? 900000000
              : 2200000000,
          'seeders': 40 - i * 12,
          'leechers': 3,
          'ageMinutes': 60 * (i + 2),
          'protocol': is4k ? 'usenet' : 'torrent',
          'approved': i < 2,
          'rejections': i < 2
              ? const <String>[]
              : const ['720p is below the profile\'s cutoff'],
          'quality': _quality(
            name.contains('2160p')
                ? 'Bluray-2160p'
                : name.contains('720p')
                ? 'WEBDL-720p'
                : 'WEBDL-1080p',
          ),
          'customFormats': const <Object?>[],
          'customFormatScore': 0,
        },
    ];
  }

  /// What `POST /release` grabs: the target and release name the guid of
  /// [releases] carries, or null for a guid the world did not hand out.
  static ({String target, String release})? grabbed(NetworkRequest r) {
    final body = r.json;
    final guid = body is Map ? '${body['guid']}' : '';
    final parts = guid.split('/');
    if (parts.length != 4 || parts.first != 'world-release') return null;
    return (target: parts[1], release: parts[3]);
  }

  /// What a `ManualImport` command does to a living world: each file it
  /// names arrives, by its download id or the release its path names.
  void importFiles(ServerContext c, Map<Object?, Object?> body) {
    final arrs = c.life?.arrs;
    final files = body['files'];
    if (arrs == null || files is! List) return;
    for (final file in files.whereType<Map<Object?, Object?>>()) {
      final id = file['downloadId'];
      final path = '${file['path']}';
      final download =
          (id is String ? c.life!.byId(id) : null) ??
          arrDownloads(c).where((d) => path.contains(d.release)).firstOrNull;
      if (download != null) arrs.import(download.id);
    }
  }

  /// The indexers the arr searches with: three, two of which an automatic
  /// search asks. Null for Prowlarr, whose indexers are its own routes.
  List<JsonMap>? get indexers => const [
    {'id': 1, 'name': 'Nyaa', 'enableAutomaticSearch': true},
    {'id': 2, 'name': 'Torrentio', 'enableAutomaticSearch': true},
    {'id': 3, 'name': 'Archive', 'enableAutomaticSearch': false},
  ];

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    final path = r.path;
    if (r.method == 'GET') {
      switch (path) {
        case final p when p == '$_base/system/status':
          return NetworkReply.json({
            'appName': appName,
            'instanceName': c.server.label.isEmpty
                ? appName
                : '$appName ${c.server.label}',
            'version': version,
            'isProduction': true,
            'osName': 'debian',
          });
        case final p when p == '$_base/health':
          return NetworkReply.json(const <Object?>[]);
        case final p when p == '$_base/queue':
          return NetworkReply.json(pagedEnvelope(r, queue(c)));
        case final p when p == '$_base/queue/details':
          return NetworkReply.json(queue(c));
        case final p when p == '$_base/history':
          return NetworkReply.json(pagedEnvelope(r, history(c)));
        case final p when p == '$_base/history/since':
          return NetworkReply.json(history(c));
        case final p when p == '$_base/calendar':
          return NetworkReply.json(calendar(c));
        case final p when p == '$_base/wanted/missing':
          return NetworkReply.json(pagedEnvelope(r, missing(c)));
        case final p when p == '$_base/wanted/cutoff':
          return NetworkReply.json(pagedEnvelope(r, const []));
        case final p when p == '$_base/blocklist':
          return NetworkReply.json(pagedEnvelope(r, const []));
        case final p when p == '$_base/parse':
          return NetworkReply.json(parse(c, r.query['title'] ?? ''));
        case final p when p == '$_base/qualityprofile':
          // The first asks for 1080p (2160p on a 4K server) and stops there.
          final top = c.server.is4k ? 2160 : 1080;
          return NetworkReply.json([
            {
              'id': 1,
              'name': c.server.is4k ? 'Ultra-HD' : 'HD-1080p',
              'cutoff': top == 2160 ? 19 : 3,
              'items': [
                {
                  'quality': {'id': 5, 'name': 'WEBDL-720p', 'resolution': 720},
                  'allowed': true,
                },
                {
                  'quality': {
                    'id': 3,
                    'name': 'WEBDL-1080p',
                    'resolution': 1080,
                  },
                  'allowed': true,
                },
                if (top == 2160)
                  {
                    'quality': {
                      'id': 19,
                      'name': 'Bluray-2160p',
                      'resolution': 2160,
                    },
                    'allowed': true,
                  },
              ],
            },
            {'id': 2, 'name': 'Any'},
          ]);
        case final p when p == '$_base/rootfolder':
          return NetworkReply.json([
            {
              'id': 1,
              'path': rootFolder(c),
              'accessible': true,
              'freeSpace': 12400000000000,
            },
          ]);
        case final p when p == '$_base/tag':
          return NetworkReply.json(const <Object?>[]);
        // No command running: nothing is being searched for.
        case final p when p == '$_base/command':
          return NetworkReply.json(const <Object?>[]);
        // A command posted here has finished by the time it is read again.
        case final p when p.startsWith('$_base/command/'):
          return NetworkReply.json({
            'id': int.tryParse(p.split('/').last) ?? 1,
            'name': 'ManualImport',
            'status': 'completed',
            'result': 'successful',
            'ended': c.ago(Duration.zero),
          });
        case final p when p == '$_base/indexer' && indexers != null:
          return NetworkReply.json(indexers);
        case final p when p == '$_base/manualimport':
          return NetworkReply.json(manualImport(r, c));
        case final p when p == '$_base/filesystem':
          return NetworkReply.json({
            'parent': '/mnt/tank/downloads/',
            'directories': [
              for (final d in arrDownloads(c))
                {
                  'type': 'folder',
                  'name': d.release,
                  'path': '/mnt/tank/downloads/complete/${d.release}',
                },
            ],
            'files': const <Object?>[],
          });
        case final p when p == '$_base/diskspace':
          return NetworkReply.json([
            {
              'path': '/mnt/tank',
              'label': 'tank',
              'freeSpace': 12400000000000,
              'totalSpace': 43600000000000,
            },
          ]);
      }
    }
    if (r.method == 'POST' && path == '$_base/command') {
      final body = r.json;
      if (body is Map) command(c, body);
      return NetworkReply.json({
        'id': 1,
        'name': body is Map ? body['name'] : 'Command',
        'status': 'queued',
        'queued': c.ago(Duration.zero),
      }, status: 201);
    }
    if (r.method == 'DELETE' && path.startsWith('$_base/queue/')) {
      _removeFromQueue(r, c);
      return NetworkReply.json(const <String, Object?>{});
    }
    return own(r, c);
  }

  String rootFolder(ServerContext c) => '/mnt/tank/media';

  /// What `DELETE queue/{id}` does to a living world: the row's download
  /// leaves the client too (`removeFromClient`, Radarr's default), or only
  /// the queue. The row's id is its place in the queue.
  void _removeFromQueue(NetworkRequest r, ServerContext c) {
    final life = c.life;
    final id = int.tryParse(r.path.split('/').last);
    final rows = arrDownloads(c);
    if (life == null || id == null || id < 1 || id > rows.length) return;
    final download = rows[id - 1];
    if (r.query['removeFromClient'] == 'false') {
      life.leaveArr(download.id);
    } else {
      life.remove(download.id);
    }
  }

  /// What `GET manualimport` finds in a download's folder: one file per
  /// download of this server whose folder or id the request names. A
  /// download the arr cannot place (Sonarr's tapes) comes back with no
  /// episodes and a rejection, as it does live.
  List<JsonMap> manualImport(NetworkRequest r, ServerContext c) {
    final folder = r.query['folder'];
    final downloadId = r.query['downloadId']?.toLowerCase();
    return [
      for (final (i, d) in arrDownloads(c).indexed)
        if ((folder != null && folder.contains(d.release)) ||
            (downloadId != null && downloadId == d.id.toLowerCase()))
          manualImportItem(c, d, id: i + 1),
    ];
  }

  JsonMap manualImportItem(
    ServerContext c,
    WorldDownload d, {
    required int id,
  }) {
    final folder = '/mnt/tank/downloads/complete/${d.release}';
    return {
      'id': id,
      'path': '$folder/${d.release}.mkv',
      'relativePath': '${d.release}.mkv',
      'folderName': d.release,
      'name': d.release,
      'size': d.size,
      'downloadId': d.id.toUpperCase(),
      // As its name says: the tapes are 720p.
      'quality': _quality(
        d.release.contains('720p') ? 'WEBDL-720p' : 'WEBDL-1080p',
      ),
      'languages': const [
        {'id': 1, 'name': 'English'},
      ],
      'releaseGroup': 'WORLD',
      'customFormats': const <Object?>[],
      'rejections': const <Object?>[],
    };
  }
}

// === Radarr ================================================================

class RadarrFake extends ArrFake {
  const RadarrFake();

  @override
  String get apiVersion => 'v3';
  @override
  String get appName => 'Radarr';
  @override
  String get version => '5.14.0.9383';

  @override
  String rootFolder(ServerContext c) =>
      c.server.is4k ? '/mnt/tank/media/films-4k' : '/mnt/tank/media/films';

  /// `(id, title, hasFile, added ago)` on the first Radarr. The ids restart
  /// at 1 on each server, as they do live: the same id names a different film
  /// on Radarr 4K, which is what makes a manual import that lands on the wrong
  /// server testable at all.
  static const libraryHd = [
    (1, WorldTitles.spriteFright, false, Duration(days: 20)),
    (2, WorldTitles.bigBuckBunny, false, Duration(days: 4)),
    (3, WorldTitles.coffeeRun, true, Duration(hours: 2, minutes: 15)),
    (4, WorldTitles.sintel, true, Duration(days: 2)),
    (5, WorldTitles.tearsOfSteel, true, Duration(days: 17)),
    (6, WorldTitles.elephantsDream, true, Duration(days: 40)),
  ];

  /// The same, on Radarr 4K.
  static const library4k = [
    (1, WorldTitles.elephantsDream, false, Duration(days: 3)),
    (2, WorldTitles.sintel, false, Duration(days: 1)),
    (3, WorldTitles.spring, true, Duration(hours: 2, minutes: 1)),
    (4, WorldTitles.tearsOfSteel, true, Duration(days: 1, hours: 2)),
  ];

  /// The id [title] has on the HD or the 4K Radarr, or null.
  static int? idOf(WorldTitle title, {required bool is4k}) {
    for (final entry in is4k ? library4k : libraryHd) {
      if (entry.$2 == title) return entry.$1;
    }
    return null;
  }

  List<(int, WorldTitle, bool, Duration)> _library(ServerContext c) {
    final life = c.life;
    if (life == null) return c.server.is4k ? library4k : libraryHd;
    return [
      for (final m in life.arrs.movies(c.server.id))
        (m.id, m.title, m.hasFile, c.now.difference(m.added)),
    ];
  }

  /// How long ago film [entry] arrived: in a living world, when it was
  /// imported; as written, when it was added.
  Duration _arrivedAgo(
    ServerContext c,
    (int, WorldTitle, bool, Duration) entry,
  ) {
    final arrived = c.life?.arrs.movie(c.server.id, entry.$1)?.arrived;
    return arrived == null ? entry.$4 : c.now.difference(arrived);
  }

  JsonMap _movie(ServerContext c, (int, WorldTitle, bool, Duration) entry) {
    final (id, title, hasFile, added) = entry;
    final spriteFright = title == WorldTitles.spriteFright;
    return {
      'id': id,
      'title': title.title,
      'sortTitle': title.title.toLowerCase(),
      'titleSlug': '${title.slug}-${title.tmdbId}',
      'year': title.year,
      'tmdbId': title.tmdbId,
      if (title.imdbId != null) 'imdbId': title.imdbId,
      'status': 'released',
      'monitored': c.life?.arrs.movie(c.server.id, id)?.monitored ?? true,
      'hasFile': hasFile,
      'isAvailable': true,
      'sizeOnDisk': hasFile ? (c.server.is4k ? 9800000000 : 1200000000) : 0,
      'runtime': 12,
      'qualityProfileId': 1,
      'minimumAvailability': 'released',
      'path': '${rootFolder(c)}/${title.title} (${title.year})',
      if (hasFile) 'movieFile': _movieFile(c, id, title),
      'added': c.ago(added),
      if (spriteFright) 'digitalRelease': c.agoToday(const Duration(hours: 6)),
      if (spriteFright) 'physicalRelease': c.ahead(const Duration(days: 13)),
      'images': WorldArtwork.arrImages(title),
      'genres': const ['Animation'],
      'ratings': const <String, Object?>{},
    };
  }

  /// The file a movie with one carries, as Radarr embeds it
  /// (`MovieFileResource`). The titles cover the ways a file relates to its
  /// release: renamed, with the scene name kept (Coffee Run, Spring); kept as
  /// released (Tears of Steel); renamed, with only the original path kept
  /// (Sintel); renamed with no original recorded (Elephants Dream).
  JsonMap _movieFile(ServerContext c, int id, WorldTitle title) {
    final is4k = c.server.is4k;
    final release =
        '${title.title.replaceAll(' ', '.')}.${title.year}.'
        '${is4k ? '2160p.UHD.BluRay.x265' : '1080p.BluRay.x264'}-WORLD';
    final quality = is4k ? 'Bluray-2160p' : 'Bluray-1080p';
    final renamed = '${title.title} (${title.year}) $quality.mkv';
    final keptAsReleased = title == WorldTitles.tearsOfSteel;
    final relativePath = keptAsReleased ? '$release.mkv' : renamed;
    final folder = '${rootFolder(c)}/${title.title} (${title.year})';
    return {
      'id': 100 + id,
      'movieId': id,
      'relativePath': relativePath,
      'path': '$folder/$relativePath',
      'size': is4k ? 9800000000 : 1200000000,
      'dateAdded': c.ago(const Duration(days: 1)),
      if (title != WorldTitles.sintel && title != WorldTitles.elephantsDream)
        'sceneName': release,
      if (title == WorldTitles.sintel)
        'originalFilePath': '$release/${title.slug}.mkv'
      else if (title != WorldTitles.elephantsDream)
        'originalFilePath': '$release.mkv',
      'releaseGroup': 'WORLD',
      'quality': _quality(quality),
    };
  }

  @override
  JsonMap parse(ServerContext c, String title) {
    final world = ArrFake.titleOfRelease(title);
    if (world == null || world.isSeries) return {'title': title};
    return {
      'title': title,
      'parsedMovieInfo': {
        'movieTitles': [world.title],
        'primaryMovieTitle': world.title,
        'year': world.year,
      },
      'movie': ?_movieFor(c, world),
    };
  }

  List<JsonMap> movies(ServerContext c) => [
    for (final entry in _library(c)) _movie(c, entry),
  ];

  JsonMap? _movieFor(ServerContext c, WorldTitle? title) {
    for (final entry in _library(c)) {
      if (entry.$2 == title) return _movie(c, entry);
    }
    return null;
  }

  @override
  List<JsonMap> queue(ServerContext c) => [
    for (final (i, d) in arrDownloads(c).indexed)
      arrQueueRecord(
        c,
        d,
        index: i + 1,
        media: 'movie',
        item: _movieFor(c, d.title),
      ),
  ];

  @override
  List<JsonMap> history(ServerContext c) => [
    for (final entry in _byArrival(c))
      if (entry.$3)
        {
          'id': entry.$1,
          'movieId': entry.$1,
          'eventType': 'downloadFolderImported',
          'sourceTitle':
              '${entry.$2.title.replaceAll(' ', '.')}.${entry.$2.year}'
              '${c.server.is4k ? '.2160p' : '.1080p'}',
          'date': c.ago(_arrivedAgo(c, entry)),
          'quality': _quality(c.server.is4k ? 'Bluray-2160p' : 'Bluray-1080p'),
          'movie': _movie(c, entry),
          // An import names the file it dropped and the one it became.
          'data': {
            'droppedPath':
                '/mnt/tank/downloads/complete/'
                '${entry.$2.title.replaceAll(' ', '.')}.${entry.$2.year}.mkv',
            'importedPath':
                '${rootFolder(c)}/${entry.$2.title} (${entry.$2.year})/'
                '${entry.$2.title} (${entry.$2.year}).mkv',
          },
        },
  ];

  /// The library, the latest arrival first once the world lives: what
  /// arrived in the demo heads the history, as it would.
  List<(int, WorldTitle, bool, Duration)> _byArrival(ServerContext c) {
    final library = _library(c);
    if (c.life == null) return library;
    return [...library]
      ..sort((a, b) => _arrivedAgo(c, a).compareTo(_arrivedAgo(c, b)));
  }

  @override
  void command(ServerContext c, Map<Object?, Object?> body) {
    final arrs = c.life?.arrs;
    if (arrs == null) return;
    switch (body['name']) {
      case 'MoviesSearch':
        final ids = body['movieIds'];
        if (ids is List) {
          for (final id in ids.whereType<int>()) {
            arrs.searchMovie(c.server.id, id);
          }
        }
      case 'ManualImport':
        importFiles(c, body);
    }
  }

  @override
  List<JsonMap> calendar(ServerContext c) => [
    for (final entry in _library(c))
      if (entry.$2 == WorldTitles.spriteFright) _movie(c, entry),
  ];

  @override
  List<JsonMap> missing(ServerContext c) => [
    for (final entry in _library(c))
      if (!entry.$3) _movie(c, entry),
  ];

  @override
  NetworkReply? own(NetworkRequest r, ServerContext c) {
    if (r.method == 'GET' && r.path == '/api/v3/collection') {
      // Every Blender film belongs to one collection; Radarr lists it once
      // it holds one of them.
      final held = {for (final entry in _library(c)) entry.$2.tmdbId};
      final parts = SeerrFake.collectionParts;
      return NetworkReply.json([
        {
          'id': 1,
          'title': SeerrFake.collectionName,
          'tmdbId': SeerrFake.collectionId,
          'monitored': false,
          'movies': [
            for (final t in parts)
              {
                'tmdbId': t.tmdbId,
                'title': t.title,
                'year': t.year,
                'isExisting': held.contains(t.tmdbId),
                'isExcluded': false,
              },
          ],
          'missingMovies': parts.where((t) => !held.contains(t.tmdbId)).length,
        },
      ]);
    }
    if (r.method == 'GET' && r.path == '/api/v3/movie') {
      final tmdb = r.query['tmdbId'];
      final all = movies(c);
      return NetworkReply.json(
        tmdb == null
            ? all
            : all.where((m) => '${m['tmdbId']}' == tmdb).toList(),
      );
    }
    final one = RegExp(r'^/api/v3/movie/(\d+)$').firstMatch(r.path);
    if (r.method == 'GET' && one != null) {
      final id = int.parse(one.group(1)!);
      for (final entry in _library(c)) {
        if (entry.$1 == id) return NetworkReply.json(_movie(c, entry));
      }
      return NetworkReply.json({'message': 'NotFound'}, status: 404);
    }
    if (r.method == 'GET' && r.path == '/api/v3/movie/lookup') {
      return NetworkReply.json(movies(c));
    }
    // One film looked up by its TMDB id, as Radarr answers it whether or not
    // it holds it: a film it does not hold has no id of its own.
    if (r.method == 'GET' && r.path == '/api/v3/movie/lookup/tmdb') {
      final tmdb = r.query['tmdbId'];
      for (final title in WorldTitles.all) {
        if (!title.isSeries && '${title.tmdbId}' == tmdb) {
          final held = [
            for (final entry in _library(c))
              if (entry.$2 == title) _movie(c, entry),
          ];
          return NetworkReply.json(
            held.firstOrNull ??
                {
                  'title': title.title,
                  'titleSlug': '${title.slug}-${title.tmdbId}',
                  'year': title.year,
                  'tmdbId': title.tmdbId,
                  'images': WorldArtwork.arrImages(title),
                  'minimumAvailability': 'released',
                },
          );
        }
      }
      return NetworkReply.json({'message': 'NotFound'}, status: 404);
    }
    // An add: Radarr answers with the new record. A living world keeps it,
    // and searches for it when asked to.
    if (r.method == 'POST' && r.path == '/api/v3/movie') {
      final body = r.json;
      final arrs = c.life?.arrs;
      final title = body is Map ? ArrFake.titleOfTmdb(body['tmdbId']) : null;
      if (arrs != null && title != null && !title.isSeries) {
        final options = body['addOptions'];
        final movie = arrs.addMovie(
          c.server.id,
          title,
          monitored: body['monitored'] != false,
          search: options is Map && options['searchForMovie'] == true,
        );
        return NetworkReply.json(
          _movie(c, (movie.id, title, false, Duration.zero)),
          status: 201,
        );
      }
      return NetworkReply.json({
        if (body is Map) ...body.cast<String, Object?>(),
        'id': 100,
        'hasFile': false,
      }, status: 201);
    }
    if (r.method == 'DELETE' && one != null) {
      c.life?.arrs.deleteMovie(c.server.id, int.parse(one.group(1)!));
      return NetworkReply.json(const <String, Object?>{});
    }
    // An edit: Radarr answers with the record as it now stands. A living
    // world keeps the monitoring.
    if (r.method == 'PUT' && one != null) {
      final body = r.json;
      final movie = c.life?.arrs.movie(c.server.id, int.parse(one.group(1)!));
      if (movie != null && body is Map && body['monitored'] is bool) {
        movie.monitored = body['monitored'] as bool;
      }
      return NetworkReply.json(body);
    }
    // Interactive search, in a living world: three releases of the film,
    // each a grab away.
    if (r.method == 'GET' && r.path == '/api/v3/release' && c.life != null) {
      final id = int.tryParse(r.query['movieId'] ?? '');
      final movie = id == null ? null : c.life!.arrs.movie(c.server.id, id);
      if (movie == null) return NetworkReply.json(const <Object?>[]);
      return NetworkReply.json(
        releases(c, 'movie-${movie.id}', movie.title, season: null),
      );
    }
    if (r.method == 'POST' && r.path == '/api/v3/release' && c.life != null) {
      final grab = ArrFake.grabbed(r);
      final id = grab == null
          ? null
          : int.tryParse(grab.target.replaceFirst('movie-', ''));
      if (grab != null && id != null) {
        c.life!.arrs.searchMovie(c.server.id, id, release: grab.release);
      }
      return NetworkReply.json(r.json, status: 201);
    }
    // One film's history, unpaged, as `/history/movie` answers it.
    if (r.method == 'GET' && r.path == '/api/v3/history/movie') {
      final id = r.query['movieId'];
      return NetworkReply.json([
        for (final record in history(c))
          if ('${record['movieId']}' == id) record,
      ]);
    }
    if (r.method == 'GET' && r.path == '/api/v3/moviefile') {
      return NetworkReply.json(const <Object?>[]);
    }
    return null;
  }
}

// === Sonarr ================================================================

class SonarrFake extends ArrFake {
  const SonarrFake();

  @override
  String get apiVersion => 'v3';
  @override
  String get appName => 'Sonarr';
  @override
  String get version => '4.0.9.2244';

  bool _anime(ServerContext c) =>
      c.server.label.toLowerCase().contains('anime');

  @override
  String rootFolder(ServerContext c) =>
      _anime(c) ? '/mnt/tank/media/anime' : '/mnt/tank/media/series';

  JsonMap _series(ServerContext c, int id, WorldTitle title) {
    final live = _live(c, id);
    if (live != null && !live.seeded) return _addedSeries(c, live);
    final cosmos = title == WorldTitles.cosmosLaundromat;
    // What arrived in the demo of the second season, beyond its first three.
    final more = live == null
        ? 0
        : live.arrivedEpisodes.where((e) => e.$1 == 2 && e.$2 > 3).length;
    bool seasonOn(int number) => live?.seasonsMonitored[number] ?? true;
    return {
      'id': id,
      'title': title.title,
      'sortTitle': title.title.toLowerCase(),
      'titleSlug': title.slug,
      'year': title.year,
      'tvdbId': title.tvdbId,
      'tmdbId': title.tmdbId,
      'status': 'continuing',
      'monitored': live?.monitored ?? true,
      'seriesType': _anime(c) ? 'anime' : 'standard',
      'path': '${rootFolder(c)}/${title.title}',
      'qualityProfileId': 1,
      'added': c.ago(const Duration(days: 300)),
      'images': WorldArtwork.arrImages(title),
      'genres': const ['Animation'],
      if (cosmos) 'nextAiring': c.ahead(const Duration(days: 3, minutes: 7)),
      if (title == WorldTitles.nightShift)
        'nextAiring': c.ahead(const Duration(days: 1, hours: 1, minutes: 7)),
      'seasons': cosmos
          ? [
              _season(1, 10, 10, 10, size: 6400000000, on: seasonOn(1)),
              _season(
                2,
                3 + more,
                10,
                10,
                size: 2480000000 + more * 1200000000,
                on: seasonOn(2),
              ),
              _season(3, 0, 0, 8, on: seasonOn(3)),
            ]
          : [
              _season(1, 8, 8, 8, on: seasonOn(1)),
              _season(2, 4, 5, 10, on: seasonOn(2)),
            ],
      'statistics': cosmos
          ? {
              'seasonCount': 3,
              'episodeFileCount': 13 + more,
              'episodeCount': 20,
              'totalEpisodeCount': 28,
              // Its files: twelve in 720p, one in 1080p.
              'sizeOnDisk': 8880000000 + more * 1200000000,
              'percentOfEpisodes': (13 + more) * 100.0 / 20,
            }
          : {
              'seasonCount': 2,
              'episodeFileCount': 12,
              'episodeCount': 13,
              'totalEpisodeCount': 18,
              'sizeOnDisk': 9000000000,
              'percentOfEpisodes': 92.3,
            },
    };
  }

  /// A series added in the demo: one season of eight, on disk once its pack
  /// arrived.
  JsonMap _addedSeries(ServerContext c, LiveSeries live) {
    final title = live.title;
    final files = live.arrivedSeasons.contains(1) ? 8 : 0;
    return {
      'id': live.id,
      'title': title.title,
      'sortTitle': title.title.toLowerCase(),
      'titleSlug': title.slug,
      'year': title.year,
      'tvdbId': title.tvdbId,
      'tmdbId': title.tmdbId,
      'status': 'ended',
      'monitored': live.monitored,
      'seriesType': _anime(c) ? 'anime' : 'standard',
      'path': '${rootFolder(c)}/${title.title}',
      'qualityProfileId': 1,
      'added': c.ago(c.now.difference(live.added)),
      'images': WorldArtwork.arrImages(title),
      'genres': const ['Animation'],
      'seasons': [
        _season(1, files, 8, 8, on: live.seasonsMonitored[1] ?? true),
      ],
      'statistics': {
        'seasonCount': 1,
        'episodeFileCount': files,
        'episodeCount': 8,
        'totalEpisodeCount': 8,
        'sizeOnDisk': files * 800000000,
        'percentOfEpisodes': files * 100.0 / 8,
      },
    };
  }

  static JsonMap _season(
    int number,
    int files,
    int aired,
    int total, {
    int? size,
    bool on = true,
  }) => {
    'seasonNumber': number,
    'monitored': on,
    'statistics': {
      'episodeFileCount': files,
      'episodeCount': aired,
      'totalEpisodeCount': total,
      'sizeOnDisk': size ?? files * 1100000000,
      'percentOfEpisodes': aired == 0 ? 0.0 : files * 100.0 / aired,
    },
  };

  static const libraryMain = [
    (1, WorldTitles.cosmosLaundromat),
    (2, WorldTitles.nightShift),
  ];
  static const libraryAnime = [(1, WorldTitles.agent327)];

  /// The id [title] has on the main Sonarr, or null.
  static int? idOf(WorldTitle title) {
    for (final (id, t) in libraryMain) {
      if (t == title) return id;
    }
    return null;
  }

  List<(int, WorldTitle)> _library(ServerContext c) {
    final life = c.life;
    if (life == null) return _anime(c) ? libraryAnime : libraryMain;
    return [for (final s in life.arrs.series(c.server.id)) (s.id, s.title)];
  }

  LiveSeries? _live(ServerContext c, int id) =>
      c.life?.arrs.oneSeries(c.server.id, id);

  /// A release of a series this Sonarr holds names the series; the episode is
  /// read off its `S02E04`.
  @override
  JsonMap parse(ServerContext c, String title) {
    final world = ArrFake.titleOfRelease(title);
    if (world == null || !world.isSeries) return {'title': title};
    final code = RegExp(r'S(\d+)E(\d+)').firstMatch(title);
    final held = [
      for (final (id, t) in _library(c))
        if (t == world) _series(c, id, t),
    ];
    return {
      'title': title,
      'parsedEpisodeInfo': {
        'seriesTitle': world.title,
        if (code != null) 'seasonNumber': int.parse(code.group(1)!),
        'episodeNumbers': [if (code != null) int.parse(code.group(2)!)],
      },
      if (held.isNotEmpty) 'series': held.first,
    };
  }

  List<JsonMap> series(ServerContext c) => [
    for (final (id, t) in _library(c)) _series(c, id, t),
  ];

  /// Cosmos Laundromat's episodes: S1 on disk, S2 E1–E3 on disk, E4–E10
  /// aired and missing (E4, E5 downloading), S3 E1–E8 announced with dates
  /// and E9–E10 announced without one (Sonarr's `TBA`, no `airDateUtc`).
  List<JsonMap> _episodes(ServerContext c, int seriesId) {
    if (_anime(c) || seriesId != 1) return const [];
    final live = _live(c, seriesId);
    var id = 1000;
    JsonMap episode(
      int season,
      int number, {
      required bool file,
      Duration? airedAgo,
      Duration? airsIn,
      bool dated = true,
    }) => {
      'id': ++id,
      'seriesId': 1,
      'seasonNumber': season,
      'episodeNumber': number,
      'title': switch ((season, number)) {
        (2, 3) => 'The Second Cycle',
        (2, 6) => 'The Seventh Cycle',
        _ => 'Episode $number',
      },
      'hasFile':
          file || (live?.arrivedEpisodes.contains((season, number)) ?? false),
      if (file || (live?.arrivedEpisodes.contains((season, number)) ?? false))
        'episodeFileId': id + 5000,
      'monitored': live?.episodesMonitored[id] ?? true,
      if (dated)
        'airDateUtc': airsIn != null
            ? c.ahead(airsIn)
            : c.ago(airedAgo ?? const Duration(days: 400)),
    };
    return [
      for (var e = 1; e <= 10; e++) episode(1, e, file: true),
      for (var e = 1; e <= 10; e++)
        episode(
          2,
          e,
          file: e <= 3,
          // The tenth aired yesterday: every one of them has.
          airedAgo: Duration(days: 71 - e * 7),
        ),
      for (var e = 1; e <= 8; e++)
        episode(
          3,
          e,
          file: false,
          airsIn: Duration(days: 3 + (e - 1) * 7, minutes: 7),
        ),
      for (var e = 9; e <= 10; e++) episode(3, e, file: false, dated: false),
    ];
  }

  JsonMap _episodeFile(JsonMap e, String quality, int resolution, String at) {
    final code =
        'S${'${e['seasonNumber']}'.padLeft(2, '0')}'
        'E${'${e['episodeNumber']}'.padLeft(2, '0')}';
    return {
      'id': e['episodeFileId'],
      'seriesId': e['seriesId'],
      'seasonNumber': e['seasonNumber'],
      'relativePath':
          'Season ${'${e['seasonNumber']}'.padLeft(2, '0')}/'
          'Cosmos Laundromat - $code - ${e['title']} $quality.mkv',
      'size': resolution == 1080 ? 1200000000 : 640000000,
      'dateAdded': at,
      'quality': {
        'quality': {'name': quality, 'resolution': resolution},
      },
      'qualityCutoffNotMet': resolution < 1080,
    };
  }

  @override
  void command(ServerContext c, Map<Object?, Object?> body) {
    final arrs = c.life?.arrs;
    if (arrs == null) return;
    final server = c.server.id;
    final seriesId = body['seriesId'];
    switch (body['name']) {
      case 'SeriesSearch' when seriesId is int:
        final live = _live(c, seriesId);
        if (live == null) return;
        if (!live.seeded) {
          arrs.searchSeason(server, seriesId, 1);
          return;
        }
        // The world's own: every aired episode it does not hold.
        for (final e in _episodes(c, seriesId)) {
          if (e['hasFile'] != true && e['airDateUtc'] is String) {
            final aired = DateTime.parse(e['airDateUtc'] as String);
            if (aired.isBefore(c.now)) {
              arrs.searchEpisode(
                server,
                seriesId,
                e['seasonNumber'] as int,
                e['episodeNumber'] as int,
              );
            }
          }
        }
      case 'SeasonSearch' when seriesId is int:
        final season = body['seasonNumber'];
        arrs.searchSeason(server, seriesId, season is int ? season : 1);
      case 'EpisodeSearch':
        final ids = body['episodeIds'];
        if (ids is! List) return;
        for (final e in _episodes(c, 1)) {
          if (ids.contains(e['id'])) {
            arrs.searchEpisode(
              server,
              1,
              e['seasonNumber'] as int,
              e['episodeNumber'] as int,
            );
          }
        }
      case 'ManualImport':
        importFiles(c, body);
    }
  }

  /// Whether Cosmos Laundromat's library has a file of [season] [episode]:
  /// the first season and the second's first three, as `_episodes` says.
  static bool _hasFile(int season, int episode) =>
      season == 1 || (season == 2 && episode <= 3);

  /// The id Sonarr gives episode [episode] of season [season] of series
  /// [seriesId]: Cosmos Laundromat's are its episode list's, 1001 onwards;
  /// another series' sit in their own thousand (Night Shift's S2 E5, on the
  /// calendar, is 2105).
  static int episodeIdOf(int seriesId, int season, int episode) => seriesId == 1
      ? 1000 + (season - 1) * 10 + episode
      : seriesId * 1000 + (season - 1) * 100 + episode;

  /// The series this Sonarr holds [title] under, as its id and its record.
  (int, JsonMap)? _seriesFor(ServerContext c, WorldTitle? title) {
    for (final (id, t) in _library(c)) {
      if (t == title) return (id, _series(c, id, t));
    }
    return null;
  }

  /// Each record names its own series and episode: Night Shift's are Night
  /// Shift's, never Cosmos Laundromat's.
  @override
  List<JsonMap> queue(ServerContext c) => [
    for (final (i, d) in arrDownloads(c).indexed)
      if (_seriesFor(c, d.title) case final held)
        arrQueueRecord(
          c,
          d,
          index: i + 1,
          media: 'series',
          item: held?.$2,
          episodeId: held == null || d.season == null || d.episode == null
              ? null
              : episodeIdOf(held.$1, d.season!, d.episode!),
        ),
  ];

  @override
  List<JsonMap> history(ServerContext c) => _anime(c)
      ? const []
      : [
          {
            'id': 1,
            'seriesId': 1,
            'episodeId': 1013,
            'eventType': 'downloadFolderImported',
            'sourceTitle': 'Cosmos.Laundromat.S02E03.1080p.WEB',
            'date': c.ago(const Duration(hours: 2, minutes: 43)),
            'quality': _quality('WEBDL-1080p'),
            'series': _series(c, 1, WorldTitles.cosmosLaundromat),
            'episode': _episodes(c, 1)[12],
            'data': const <String, Object?>{},
          },
        ];

  @override
  List<JsonMap> calendar(ServerContext c) {
    if (_anime(c)) return const [];
    final cosmos = _series(c, 1, WorldTitles.cosmosLaundromat);
    return [
      {..._episodes(c, 1)[20], 'series': cosmos},
      {
        'id': 2105,
        'seriesId': 2,
        'seasonNumber': 2,
        'episodeNumber': 5,
        'title': 'Episode 5',
        'hasFile': false,
        'monitored': true,
        'airDateUtc': c.ahead(const Duration(days: 1, hours: 1, minutes: 7)),
        'series': _series(c, 2, WorldTitles.nightShift),
      },
    ];
  }

  @override
  List<JsonMap> missing(ServerContext c) => [
    for (final e in _episodes(c, 1))
      if (e['seasonNumber'] == 2 && e['hasFile'] == false)
        {...e, 'series': _series(c, 1, WorldTitles.cosmosLaundromat)},
  ];

  @override
  JsonMap manualImportItem(
    ServerContext c,
    WorldDownload d, {
    required int id,
  }) {
    final base = super.manualImportItem(c, d, id: id);
    final placed = d.season != null && d.episode != null;
    final (seriesId, series) =
        _seriesFor(c, d.title) ??
        (1, _series(c, 1, WorldTitles.cosmosLaundromat));
    return {
      ...base,
      'series': series,
      if (placed) 'seasonNumber': d.season,
      'episodes': placed
          ? [
              {
                'id': episodeIdOf(seriesId, d.season!, d.episode!),
                'seriesId': seriesId,
                'seasonNumber': d.season,
                'episodeNumber': d.episode,
                'title': 'Episode ${d.episode}',
                // The library's file of it, which the import replaces:
                // `_episodes` numbers them the same way.
                if (_hasFile(d.season!, d.episode!)) ...{
                  'hasFile': true,
                  'episodeFileId':
                      episodeIdOf(seriesId, d.season!, d.episode!) + 5000,
                } else
                  'hasFile': false,
              },
            ]
          : const <Object?>[],
      'rejections': placed
          ? const <Object?>[]
          : const [
              {
                'reason': 'Unable to determine episode from the file name',
                'type': 'permanent',
              },
            ],
    };
  }

  @override
  NetworkReply? own(NetworkRequest r, ServerContext c) {
    if (r.method == 'GET' && r.path == '/api/v3/series') {
      // `?tvdbId=` filters, as Sonarr's own route does.
      final tvdb = r.query['tvdbId'];
      final all = series(c);
      return NetworkReply.json(
        tvdb == null
            ? all
            : all.where((s) => '${s['tvdbId']}' == tvdb).toList(),
      );
    }
    final one = RegExp(r'^/api/v3/series/(\d+)$').firstMatch(r.path);
    if (r.method == 'GET' && one != null) {
      final id = int.parse(one.group(1)!);
      for (final (sid, t) in _library(c)) {
        if (sid == id) return NetworkReply.json(_series(c, sid, t));
      }
      return NetworkReply.json({'message': 'NotFound'}, status: 404);
    }
    // An edit: Sonarr answers with the record as it now stands. A living
    // world keeps the monitoring, the series' and each season's.
    if (r.method == 'PUT' && one != null) {
      final body = r.json;
      final live = _live(c, int.parse(one.group(1)!));
      if (live != null && body is Map) {
        if (body['monitored'] is bool) {
          live.monitored = body['monitored'] as bool;
        }
        final seasons = body['seasons'];
        if (seasons is List) {
          for (final s in seasons.whereType<Map<Object?, Object?>>()) {
            final number = s['seasonNumber'];
            if (number is int && s['monitored'] is bool) {
              live.seasonsMonitored[number] = s['monitored'] as bool;
            }
          }
        }
      }
      return NetworkReply.json(body, status: 202);
    }
    if (r.method == 'DELETE' && one != null) {
      c.life?.arrs.deleteSeries(c.server.id, int.parse(one.group(1)!));
      return NetworkReply.json(const <String, Object?>{});
    }
    // Interactive search, in a living world: three releases of the season
    // or the episode asked for.
    if (r.method == 'GET' && r.path == '/api/v3/release' && c.life != null) {
      final episodeId = int.tryParse(r.query['episodeId'] ?? '');
      final seriesId =
          int.tryParse(r.query['seriesId'] ?? '') ??
          (episodeId == null ? null : 1);
      final live = seriesId == null ? null : _live(c, seriesId);
      if (live == null) return NetworkReply.json(const <Object?>[]);
      final episode = episodeId == null
          ? null
          : _episodes(
              c,
              live.id,
            ).where((e) => e['id'] == episodeId).firstOrNull;
      final season =
          int.tryParse(r.query['seasonNumber'] ?? '') ??
          (episode?['seasonNumber'] as int?) ??
          1;
      final target = episode == null
          ? 'series-${live.id}-season-$season'
          : 'series-${live.id}-episode-$season-${episode['episodeNumber']}';
      return NetworkReply.json(releases(c, target, live.title, season: season));
    }
    if (r.method == 'POST' && r.path == '/api/v3/release' && c.life != null) {
      final grab = ArrFake.grabbed(r);
      final parts = grab?.target.split('-') ?? const <String>[];
      final arrs = c.life!.arrs;
      if (parts.length >= 4 && parts[0] == 'series') {
        final id = int.tryParse(parts[1]) ?? 0;
        if (parts[2] == 'season') {
          arrs.searchSeason(c.server.id, id, int.tryParse(parts[3]) ?? 1);
        } else if (parts[2] == 'episode' && parts.length == 5) {
          arrs.searchEpisode(
            c.server.id,
            id,
            int.tryParse(parts[3]) ?? 1,
            int.tryParse(parts[4]) ?? 1,
          );
        }
      }
      return NetworkReply.json(r.json, status: 201);
    }
    // One series' history, unpaged, as `/history/series` answers it.
    if (r.method == 'GET' && r.path == '/api/v3/history/series') {
      final id = r.query['seriesId'];
      return NetworkReply.json([
        for (final record in history(c))
          if ('${record['seriesId']}' == id) record,
      ]);
    }
    if (r.method == 'GET' && r.path == '/api/v3/episode') {
      final id = int.tryParse(r.query['seriesId'] ?? '') ?? 0;
      return NetworkReply.json(_episodes(c, id));
    }
    if (r.method == 'GET' && r.path == '/api/v3/series/lookup') {
      // By id (`tvdb:300003`, `tmdb:300003`): the world's series under it,
      // as this Sonarr holds it or as it would add it. Any other term: the
      // library, whatever it says.
      final byId = RegExp(
        r'^(tvdb|tmdb):(\d+)$',
      ).firstMatch(r.query['term'] ?? '');
      if (byId == null) return NetworkReply.json(series(c));
      final id = int.parse(byId.group(2)!);
      for (final title in WorldTitles.catalogue) {
        if (!title.isSeries) continue;
        if ((byId.group(1) == 'tvdb' ? title.tvdbId : title.tmdbId) != id) {
          continue;
        }
        return NetworkReply.json([
          _seriesFor(c, title)?.$2 ??
              {
                'title': title.title,
                'sortTitle': title.title.toLowerCase(),
                'titleSlug': title.slug,
                'year': title.year,
                'tvdbId': title.tvdbId,
                'tmdbId': title.tmdbId,
                'status': 'continuing',
                'seriesType': 'standard',
                'images': WorldArtwork.arrImages(title),
                'seasons': [
                  {'seasonNumber': 1, 'monitored': true},
                ],
              },
        ]);
      }
      return NetworkReply.json(const <Object?>[]);
    }
    // An add: Sonarr answers with the new record. A living world keeps it,
    // and searches for it when asked to.
    if (r.method == 'POST' && r.path == '/api/v3/series') {
      final body = r.json;
      final arrs = c.life?.arrs;
      final title = body is Map ? ArrFake.titleOfTvdb(body['tvdbId']) : null;
      if (arrs != null && title != null) {
        final options = body['addOptions'];
        final added = arrs.addSeries(
          c.server.id,
          title,
          monitored: body['monitored'] != false,
          search: options is Map && options['searchForMissingEpisodes'] == true,
        );
        return NetworkReply.json(_series(c, added.id, title), status: 201);
      }
      return NetworkReply.json({
        if (body is Map) ...body.cast<String, Object?>(),
        'id': 100,
      }, status: 201);
    }
    if (r.method == 'GET' && r.path == '/api/v3/episodefile') {
      final id = int.tryParse(r.query['seriesId'] ?? '') ?? 0;
      // The first season and the second's first two in 720p, below the
      // profile's 1080p; the third episode in 1080p, imported this evening.
      return NetworkReply.json([
        for (final e in _episodes(c, id))
          if (e['hasFile'] == true)
            if (e['seasonNumber'] == 2 && e['episodeNumber'] == 3)
              _episodeFile(
                e,
                'WEBDL-1080p',
                1080,
                c.agoToday(const Duration(hours: 2, minutes: 43)),
              )
            else
              _episodeFile(
                e,
                'WEBDL-720p',
                720,
                c.ago(const Duration(days: 40)),
              ),
      ]);
    }
    if (r.method == 'PUT' && r.path == '/api/v3/episode/monitor') {
      final body = r.json;
      final live = _live(c, 1);
      if (live != null && body is Map && body['monitored'] is bool) {
        final ids = body['episodeIds'];
        if (ids is List) {
          for (final id in ids.whereType<int>()) {
            live.episodesMonitored[id] = body['monitored'] as bool;
          }
        }
      }
      return const NetworkReply(202);
    }
    return null;
  }
}

// === Lidarr ================================================================

class LidarrFake extends ArrFake {
  const LidarrFake();

  @override
  String get apiVersion => 'v1';
  @override
  String get appName => 'Lidarr';
  @override
  String get version => '2.6.4.4402';

  @override
  String rootFolder(ServerContext c) => '/mnt/tank/media/music';

  JsonMap _artist(ServerContext c) => {
    'id': 1,
    'artistName': 'Jan Morgenstern',
    'sortName': 'morgenstern, jan',
    'foreignArtistId': 'b3c7d8e9-0000-4000-8000-00000000jm01',
    'status': 'continuing',
    'monitored': true,
    'monitorNewItems': 'all',
    'path': '/mnt/tank/media/music/Jan Morgenstern',
    'qualityProfileId': 1,
    'metadataProfileId': 1,
    'added': c.ago(const Duration(days: 500)),
    'images': const <Object?>[],
    'statistics': {
      'albumCount': 4,
      'trackFileCount': 15,
      'trackCount': 20,
      'totalTrackCount': 20,
      'sizeOnDisk': 900000000,
      'percentOfTracks': 75.0,
    },
  };

  /// Sintel's five tracks, as `GET /api/v1/track?albumId=3` sends them; the
  /// other albums list none.
  static const _sintelTracks = [
    (1, 'Opening', 168000),
    (2, 'Scales', 252000),
    (3, 'The Dragon', 336000),
    (4, 'Snow', 234000),
    (5, 'Finale', 270000),
  ];

  List<JsonMap> _tracks(NetworkRequest r) => [
    if (r.uri.queryParameters['albumId'] == '3')
      for (final (number, title, duration) in _sintelTracks)
        {
          'id': 300 + number,
          'albumId': 3,
          'mediumNumber': 1,
          'trackNumber': '$number',
          'title': title,
          'duration': duration,
          'hasFile': true,
        },
  ];

  List<JsonMap> _albums(ServerContext c) => [
    for (final (id, title, year, onDisk) in const [
      (1, 'Elephants Dream', 2006, true),
      (2, 'Big Buck Bunny', 2008, true),
      (3, 'Sintel', 2010, true),
      (4, 'Sintel (Anniversary Edition)', 2026, false),
    ])
      {
        'id': id,
        'artistId': 1,
        'title': title,
        'foreignAlbumId': 'album-jm-$id',
        'albumType': 'Album',
        'monitored': true,
        'releaseDate': id == 4
            ? c.ahead(const Duration(days: 1, hours: 6))
            : '$year-01-01T00:00:00Z',
        'images': const <Object?>[],
        'duration': id == 3 ? 1260000 : 0,
        'artist': _artist(c),
        'statistics': {
          'trackFileCount': onDisk ? 5 : 0,
          'trackCount': 5,
          'totalTrackCount': 5,
          'sizeOnDisk': onDisk ? 300000000 : 0,
          'percentOfTracks': onDisk ? 100.0 : 0.0,
        },
      },
  ];

  @override
  List<JsonMap> calendar(ServerContext c) => [
    for (final album in _albums(c))
      if (album['id'] == 4) album,
  ];

  /// The wishlist: the albums Lidarr monitors and holds no file of, which
  /// in this library is the anniversary edition alone.
  @override
  List<JsonMap> missing(ServerContext c) => [
    for (final album in _albums(c))
      if ((album['statistics'] as JsonMap)['trackFileCount'] == 0) album,
  ];

  /// What Lidarr's history holds, newest first: Sintel's tags rewritten
  /// today, then the two older albums grabbed and filed weeks ago, a record
  /// per track file as Lidarr writes them (the app folds them back into one
  /// album). No import is from this week, so the Arrived band, which counts
  /// the week's imports, stays the films' and episodes'. The queue is empty:
  /// every download of the world is a film or an episode, and a Lidarr row
  /// has to join one.
  @override
  List<JsonMap> history(ServerContext c) {
    final albums = {for (final album in _albums(c)) album['id'] as int: album};
    var id = 0;
    final records = <JsonMap>[];

    // The album as a record embeds it: without its own copy of the artist.
    JsonMap embedded(int albumId) => {...albums[albumId]!}..remove('artist');

    void grabbed(int albumId, String release, String date) {
      records.add({
        'id': ++id,
        'albumId': albumId,
        'artistId': 1,
        'eventType': 'grabbed',
        'sourceTitle': release,
        'date': date,
        'quality': _format('FLAC', 6),
        'downloadId': _albumDownloadId(albumId),
        'artist': _artist(c),
        'album': embedded(albumId),
        'data': {'indexer': 'Fjord Tracker', 'downloadClient': 'qBittorrent'},
      });
    }

    // One record per track file, newest first: the last track on top.
    void perTrack(
      int albumId,
      String eventType,
      int tracks,
      String Function(int track) date, {
      required String release,
      bool retag = false,
    }) {
      final album = albums[albumId]!;
      final folder =
          '${album['title']} (${(album['releaseDate'] as String).substring(0, 4)})';
      for (var n = tracks; n >= 1; n--) {
        final name =
            '${n.toString().padLeft(2, '0')} ${_trackTitle(albumId, n)}.flac';
        final path = '${rootFolder(c)}/Jan Morgenstern/$folder/$name';
        records.add({
          'id': ++id,
          'albumId': albumId,
          'artistId': 1,
          'trackId': albumId * 100 + n,
          'eventType': eventType,
          'sourceTitle': retag ? path : release,
          'date': date(n),
          'quality': _format('FLAC', 6),
          'downloadId': _albumDownloadId(albumId),
          'artist': _artist(c),
          'album': embedded(albumId),
          'data': {
            if (!retag)
              'droppedPath': '/mnt/tank/downloads/complete/$release/$name',
            if (!retag) 'importedPath': path,
            if (retag) 'path': path,
            'size': 60000000,
          },
        });
      }
    }

    const sintel = 'Jan Morgenstern - Sintel (2010) FLAC';
    const bunny = 'Jan Morgenstern - Big Buck Bunny (2008) FLAC';
    const elephants = 'Jan Morgenstern - Elephants Dream (2006) FLAC';
    perTrack(
      3,
      'trackFileRetagged',
      5,
      (n) => c.agoToday(Duration(hours: 1, minutes: 50 - n)),
      release: sintel,
      retag: true,
    );
    perTrack(
      2,
      'trackFileImported',
      5,
      (n) => c.ago(Duration(days: 9, hours: 4, minutes: 50 - n)),
      release: bunny,
    );
    grabbed(2, bunny, c.ago(const Duration(days: 9, hours: 5)));
    perTrack(
      1,
      'trackFileImported',
      5,
      (n) => c.ago(Duration(days: 31, hours: 7, minutes: 50 - n)),
      release: elephants,
    );
    grabbed(1, elephants, c.ago(const Duration(days: 31, hours: 8)));
    return records;
  }

  /// The id a torrent of album [albumId] carries in history: forty hex
  /// digits, upper-cased as the arrs record a hash.
  static String _albumDownloadId(int albumId) =>
      'D0C1A2B3${albumId.toString().padLeft(32, '0')}';

  /// Track [n] of album [albumId]: Sintel's own, a numbered one elsewhere.
  static String _trackTitle(int albumId, int n) => albumId == 3
      ? _sintelTracks[n - 1].$2
      : 'Track ${n.toString().padLeft(2, '0')}';

  @override
  NetworkReply? own(NetworkRequest r, ServerContext c) {
    if (r.method != 'GET') return null;
    return switch (r.path) {
      '/api/v1/artist' => NetworkReply.json([_artist(c)]),
      '/api/v1/artist/1' => NetworkReply.json(_artist(c)),
      // The search route, as Radarr's and Sonarr's fakes answer theirs: the
      // world's artist, with its library id, whatever the term.
      '/api/v1/artist/lookup' => NetworkReply.json([_artist(c)]),
      '/api/v1/album' => NetworkReply.json(_albums(c)),
      '/api/v1/metadataprofile' => NetworkReply.json([
        {'id': 1, 'name': 'Standard'},
      ]),
      '/api/v1/track' => NetworkReply.json(_tracks(r)),
      '/api/v1/trackfile' => NetworkReply.json(const <Object?>[]),
      _ => null,
    };
  }
}

// === Readarr (World B) ======================================================

class ReadarrFake extends ArrFake {
  const ReadarrFake();

  @override
  String get apiVersion => 'v1';
  @override
  String get appName => 'Readarr';
  @override
  String get version => '0.4.3.2665';

  @override
  String rootFolder(ServerContext c) => '/mnt/user/media/books';

  /// Jules Verne, as the board draws him: seven books, six on disk.
  JsonMap _author(ServerContext c) => {
    'id': 1,
    'authorName': 'Jules Verne',
    'authorNameLastFirst': 'Verne, Jules',
    'titleSlug': 'jules-verne',
    'status': 'ended',
    'monitored': true,
    'path': '/mnt/user/media/books/Jules Verne',
    'qualityProfileId': 1,
    'images': const <Object?>[],
    'statistics': {
      'bookCount': 7,
      'bookFileCount': 6,
      'totalBookCount': 7,
      'sizeOnDisk': 42000000,
    },
  };

  /// His books; Five Weeks in a Balloon is wanted.
  static const _books = [
    (1, 'Five Weeks in a Balloon', 1863, false),
    (2, 'Journey to the Centre of the Earth', 1864, true),
    (3, 'From the Earth to the Moon', 1865, true),
    (4, 'Twenty Thousand Leagues Under the Seas', 1870, true),
    (5, 'Around the World in Eighty Days', 1872, true),
    (6, 'The Mysterious Island', 1875, true),
    (7, 'Michael Strogoff', 1876, true),
  ];

  /// A book as a wanted, calendar or history record embeds it: the book
  /// itself and, for the rows that name one, its author.
  JsonMap _book(
    ServerContext c,
    (int, String, int, bool) entry, {
    String? releaseDate,
    bool withAuthor = true,
  }) {
    final (id, title, year, onDisk) = entry;
    return {
      'id': id,
      'authorId': 1,
      'title': title,
      'monitored': true,
      'releaseDate': releaseDate ?? '$year-01-01T00:00:00Z',
      'images': const <Object?>[],
      'statistics': {
        'bookFileCount': onDisk ? 1 : 0,
        'bookCount': 1,
        'totalBookCount': 1,
      },
      if (withAuthor) 'author': _author(c),
    };
  }

  /// The wishlist: the one book of his Readarr monitors and holds no file of.
  @override
  List<JsonMap> missing(ServerContext c) => [
    for (final entry in _books)
      if (!entry.$4) _book(c, entry),
  ];

  /// A posthumous manuscript of his, out in two days: the one dated thing
  /// the calendar holds. Not in his book list, which is the seven he wrote.
  @override
  List<JsonMap> calendar(ServerContext c) => [
    _book(c, (
      8,
      'Paris in the Twentieth Century',
      1994,
      false,
    ), releaseDate: c.ahead(const Duration(days: 2))),
  ];

  /// What Readarr's history holds, newest first: Around the World in Eighty
  /// Days retagged today, then two older books of his grabbed and filed
  /// weeks ago. No import is from this week, so the Arrived band, which
  /// counts the week's imports, stays the films' and episodes'. The queue is
  /// empty: every download of the world is a film or an episode, and a
  /// Readarr row has to join one.
  @override
  List<JsonMap> history(ServerContext c) {
    var id = 0;
    final records = <JsonMap>[];

    void event(
      int bookId,
      String eventType,
      String release,
      String date, {
      Map<String, Object?> data = const {},
    }) {
      final entry = _books.firstWhere((b) => b.$1 == bookId);
      records.add({
        'id': ++id,
        'bookId': bookId,
        'authorId': 1,
        'eventType': eventType,
        'sourceTitle': release,
        'date': date,
        'quality': _format('EPUB', 3),
        'downloadId': 'E0B0C0D0${bookId.toString().padLeft(32, '0')}',
        'book': _book(c, entry, withAuthor: false),
        'author': _author(c),
        'data': data,
      });
    }

    void filed(int bookId, String release, String date) {
      final entry = _books.firstWhere((b) => b.$1 == bookId);
      final file = '${entry.$2}.epub';
      event(
        bookId,
        'bookFileImported',
        release,
        date,
        data: {
          'droppedPath': '/mnt/user/downloads/complete/$release/$file',
          'importedPath': '${rootFolder(c)}/Jules Verne/${entry.$2}/$file',
          'size': 7000000,
        },
      );
    }

    const strogoff = 'Jules.Verne.Michael.Strogoff.EPUB-WORLD';
    const island = 'Jules.Verne.The.Mysterious.Island.EPUB-WORLD';
    // Today a retag, which Readarr writes when it rewrites a file's tags.
    event(
      5,
      'bookFileRetagged',
      '${rootFolder(c)}/Jules Verne/Around the World in Eighty Days/'
          'Around the World in Eighty Days.epub',
      c.agoToday(const Duration(hours: 1, minutes: 20)),
      data: const {'size': 7000000},
    );
    filed(7, strogoff, c.ago(const Duration(days: 9, hours: 3)));
    event(
      7,
      'grabbed',
      strogoff,
      c.ago(const Duration(days: 9, hours: 3, minutes: 20)),
      data: const {'indexer': 'Archive', 'downloadClient': 'NZBGet'},
    );
    filed(6, island, c.ago(const Duration(days: 23, hours: 9)));
    event(
      6,
      'grabbed',
      island,
      c.ago(const Duration(days: 23, hours: 9, minutes: 25)),
      data: const {'indexer': 'Archive', 'downloadClient': 'NZBGet'},
    );
    return records;
  }

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    // Readarr's own profile, for books.
    if (r.method == 'GET' && r.path == '/api/v1/qualityprofile') {
      return NetworkReply.json([
        {'id': 1, 'name': 'eBook'},
        {'id': 2, 'name': 'Spoken'},
      ]);
    }
    return super.answer(r, c);
  }

  @override
  NetworkReply? own(NetworkRequest r, ServerContext c) {
    if (r.method != 'GET') return null;
    return switch (r.path) {
      '/api/v1/author' => NetworkReply.json([_author(c)]),
      '/api/v1/author/1' => NetworkReply.json(_author(c)),
      '/api/v1/book' => NetworkReply.json([
        if (r.query['authorId'] case null || '1')
          for (final entry in _books) _book(c, entry, withAuthor: false),
      ]),
      _ => null,
    };
  }
}

// === Prowlarr ==============================================================

class ProwlarrFake extends ArrFake {
  const ProwlarrFake();

  @override
  List<JsonMap>? get indexers => null;

  @override
  String get apiVersion => 'v1';
  @override
  String get appName => 'Prowlarr';
  @override
  String get version => '1.24.3.4754';

  static const indexerNames = [
    'Atlas NZB',
    'Beacon Usenet',
    'Cedar Index',
    'Delta Newz',
    'Ember NZB',
    'Fjord Tracker',
    'Grove Index',
    'Harbor Newz',
    'Iris Tracker',
    'Juniper NZB',
    'Kestrel Index',
    'Lumen Tracker',
    'Meridian NZB',
    'Nova Index',
  ];

  static const _grabs = {
    'Atlas NZB': 12,
    'Beacon Usenet': 9,
    'Fjord Tracker': 7,
    'Harbor Newz': 5,
  };

  /// One application as `GET /api/v1/applications` sends it: an
  /// `ApplicationResource` whose fields are the implementation's settings
  /// (`Applications/Radarr/RadarrSettings.cs`: `prowlarrUrl`, `baseUrl`,
  /// `apiKey`, `syncCategories`), the key masked as `ClientSchema/
  /// SchemaBuilder.cs` masks every `ApiKey` field. Under `withDockerHostnames`
  /// both addresses are the containers'.
  static JsonMap _application(
    int id,
    String name, {
    required String baseUrl,
    required bool docker,
  }) {
    final implementation = name.split(' ').first;
    return {
      'id': id,
      'name': name,
      'syncLevel': 'fullSync',
      'fields': [
        {
          'order': 0,
          'name': 'prowlarrUrl',
          'label': 'Prowlarr Server',
          'value': docker ? WorldContainers.prowlarr : WorldHosts.prowlarr,
          'type': 'textbox',
          'advanced': false,
          'privacy': 'normal',
          'isFloat': false,
        },
        {
          'order': 1,
          'name': 'baseUrl',
          'label': '$implementation Server',
          'value': baseUrl,
          'type': 'textbox',
          'advanced': false,
          'privacy': 'normal',
          'isFloat': false,
        },
        {
          'order': 2,
          'name': 'apiKey',
          'label': 'API Key',
          'value': '********',
          'type': 'textbox',
          'advanced': false,
          'privacy': 'apiKey',
          'isFloat': false,
        },
        {
          'order': 5,
          'name': 'syncCategories',
          'label': 'Sync Categories',
          'value': const [2000, 2010, 2020, 2030, 2040, 2045, 2050, 2060],
          'type': 'select',
          'advanced': true,
          'privacy': 'normal',
          'isFloat': false,
        },
      ],
      'implementationName': implementation,
      'implementation': implementation,
      'configContract': '${implementation}Settings',
      'infoLink':
          'https://wiki.servarr.com/prowlarr/supported#'
          '${implementation.toLowerCase()}',
      'tags': const <Object?>[],
    };
  }

  @override
  NetworkReply? own(NetworkRequest r, ServerContext c) {
    if (r.method != 'GET') return null;
    switch (r.path) {
      case '/api/v1/indexer':
        return NetworkReply.json([
          for (final (i, name) in indexerNames.indexed)
            {
              'id': i + 1,
              'name': name,
              'enable': true,
              'protocol': name.contains('Tracker') ? 'torrent' : 'usenet',
              'privacy': 'private',
              'priority': 25,
              'appProfileId': 1,
              'tags': const <Object?>[],
              'fields': const <Object?>[],
            },
        ]);
      case '/api/v1/indexerstatus':
        return NetworkReply.json(const <Object?>[]);
      case '/api/v1/indexerstats':
        return NetworkReply.json({
          'indexers': [
            for (final (i, name) in indexerNames.indexed)
              {
                'indexerId': i + 1,
                'indexerName': name,
                'numberOfQueries': 90 + i,
                'numberOfGrabs': _grabs[name] ?? 1,
                'numberOfFailedQueries': 0,
                'numberOfFailedGrabs': 0,
                'averageResponseTime': 420,
              },
          ],
          'userAgents': const <Object?>[],
          'hosts': const <Object?>[],
        });
      case '/api/v1/applications':
        return NetworkReply.json([
          for (final (i, (name, id, url)) in const [
            ('Radarr', WorldIds.radarr, WorldHosts.radarr),
            ('Radarr 4K', WorldIds.radarr4k, WorldHosts.radarr4k),
            ('Sonarr', WorldIds.sonarr, WorldHosts.sonarr),
            ('Lidarr', WorldIds.lidarr, WorldHosts.lidarr),
          ].indexed)
            _application(
              i + 1,
              name,
              docker: c.profile.dockerHostnames,
              baseUrl: c.profile.dockerHostnames
                  ? WorldContainers.of(id) ?? url
                  : url,
            ),
        ]);
      case '/api/v1/appprofile':
        return NetworkReply.json([
          {'id': 1, 'name': 'Standard'},
        ]);
      case '/api/v1/indexer/categories':
        return NetworkReply.json(const <Object?>[]);
    }
    return null;
  }
}

// === Bazarr ================================================================

/// Bazarr follows the Radarr and Sonarr it was pointed at in its own
/// settings; it has no idea which Cupola connection that is.
class BazarrFake extends ServiceFake {
  const BazarrFake();

  // Bazarr takes its key as `X-API-KEY` and answers a bad one with 401.

  @override
  NetworkReply? answer(NetworkRequest r, ServerContext c) {
    if (r.method != 'GET') {
      return NetworkReply.json(const <String, Object?>{}, status: 204);
    }
    switch (r.path) {
      case '/api/system/status':
        return NetworkReply.json({
          'data': {
            'bazarr_version': '1.5.1',
            'sonarr_version': '4.0.9.2244',
            'radarr_version': '5.14.0.9383',
            'operating_system': 'Linux',
          },
        });
      case '/api/badges':
        final followsSonarr = c.profile.bazarrFollows.contains(
          ServiceKey.sonarr,
        );
        return NetworkReply.json({
          'episodes': followsSonarr ? 49 : 0,
          'movies': 8,
          'providers': 0,
          'status': 0,
          'sonarr_signalr': followsSonarr ? 'LIVE' : '',
          'radarr_signalr': 'LIVE',
          'announcements': 0,
        });
      case '/api/system/health':
        return NetworkReply.json({'data': const <Object?>[]});
      case '/api/providers':
        return NetworkReply.json({
          'data': [
            for (final name in const ['opensubtitlescom', 'podnapisi', 'subdl'])
              {'name': name, 'status': 'Good', 'retry': '-'},
          ],
        });
      case '/api/system/languages/profiles':
        return NetworkReply.json(const <Object?>[]);
      case '/api/movies/wanted':
        final rows = [
          {
            'title': WorldTitles.tearsOfSteel.title,
            'radarrId': _tearsOfSteel,
            'missing_subtitles': _german,
            'sceneName': 'Tears.of.Steel.2012.1080p',
          },
        ];
        final ids = _ids(r, 'radarrid[]');
        if (ids == null) return NetworkReply.json({'data': rows, 'total': 8});
        return _rows([
          for (final row in rows)
            if (ids.contains(row['radarrId'])) row,
        ]);
      case '/api/episodes/wanted'
          when !c.profile.bazarrFollows.contains(ServiceKey.sonarr):
        return NetworkReply.json({'data': const <Object?>[], 'total': 0});
      case '/api/episodes/wanted':
        final rows = [
          for (var e = 1; e <= 3; e++)
            {
              'seriesTitle': WorldTitles.cosmosLaundromat.title,
              'episode_number': '2x0$e',
              'episodeTitle': 'Episode $e',
              'sonarrSeriesId': _cosmosLaundromat,
              'sonarrEpisodeId': 1010 + e,
              'missing_subtitles': _italian,
            },
        ];
        // Wanted filters by episode, never by series.
        final ids = _ids(r, 'episodeid[]');
        if (ids == null) return NetworkReply.json({'data': rows, 'total': 49});
        return _rows([
          for (final row in rows)
            if (ids.contains(row['sonarrEpisodeId'])) row,
        ]);
      case '/api/movies/history':
      case '/api/episodes/history':
        return NetworkReply.json({'data': const <Object?>[], 'total': 0});
      // The library as a page, or, by id, the one title a page of the world
      // opens.
      case '/api/movies':
        return _library(r, _movies(), 'radarrid[]', 'radarrId');
      case '/api/series':
        if (!c.profile.bazarrFollows.contains(ServiceKey.sonarr)) {
          return _rows(const []);
        }
        return _library(r, _series(), 'seriesid[]', 'sonarrSeriesId');
      case '/api/episodes':
        // Bazarr refuses this read without an id.
        final ids = _ids(r, 'seriesid[]');
        if (ids == null) {
          return NetworkReply.json(
            'Series or Episode ID not provided',
            status: 404,
          );
        }
        if (!c.profile.bazarrFollows.contains(ServiceKey.sonarr)) {
          return _rows(const []);
        }
        return _rows([
          if (ids.contains(_cosmosLaundromat))
            for (var e = 1; e <= 4; e++)
              {
                'sonarrSeriesId': _cosmosLaundromat,
                'sonarrEpisodeId': 1010 + e,
                'season': 2,
                'episode': e,
                'title': 'Episode $e',
                'monitored': true,
                // English on each; the fourth has its Italian too.
                'subtitles': [
                  {..._english[0], 'path': '/mnt/tank/media/S02E0$e.en.srt'},
                  if (e == 4)
                    {..._italian[0], 'path': '/mnt/tank/media/S02E04.it.srt'},
                ],
                'missing_subtitles': e < 4 ? _italian : const <Object?>[],
              },
          // Night Shift has both languages on all of its four.
          if (ids.contains(_nightShift))
            for (var e = 1; e <= 4; e++)
              {
                'sonarrSeriesId': _nightShift,
                'sonarrEpisodeId': 2010 + e,
                'season': 2,
                'episode': e,
                'title': 'Episode $e',
                'monitored': true,
                'subtitles': [
                  for (final (language, code) in const [
                    (_english, 'en'),
                    (_italian, 'it'),
                  ])
                    {
                      ...language[0],
                      'path':
                          '/mnt/tank/media/series/Night Shift/Season 02/'
                          'Night Shift S02E0$e.$code.srt',
                    },
                ],
                'missing_subtitles': const <Object?>[],
              },
        ]);
    }
    return null;
  }

  /// The Radarr and Sonarr ids Bazarr follows the world's titles under.
  static const _tearsOfSteel = 5;
  static const _cosmosLaundromat = 1;
  static const _nightShift = 2;

  /// The films Bazarr holds subtitles for: the ones the first Radarr has a
  /// file of. Tears of Steel is the one still wanting a language, German, as
  /// the Wanted tab says; the others have theirs.
  List<JsonMap> _movies() => [
    for (final (id, title, languages) in const [
      (3, WorldTitles.coffeeRun, [_english, _italian]),
      (4, WorldTitles.sintel, [_english, _italian, _german]),
      (_tearsOfSteel, WorldTitles.tearsOfSteel, []),
      (6, WorldTitles.elephantsDream, [_english, _italian]),
    ])
      {
        'radarrId': id,
        'title': title.title,
        'sortTitle': title.title.toLowerCase(),
        'year': title.year,
        'path': '/mnt/tank/media/films/${title.title} (${title.year})',
        'monitored': true,
        'profileId': 1,
        'tags': const <Object?>[],
        'missing_subtitles': id == _tearsOfSteel ? _german : const <Object?>[],
        'subtitles': [
          for (final language in languages)
            {
              ...language[0],
              'path':
                  '/mnt/tank/media/films/${title.title} (${title.year})/'
                  '${title.title} (${title.year}).${language[0]['code2']}.srt',
            },
        ],
      },
  ];

  /// The series Bazarr follows through Sonarr: Cosmos Laundromat, three of
  /// whose four episodes still want Italian, and Night Shift, complete.
  List<JsonMap> _series() => [
    for (final (id, title, missing, files) in const [
      (_cosmosLaundromat, WorldTitles.cosmosLaundromat, 3, 4),
      (_nightShift, WorldTitles.nightShift, 0, 4),
    ])
      {
        'sonarrSeriesId': id,
        'title': title.title,
        'sortTitle': title.title.toLowerCase(),
        'year': title.year,
        'path': '/mnt/tank/media/series/${title.title}',
        'monitored': true,
        'profileId': 1,
        'tags': const <Object?>[],
        'episodeMissingCount': missing,
        'episodeFileCount': files,
      },
  ];

  /// [rows] as Bazarr lists a library: the titles whose [idKey] a `name[]`
  /// filter asked for, or, with no filter, a page of `start` and `length`
  /// and the size of the whole.
  static NetworkReply _library(
    NetworkRequest r,
    List<JsonMap> rows,
    String name,
    String idKey,
  ) {
    final ids = _ids(r, name);
    if (ids != null) {
      return _rows([
        for (final row in rows)
          if (ids.contains(row[idKey])) row,
      ]);
    }
    final start = (int.tryParse(r.query['start'] ?? '') ?? 0).clamp(
      0,
      rows.length,
    );
    final length = int.tryParse(r.query['length'] ?? '') ?? rows.length;
    return NetworkReply.json({
      'data': rows.skip(start).take(length < 0 ? rows.length : length).toList(),
      'total': rows.length,
    });
  }

  static const _german = [
    {'name': 'German', 'code2': 'de', 'code3': 'deu'},
  ];
  static const _italian = [
    {'name': 'Italian', 'code2': 'it', 'code3': 'ita'},
  ];
  static const _english = [
    {'name': 'English', 'code2': 'en', 'code3': 'eng'},
  ];

  /// The ids a `name[]` filter asked for, or null when it asked for none.
  static Set<int>? _ids(NetworkRequest r, String name) {
    final values = r.uri.queryParametersAll[name];
    if (values == null || values.isEmpty) return null;
    return {for (final v in values) ?int.tryParse(v)};
  }

  static NetworkReply _rows(List<Map<String, Object?>> rows) =>
      NetworkReply.json({'data': rows, 'total': rows.length});
}

// === Shared builders =======================================================

/// The world's downloads whose arr row lives on the server [c] reached.
List<WorldDownload> arrDownloads(ServerContext c) => [
  for (final d in c.downloads)
    if (d.arr == c.server.id &&
        d.state != DownloadState.seeding &&
        d.state != DownloadState.stopped &&
        (!d.onlyWithClient ||
            c.profile.connections.any((x) => x.service.name == d.client)))
      d,
];

/// One arr queue record for [d], the shape Radarr/Sonarr/Lidarr share.
Map<String, Object?> arrQueueRecord(
  ServerContext c,
  WorldDownload d, {
  required int index,
  required String media,
  Map<String, Object?>? item,
  int? episodeId,
}) {
  final (status, trackedStatus, trackedState, messages) = switch (d.state) {
    DownloadState.stuck => (
      'warning',
      'warning',
      'downloading',
      [
        {
          'title': d.release,
          'messages': ['The download is stalled with no connections'],
        },
      ],
    ),
    DownloadState.queued => ('queued', 'ok', 'downloading', const <Object?>[]),
    // The client, or somebody, paused it; the arr only reports the pause.
    DownloadState.heldByClient ||
    DownloadState.paused => ('paused', 'ok', 'downloading', const <Object?>[]),
    DownloadState.importBlocked => (
      'completed',
      'warning',
      'importBlocked',
      [
        {
          'title': d.release,
          'messages': [WorldDownloads.blockedImportMessage],
        },
      ],
    ),
    _ => ('downloading', 'ok', 'downloading', const <Object?>[]),
  };
  final eta = d.eta;
  return {
    'id': index,
    if (media == 'movie') 'movieId': item?['id'],
    if (media == 'movie' && item != null) 'movie': item,
    if (media == 'series') 'seriesId': item?['id'],
    if (media == 'series' && item != null) 'series': item,
    if (media == 'series' && d.season != null) 'seasonNumber': d.season,
    if (media == 'series' && episodeId != null) 'episodeId': episodeId,
    if (media == 'series' && episodeId != null)
      'episode': {
        'id': episodeId,
        'seriesId': item?['id'],
        'seasonNumber': d.season,
        'episodeNumber': d.episode,
        'title': 'Episode ${d.episode}',
        'hasFile': false,
        'monitored': true,
      },
    'title': d.release,
    'size': d.size,
    'sizeleft': d.sizeLeft,
    if (eta != null) 'timeleft': _clock(eta),
    if (eta != null) 'estimatedCompletionTime': c.ahead(eta),
    'added': c.ago(const Duration(hours: 3, minutes: 20)),
    'status': status,
    'trackedDownloadStatus': trackedStatus,
    'trackedDownloadState': trackedState,
    'statusMessages': messages,
    if (d.state == DownloadState.stuck)
      'errorMessage': 'The download is stalled with no connections',
    // A torrent's hash upper-cased, as the arrs record it; a usenet job's
    // id as its client handed it out.
    'downloadId': _usenet(d) ? d.id : d.id.toUpperCase(),
    'protocol': _usenet(d) ? 'usenet' : 'torrent',
    'downloadClient': switch (d.client) {
      'sabnzbd' => 'SABnzbd',
      'nzbget' => 'NZBGet',
      'transmission' => 'Transmission',
      _ => 'qBittorrent',
    },
    'indexer': _usenet(d) ? 'Atlas NZB' : 'Fjord Tracker',
    'outputPath': '/mnt/tank/downloads/complete/${d.release}',
    'quality': _quality(
      d.release.contains('2160p')
          ? 'Bluray-2160p'
          : d.release.contains('720p')
          ? 'WEBDL-720p'
          : 'WEBDL-1080p',
    ),
    'languages': const [
      {'id': 1, 'name': 'English'},
    ],
    'customFormats': const <Object?>[],
  };
}

bool _usenet(WorldDownload d) => d.client == 'sabnzbd' || d.client == 'nzbget';

/// The quality of a music or book file, which is its format: `FLAC`, `EPUB`.
Map<String, Object?> _format(String name, int id) => {
  'quality': {'id': id, 'name': name},
  'revision': {'version': 1, 'real': 0, 'isRepack': false},
};

Map<String, Object?> _quality(String name) => {
  'quality': {
    'id': 7,
    'name': name,
    'resolution': name.contains('2160')
        ? 2160
        : name.contains('720')
        ? 720
        : 1080,
  },
  'revision': {'version': 1, 'real': 0, 'isRepack': false},
};

String _clock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inHours)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
}
