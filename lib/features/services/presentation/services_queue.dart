import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/status/arr_queue_snapshot.dart';
import 'package:cupola/core/status/media_names.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/arr_model_helpers.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/nzbget/presentation/nzbget_provider.dart';
import 'package:cupola/features/readarr/presentation/readarr_provider.dart';
import 'package:cupola/features/sabnzbd/data/sabnzbd_client.dart';
import 'package:cupola/features/sabnzbd/domain/models/sabnzbd_models.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/movies/data/radarr_service.dart';
import 'package:cupola/features/music/data/lidarr_service.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/qbittorrent/domain/models/torrent.dart';
import 'package:cupola/features/qbittorrent/presentation/qbittorrent_provider.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/services/domain/arr_import.dart';
import 'package:cupola/features/services/domain/download_client_faults.dart';
import 'package:cupola/features/services/domain/download_join.dart';
import 'package:cupola/features/services/domain/download_names.dart';
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/domain/queue_title.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/transmission/presentation/transmission_provider.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/services/presentation/services_history.dart';
import 'package:cupola/features/services/presentation/services_probe.dart';

/// How many in-flight items the hub shows before deferring to `/activity`.
///
/// Raised from three when the provider stopped being Radarr-plus-Sonarr: with
/// seven possible sources, three slots meant a busy usenet queue could hide every
/// torrent on the screen.
const int servicesQueuePreviewLimit = 5;

/// Everything a transfer row prints, per source, in one shape.
///
/// The fields are the row's grammar rather than one service's vocabulary: see
/// `domain/in_flight.dart`. It used to carry a pre-joined `subtitle` composed by
/// each loader in its own words, which is why a Radarr row and a SABnzbd row
/// could not be read down a column: they were two different sentences that
/// happened to be the same length.
class ServiceQueueItem {
  const ServiceQueueItem({
    required this.service,
    required this.title,
    this.subject,
    required this.progress,
    required this.clientLabel,
    this.id = '',
    this.quality,
    this.doneBytes,
    this.totalBytes,
    this.etaSeconds,
    this.fault,
    this.stalledSince,
    this.swarmSeeds,
    this.awaitingMetadata = false,
    this.warning,
    this.clientRateBytesPerSecond,
    this.route,
    this.detail,
    this.downloadId,
    this.clientService,
    this.instanceId = '',
    this.connectionName,
    this.clientInstanceId = '',
    this.mediaId,
    this.outputPath,
    this.category,
    this.held = false,
    this.queued = false,
    this.startsInSeconds,
    this.rateBytesPerSecond,
    this.tmdbId,
    this.tvdbId,
    this.posterUrl,
    this.queueTitle,
    MediaNames? names,
  }) : _names = names;

  final ServiceKey service;

  /// The client's own id for this transfer: a torrent hash, an nzo id, a queue
  /// record id. Keys the row and the decision it can become.
  final String id;

  final String title;

  /// What a sentence calls it, when that is not [title]: `Cupertino S1
  /// E1–E8` for the season pack a row calls `Cupertino · 8 episodes`, which
  /// cannot be the subject of `… needs a manual import`.
  final String? subject;

  /// What a sentence or a spoken label calls it: [subject], or [title].
  String get sentenceTitle => subject ?? title;

  /// Fraction complete, or null when the client did not say. Null is not zero:
  /// a usenet item that has not started reports nothing, and sorting it as 0%
  /// would bury the transfer about to finish.
  final double? progress;

  /// The release's quality, when the source has one. A download client knows the
  /// file size, not the profile the \*arr grabbed it under.
  final String? quality;

  final int? doneBytes;
  final int? totalBytes;
  final int? etaSeconds;

  /// Who is moving the bytes, in words. For an \*arr row this is the download
  /// client named in the queue record: the arr is the one that asked, not the
  /// one that is transferring.
  final String clientLabel;

  /// Why this stopped being a transfer, or null while it still is one. A row
  /// with a fault leaves this region entirely and becomes a decision, which
  /// decision, and so which remedy, is what the value says. See
  /// [InFlightFault].
  final InFlightFault? fault;

  /// When it stopped being a transfer, as near as the source can date it:
  /// qBittorrent's last activity, or the \*arr's `added`. Feeds the decision's
  /// ranking.
  final DateTime? stalledSince;

  /// How many peers with the whole file the trackers know of, on a torrent
  /// client's row (qBittorrent's `num_complete`), or null when the client does
  /// not say. On a stall it picks the remedy: somebody has the file but none
  /// is reachable, so asking the trackers again can help, or nobody has it,
  /// and only another download can ([stuckRemedyFor]).
  final int? swarmSeeds;

  /// Whether the client is still fetching a torrent's file list (qBittorrent's
  /// `metaDL`, a magnet not yet resolved). Nobody has sent even that yet, so
  /// [swarmSeeds] says nothing about this row: its stall is worded as such
  /// ([stuckExplanation]). False on every other row.
  final bool awaitingMetadata;

  /// The source's own message about this row, when there is one.
  final String? warning;

  /// The rate of the **client**, not of this row, carried on every row that
  /// client contributes.
  ///
  /// A byte rate is a countable unit and sums, but only once per client: adding
  /// it per row would multiply one client's throughput by its queue depth. The
  /// eyebrow sums over distinct clients for exactly that reason, and an \*arr
  /// carries none: the bytes it is waiting on are already being counted by the
  /// client that is moving them.
  final int? clientRateBytesPerSecond;

  /// Where the row leads.
  final String? route;

  /// Extra facts a decision row prints that a transfer row does not: seeds, the
  /// current rate, the arr's own warning.
  final String? detail;

  /// The download client's id for the transfer an \*arr row is tracking: the
  /// torrent hash, the SABnzbd `nzo_id`, the NZBGet id. The key
  /// [joinQueueSources] joins an \*arr row to the client row moving the same
  /// bytes on. Null on a client's own row, whose [id] already is that id.
  final String? downloadId;

  /// The connected client moving these bytes: itself on a client's own row,
  /// and on an \*arr row only once [joinQueueSources] has matched it to one.
  ///
  /// What the eyebrow keys the rate on, since an \*arr row that absorbed a
  /// torrent carries the torrent's client rate.
  final ServiceKey? clientService;

  /// The connection the row was read from, for a remedy that opens a flow
  /// bound to one connection (the import wizard's `?i=`) and for a route
  /// into a detail page, whose ids are that server's.
  final String instanceId;

  /// What tells [instanceId] apart from the service's other connections, by
  /// the app's one rule, or null while the service has only the one. On the
  /// row's line, so two Radarr rows say which Radarr.
  final String? connectionName;

  /// The connection of the download client moving these bytes: the row's own
  /// on a client's row, and the client row's on an \*arr row joined to one.
  /// Empty while nothing has said which. What "Open in qBittorrent" opens,
  /// and what the eyebrow keys a client's rate on.
  final String clientInstanceId;

  /// The library item an \*arr row belongs to (the movie, series, artist or
  /// author), which a manual import is filed under. Null when the record names
  /// none, or when several records folded into this row name different ones.
  final int? mediaId;

  /// Where the client is writing, as the \*arr reports it: what a manual
  /// import is seeded from.
  final String? outputPath;

  /// The title's poster, from the movie, series or artist an \*arr record
  /// embeds, when the arr links to one off its own host: what a row on Home
  /// shows beside the title. Null on a client's own row.
  final String? posterUrl;

  /// What the \*arr's record says about the title beyond its name (the year,
  /// the profile, the library folder, the episode): what the download's own
  /// page states. Null on a client's own row, and when the record embeds no
  /// title.
  final QueueTitle? queueTitle;

  final MediaNames? _names;

  /// What the transfer is and which copy it is ([MediaNames]): on an \*arr
  /// row, the arr's item and the release it grabbed, which a row joined to
  /// its client keeps; on a client's own row that no arr claims, its raw
  /// name, until something recognises it. [title] is what the row draws
  /// today; these are what the row is.
  MediaNames get names => _names ?? MediaNames.raw(title);

