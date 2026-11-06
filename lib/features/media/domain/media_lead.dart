import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/media/domain/media_copies.dart';
import 'package:cupola/features/media/domain/media_reading.dart';
import 'package:cupola/features/media/domain/operator_adds_via.dart';
import 'package:cupola/features/media/domain/media_rows.dart';
import 'package:cupola/features/media/domain/media_series.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';

/// The one action that leads a Media page, decided from its rows.
///
/// One decision for every page and both audiences: it replaces the two that
/// a title had before, `resolveMediaAction` for the arr pages and an `if` in
/// the Seerr page's buttons. A copy that needs something still names its own
/// action through `resolveMediaAction` ([MediaLeadCopy]); this decides which
/// copy, or whether something else leads.
sealed class MediaLead {
  const MediaLead();
}

/// A source that could outrank whatever would lead now has not answered: the
/// slot keeps its place, so the lead never flips from Trailer to Play.
final class MediaLeadWaiting extends MediaLead {
  const MediaLeadWaiting();
}

/// Play, or resume, on the media server that holds a verified copy.
final class MediaLeadPlay extends MediaLead {
  const MediaLeadPlay(this.server, this.item, {this.episode});

  final ServiceInstance server;
  final StreamItem item;

  /// For a series, the episode Play opens (`mediaNextEpisode`): null for a
  /// movie, and when every episode is watched or none could be read.
  final StreamItem? episode;

  /// The viewer is partway in: `Resume`.
  bool get resume => (episode ?? item).isInProgress;
}

/// The operator's arr is set up and none of its connections holds the title:
/// add it.
final class MediaLeadAdd extends MediaLead {
  const MediaLeadAdd(this.arr, {this.alternative});

  /// Radarr for a film, Sonarr for a series.
  final ServiceKey arr;

  /// The other way the add sheet may offer: the operator's Seerr, which takes
  /// the request instead. Null when there is no Seerr to ask, or when it may
  /// not ask for this kind.
  final ServiceInstance? alternative;
}

/// Ask for the title through [seerr]: the requester always, and an operator
/// whose arr is not set up in Cupola while Seerr is (F-person-add), or who
/// chose to go through Seerr.
final class MediaLeadRequest extends MediaLead {
  const MediaLeadRequest(this.seerr, {this.alternative});

  final ServiceInstance seerr;

  /// The other way the request sheet may offer: the arr the operator can add
  /// the title to straight away. Null when no arr is set up for the kind.
  final ServiceKey? alternative;
}

/// A copy that needs something leads with its own action
/// (`resolveMediaAction` on [status]): the one the page was opened on, or the
/// first that is not on disk.
final class MediaLeadCopy extends MediaLead {
  const MediaLeadCopy(this.connection, this.status);

  final ServiceInstance connection;
  final MediaStatusInfo status;
}

/// The operator has no media server in Cupola, and Seerr says the title is
/// on the one it is set up with: Seerr's link opens it there (rule 9), as it
/// does for the requester.
final class MediaLeadWatch extends MediaLead {
  const MediaLeadWatch(this.claim);

  final MediaServerThroughSeerrRow claim;

  /// Jellyfin, Plex or Emby: a claim leads only once Seerr has named its server.
  ServiceKey get server => claim.server!;
  Uri get url => claim.url;
}

/// Nothing to play and nothing to do: Seerr's trailer leads.
final class MediaLeadTrailer extends MediaLead {
  const MediaLeadTrailer();
}

/// Nothing leads: the rows carry the page.
final class MediaLeadNone extends MediaLead {
  const MediaLeadNone();
}

