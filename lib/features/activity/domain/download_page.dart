/// The words of one download's own page (`/activity/download?i=&id=`): which
/// download the address names, where it stands, the steps it goes through,
/// and the facts under them.
library;

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/string_utils.dart' show capitalizeFirst;
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/status_badge.dart' show StatusTone;
import 'package:cupola/features/activity/domain/activity_download.dart';
import 'package:cupola/features/activity/domain/stuck_download_fault.dart'
    show arrName, clientName;
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/requests/domain/my_requests.dart'
    show aroundWords;
import 'package:cupola/features/services/domain/download_join.dart'
    show downloadJoinKey;
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/presentation/services_provider.dart'
    show ServiceQueueItem;
import 'package:cupola/features/settings/domain/service_key.dart';

/// The download [item] is across reads, as the page's address names it: the
/// client's id for the transfer (the torrent hash, the usenet job's id) when
/// the \*arr's record carries one, which the client's own row shares; else
/// the row's own id.
String downloadPageKey(ServiceQueueItem item) =>
    switch (item.downloadId?.trim()) {
      final id? when id.isNotEmpty => id,
      _ => item.id,
    };

/// The download among [items] the address `?i=[instanceId]&id=[key]` names,
/// or null when none is in the queue any more.
///
/// The connection may be the \*arr's or the client's: a link made while no
/// \*arr claimed a torrent still finds it once one does. An empty
/// [instanceId] is any connection.
ServiceQueueItem? downloadAt(
  Iterable<ServiceQueueItem> items, {
  required String instanceId,
  required String key,
}) {
  final wanted = downloadJoinKey(key);
  if (wanted.isEmpty) return null;
  ServiceQueueItem? claimed;
  for (final item in items) {
    final same =
        downloadJoinKey(downloadPageKey(item)) == wanted ||
        downloadJoinKey(item.id) == wanted;
    if (!same) continue;
    if (instanceId.isEmpty || item.instanceId == instanceId) return item;
    if (item.clientInstanceId == instanceId) claimed ??= item;
  }
  return claimed;
}

/// Where a download stands, as its page says it.
enum DownloadStand {
  downloading,
  queued,

  /// Somebody stopped it on purpose: the backlog's neutral, not a fault.
  stopped,
  stuck,
  failed,

  /// Finished, and the \*arr would not import it on its own.
  needsImport,
}

/// Where [item] stands; [held] is a Stop or a Resume just sent, standing
/// until the queue says the same.
DownloadStand downloadStandOf(ServiceQueueItem item, {bool? held}) =>
    switch (item.fault) {
      InFlightFault.needsImport => DownloadStand.needsImport,
      InFlightFault.failed => DownloadStand.failed,
      InFlightFault.stalled => DownloadStand.stuck,
      null when held ?? item.held => DownloadStand.stopped,
      null when item.queued => DownloadStand.queued,
      null => DownloadStand.downloading,
    };

/// The word beside the big percentage: `Downloading`, `Queued`, `Stopped`,
/// `Stuck`, `Failed`, `Needs you`.
String downloadStandWord(DownloadStand stand) => switch (stand) {
  DownloadStand.downloading => 'Downloading',
  DownloadStand.queued => 'Queued',
  DownloadStand.stopped => StateWord.stopped.label,
  DownloadStand.stuck => StateWord.stuck.label,
  DownloadStand.failed => StateWord.failed.label,
  DownloadStand.needsImport => StateWord.needsYou.label,
};

/// Its tone: blue while it moves or waits its turn, neutral when stopped on
/// purpose, amber for a fault.
StatusTone downloadStandTone(DownloadStand stand) => switch (stand) {
  DownloadStand.downloading || DownloadStand.queued => StatusTone.info,
  DownloadStand.stopped => StatusTone.neutral,
  DownloadStand.stuck ||
  DownloadStand.failed ||
  DownloadStand.needsImport => StatusTone.warning,
};