  /// The download client's category (or Transmission's first label) on a
  /// client's own row: which arr the name can be put to
  /// ([arrForClientCategory]). Null on an \*arr row.
  final String? category;

  /// This row named [names]: everything else as it was.
  ServiceQueueItem withNames(MediaNames names) => ServiceQueueItem(
    service: service,
    title: title,
    subject: subject,
    progress: progress,
    clientLabel: clientLabel,
    id: id,
    quality: quality,
    doneBytes: doneBytes,
    totalBytes: totalBytes,
    etaSeconds: etaSeconds,
    fault: fault,
    stalledSince: stalledSince,
    swarmSeeds: swarmSeeds,
    awaitingMetadata: awaitingMetadata,
    warning: warning,
    clientRateBytesPerSecond: clientRateBytesPerSecond,
    route: route,
    detail: detail,
    downloadId: downloadId,
    clientService: clientService,
    instanceId: instanceId,
    connectionName: connectionName,
    clientInstanceId: clientInstanceId,
    mediaId: mediaId,
    outputPath: outputPath,
    category: category,
    held: held,
    queued: queued,
    startsInSeconds: startsInSeconds,
    rateBytesPerSecond: rateBytesPerSecond,
    tmdbId: tmdbId,
    tvdbId: tvdbId,
    posterUrl: posterUrl,
    queueTitle: queueTitle,
    names: names,
  );

  /// A download somebody stopped on purpose, with bytes still to come:
  /// backlog, not in flight and not a fault, on every client alike. An \*arr
  /// row is held while its record says paused, or while the client row it
  /// joined is held.
  final bool held;

  /// Waiting its turn to download, with bytes still to come: in line at its
  /// client (qBittorrent's `queuedDL`, Transmission's download wait, a
  /// SABnzbd `Queued` job, an NZBGet `QUEUED` group), or an \*arr record
  /// whose `status` is `queued` or `delay`. Not a fault, not held, and not
  /// moving ([isMoving]): it used to be counted as moving, so four transfers
  /// and one that had not started read "5 moving".
  ///
  /// An \*arr row joined to a client row takes the client's word, as it does
  /// for progress.
  final bool queued;

  /// How long until a queued job starts, in seconds, or null when nothing
  /// says. SABnzbd only: it dates each job's finish (`timeleft`, counted
  /// from the head of the queue), so a job starts when the one ahead of it
  /// finishes. The other clients give no estimate.
  final int? startsInSeconds;

  /// The speed of **this** transfer, in bytes a second, or null when the
  /// source says nothing. Distinct from [clientRateBytesPerSecond], the whole
  /// client's: qBittorrent's `dlspeed` and Transmission's `rateDownload` are
  /// per torrent. SABnzbd and NZBGet report a rate for the client only, so
  /// they give it to the one job that is downloading when exactly one is,
  /// and none otherwise. An \*arr row joined to a client row takes the
  /// client row's. Never 0 for a figure nobody took.
  final int? rateBytesPerSecond;

  /// The title's TMDB id on an \*arr row, from the movie Radarr (or the
  /// series Sonarr) embeds in the queue record: what lets a page match a
  /// download to the Seerr request that asked for it. Null on a client's own
  /// row and when the record carries none.
  final int? tmdbId;

  /// The series' TVDB id on a Sonarr row, from the series the queue record
  /// embeds. Null elsewhere and when the record carries none.
  final int? tvdbId;

  /// Whether this transfer is genuinely moving, or waiting to.
  bool get isActive => fault == null && !held;

  /// Whether this transfer is moving now: active, and not waiting its turn.
  bool get isMoving => isActive && !queued;

  /// Whether this row's client dates the last byte it received (qBittorrent,
  /// Transmission), so that its own clock, not a flag, decides a stall.
  bool get measuresIdle =>
      service == ServiceKey.qbittorrent || service == ServiceKey.transmission;
}

/// Everything currently transferring, across every configured source.
///
/// This is the region the old dashboard put *last*, below three browse rails,
/// while sourcing it from Radarr and Sonarr only: so the most time-sensitive
/// thing on a control-room screen was both buried and mostly blind. It now covers
/// the two arr services it always did, plus Lidarr and Readarr, plus the four
/// download clients that actually move the bytes.
///
/// Stalls are **not** filtered out here: they are in the list, flagged, because
/// the decisions region reads the same provider and a second fetch to find the
/// stuck ones would be the same queue asked twice. `servicesInFlightProvider` is
/// the filtered view the region draws.
///
/// Every source is gated on being configured and degrades to `[]` on failure, so
/// one unreachable client cannot empty or block the region. The failure is
/// kept, classified, in [ServicesQueue.coverage]: the rows can do without a dark
/// client, but the count above them cannot count it as zero.
final servicesQueueProvider = FutureProvider<ServicesQueue>((ref) async {
  // Every configured connection of the eight sources, each watched on its own
  // narrow key rather than the whole model. A bare
  // `ref.watch(currentSettingsProvider)` re-ran every queue fetch on every
  // settings write, including a theme-mode toggle, which cannot change a
  // queue.
  //
  // Every connection rather than the lens: Home counts the whole household,
  // the way its header does. A stall on the second Radarr, or a blocked
  // import on it, is the user's as much as one on the first, and reading the
  // lens alone left it off Home with nothing saying so.
  final arrQueues = [
    for (final service in const [
      ServiceKey.radarr,
      ServiceKey.sonarr,
      ServiceKey.lidarr,
      ServiceKey.readarr,
    ])
      for (final source in watchMergeConnections(ref, service))
        _readQueueSource(source, () => _loadServiceQueueItems(ref, source)),
  ];
  final clientQueues = _readDownloadClients(ref);
  final namer = _watchDownloadNamer(ref);
  final results = await Future.wait([...arrQueues, ...clientQueues]);

  // One row per transfer, not one per source that can see it. A Radarr grab
  // moving through qBittorrent is in both queues, and concatenating them drew
  // it twice and counted it twice, and a stall in it became two decisions.
  final joined = joinQueueSources(
    arr: results
        .take(arrQueues.length)
        .expand((result) => result.items)
        .toList(growable: false),
    clients: results
        .skip(arrQueues.length)
        .expand((result) => result.items)
        .toList(growable: false),
  );
  // A client row no arr claims has only its raw name: the arrs are asked to
  // read it, within this read's cap.
  final items = await _nameClientRows(namer, joined);

  // Closest to landing first. An item whose client reports no progress sorts
  // last rather than as zero: unknown is not the same as "just started", and
  // pushing it to the top would bury the transfer that is about to finish.
  //
  // Decorated with the source index because `List.sort` is not guaranteed
  // stable. Without it, several progress-less items (normal for a usenet queue
  // that has not started) could come back in a different order on each build,
  // which reads on screen as rows shuffling for no reason.
  final ordered =
      List.generate(
        items.length,
        (index) => (index: index, item: items[index]),
        growable: false,
      )..sort((a, b) {
        // What waits its turn goes after everything else, in the order its
        // client queues it: a queue's order is the only thing that says
        // which starts next, and a queued torrent's progress says nothing
        // about it.
        if (a.item.queued != b.item.queued) return a.item.queued ? 1 : -1;
        if (a.item.queued) return a.index.compareTo(b.index);
        final progressA = a.item.progress;
        final progressB = b.item.progress;
        if (progressA != progressB) {
          if (progressA == null) return 1;
          if (progressB == null) return -1;
          final byProgress = progressB.compareTo(progressA);
          if (byProgress != 0) return byProgress;
        }
        return a.index.compareTo(b.index);
      });

  return (
    items: ordered.map((entry) => entry.item).toList(growable: false),
    coverage: SourceCoverage.merge(results.map((result) => result.coverage)),
  );
});

/// One source's queue rows, and whether the walk that read them stopped short
/// of the end ([ArrRecordPage.cutShort]).
typedef _QueueRead = ({List<ServiceQueueItem> items, bool cutShort});

