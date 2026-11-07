/// Accessible strings for the Stream surfaces.
///
/// Pure and Flutter-free, the same discipline as `services_semantics.dart`: a
/// label composed inside a `build` method and asserted in a test is two strings
/// that drift.
///
/// The Stream board needs this more than most screens do. A session card paints
/// three stacked lines whose *visual* order is chosen for scanning: the title
/// first, because that is what the eye looks for, while the useful spoken order
/// is different: who, then what, then the thing you would act on. Reading the card
/// top to bottom aloud produces a comma list with no structure, which is the exact
/// failure `serviceMatrixCellValue` already documents for the matrix cell.
library;

import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/percent_format.dart';

String _join(Iterable<String?> parts) => joinDisplayParts([
  for (final part in parts) part == null ? null : spokenPercents(part),
], separator: ', ');

/// What one session card announces.
///
/// Order is deliberate and differs from the visual order:
///
///  * **[userName] first.** On a household server the first question is whose
///    playback this is, and it is the one fact the visual layout puts *last*
///    (bottom line, beside the device) because the poster and title dominate.
///  * **The cost next**, when there is one. [transcodeReason] is the reason the
///    board exists, so it is spoken before the device and the position rather
///    than after them, where a long title could push it past the point a listener
///    stops attending.
///  * **[bitrateLabel] is spoken as "about"** when nominal, because it is the
///    file's own bitrate rather than measured throughput. Saying a precise-sounding
///    figure would assert something neither server reports.
///
/// [isPaused] is spoken rather than left to the icon: a paused session still holds
/// its transcode, so "paused" and "playing" are materially different states for
/// the operator and a pause glyph is not announced by itself.
String streamSessionValue({
  required String userName,
  required String title,
  required String? subtitle,
  required String playMethodLabel,
  required String? transcodeReason,
  required String deviceLabel,
  required String? progressLabel,
  required String? bitrateLabel,
  required bool bitrateIsNominal,
  required bool isPaused,
  String? serverName,
}) {
  final cost = transcodeReason == null
      ? playMethodLabel
      : '$playMethodLabel, $transcodeReason';
  final rate = bitrateLabel == null
      ? null
      : (bitrateIsNominal ? 'about $bitrateLabel' : bitrateLabel);

  return _join([
    userName,
    isPaused ? 'paused' : null,
    title,
    subtitle,
    cost,
    rate,
    'on $deviceLabel',
    serverName == null ? null : 'from $serverName',
    progressLabel,
  ]);
}

/// The board's own state, when nobody is watching.
///
/// Used **both** on screen and by the screen reader: one string, because this is
/// a state and not a failure, and a visible "Nothing playing" beside a spoken
/// "error" would be two different bug reports. Deliberately not phrased as an
/// absence of content ("No sessions found"): the server is answering, and an idle
/// media server at 3pm on a Tuesday is the normal condition, not an empty state.
const String streamIdleMessage = 'Nobody is watching right now';

/// What one library row announces.
///
/// [lastScannedLabel] is null on Jellyfin, which exposes no per-library scan
/// timestamp: only a global scheduled task. The row simply omits it rather than
/// speaking "unknown", which would imply the server was asked and declined.
///
/// **No item count, on the Overview or in its spoken form** (decision 21): the
/// count is a separate request per library and is paid on the pushed Libraries
/// page. Speaking a figure the visible row does not show would also put the two
/// out of step, which is the failure this file exists to prevent.
String streamLibraryValue({
  required String kindLabel,
  required String? lastScannedLabel,
  required bool isRefreshing,
}) => _join([kindLabel, isRefreshing ? 'scanning now' : lastScannedLabel]);

/// The line under the Overview's *Libraries* header.
///
/// The two facts a single `getLibraries` response can answer for free: how many
/// rooms there are, and whether one of them is being scanned right now. Both are
/// about the shelf rather than about what is on it, which is the line decision
/// 21 draws.
///
/// [scanningName] names the library when exactly one is scanning, because that
/// is the case worth pointing at. Several at once is a full rescan and gets a
/// count instead; naming the first would imply the others are idle.
String streamLibrariesSummary({
  required int total,
  required String? scanningName,
  required int scanningCount,
}) {
  final rooms = '$total ${total == 1 ? 'library' : 'libraries'}';
  if (scanningCount == 0) return rooms;
  if (scanningCount == 1 && scanningName != null && scanningName.isNotEmpty) {
    return '$rooms\u00A0· $scanningName scanning';
  }
  return '$rooms\u00A0· $scanningCount scanning';
}

/// The confirm prompt for stopping someone else's playback.
///
/// Names the person and the title, because this is the one Stream action that
/// interrupts another human being in the house. Both servers only *dispatch* a
/// stop; the client may ignore it, so the copy promises to ask, not to succeed.
String streamStopSessionPrompt({
  required String userName,
  required String title,
}) => 'Ask $userName’s player to stop $title?';