/// The big figure: `62%`, never `100%` before the whole file is there
/// ([formatPercent]). Null when the client gave none.
String? downloadPercent(ServiceQueueItem item) {
  final progress = item.progress;
  if (progress == null) return null;
  return formatPercent(progress * 100);
}

/// What has arrived of the whole: `1.1 GB of 2 GB`. Null when the client did
/// not measure both.
String? arrivedOfTotal(ServiceQueueItem item) {
  final done = item.doneBytes;
  final total = item.totalBytes;
  if (done == null || total == null || total <= 0) return null;
  return formatBytesOfTotal(done.clamp(0, total), total);
}

/// The line under the figure: `4.2 MB/s · 11 min left · ready around 21:10`
/// while it moves; `Starts in about 6 min` in line; `1.1 GB of 2 GB arrived`
/// when stopped (`1.1 GB arrived` when the total is not known); `Nothing for
/// 3 h` when stuck. Null when nothing is known.
String? downloadPaceLine(
  ServiceQueueItem item, {
  required DateTime now,
  bool? held,
}) {
  switch (downloadStandOf(item, held: held)) {
    case DownloadStand.downloading:
      final rate = item.rateBytesPerSecond;
      final eta = item.etaSeconds;
      final parts = [
        if (rate != null) formatBytesPerSecond(rate),
        if (eta != null && eta > 0) ...[
          '${formatTimeSpan(Duration(seconds: eta))} left',
          'ready around ${aroundWords(now.add(Duration(seconds: eta)), now: now)}',
        ],
      ];
      if (parts.isNotEmpty) return parts.join(dotSeparator);
      return switch (arrivedOfTotal(item)) {
        final arrived? => '$arrived arrived',
        null => null,
      };
    case DownloadStand.queued:
      final starts = item.startsInSeconds;
      return starts == null || starts <= 0
          ? 'Waits its turn in ${clientName(item)}'
          : 'Starts in about ${formatTimeSpan(Duration(seconds: starts))}';
    case DownloadStand.stopped:
      return _arrivedLine(item);
    case DownloadStand.stuck:
      final words = nothingForWords(item.stalledSince, now: now);
      return words == null ? null : capitalizeFirst(words);
    case DownloadStand.failed || DownloadStand.needsImport:
      return null;
  }
}

/// What a stopped download says of its bytes: `1.1 GB of 2 GB arrived` when
/// the total is known too, `1.1 GB arrived` when it is not. Null when nothing
/// has arrived, or the client did not say how much.
String? _arrivedLine(ServiceQueueItem item) {
  final done = item.doneBytes;
  if (done == null || done <= 0) return null;
  return switch (arrivedOfTotal(item)) {
    final arrived? => '$arrived arrived',
    null => '${formatBytes(done)} arrived',
  };
}

/// The line under the title: `2021 · out on digital today · Anna asked for
/// it`, `S2 E4 · The Second Cycle · Anna asked for it`. Empty when nothing
/// is known.
String downloadMetaLine(
  ServiceQueueItem item, {
  SeerrRequest? request,
  required DateTime now,
}) {
  final title = item.queueTitle;
  final who = request?.requestedBy?.displayName.trim();
  return [
    if (title?.episode case final episode?)
      episode
    else if (title?.year case final year?)
      '$year',
    if (title != null && item.service == ServiceKey.radarr)
      ?_outToday(
        inCinemas: title.inCinemas,
        digital: title.digitalRelease,
        disc: title.physicalRelease,
        now: now,
      ),
    if (who != null && who.isNotEmpty) '$who asked for it',
  ].join(dotSeparator);
}

/// `out on digital today`, `in cinemas today`, `out on disc today`, for the
/// release dated today; null when none is.
String? _outToday({
  DateTime? inCinemas,
  DateTime? digital,
  DateTime? disc,
  required DateTime now,
}) {
  bool today(DateTime? date) =>
      date != null &&
      date.year == now.year &&
      date.month == now.month &&
      date.day == now.day;
  if (today(digital)) return 'out ${Lexicon.onDigital} today';
  if (today(disc)) return 'out ${Lexicon.onDisc} today';
  if (today(inCinemas)) return '${Lexicon.inCinemas} today';
  return null;
}