/// One connection's queue, read, with whether it answered.
///
/// One connection that fails takes its own rows out and nobody else's, and
/// its failure is kept, classified, so a count over the rest can say what it
/// leaves out.
Future<ServicesQueue> _readQueueSource(
  MergeConnection source,
  Future<_QueueRead> Function() load,
) async {
  try {
    final read = await load();
    return (
      items: read.items,
      // A walk that stopped short answered, with part of its queue: the
      // count over it is a floor.
      coverage: SourceCoverage.answeredBy(
        source.service,
        cutShort: read.cutShort,
        instanceId: source.instanceId,
        name: source.name,
      ),
    );
  } catch (error) {
    return (
      items: const <ServiceQueueItem>[],
      coverage: SourceCoverage.failure(
        source.service,
        error,
        instanceId: source.instanceId,
        name: source.name,
      ),
    );
  }
}

/// Every configured download client connection's own queue, one read each.
///
/// [fresh] asks the lens's connection through its client too, rather than
/// through the list its own page holds and polls. Home shares that list with
/// the page; a surface with a poll of its own (Activity) would read it as it
/// stood whenever the page last ran.
List<Future<ServicesQueue>> _readDownloadClients(
  Ref ref, {
  bool fresh = false,
}) {
  // The clients answer with their whole queue in one read, so there is no
  // walk to stop short.
  Future<_QueueRead> whole(Future<List<ServiceQueueItem>> items) async =>
      (items: await items, cutShort: false);
  MergeConnection asked(MergeConnection source) => fresh
      ? (
          service: source.service,
          instanceId: source.instanceId,
          name: source.name,
          isLens: false,
          connection: source.connection,
        )
      : source;
  return [
    for (final source in watchMergeConnections(ref, ServiceKey.qbittorrent))
      _readQueueSource(
        source,
        () => whole(_loadQbittorrentQueueItems(ref, asked(source))),
      ),
    for (final source in watchMergeConnections(ref, ServiceKey.transmission))
      _readQueueSource(
        source,
        () => whole(_loadTransmissionQueueItems(ref, asked(source))),
      ),
    for (final source in watchMergeConnections(ref, ServiceKey.sabnzbd))
      _readQueueSource(
        source,
        () => whole(_loadSabnzbdQueueItems(ref, asked(source))),
      ),
    for (final source in watchMergeConnections(ref, ServiceKey.nzbget))
      _readQueueSource(
        source,
        () => whole(_loadNzbgetQueueItems(ref, asked(source))),
      ),
  ];
}

/// How many `/parse` requests one read may send.
///
/// A name is put to an arr once and its answer kept ([DownloadNameCache]), so
/// a list of new names is read a few per read rather than all in one burst; a
/// name past the cap keeps its raw form until a later read reaches it.
const int downloadNameParseCap = 6;

/// The arrs' readings of download names, per connection and name, for the
/// life of the app.
///
/// Only answers are kept. A connection that did not answer recognised
/// nothing, and is asked again on the next read.
class DownloadNameCache {
  final Map<String, MediaNames?> _answers = {};

  bool has(String key) => _answers.containsKey(key);

  MediaNames? operator [](String key) => _answers[key];

  void operator []=(String key, MediaNames? names) => _answers[key] = names;
}

final downloadNameCacheProvider = Provider<DownloadNameCache>(
  (ref) => DownloadNameCache(),
);

/// A download to name: the client's id for it, its raw name, its category.
typedef UnnamedDownload = ({String id, String name, String? category});

/// The arrs that can read a download's name, each with its client, and their
/// kept answers.
///
/// Taken at the start of a read, before it awaits anything
/// ([_watchDownloadNamer]), so naming never reaches back into a provider
/// that may have been rebuilt or dropped while its requests were out.
class _DownloadNamer {
  _DownloadNamer(this._cache, this._arrs);

  final DownloadNameCache _cache;
  final Map<
    ServiceKey,
    List<({MergeConnection source, ArrActivityMixin parser})>
  >
  _arrs;

  /// Names [downloads] no arr's queue claims, by asking the arrs to read them
  /// (`parseTitle`), and answers each one's names by its id.
  ///
  /// The arrs asked are the one the client's category points at
  /// ([arrForClientCategory]) when it is set up, every set-up one otherwise,
  /// in [parsingArrs]'s order and each connection in the user's. A library
  /// item from any of them wins; the first parser reading stands otherwise;
  /// with neither, the raw name is the title. At most [cap] requests leave per
  /// call, and every answer is kept, so a name is read once.
  Future<Map<String, MediaNames>> name(
    List<UnnamedDownload> downloads, {
    int cap = downloadNameParseCap,
  }) async {
    if (downloads.isEmpty) return const {};
    var budget = cap;

    Future<MediaNames> read(UnnamedDownload download) async {
      final hint = arrForClientCategory(download.category);
      final asked = hint != null && (_arrs[hint]?.isNotEmpty ?? false)
          ? _arrs[hint]!
          : [for (final service in parsingArrs) ...?_arrs[service]];
      MediaNames? parsed;
      for (final (:source, :parser) in asked) {
        final key = [
          source.service.name,
          source.instanceId,
          source.connection.url,
          download.name,
        ].join('|');
        MediaNames? answer;
        if (_cache.has(key)) {
          answer = _cache[key];
        } else {
          if (budget <= 0) break;
          budget--;
          try {
            final reply = await parser.parseTitle(download.name);
            answer = namesFromParse(source.service, download.name, reply);
            _cache[key] = answer;
          } catch (_) {
            // Silent or refusing: it recognised nothing this time, and is
            // asked again next time.
            continue;
          }
        }
        if (answer?.source == MediaTitleSource.library) return answer!;
        parsed ??= answer;
      }
      return parsed ?? MediaNames.raw(download.name);
    }

    final named = await Future.wait(downloads.map(read));
    return {
      for (final (index, download) in downloads.indexed)
        download.id: named[index],
    };
  }
}

/// The arrs a read may put names to, watched on their narrow keys: call it
/// before the read's first `await`.
_DownloadNamer _watchDownloadNamer(Ref ref) =>
    _DownloadNamer(ref.read(downloadNameCacheProvider), {
      for (final service in parsingArrs)
        service: [
          for (final source in watchMergeConnections(ref, service))
            (source: source, parser: _parserOf(ref, source)),
        ],
    });

ArrActivityMixin _parserOf(
  Ref ref,
  MergeConnection source,
) => switch (source.service) {
  ServiceKey.radarr => ref.watch(radarrServiceForProvider(source.instanceId)),
  ServiceKey.sonarr => ref.watch(sonarrServiceForProvider(source.instanceId)),
  ServiceKey.lidarr => ref.watch(lidarrServiceForProvider(source.instanceId)),
  _ => throw ArgumentError.value(source.service, 'service'),
};

/// [rows] with every client row no arr claims named by the arrs
/// ([_DownloadNamer.name]); the rest as they are.
Future<List<ServiceQueueItem>> _nameClientRows(
  _DownloadNamer namer,
  List<ServiceQueueItem> rows,
) async {
  // Keyed on the connection too: two NZBGet both number their jobs from one.
  String key(ServiceQueueItem row) =>
      '${row.service.name}|${row.clientInstanceId}|${row.id}';
  final unnamed = [
    for (final row in rows)
      if (row.clientService == row.service && row.names.isRaw && !row.held)
        (id: key(row), name: row.title, category: row.category),
  ];
  if (unnamed.isEmpty) return rows;
  final names = await namer.name(unnamed);
  return [
    for (final row in rows)
      if (row.clientService == row.service && names[key(row)] != null)
        row.withNames(names[key(row)]!)
      else
        row,
  ];
}