/// The lead of a page with [rows], for [audience].
///
/// In order: a verified copy on a media server plays (rule 7: an unverified
/// one never does); the requester asks for anything else; the operator adds a
/// title nobody holds, or asks for it through Seerr, as [addsVia] chooses, or
/// follows the movie copy that needs something, [focus] first (the
/// connection the page was opened from), or opens the title through Seerr's
/// link where Cupola has no media server; then the trailer; then nothing. A
/// connection that did not answer is never read as one that holds nothing: no
/// Add while an arr is silent, though a Seerr that answered can still be
/// asked.
///
/// [seerrMayRequest] says whether a Seerr that has answered can take a request
/// for this title's kind now: its account may ask, and it has a server to send
/// it to. Null while that is not known yet, which holds the lead when the
/// operator goes through Seerr, so the lead does not flip to Add and back.
/// Absent, every answered Seerr may request.
MediaLead resolveMediaLead(
  List<MediaRow> rows, {
  required Audience audience,
  String? focus,
  OperatorAddsVia addsVia = OperatorAddsVia.seerr,
  bool? Function(ServiceInstance seerr)? seerrMayRequest,
}) {
  final streams = rows.whereType<MediaConnectionRow<MediaStreamCopy>>();
  if (streams.any((row) => row.reading is MediaReadingWaiting)) {
    return const MediaLeadWaiting();
  }
  final found = [
    for (final row in streams)
      if (row.reading case MediaReadingAnswered(
        :final answer,
      ) when answer.value.outcome == StreamLookupOutcome.found)
        MediaLeadPlay(
          row.connection,
          answer.value.item!,
          episode: switch (answer.value.episodes) {
            final episodes? => mediaNextEpisode(episodes),
            null => null,
          },
        ),
  ];
  if (found.isNotEmpty) {
    return found.where((play) => play.resume).firstOrNull ?? found.first;
  }

  final seerrs = rows.whereType<MediaConnectionRow<MediaSeerrRecord>>();
  if (audience == Audience.requester) {
    final seerr = seerrs.firstOrNull;
    return seerr == null
        ? const MediaLeadNone()
        : MediaLeadRequest(seerr.connection);
  }

  final copies = [
    for (final row in rows)
      if (row
          case MediaConnectionRow<MediaRadarrCopy>() ||
              MediaConnectionRow<MediaSonarrCopy>())
        row as MediaConnectionRow,
  ];
  if (copies.any((row) => row.reading is MediaReadingWaiting)) {
    return const MediaLeadWaiting();
  }
  final tracked = [
    for (final row in copies)
      if (_statusOf(row) case final status?) (row: row, status: status),
  ];
  if (tracked.isEmpty) {
    final allAnswered = copies.every(
      (row) => row.reading is MediaReadingAnswered,
    );
    if (copies.isNotEmpty && allAnswered) {
      return _operatorAdds(
        copies.first.service,
        seerrs.firstOrNull,
        addsVia: addsVia,
        seerrMayRequest: seerrMayRequest,
      );
    }
    if (copies.isEmpty && seerrs.isNotEmpty) {
      return MediaLeadRequest(seerrs.first.connection);
    }
    // An arr that did not answer may hold the title, so nothing is added to
    // it; but a Seerr that answered speaks for its own copy, and asking it
    // stays open whichever way the operator adds (Matt, 12/10).
    if (copies.isNotEmpty && !allAnswered) {
      if (seerrs.firstOrNull case final seerr?
          when seerr.reading is MediaReadingAnswered) {
        final may = seerrMayRequest == null
            ? true
            : seerrMayRequest(seerr.connection);
        if (may == null) return const MediaLeadWaiting();
        if (may) return MediaLeadRequest(seerr.connection);
      }
    }
  } else {
    // A series' copy never leads: its rows say what is downloading and
    // missing, and its searches are its episodes'.
    final needing = tracked.where(
      (copy) =>
          copy.row.service == ServiceKey.radarr &&
          copy.status.availability != MediaAvailability.available,
    );
    final lead =
        needing.where((copy) => copy.row.connection.id == focus).firstOrNull ??
        needing.firstOrNull;
    if (lead != null) return MediaLeadCopy(lead.row.connection, lead.status);
  }

  if (seerrs.any((row) => row.reading is MediaReadingWaiting)) {
    return const MediaLeadWaiting();
  }
  if (rows.whereType<MediaServerThroughSeerrRow>().firstOrNull
      case final claim?) {
    return claim.server == null
        ? const MediaLeadWaiting()
        : MediaLeadWatch(claim);
  }
  final trailer = seerrs.any(
    (row) => switch (row.reading) {
      MediaReadingAnswered(:final answer) => answer.value.hasTrailer,
      _ => false,
    },
  );
  return trailer ? const MediaLeadTrailer() : const MediaLeadNone();
}

/// What the operator leads with on a title no arr connection holds, once every
/// arr has answered: the request through Seerr, or the add to [arr].
///
/// Through Seerr, the lead waits for a Seerr that has not answered and for the
/// answer on whether it may request, so it does not flip to Add and back. A
/// Seerr that failed, or that may not request this kind, leads with the add.
/// The other way is offered only where it can be used.
MediaLead _operatorAdds(
  ServiceKey arr,
  MediaConnectionRow<MediaSeerrRecord>? seerr, {
  required OperatorAddsVia addsVia,
  required bool? Function(ServiceInstance seerr)? seerrMayRequest,
}) {
  if (seerr == null) return MediaLeadAdd(arr);
  final reading = seerr.reading;
  if (reading is MediaReadingAnswered) {
    final may = seerrMayRequest == null
        ? true
        : seerrMayRequest(seerr.connection);
    if (addsVia == OperatorAddsVia.seerr) {
      if (may == null) return const MediaLeadWaiting();
      if (may) return MediaLeadRequest(seerr.connection, alternative: arr);
    }
    return MediaLeadAdd(
      arr,
      alternative: may == true ? seerr.connection : null,
    );
  }
  if (reading is MediaReadingWaiting) {
    return addsVia == OperatorAddsVia.seerr
        ? const MediaLeadWaiting()
        : MediaLeadAdd(arr);
  }
  return MediaLeadAdd(arr);
}

/// The status of the copy [row] answered with, null while it is not tracked
/// or did not answer.
MediaStatusInfo? _statusOf(MediaConnectionRow row) => switch (row.reading) {
  MediaReadingAnswered(:final answer) => switch (answer.value) {
    final MediaRadarrCopy copy => copy.status,
    final MediaSonarrCopy copy => copy.status,
    _ => null,
  },
  _ => null,
};
