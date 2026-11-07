/// The words of the Home's Now playing module: who is watching what, on
/// which screen, and how long is left.
///
/// No transcode detail and no bitrate: what a playback costs the server is
/// the media server's page's business. The bar is ink, since watching is not
/// a status.
library;

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';

/// How many sessions the module draws before the way to the server's page.
const nowPlayingRowLimit = 4;

/// `Anna · Sintel`, `Anna · Cosmos Laundromat · S2 E3`: who, and what. The
/// episode's code and not its name, which the series page has.
String nowPlayingTitle(StreamSession session) {
  final code = episodeCodePattern
      .matchAsPrefix(session.subtitle ?? '')
      ?.group(0);
  final who = session.userName.trim();
  return [if (who.isNotEmpty) who, session.title, ?code].join(dotSeparator);
}

/// `Living room TV · 9 min left`, with `Paused` before the time while the
/// player holds it: where, and how long is left. Nothing about when it
/// started, which no server says.
///
/// [via] leads the line for a playback only Tracearr sees (`Plex · through
/// Tracearr`), first because a line that is cut at the end must keep it: it
/// says why the row has no Stop.
String nowPlayingLine(StreamSession session, {String? via}) {
  final remaining = session.remaining;
  return [
    ?via,
    if (session.deviceLabel.trim().isNotEmpty) session.deviceLabel.trim(),
    if (session.isPaused) StateWord.paused.label,
    if (remaining != null) '${formatTimeSpan(remaining)} left',
  ].join(dotSeparator);
}

/// The initial on the row's disc: the first letter of who is watching.
String nowPlayingInitial(StreamSession session) {
  final who = session.userName.trim();
  return who.isEmpty ? '?' : String.fromCharCode(who.runes.first).toUpperCase();
}

/// What Now playing says of the sources that did not answer: the sentence
/// every region says (`coverageFailureSentence`), and, when Tracearr is one of
/// them, what its silence takes out. The media servers' own rows stand, so
/// what is missing is only what Tracearr alone sees: a server Cupola has no
/// connection to. One line, never one for each.
String nowPlayingOfflineSentence(SourceCoverage coverage) {
  final sentence = coverageFailureSentence(coverage);
  if (!coverage.failedServices.contains(ServiceKey.tracearr)) return sentence;
  return '$sentence $nowPlayingTracearrMissing';
}

/// What is not on the list while Tracearr is silent.
const nowPlayingTracearrMissing = 'What only Tracearr sees is not shown.';