/// Every download in one client connection's own list, named: the arr's item
/// for a download an arr's queue claims ([joinDownloads], the join In flight
/// and Activity read), the arrs' reading for the rest ([_nameDownloads]),
/// keyed on the client's id for it. Its machine name is the client's own
/// name for it, as the client reported it.
///
/// What the clients' own pages read their rows' names off; the rows keep
/// their look until those pages are redrawn. An arr whose queue does not
/// answer claims nothing, and its downloads are asked about by name instead.
final downloadClientNamesProvider = FutureProvider.autoDispose
    .family<Map<String, MediaNames>, InstanceRef>((ref, client) async {
      // Every read and every watch started before the first await: see
      // [_DownloadNamer].
      final list = _clientList(ref, client);
      final queues = Future.wait([
        for (final service in const [
          ServiceKey.radarr,
          ServiceKey.sonarr,
          ServiceKey.lidarr,
          ServiceKey.readarr,
        ])
          for (final source in watchMergeConnections(ref, service))
            _readQueueSource(source, () => _loadServiceQueueItems(ref, source)),
      ]);
      final namer = _watchDownloadNamer(ref);
      final rows = await list;
      final arrQueues = await queues;
      final join = joinDownloads<ServiceQueueItem, UnnamedDownload>(
        arr: [for (final queue in arrQueues) ...queue.items],
        clients: rows,
        arrDownloadId: (row) => row.downloadId,
        clientDownloadId: (row) => row.id,
      );
      final claimed = <String, MediaNames>{};
      for (final (:arr, :client) in join.joined) {
        if (client == null || claimed.containsKey(client.id)) continue;
        final title = arr.names.title;
        claimed[client.id] = arr.names.isRaw || title == client.name
            ? MediaNames.raw(client.name)
            : MediaNames(
                title: title,
                machineName: client.name,
                machineKind: MachineNameKind.release,
                source: arr.names.source,
              );
      }
      return {...claimed, ...await namer.name(join.unclaimed)};
    }, retry: noProviderRetry);

/// One client connection's whole list, every download in it: the torrent
/// library, the usenet queue.
Future<List<UnnamedDownload>> _clientList(Ref ref, InstanceRef client) async {
  final id = client.instanceId;
  return switch (client.service) {
    ServiceKey.qbittorrent => [
      for (final torrent
          in (await ref.watch(qbittorrentServiceForProvider(id)).mainData())
              .torrents)
        (id: torrent.hash, name: torrent.name, category: torrent.category),
    ],
    ServiceKey.transmission => [
      for (final torrent
          in await ref.watch(transmissionClientForProvider(id)).torrents())
        (
          id: torrent.hashString,
          name: torrent.name,
          category: torrent.labels.firstOrNull,
        ),
    ],
    ServiceKey.sabnzbd => [
      for (final slot
          in (await ref
                  .watch(sabnzbdClientForProvider(id))
                  .getQueue(limit: SabnzbdClient.wholeQueue))
              .slots)
        (id: slot.nzoId, name: slot.filename, category: slot.category),
    ],
    ServiceKey.nzbget => [
      for (final group
          in await ref.watch(nzbgetClientForProvider(id)).listGroups())
        (id: group.downloadId, name: group.name, category: group.category),
    ],
    _ => throw ArgumentError.value(client.service, 'service', 'not a client'),
  };
}

/// Every configured download client's own queue, as transfer rows, and which
/// of the clients answered.
///
/// What a surface outside Home joins its \*arr records against
/// ([joinDownloads]): Activity reads the same four clients, by the same rules
/// (`download_client_faults.dart`), as In flight does. Read fresh, every
/// connection through its own client: see [_readDownloadClients].
Future<ServicesQueue> downloadClientQueues(Ref ref) async {
  final reads = await Future.wait(_readDownloadClients(ref, fresh: true));
  return (
    items: [for (final read in reads) ...read.items],
    coverage: SourceCoverage.merge(reads.map((read) => read.coverage)),
  );
}

/// Every transfer the configured sources reported, and which of them answered.
typedef ServicesQueue = ({
  List<ServiceQueueItem> items,
  SourceCoverage coverage,
});

/// The transfers the IN FLIGHT region draws, and the numbers above them.
///
/// Active only: a faulted transfer is not in flight, it is a decision, and the
/// region says so in a footnote rather than silently showing a different count
/// from the client's own queue.
///
/// [preview] and [activeCount] are two fields because they answer two
/// questions. The rows are capped at [servicesQueuePreviewLimit]; the eyebrow
/// states how many transfers there are, and it used to state it by counting
/// the capped list: thirty downloads read "5 downloading".
///
/// [preview] and [activeCount] are the **moving** rows only: a download
/// waiting its turn is not moving, and is in [queued] instead, in its
/// client's queue order, for the page that says when it starts. [movingCount]
/// is the same figure as [activeCount] under its honest name.
///
/// [coverage] is the queue's: [activeCount] is a count over the sources that
/// answered, and only over them.
typedef ServicesInFlight = ({
  List<ServiceQueueItem> preview,
  int activeCount,
  int movingCount,
  List<ServiceQueueItem> queued,
  List<ServiceQueueItem> faults,
  int held,
  int? rateBytesPerSecond,
  int clients,
  SourceCoverage coverage,
});

final servicesInFlightProvider = FutureProvider<ServicesInFlight>((ref) async {
  final queue = await ref.watch(servicesQueueProvider.future);
  final items = queue.items;
  final moving = items.where((item) => item.isMoving).toList(growable: false);
  final queued = items
      .where((item) => item.isActive && item.queued)
      .toList(growable: false);
  final faults = items
      .where((item) => item.fault != null)
      .toList(growable: false);
  // Paused on purpose: neither moving nor a decision, and counted only so the
  // region does not call a paused queue an empty one.
  final held = items.where((item) => item.fault == null && item.held).length;

  // Summed once per client, never once per row: see
  // [ServiceQueueItem.clientRateBytesPerSecond]. Keyed on the client rather
  // than on the row's service, because an \*arr row that absorbed a torrent
  // carries that torrent's client rate.
  // Keyed on the client's connection too: two qBittorrent are two clients,
  // and keyed on the service alone the second one's rate replaced the
  // first's.
  final rates = <(ServiceKey, String), int>{};
  for (final item in items) {
    final rate = item.clientRateBytesPerSecond;
    final client = item.clientService;
    if (rate != null && client != null) {
      rates[(client, item.clientInstanceId)] = rate;
    }
  }

  return (
    preview: moving.take(servicesQueuePreviewLimit).toList(growable: false),
    activeCount: moving.length,
    movingCount: moving.length,
    queued: queued,
    faults: faults,
    held: held,
    rateBytesPerSecond: rates.isEmpty
        ? null
        : rates.values.fold(0, (sum, rate) => sum + rate),
    clients: rates.length,
    coverage: queue.coverage,
  );
});

/// Joins the \*arr queues to the download-client queues, one row per transfer.
///
/// The match is [joinDownloads], the one Activity's records go through too:
/// an \*arr row names the client's own id for the transfer in `downloadId`.
/// The \*arr row wins: it knows the title, the quality and whether the file
/// can be imported. The client row lends it what only the client measures:
/// progress, bytes, time left, rate, and a stall the \*arr has not noticed
/// yet. A client row no \*arr claims (a torrent added by hand) stays a row of
/// its own.
///
/// Pure and top-level, so the rule is testable without a container.
List<ServiceQueueItem> joinQueueSources({
  required List<ServiceQueueItem> arr,
  required List<ServiceQueueItem> clients,
}) {
  final join = joinDownloads<ServiceQueueItem, ServiceQueueItem>(
    arr: arr,
    clients: clients,
    arrDownloadId: (row) => row.downloadId,
    clientDownloadId: (row) => row.id,
  );
  return [
    for (final (:arr, :client) in join.joined)
      client == null ? arr : _joinedQueueItem(arr, client),
    ...join.unclaimed,
  ];
}