/// How far a step of a download has come.
enum DownloadStepState {
  done,

  /// The step it is on now.
  now,

  /// The step it is on, stopped there on purpose.
  stopped,

  /// A step still to come.
  later,

  /// The step it stopped on, with a fault.
  fault,
}

/// One step of the way: `Grabbed` · `Radarr → qBittorrent`.
typedef DownloadStep = ({String name, String detail, DownloadStepState state});

/// The arrs whose downloads go through every step.
const _arrs = {
  ServiceKey.radarr,
  ServiceKey.sonarr,
  ServiceKey.lidarr,
  ServiceKey.readarr,
};

/// The media servers a step may name, in the order the app prefers them
/// (registry order).
final downloadPlayers = mediaServers;

/// The way from the grab to the server: `Grabbed` (`Radarr → qBittorrent`),
/// `Downloading` (`qBittorrent · 62%`), `Import` (`Radarr, when it
/// finishes`), and `On Jellyfin` (`around 21:10`) when [player] is set up to
/// play it. A transfer no \*arr asked for has none: its one step is its own.
List<DownloadStep> downloadStepsOf(
  ServiceQueueItem item, {
  ServiceKey? player,
  required DateTime now,
  bool? held,
}) {
  if (!_arrs.contains(item.service)) return const [];
  final arr = arrName(item);
  final client = clientName(item);
  final stand = downloadStandOf(item, held: held);
  final percent = downloadPercent(item);
  final at = percent == null ? '' : ' at $percent';
  final download = switch (stand) {
    DownloadStand.downloading => (
      name: 'Downloading',
      detail: percent == null ? client : '$client\u00A0· $percent',
      state: DownloadStepState.now,
    ),
    DownloadStand.queued => (
      name: 'Downloading',
      detail: '$client\u00A0· queued',
      state: DownloadStepState.now,
    ),
    DownloadStand.stopped => (
      name: 'Downloading',
      // No figure: the readout above says `62% Stopped`, and the longer
      // detail wrapped and moved the page under the finger that stopped it.
      detail: '$client\u00A0· stopped',
      state: DownloadStepState.stopped,
    ),
    DownloadStand.stuck => (
      name: 'Downloading',
      detail: '$client\u00A0· stuck$at',
      state: DownloadStepState.fault,
    ),
    DownloadStand.failed => (
      name: 'Downloading',
      detail: '$client\u00A0· failed',
      state: DownloadStepState.fault,
    ),
    DownloadStand.needsImport => (
      name: 'Downloaded',
      detail: client,
      state: DownloadStepState.done,
    ),
  };
  final import = stand == DownloadStand.needsImport
      ? (
          name: 'Import',
          detail: '$arr needs you',
          state: DownloadStepState.fault,
        )
      : (
          name: 'Import',
          detail: '$arr, when it finishes',
          state: DownloadStepState.later,
        );
  final eta = item.etaSeconds;
  final plays = player != null && item.service != ServiceKey.readarr;
  return [
    (
      name: 'Grabbed',
      detail: downloadRoute(item),
      state: DownloadStepState.done,
    ),
    download,
    import,
    if (plays)
      (
        name: 'On ${player.title}',
        detail: stand == DownloadStand.downloading && eta != null && eta > 0
            ? 'around ${aroundWords(now.add(Duration(seconds: eta)), now: now)}'
            : 'once imported',
        state: DownloadStepState.later,
      ),
  ];
}

/// One fact under the steps: `Release` · `Sprite.Fright.2021.1080p.WEB`.
/// A [machine] value is a machine's string, drawn in the mono face; an
/// [address] follows the value, in the mono face alone (`qBittorrent` ·
/// `nas.home.arpa:8080`).
typedef DownloadFact = ({
  String label,
  String value,
  bool machine,
  String? address,
});

