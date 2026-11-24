import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dynamic_map_utils.dart';
import 'package:cupola/core/utils/percent_format.dart';

/// What can be done from a copy's panel, the first one leading.
enum MediaCopyAction {
  /// The arr drops this download, never picks it again, and looks for
  /// another (`blocklistAndRetry`).
  tryAnother('Try another download'),

  /// Stops the download and deletes what arrived; the title stays wanted.
  removeDownload('Remove download'),

  /// The download is done and the arr cannot place it: the import, by hand.
  finishImport('Finish import'),

  /// The arr asks its indexers now and grabs the best it finds.
  automaticSearch('Automatic search'),

  /// The releases, to pick one by hand.
  chooseRelease('Choose a release'),

  /// The arr starts looking for it.
  monitor('Monitor');

  const MediaCopyAction(this.label);

  final String label;
}

/// What a copy that needs something says where the lead stands: a
/// headline, what is happening and why, and what can be done.
class MediaCopyPanel {
  const MediaCopyPanel({
    required this.headline,
    required this.sentence,
    this.tone,
    this.source,
    this.status,
    this.release,
    this.progress,
    this.actions = const [],
    this.consequence,
    this.busy = false,
  });

  /// `In Radarr · searching`, `Stuck at 47%`.
  final String headline;

  /// Amber for a fault with a remedy, red for a download client that does
  /// not answer; null when nothing is wrong.
  final StatusTone? tone;

  /// Who has it, for a download: `Radarr · qBittorrent`.
  final String? source;

  /// What is happening now, in blue: `Radarr asked your indexers at 20:53`.
  final String? status;

  /// Why, and what follows, in a sentence or two.
  final String sentence;

  /// The release the download is, exactly as the arr names it.
  final String? release;

  /// How far the download is, 0 to 1, while it moves.
  final double? progress;

  /// What can be done, the first leading.
  final List<MediaCopyAction> actions;

  /// What the first action does, under it, when it is not obvious.
  final String? consequence;

  /// The arr is working on it: a spinner beside the headline.
  final bool busy;
}