ServiceQueueItem _joinedQueueItem(
  ServiceQueueItem arr,
  ServiceQueueItem client,
) {
  // The \*arr's fault first: an import it refuses is the more specific truth.
  // The client's stall second: the \*arr polls its client on a minute's delay
  // and can still be calling a dead transfer "downloading".
  //
  // Except a stall, where the torrent client measured how long nothing has
  // arrived: the \*arr's "stalled" is the client's own instant flag, read a
  // minute late, and it would raise the fault the 30 minutes hold back.
  final arrStallOverruled =
      arr.fault == InFlightFault.stalled && client.measuresIdle;
  final arrFault = arrStallOverruled ? null : arr.fault;
  final fault = arrFault ?? client.fault;
  final faultFromClient = arrFault == null && client.fault != null;
  // The byte pair travels together: one side's done over the other's total
  // is a figure neither source reported.
  final clientMeasured = client.totalBytes != null;

  return ServiceQueueItem(
    service: arr.service,
    id: arr.id,
    title: arr.title,
    subject: arr.subject,
    progress: client.progress ?? arr.progress,
    clientLabel: arr.clientLabel,
    quality: arr.quality,
    doneBytes: clientMeasured ? client.doneBytes : arr.doneBytes,
    totalBytes: clientMeasured ? client.totalBytes : arr.totalBytes,
    etaSeconds: client.etaSeconds ?? arr.etaSeconds,
    fault: fault,
    stalledSince: faultFromClient ? client.stalledSince : arr.stalledSince,
    swarmSeeds: client.swarmSeeds,
    awaitingMetadata: client.awaitingMetadata,
    // A stall the client overruled takes the \*arr's message with it; one the
    // client confirms keeps it, the more telling of the two.
    warning: arrStallOverruled && fault != InFlightFault.stalled
        ? client.warning
        : arr.warning ?? client.warning,
    clientRateBytesPerSecond: client.clientRateBytesPerSecond,
    route: arr.route,
    detail: faultFromClient ? client.detail : arr.detail,
    downloadId: arr.downloadId,
    clientService: client.clientService,
    instanceId: arr.instanceId,
    connectionName: arr.connectionName,
    clientInstanceId: client.clientInstanceId,
    mediaId: arr.mediaId,
    outputPath: arr.outputPath,
    // The client's word on a pause, which is fresher than the arr's.
    held: fault == null && client.held,
    // And on waiting its turn, as on progress: the arr's `queued` is its
    // minute-old reading of the same client.
    queued: fault == null && !client.held && client.queued,
    startsInSeconds: client.startsInSeconds,
    rateBytesPerSecond: client.rateBytesPerSecond,
    tmdbId: arr.tmdbId,
    tvdbId: arr.tvdbId,
    posterUrl: arr.posterUrl,
    queueTitle: arr.queueTitle,
    // The arr's names, and the release the client is moving when the arr's
    // record did not carry one: a matched row never loses its release name.
    names: arr.names.withMachineName(client.title, MachineNameKind.release),
  );
}

/// Active torrents, and any torrent reporting a fault, as in-flight items.
///
/// Filters to transfers that are genuinely moving or waiting to: a seeding
/// library of four hundred torrents is not "in flight", and unfiltered it would
/// crowd out every other source. A torrent in `error` or `missingFiles` is
/// kept whatever it was doing, as a fault: see [qbittorrentInFlight].
Future<List<ServiceQueueItem>> _loadQbittorrentQueueItems(
  Ref ref,
  MergeConnection source,
) async {
  // The lens's own list is the one the qBittorrent page already holds; any
  // other connection is asked through its own long-lived client.
  //
  // Read, not watched: a watch made the queue (and with it every arr queue
  // read behind it) start again at each three-second tick of the page that
  // owns the list, which on a desktop is a graph that is never paused.
  // `desktopDownloadsPollProvider` and the Home and Activity polls read the
  // group again on their own, slower clocks.
  final torrents = source.isLens
      ? await ref.read(allTorrentsProvider.future)
      : (await ref
                .watch(qbittorrentServiceForProvider(source.instanceId))
                .mainData())
            .torrents;
  final now = ref.watch(stallClockProvider)();
  final read = [
    for (final torrent in torrents)
      if (qbittorrentInFlight(torrent, now: now) case final reading?)
        (torrent: torrent, reading: reading),
  ];

  // The client's rate, summed over what it is actually downloading, and carried
  // on each of its rows.
  final clientRate = read.fold<int>(0, (sum, row) => sum + row.torrent.dlSpeed);

  return [
    for (final (:torrent, :reading) in read)
      ServiceQueueItem(
        service: ServiceKey.qbittorrent,
        id: torrent.hash,
        title: torrent.name,
        progress: torrent.progress.clamp(0, 1).toDouble(),
        // No quality: a torrent client sees a file name, not a profile.
        doneBytes: torrent.downloaded > 0
            ? torrent.downloaded
            : (torrent.size * torrent.progress).round(),
        totalBytes: torrent.size > 0 ? torrent.size : null,
        etaSeconds: _qbEta(torrent.eta),
        // Named when there are two, so a stall says which qBittorrent.
        clientLabel: serviceWithConnection(
          ServiceKey.qbittorrent,
          source.name,
          joiner: ' ',
        ),
        clientService: ServiceKey.qbittorrent,
        instanceId: source.instanceId,
        clientInstanceId: source.instanceId,
        clientRateBytesPerSecond: clientRate,
        // A stall looks identical to a slow download until you notice it has
        // not moved, and a torrent in error looked like nothing at all: it was
        // dropped with the seeding library. Both leave the region as a
        // decision now, each by its own fault.
        fault: reading.fault,
        warning: reading.reason,
        held: reading.held,
        queued: reading.queued,
        // This torrent's own `dlspeed`.
        rateBytesPerSecond: torrent.dlSpeed,
        stalledSince: reading.fault == null
            ? null
            : idleSince(
                lastActivity: torrent.lastActivity,
                added: torrent.addedOn,
              ),
        swarmSeeds: torrent.swarmSeeds < 0 ? null : torrent.swarmSeeds,
        awaitingMetadata: torrent.parsedState == TorrentState.metaDownloading,
        detail: joinDisplayParts([
          formatSpeed(torrent.dlSpeed),
          countedNoun(torrent.seeders, 'seed', 'seeds'),
        ]),
        route: ServiceRoutes.qbittorrentTorrent(torrent.hash),
        category: torrent.category,
      ),
  ];
}

/// Transmission's torrents, as in-flight items: the incoming ones, and any
/// torrent reporting a fault. See [transmissionInFlight] for the rule.
///
/// It used to be no source at all. A Sonarr grab moving through Transmission
/// was drawn off the arr's queue alone, with the arr's minute-old progress and
/// no rate, and a torrent added by hand was not on Home anywhere.
Future<List<ServiceQueueItem>> _loadTransmissionQueueItems(
  Ref ref,
  MergeConnection source,
) async {
  // As qBittorrent: the lens's list is the one the Transmission page holds.
  final torrents = source.isLens
      ? await ref.read(transmissionTorrentsProvider.future)
      : await ref
            .watch(transmissionClientForProvider(source.instanceId))
            .torrents();
  final now = ref.watch(stallClockProvider)();
  final read = [
    for (final torrent in torrents)
      if (transmissionInFlight(torrent, now: now) case final reading?)
        (torrent: torrent, reading: reading),
  ];

  // `rateDownload` is per torrent; the client's rate is their sum, carried on
  // each of its rows and counted once.
  final clientRate = read.fold<int>(
    0,
    (sum, row) => sum + row.torrent.rateDownload,
  );

  return [
    for (final (:torrent, :reading) in read)
      ServiceQueueItem(
        service: ServiceKey.transmission,
        id: torrent.hashString,
        title: torrent.name,
        progress: torrent.progress,
        // `sizeWhenDone` is what this torrent will weigh with its unwanted
        // files skipped, and `leftUntilDone` is measured against it, so the
        // pair is taken together or not at all.
        doneBytes: torrent.sizeWhenDone > 0
            ? torrent.sizeWhenDone - torrent.leftUntilDone
            : null,
        totalBytes: torrent.sizeWhenDone > 0 ? torrent.sizeWhenDone : null,
        // Negative is "not available" (-1) or "unknown" (-2), never a time.
        etaSeconds: torrent.eta < 0 ? null : torrent.eta,
        clientLabel: serviceWithConnection(
          ServiceKey.transmission,
          source.name,
          joiner: ' ',
        ),
        clientService: ServiceKey.transmission,
        instanceId: source.instanceId,
        clientInstanceId: source.instanceId,
        clientRateBytesPerSecond: clientRate,
        fault: reading.fault,
        warning: reading.reason,
        held: reading.held,
        queued: reading.queued,
        // This torrent's own `rateDownload`.
        rateBytesPerSecond: torrent.rateDownload,
        stalledSince: reading.fault == null
            ? null
            : idleSince(
                lastActivity: torrent.activityDate,
                added: torrent.addedDate,
                started: torrent.startDate,
              ),
        detail: joinDisplayParts([
          formatSpeed(torrent.rateDownload),
          countedNoun(torrent.peersSendingToUs, 'peer', 'peers'),
        ]),
        route: ServiceRoutes.forService(ServiceKey.transmission),
        category: torrent.labels.firstOrNull,
      ),
  ];
}