/// Release, Profile, Folder and Client, each where it is known: the profile
/// with the \*arr that holds it (`HD-1080p · Radarr`), the client with its
/// address (`qBittorrent · nas.home.arpa:8080`).
List<DownloadFact> downloadFactsOf(
  ServiceQueueItem item, {
  String? profile,
  String? clientAddress,
}) {
  final release = item.names.machineName;
  final folder = item.queueTitle?.folder;
  final client = clientName(item);
  return [
    if (release != null && release.isNotEmpty && release != item.title)
      (label: 'Release', value: release, machine: true, address: null),
    if (profile != null && profile.trim().isNotEmpty)
      (
        label: 'Profile',
        value: '${profile.trim()}\u00A0· ${arrName(item)}',
        machine: false,
        address: null,
      ),
    if (folder != null)
      (label: 'Folder', value: folder, machine: true, address: null),
    (label: 'Client', value: client, machine: false, address: clientAddress),
  ];
}

/// Where a connection is reached, as the facts say it: `nas.home.arpa:8080`.
/// Null for an address that does not parse.
String? connectionAddress(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || uri.host.isEmpty) return null;
  return uri.hasPort ? '${uri.host}:${uri.port}' : uri.host;
}

/// The client moving [item]'s bytes, its connection and its own id for the
/// transfer: what Stop and Resume are sent to. Null when no connected client
/// is: an \*arr row its client was not matched to cannot be stopped from
/// here.
typedef DownloadClientHandle = ({
  ServiceKey client,
  String instanceId,
  String id,
});

const _clients = {
  ServiceKey.qbittorrent,
  ServiceKey.transmission,
  ServiceKey.sabnzbd,
  ServiceKey.nzbget,
};

DownloadClientHandle? downloadClientOf(ServiceQueueItem item) {
  final own = _clients.contains(item.service);
  final client = own ? item.service : item.clientService;
  if (client == null || !_clients.contains(client)) return null;
  final instanceId = own ? item.instanceId : item.clientInstanceId;
  final raw = (own ? item.id : item.downloadId)?.trim();
  if (raw == null || raw.isEmpty) return null;
  // A torrent's hash in the case its client reads it; an \*arr records it
  // upper-cased.
  final id =
      client == ServiceKey.qbittorrent || client == ServiceKey.transmission
      ? raw.toLowerCase()
      : raw;
  return (client: client, instanceId: instanceId, id: id);
}

/// Whether Stop (or, once stopped, Resume) is offered: a connected client
/// moves it, and it has not finished or failed.
bool canStopDownload(ServiceQueueItem item) =>
    downloadClientOf(item) != null &&
    item.fault != InFlightFault.needsImport &&
    item.fault != InFlightFault.failed;

/// `since you opened this · 4 min`: how long the speed has been watched.
String rateTraceCaption(Duration watched) => watched.inMinutes < 1
    ? 'since you opened this'
    : 'since you opened this\u00A0· ${withUnit(watched.inMinutes, 'min')}';

/// One reading of a download's speed, taken when the queue was read.
typedef RateSample = ({DateTime at, int bytesPerSecond});

/// The most readings a page keeps: an hour at Activity's pace.
const rateTraceLength = 240;

/// [trace] with [item]'s speed at [at] after it, while it moves and its
/// client measures it; [trace] as it was otherwise. The oldest reading goes
/// past [rateTraceLength].
List<RateSample> withRateSample(
  List<RateSample> trace,
  ServiceQueueItem? item, {
  required DateTime at,
}) {
  final rate = item?.rateBytesPerSecond;
  if (item == null || rate == null || !item.isMoving) return trace;
  final next = [...trace, (at: at, bytesPerSecond: rate)];
  return next.length > rateTraceLength
      ? next.sublist(next.length - rateTraceLength)
      : next;
}
