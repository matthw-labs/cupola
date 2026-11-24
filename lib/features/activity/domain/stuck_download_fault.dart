/// The words of a stuck download's card in Needs you: what happened, for how
/// long, which way out comes first, what each way out does, and what the card
/// says once one was taken.
library;

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/activity/domain/activity_download.dart';
import 'package:cupola/features/activity/domain/download_page.dart'
    show downloadClientOf;
import 'package:cupola/features/services/domain/in_flight.dart';
import 'package:cupola/features/services/presentation/services_provider.dart'
    show ServiceQueueItem;
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart'
    show serviceWithConnection;

/// A way out of a stuck download.
enum StuckAction {
  /// The arr drops this download, blocklists it and looks for another.
  tryAnotherDownload,

  /// qBittorrent asks the trackers for peers again; what arrived stays.
  lookForPeers,

  /// The arr stops it and deletes it; the title stays wanted.
  remove,

  /// Out of every count of faults for a day, unless it stops again.
  keepWaiting,

  /// Its client's own page: the one way out where no other is known.
  openClient,
}

/// The ways out a card offers: the one amber fill, then the quieter two.
typedef StuckActions = ({StuckAction primary, List<StuckAction> secondary});

/// The arrs whose queue record a download can be dropped or removed through.
const _arrs = {ServiceKey.radarr, ServiceKey.sonarr, ServiceKey.lidarr};

/// Whether [item] is an arr's queue record, which the arr can drop, blocklist
/// and remove: a transfer no arr asked for is only its client's.
bool hasArrRecord(ServiceQueueItem item) =>
    _arrs.contains(item.service) && (int.tryParse(item.id) ?? 0) > 0;

/// Whether qBittorrent can be asked for peers again for [item]: a torrent of
/// a qBittorrent connection, known by its hash, an \*arr's or one added by
/// hand.
bool canLookForPeers(ServiceQueueItem item) =>
    downloadClientOf(item)?.client == ServiceKey.qbittorrent;

/// The ways out of [item], first the one the trackers point to
/// ([stuckRemedyFor]) where it can be taken.
///
/// A failed download does not move again by waiting, so it is not offered
/// Keep waiting. Remove passes through the arr, never the client alone
/// (ledger A6): a transfer with no arr record has its client's page instead.
StuckActions stuckActionsFor(ServiceQueueItem item) {
  final arr = hasArrRecord(item);
  final peers = canLookForPeers(item);
  if (item.fault == InFlightFault.failed) {
    return arr
        ? (
            primary: StuckAction.tryAnotherDownload,
            secondary: const [StuckAction.remove],
          )
        : (primary: StuckAction.openClient, secondary: const []);
  }
  final remedy = stuckRemedyFor(swarmSeeds: item.swarmSeeds);
  if (peers && (remedy == StuckRemedy.lookForPeers || !arr)) {
    return (
      primary: StuckAction.lookForPeers,
      secondary: [
        if (arr) StuckAction.tryAnotherDownload,
        StuckAction.keepWaiting,
      ],
    );
  }
  if (arr) {
    return (
      primary: StuckAction.tryAnotherDownload,
      secondary: const [StuckAction.remove, StuckAction.keepWaiting],
    );
  }
  return (
    primary: StuckAction.openClient,
    secondary: const [StuckAction.keepWaiting],
  );
}

/// The card's headline: `Big Buck Bunny is stuck at 47%`, `… is stuck` when
/// its client gave no figure, `… failed` when the client gave up on it.
String stuckHeadline(ServiceQueueItem item) {
  if (item.fault == InFlightFault.failed) return '${item.sentenceTitle} failed';
  final percent = item.progress == null
      ? null
      : (item.progress! * 100).floor().clamp(0, 99);
  return percent == null
      ? '${item.sentenceTitle} is stuck'
      : '${item.sentenceTitle} is stuck at ${formatPercent(percent)}';
}

/// How long nothing has arrived, in a sentence's words: `3 hours`,
/// `40 minutes`, `2 days`, `1 hour`. Null when its client did not date it.
String? idleWords(DateTime? since, {required DateTime now}) {
  if (since == null) return null;
  final idle = now.difference(since);
  if (idle.isNegative) return null;
  String count(int n, String one, String many) => '$n ${n == 1 ? one : many}';
  return switch (idle) {
    _ when idle.inDays >= 2 => count(idle.inDays, 'day', 'days'),
    _ when idle.inHours >= 1 => count(idle.inHours, 'hour', 'hours'),
    _ => count(idle.inMinutes, 'minute', 'minutes'),
  };
}

/// The sentence under the headline: how long nothing has arrived, and what
/// the trackers say of the whole file.
///
/// `Nothing has arrived for 3 hours, and nobody sharing it has the whole file
/// any more.` when qBittorrent counts no one with it; `…, though somebody
/// sharing it has the whole file.` when it counts some; the time alone when
/// no client counts. A magnet still fetching its file list
/// ([ServiceQueueItem.awaitingMetadata]) says, whatever the count, that
/// nothing has come, not even the list of its files: nobody has sent that, so
/// the count of whole copies says nothing. A failed download says why, in its
/// client's words when it gave them.
String stuckExplanation(ServiceQueueItem item, {required DateTime now}) {
  if (item.fault == InFlightFault.failed) {
    final reason = item.warning;
    if (reason != null && reason.isNotEmpty) return sentence(reason);
    return '${item.clientLabel.isEmpty ? item.service.title : item.clientLabel}'
        ' gave up on it.';
  }
  final idle = idleWords(item.stalledSince, now: now);
  if (item.awaitingMetadata) {
    return idle == null
        ? 'Nothing is arriving, not even the list of its files.'
        : 'Nothing has arrived for $idle, not even the list of its files.';
  }
  final head = idle == null
      ? 'Nothing is arriving'
      : 'Nothing has arrived for $idle';
  final seeds = item.swarmSeeds;
  if (seeds == null) return '$head.';
  return seeds > 0
      ? '$head, though somebody sharing it has the whole file.'
      : '$head, and nobody sharing it has the whole file any more.';
}