/// qBittorrent's "no estimate" sentinel, in seconds (100 days).
///
/// Printed literally it reads `100 d left`, which is not an estimate: it is the
/// client saying it has none. Mapped to null so the row prints `—`.
const int _qbNoEta = 8640000;

int? _qbEta(int eta) => eta <= 0 || eta >= _qbNoEta ? null : eta;

/// SABnzbd's queue, as in-flight items, with its faults: a job SABnzbd paused
/// itself, and every job of a queue its disk stopped. See
/// [sabnzbdSlotInFlight].
Future<List<ServiceQueueItem>> _loadSabnzbdQueueItems(
  Ref ref,
  MergeConnection source,
) async {
  final queue = source.isLens
      ? await ref.read(sabnzbdQueueProvider.future)
      : await ref
            .watch(sabnzbdClientForProvider(source.instanceId))
            .getQueue(limit: SabnzbdClient.wholeQueue);
  final rate = (queue.kbPerSec * 1024).round();
  const megabyte = 1024 * 1024;
  final stoppedByDisk = sabnzbdQueueStoppedByDisk(queue);

  // A queue somebody paused holds every job in it; one its disk stopped
  // stalls them.
  final pausedOnPurpose = queue.paused && !stoppedByDisk;
  final read = [
    for (final slot in queue.slots)
      (
        slot: slot,
        reading: sabnzbdSlotInFlight(
          slot,
          stoppedByDisk: stoppedByDisk,
          pausedOnPurpose: pausedOnPurpose,
        ),
      ),
  ];

  // When each queued job starts: the finish of the one ahead of it.
  final startsIn = sabnzbdStartsInSeconds([
    for (final slot in queue.slots) parseClockDuration(slot.timeLeft),
  ]);
  // SABnzbd reports one speed, for the whole queue. It is the speed of the
  // job that is downloading when exactly one is, and nobody's otherwise.
  final downloading = [
    for (final (:slot, :reading) in read)
      if (_isMovingSlot(slot, reading)) slot.nzoId,
  ];

  return [
    for (final (index, (:slot, :reading)) in read.indexed)
      ServiceQueueItem(
        service: ServiceKey.sabnzbd,
        id: slot.nzoId,
        title: slot.filename,
        progress: slot.progress,
        // The slot's own `mb` (what the job weighs) and `mbleft` (what is
        // still to come), taken together or not at all: a slot that carried
        // no usable `mb` reads `—`, never a total inferred from the
        // percentage.
        doneBytes: switch (slot.mb) {
          final double total => ((total - slot.mbLeft) * megabyte).round(),
          null => null,
        },
        totalBytes: switch (slot.mb) {
          final double total => (total * megabyte).round(),
          null => null,
        },
        etaSeconds: parseClockDuration(slot.timeLeft),
        clientLabel: serviceWithConnection(
          ServiceKey.sabnzbd,
          source.name,
          joiner: ' ',
        ),
        clientService: ServiceKey.sabnzbd,
        instanceId: source.instanceId,
        clientInstanceId: source.instanceId,
        clientRateBytesPerSecond: rate,
        fault: reading.fault,
        // A job or a queue paused on purpose is stopped *on purpose*, which
        // the tone rule files under neutral: held, not a fault, not a
        // decision, and not in flight. A queue its disk stopped is a fault,
        // and says so.
        held: reading.held,
        queued: reading.queued,
        startsInSeconds: reading.queued ? startsIn[index] : null,
        rateBytesPerSecond:
            downloading.length == 1 && downloading.single == slot.nzoId
            ? rate
            : null,
        warning: reading.reason,
        route: ServiceRoutes.forService(ServiceKey.sabnzbd),
        category: slot.category,
      ),
  ];
}

/// Whether a SABnzbd slot is fetching articles right now: moving by the
/// client's reading, and in the `Downloading` or `Fetching` status.
bool _isMovingSlot(SabnzbdQueueSlot slot, InFlightReading reading) {
  if (reading.fault != null || reading.held || reading.queued) return false;
  final status = slot.status.toLowerCase();
  return status == 'downloading' || status == 'fetching';
}

Future<List<ServiceQueueItem>> _loadNzbgetQueueItems(
  Ref ref,
  MergeConnection source,
) async {
  // The queue and the client's status, side by side: `listgroups` carries no
  // rate at all, and NZBGet reports one only for the whole client, in
  // `status`. Read without it, NZBGet's bytes were the one transfer the
  // eyebrow's sum left out.
  final (groups, status) = source.isLens
      ? await (
          ref.read(nzbgetQueueProvider.future),
          ref.read(nzbgetStatusProvider.future),
        ).wait
      : await (
          ref.watch(nzbgetClientForProvider(source.instanceId)).listGroups(),
          ref.watch(nzbgetClientForProvider(source.instanceId)).status(),
        ).wait;
  const megabyte = 1024 * 1024;
  final stoppedByDisk = nzbgetQueueStoppedByDisk(status, groups);

  final read = [
    for (final group in groups)
      (
        group: group,
        reading: nzbgetGroupInFlight(
          group,
          stoppedByDisk: stoppedByDisk,
          pausedOnPurpose: status.paused && !stoppedByDisk,
        ),
      ),
  ];
  // NZBGet reports one speed, for the whole client. It is the speed of the
  // group that is downloading when exactly one is, and nobody's otherwise.
  // A group being unpacked or repaired reads as moving too, and is not
  // downloading.
  final downloading = [
    for (final (:group, :reading) in read)
      if (reading.fault == null &&
          !reading.held &&
          !reading.queued &&
          group.status.toUpperCase() == 'DOWNLOADING')
        group.nzbId,
  ];

  return read
      .map(
        (row) => ServiceQueueItem(
          service: ServiceKey.nzbget,
          // The key an \*arr row names this job by (its `drone` parameter,
          // else the NZBID), so [joinQueueSources] can meet the two.
          id: row.group.downloadId,
          title: row.group.name,
          progress: row.group.progress,
          // Both sizes are nullable now: NZBGet reporting neither the `*MB`
          // key nor the `*Hi`/`*Lo` pair used to read as zero megabytes, which
          // made an unmeasured job render as a finished one.
          doneBytes: switch ((
            row.group.fileSizeMb,
            row.group.remainingSizeMb,
          )) {
            (final int total, final int left) => (total - left) * megabyte,
            _ => null,
          },
          totalBytes: switch (row.group.fileSizeMb) {
            final int total => total * megabyte,
            _ => null,
          },
          // NZBGet reports a rate for the whole client and none per group, so
          // there is nothing to divide into an estimate. `—`, not a guess.
          etaSeconds: null,
          clientLabel: serviceWithConnection(
            ServiceKey.nzbget,
            source.name,
            joiner: ' ',
          ),
          clientService: ServiceKey.nzbget,
          instanceId: source.instanceId,
          clientInstanceId: source.instanceId,
          clientRateBytesPerSecond: status.downloadRateBytes,
          fault: row.reading.fault,
          warning: row.reading.reason,
          held: row.reading.held,
          queued: row.reading.queued,
          rateBytesPerSecond:
              downloading.length == 1 && downloading.single == row.group.nzbId
              ? status.downloadRateBytes
              : null,
          route: ServiceRoutes.forService(ServiceKey.nzbget),
          category: row.group.category,
        ),
      )
      .toList(growable: false);
}