/// The panel of a copy held by the connection called [name], whose state is
/// [status] and which the arr [monitored].
///
/// [record] is the copy's download as the arr's queue lists it, when it has
/// one: it names the release, the client, and how much arrived. [searchedAt]
/// is when a search for it was asked, while that search is queued or running.
///
/// The order is `resolveMediaAction`'s: the download's state first, then
/// whether the arr is looking, then what is on disk.
MediaCopyPanel mediaCopyPanel({
  required String name,
  required MediaStatusInfo status,
  required bool monitored,
  Map<String, dynamic>? record,
  DateTime? searchedAt,
}) {
  final client = stringOrNull(record?['downloadClient']);
  final source = client == null ? name : '$name\u00A0· $client';
  final release = stringOrNull(record?['title']);
  final size = doubleOrNull(record?['size']);
  final left = doubleOrNull(record?['sizeleft']);
  final arrived = size == null || left == null || size <= left
      ? null
      : formatBytes(size - left);
  final percent = status.progressPercent;
  // What the arr said, without the release it names first: the release has
  // its own line.
  final said = switch (status.detail) {
    final String detail
        when release != null && detail.startsWith('$release: ') =>
      detail.substring(release.length + 2),
    final detail => detail,
  };
  // A bare status word is no message: nothing the arr said is quoted then.
  final quoted = switch (said?.trim().toLowerCase()) {
    null || '' || 'warning' || 'error' || 'ok' => null,
    _ => said,
  };
  final says = quoted == null ? '' : ' $name says: $quoted';
  final retry =
      '$name is asked to find another release.'
      '${arrived == null ? ' Downloaded files stay.' : ' The $arrived so far stays.'}';

  switch (status.pipeline) {
    case MediaPipeline.stalled:
      return MediaCopyPanel(
        headline: percent == null
            ? 'Stuck'
            : 'Stuck at ${formatPercent(percent)}',
        tone: StatusTone.warning,
        source: source,
        sentence: 'Nothing is arriving.$says',
        release: release,
        actions: const [
          MediaCopyAction.tryAnother,
          MediaCopyAction.removeDownload,
        ],
        consequence: retry,
      );
    case MediaPipeline.failed:
      return MediaCopyPanel(
        headline: 'Failed',
        tone: StatusTone.warning,
        source: source,
        sentence: "This download won't finish.$says",
        release: release,
        actions: const [
          MediaCopyAction.tryAnother,
          MediaCopyAction.removeDownload,
        ],
        consequence: retry,
      );
    case MediaPipeline.importBlocked:
      return MediaCopyPanel(
        headline: 'Needs a manual import',
        tone: StatusTone.warning,
        source: source,
        sentence: 'The download is done; $name needs a hand importing it.$says',
        release: release,
        actions: const [MediaCopyAction.finishImport],
      );
    case MediaPipeline.clientUnavailable:
      return MediaCopyPanel(
        headline: client == null
            ? 'The download client did not answer'
            : '$client did not answer',
        tone: StatusTone.error,
        source: source,
        sentence: 'Nothing moves until it answers.',
        release: release,
      );
    case MediaPipeline.paused:
      return MediaCopyPanel(
        headline: percent == null
            ? 'Stopped'
            : 'Stopped at ${formatPercent(percent)}',
        source: source,
        sentence:
            'Someone stopped it; nothing moves until the download client starts it again.',
        release: release,
      );
    case MediaPipeline.queued:
      return MediaCopyPanel(
        headline: 'Queued',
        source: source,
        sentence: 'Waiting its turn; nothing has arrived yet.',
        release: release,
      );
    case MediaPipeline.downloading:
      return MediaCopyPanel(
        headline: percent == null
            ? 'Downloading'
            : 'Downloading\u00A0· ${formatPercent(percent)}',
        source: source,
        sentence: '$name imports it when it is done.',
        release: release,
        progress: status.progress,
      );
    case MediaPipeline.importPending:
      return MediaCopyPanel(
        headline: 'Downloaded',
        source: source,
        sentence: '$name imports it on its next pass.',
        release: release,
        busy: true,
      );
    case MediaPipeline.importing:
      return MediaCopyPanel(
        headline: 'Importing',
        source: source,
        sentence: '$name is moving the files into your library.',
        release: release,
        busy: true,
      );
    case null:
      break;
  }

  if (searchedAt != null) {
    return MediaCopyPanel(
      headline: 'In $name\u00A0· searching',
      status: '$name asked your indexers at ${formatClockTime(searchedAt)}',
      sentence:
          '$name grabs the best release it finds and Activity shows it. To '
          'pick one yourself, choose a release.',
      actions: const [MediaCopyAction.chooseRelease],
      busy: true,
    );
  }
  if (!monitored) {
    return MediaCopyPanel(
      headline: 'In $name\u00A0· not monitored',
      sentence: '$name lists it and never looks for it.',
      actions: const [MediaCopyAction.monitor, MediaCopyAction.chooseRelease],
    );
  }
  return switch (status.availability) {
    MediaAvailability.unavailable => MediaCopyPanel(
      headline: 'In $name\u00A0· not out yet',
      sentence: '$name looks for it once it is out.',
    ),
    MediaAvailability.upgradable => MediaCopyPanel(
      headline: 'In $name\u00A0· cutoff unmet',
      sentence:
          'The file is below the quality its profile asks for, so $name keeps '
          'looking.',
      actions: const [
        MediaCopyAction.automaticSearch,
        MediaCopyAction.chooseRelease,
      ],
    ),
    _ => MediaCopyPanel(
      headline: 'In $name\u00A0· missing',
      sentence:
          '$name grabs it when a release turns up. To look now, search; to '
          'pick one yourself, choose a release.',
      actions: const [
        MediaCopyAction.automaticSearch,
        MediaCopyAction.chooseRelease,
      ],
    ),
  };
}