/// [text] as a sentence: its first letter up, a full stop at its end.
String sentence(String text) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) return trimmed;
  final capital = capitalizeFirst(trimmed);
  return RegExp(r'[.!?]$').hasMatch(capital) ? capital : '$capital.';
}

/// What has arrived, as the remedies count it: `1.1 GB`. Null when the
/// client did not say, or nothing has.
String? arrivedBytes(ServiceQueueItem item) {
  final done = item.doneBytes;
  return done == null || done <= 0 ? null : formatBytes(done);
}

/// The arr that asked for [item], by the app's one rule: `Radarr`,
/// `Radarr 4K`.
String arrName(ServiceQueueItem item) =>
    serviceWithConnection(item.service, item.connectionName, joiner: ' ');

/// The client moving [item]'s bytes: `qBittorrent`.
String clientName(ServiceQueueItem item) =>
    item.clientLabel.isEmpty ? item.service.title : item.clientLabel;

/// What a way out is called on its button.
String stuckActionLabel(StuckAction action, ServiceQueueItem item) =>
    switch (action) {
      StuckAction.tryAnotherDownload => 'Try another download',
      StuckAction.lookForPeers => 'Look for peers again',
      StuckAction.remove => 'Remove',
      StuckAction.keepWaiting => 'Keep waiting',
      StuckAction.openClient => 'Open in ${clientName(item)}',
    };

/// What the amber fill does and what happens to the files already downloaded.
String? stuckActionSubtitle(StuckAction action, ServiceQueueItem item) {
  final arrived = arrivedBytes(item);
  return switch (action) {
    StuckAction.tryAnotherDownload =>
      _retryKeepsFiles(item)
          ? '${arrName(item)} is asked to find another release.'
                '${arrived == null ? ' Downloaded files stay.' : ' The $arrived so far stays.'}'
          : '${arrName(item)} drops this one'
                '${arrived == null ? '' : ' ($arrived so far)'}'
                ", won't pick it again, and looks for another.",
    StuckAction.lookForPeers =>
      '${clientName(item)} asks the trackers again.'
          '${arrived == null ? '' : ' The $arrived so far stays.'}',
    StuckAction.remove ||
    StuckAction.keepWaiting ||
    StuckAction.openClient => null,
  };
}

/// The neutral confirmation Remove asks: a title, what it does, its button.
typedef RemoveConfirmation = ({String title, String message, String confirm});

/// `Remove Big Buck Bunny's download?` · `Stops it and deletes the 1.1 GB.
/// Big Buck Bunny stays in your wanted list.` · `Remove download`.
RemoveConfirmation removeConfirmation(ServiceQueueItem item) {
  final arrived = arrivedBytes(item);
  return (
    title: "Remove ${item.sentenceTitle}'s download?",
    message:
        'Stops it and deletes '
        '${arrived == null ? 'what has arrived' : 'the $arrived'}. '
        '${item.sentenceTitle} stays in your wanted list.',
    confirm: 'Remove download',
  );
}

bool _retryKeepsFiles(ServiceQueueItem item) =>
    item.service == ServiceKey.sonarr || item.service == ServiceKey.radarr;

/// What the card says once a way out was taken.
String stuckActionNote(StuckAction action, ServiceQueueItem item) =>
    switch (action) {
      StuckAction.tryAnotherDownload =>
        _retryKeepsFiles(item)
            ? 'Retry requested\u00A0· Downloaded files kept'
            : 'Dropped\u00A0· ${arrName(item)} is looking for another download',
      StuckAction.lookForPeers =>
        'Asked again\u00A0· ${clientName(item)} is looking for peers',
      StuckAction.remove =>
        'Removed\u00A0· ${item.sentenceTitle} stays in your wanted list',
      // Kept waiting says until when: [keptWaitingNote].
      StuckAction.keepWaiting => 'Hidden\u00A0· it comes back if nothing moves',
      StuckAction.openClient => '',
    };

/// The note Keep waiting leaves, with its Undo beside it: `Hidden until
/// tomorrow 20:53 · it comes back if nothing moves`, or `until 08:10` when
/// the day is still today.
String keptWaitingNote(DateTime until, {required DateTime now}) {
  final local = until.toLocal();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final when = day == today
      ? formatClockTime(local)
      : 'tomorrow ${formatClockTime(local)}';
  return 'Hidden until $when\u00A0· it comes back if nothing moves';
}

/// The proof under the release: `Nothing for 3 h · Radarr → qBittorrent`,
/// `Failed · Radarr → qBittorrent`, `Stuck · …` when the client did not date
/// it.
String stuckProof(ServiceQueueItem item, {required DateTime now}) => [
  if (item.fault == InFlightFault.failed)
    StateWord.failed.label
  else if (nothingForWords(item.stalledSince, now: now) case final words?)
    capitalizeFirst(words)
  else
    StateWord.stuck.label,
  downloadRoute(item),
].join(dotSeparator);