/// `0:03:21` / `00:03:21.5` → seconds. Null when the source said nothing.
///
/// Shared by the \*arr `timeleft` field and SABnzbd's, which are the same shape
/// for the same reason: both are a .NET/Python duration printed for a human.
int? parseClockDuration(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final parts = raw.split(':');
  if (parts.length != 3) return null;
  final hours = int.tryParse(parts[0]);
  final minutes = int.tryParse(parts[1]);
  final seconds = int.tryParse(parts[2].split('.').first);
  if (hours == null || minutes == null || seconds == null) return null;
  return hours * 3600 + minutes * 60 + seconds;
}

/// One \*arr's queue as in-flight items. Throws when the queue cannot be read:
/// the caller keeps the failure, so a dark arr is named rather than counted as
/// an empty queue.
///
/// Read off the walk's envelope rather than its bare rows, so a walk that
/// stopped on a full page with no total says so: the region counted its rows
/// and stated them as the queue, `200 downloading` for a queue of any length
/// behind a proxy that drops `totalRecords`. The rows are grouped into
/// downloads before they are counted, so the server's record total is never a
/// figure here; a short walk only makes the count a floor.
Future<_QueueRead> _loadServiceQueueItems(
  Ref ref,
  MergeConnection source,
) async {
  // The connection these records come off, stamped on each row so a remedy
  // that opens a flow bound to one connection (the import wizard) opens it on
  // this one, and the row's route opens this server's film, whatever the lens
  // is on by the time the user taps.
  final id = source.instanceId;
  final page = switch (source.service) {
    ServiceKey.radarr =>
      await ref.watch(radarrServiceForProvider(id)).getQueuePage(),
    ServiceKey.sonarr =>
      await ref.watch(sonarrServiceForProvider(id)).getQueuePage(),
    ServiceKey.lidarr =>
      await ref.watch(lidarrServiceForProvider(id)).getQueuePage(),
    ServiceKey.readarr =>
      await ref.watch(readarrServiceForProvider(id)).getQueuePage(),
    // The download clients are not `/queue` shaped and have their own loaders;
    // the rest have no queue at all.
    ServiceKey.seerr ||
    ServiceKey.qbittorrent ||
    ServiceKey.transmission ||
    ServiceKey.bazarr ||
    ServiceKey.truenas ||
    ServiceKey.dockge ||
    ServiceKey.prowlarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.nzbget ||
    ServiceKey.unraid ||
    // A reverse proxy moves no bytes on anyone's behalf; it has nothing to
    // contribute to an in-flight queue.
    ServiceKey.nginxProxyManager ||
    // A media server has no acquisition queue at all. Its live work is
    // outbound playback, which is a different record with different actions
    // and does not belong in a queue row.
    ServiceKey.jellyfin ||
    ServiceKey.plex ||
    ServiceKey.emby ||
    // Tracearr watches playback and moves nothing: no queue of its own.
    ServiceKey.tracearr => const ArrRecordPage(records: [], total: 0),
  };
  final records = page.records.whereType<Map>().map(stringKeyMap);
  return (
    items: [
      for (final download in _groupQueueRecordsByDownload(records))
        _queueItemFromRecords(
          source.service,
          download,
          instanceId: id,
          connectionName: source.name,
        ),
    ],
    cutShort: page.cutShort,
  );
}

/// The records of one \*arr queue, one list per download.
///
/// A season pack is one torrent and **one record per episode** in Sonarr's
/// queue, every one of them carrying the same `downloadId` and the same
/// `size`/`sizeleft` (the torrent's). Drawn a row per record, one transfer
/// read as ten, and "10 downloading" counted episodes rather than downloads.
/// Records with no `downloadId` are each their own download: nothing says
/// otherwise. First-seen order.
List<List<Map<String, dynamic>>> _groupQueueRecordsByDownload(
  Iterable<Map<String, dynamic>> records,
) {
  final groups = <List<Map<String, dynamic>>>[];
  final byDownload = <String, List<Map<String, dynamic>>>{};
  for (final record in records) {
    final id = stringOrNull(record['downloadId'])?.trim().toLowerCase();
    if (id == null || id.isEmpty) {
      groups.add([record]);
      continue;
    }
    final existing = byDownload[id];
    if (existing != null) {
      existing.add(record);
      continue;
    }
    final group = [record];
    byDownload[id] = group;
    groups.add(group);
  }
  return groups;
}

/// Which fault wins when a download's records disagree: the one whose remedy
/// is least likely to clear by itself.
int _faultWeight(InFlightFault? fault) => switch (fault) {
  InFlightFault.needsImport => 3,
  InFlightFault.failed => 2,
  InFlightFault.stalled => 1,
  null => 0,
};

ServiceQueueItem _queueItemFromRecords(
  ServiceKey service,
  List<Map<String, dynamic>> records, {
  required String instanceId,
  String? connectionName,
}) {
  // One download, so its figures are the first record's: every record of a
  // pack reports the pack's size, and summing them would multiply it.
  final typedItem = records.first;
  final title = records.length == 1
      ? joinDisplayParts([
          arrPrimaryMediaTitle(typedItem) ??
              arrReleaseTitle(typedItem) ??
              'Unknown release',
          if (service == ServiceKey.sonarr) arrEpisodeCode(typedItem),
        ])
      : _packTitle(service, records);
  final size = intOrNull(typedItem['size']);
  final left = intOrNull(typedItem['sizeleft']);
  // The release the arr grabbed, the queue record's `title`, as it sent it.
  final release = stringOrNull(typedItem['title']);
  final names = records.length == 1
      ? MediaNames.ofRecord(typedItem, machineName: release)
      : _packNames(service, records, title: title, release: release);

  // The download's fault is its worst record's: one blocked episode is a
  // manual import for the pack.
  InFlightFault? fault;
  Map<String, dynamic> faulted = typedItem;
  for (final record in records) {
    final recordFault = arrQueueFault(record);
    if (_faultWeight(recordFault) > _faultWeight(fault)) {
      fault = recordFault;
      faulted = record;
    }
  }
  final warning =
      stringOrNull(faulted['errorMessage']) ?? arrQueueWarningMessage(faulted);

  final mediaIds = {for (final record in records) _queueMediaId(record)};
  final mediaId = mediaIds.length == 1 ? mediaIds.single : null;
  final held =
      fault == null &&
      ArrQueueEntry.fromQueueItem(typedItem)?.pipeline == MediaPipeline.paused;

  return ServiceQueueItem(
    service: service,
    id: '${intOrNull(typedItem['id']) ?? 0}',
    title: title,
    subject: records.length == 1 ? null : _packSubject(service, records),
    progress: queueProgress(typedItem),
    quality: _queueQualityLabel(typedItem['quality']),
    // Derived from the two figures the record actually carries, and only when
    // both are there: `size - sizeleft` is what has landed. An arr that reports
    // neither prints `—`, never `0`: a transfer nobody could measure has not
    // downloaded nothing.
    doneBytes: size == null || left == null ? null : size - left,
    totalBytes: size,
    etaSeconds: parseClockDuration(stringOrNull(typedItem['timeleft'])),
    // The client moving the bytes, which is the answer the row owes. The arr is
    // the one that asked for them: it is already the row's glyph and accent.
    clientLabel:
        stringOrNull(typedItem['downloadClient']) ??
        _queueTypeLabel(service) ??
        service.title,
    // Classified by what the record *is* (stalled, blocked, failed), and not
    // by whether it carries a warning. "Any warning is a stall" made a finished
    // download the arr could not import into a stalled transfer, with a remedy
    // in the one place that cannot fix it. A record merely carrying a warning
    // while its bytes still move stays in flight.
    fault: fault,
    stalledSince: parseAddedTimestamp(stringOrNull(typedItem['added'])),
    warning: warning,
    detail: warning,
    downloadId: stringOrNull(typedItem['downloadId']),
    instanceId: instanceId,
    connectionName: connectionName,
    mediaId: mediaId,
    outputPath: stringOrNull(typedItem['outputPath']),
    posterUrl: _queuePosterUrl(typedItem),
    queueTitle: QueueTitle.ofRecord(typedItem, single: records.length == 1),
    names: names,
    // The arr's own record of a pause, standing until a client row says
    // otherwise.
    held: held,
    // And of a wait: `queued` or `delay` on every record of the download,
    // standing until a client row says otherwise.
    queued: fault == null && !held && records.every(arrQueueIsQueued),
    // The title's ids, as the record embeds the movie or the series.
    tmdbId: _embeddedId(typedItem, switch (service) {
      ServiceKey.radarr => 'movie',
      ServiceKey.sonarr => 'series',
      _ => null,
    }, 'tmdbId'),
    tvdbId: service == ServiceKey.sonarr
        ? _embeddedId(typedItem, 'series', 'tvdbId')
        : null,
    // With the connection: a queue record's ids are its server's, and the
    // same film id names a different film on the other Radarr.
    route: switch (service) {
      // The title's own page, on this arr's copy, when the record embeds
      // the title; else the way through its id there.
      ServiceKey.radarr => switch (intOrNull(
        mapOrNull(typedItem['movie'])?['tmdbId'],
      )) {
        final tmdbId? when tmdbId > 0 => ServiceRoutes.mediaRoot(
          MediaKey.movie(tmdbId),
          focus: instanceId,
        ),
        _ =>
          intOrNull(typedItem['movieId']) == null
              ? null
              : ServiceRoutes.radarrMovie(
                  intOrNull(typedItem['movieId'])!,
                  instanceId: instanceId,
                ),
      },
      ServiceKey.sonarr => switch (intOrNull(
        mapOrNull(typedItem['series'])?['tmdbId'],
      )) {
        final tmdbId? when tmdbId > 0 => ServiceRoutes.mediaRoot(
          MediaKey.tv(tmdbId),
          focus: instanceId,
        ),
        _ =>
          intOrNull(typedItem['seriesId']) == null
              ? null
              : ServiceRoutes.sonarrSeries(
                  intOrNull(typedItem['seriesId'])!,
                  instanceId: instanceId,
                ),
      },
      ServiceKey.lidarr =>
        intOrNull(typedItem['artistId']) == null
            ? null
            : ServiceRoutes.lidarrArtist(
                intOrNull(typedItem['artistId'])!,
                instanceId: instanceId,
              ),
      _ => ServiceRoutes.forService(service),
    },
  );
}

/// The poster of the title a queue record embeds, when the arr links to one
/// any client can load.
String? _queuePosterUrl(Map<String, dynamic> record) {
  for (final key in const ['movie', 'series', 'artist']) {
    final images = mapOrNull(record[key])?['images'];
    if (images is List) return remotePosterOf(images);
  }
  return null;
}

/// [key] of the movie or series [record] embeds under [embed], or null when
/// the record embeds none, or names no real one (an unmatched download is
/// `0`).
int? _embeddedId(Map<String, dynamic> record, String? embed, String key) {
  if (embed == null) return null;
  final id = intOrNull(mapOrNull(record[embed])?[key]);
  return id == null || id <= 0 ? null : id;
}

/// The library item a queue record belongs to, or null when it names none.
int? _queueMediaId(Map<String, dynamic> record) {
  final id =
      intOrNull(record['movieId']) ??
      intOrNull(record['seriesId']) ??
      intOrNull(record['artistId']) ??
      intOrNull(record['authorId']);
  return id == null || id <= 0 ? null : id;
}

/// `The Boys · 8 episodes`: one row for a download the \*arr filed as several
/// records.
String _packTitle(ServiceKey service, List<Map<String, dynamic>> records) {
  final first = records.first;
  final (name, unit) = switch (service) {
    ServiceKey.sonarr => (arrSeriesTitle(first), 'episodes'),
    ServiceKey.lidarr => (
      arrArtistName(first) ?? arrAlbumTitle(first),
      'albums',
    ),
    ServiceKey.readarr => (
      arrAuthorName(first) ?? arrBookTitle(first),
      'books',
    ),
    _ => (arrMovieTitle(first), 'movies'),
  };
  return joinDisplayParts([
    name ?? arrReleaseTitle(first) ?? 'Unknown release',
    '${records.length} $unit',
  ]);
}

/// A Sonarr pack in a sentence: the series and the episodes its records
/// name, `Cupertino S1 E1–E8`. Null for the other arrs, whose packs' titles
/// already read as a noun, and when the records name no episode.
String? _packSubject(ServiceKey service, List<Map<String, dynamic>> records) {
  if (service != ServiceKey.sonarr) return null;
  final series = arrSeriesTitle(records.first);
  final bySeason = <int, List<int>>{};
  for (final record in records) {
    final episode = mapOrNull(record['episode']);
    final season = intOrNull(
      episode?['seasonNumber'] ?? record['seasonNumber'],
    );
    final number = intOrNull(
      episode?['episodeNumber'] ?? record['episodeNumber'],
    );
    if (season == null || number == null) continue;
    bySeason.putIfAbsent(season, () => []).add(number);
  }
  final runs = episodeRunsLine({
    for (final season in bySeason.keys.toList()..sort())
      season: bySeason[season]!.toSet().toList()..sort(),
  });
  if (series == null || runs == null) return null;
  return '$series $runs';
}

/// A pack's names: `The Boys · 8 episodes` and the pack's release, or the
/// raw release when the records name no series, artist or author.
MediaNames _packNames(
  ServiceKey service,
  List<Map<String, dynamic>> records, {
  required String title,
  required String? release,
}) {
  final first = records.first;
  final named = switch (service) {
    ServiceKey.sonarr => arrSeriesTitle(first),
    ServiceKey.lidarr => arrArtistName(first) ?? arrAlbumTitle(first),
    ServiceKey.readarr => arrAuthorName(first) ?? arrBookTitle(first),
    _ => arrMovieTitle(first),
  };
  if (named == null || release == null || release.trim().isEmpty) {
    return MediaNames.raw(title);
  }
  return MediaNames(
    title: title,
    machineName: release.trim(),
    machineKind: MachineNameKind.release,
  );
}

String? _queueTypeLabel(ServiceKey service) {
  return switch (service) {
    ServiceKey.radarr => 'Movie',
    ServiceKey.sonarr => 'Series',
    ServiceKey.lidarr => 'Music',
    ServiceKey.readarr => 'Book',
    // Nothing for the rest. Only an arr reaches this: the download clients
    // build their own rows, and each already opens with the client's name,
    // which is the whole point of the row: the bytes are coming through this
    // client rather than through an arr, and the media type is in the release
    // name behind it.
    ServiceKey.seerr ||
    ServiceKey.qbittorrent ||
    ServiceKey.transmission ||
    ServiceKey.bazarr ||
    ServiceKey.truenas ||
    ServiceKey.dockge ||
    ServiceKey.prowlarr ||
    ServiceKey.sabnzbd ||
    ServiceKey.nzbget ||
    ServiceKey.unraid ||
    ServiceKey.nginxProxyManager ||
    ServiceKey.jellyfin ||
    ServiceKey.plex ||
    ServiceKey.emby ||
    ServiceKey.tracearr => null,
  };
}

String? _queueQualityLabel(dynamic value) {
  if (value is Map) {
    final quality = mapOrNull(value['quality']);
    return stringOrNull(quality?['name']) ?? stringOrNull(value['name']);
  }

  return stringOrNull(value);
}
