import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_playback.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';

/// The media server a Tracearr row says it is on, as the service Cupola
/// would hold for it, or null for a kind Tracearr named that Cupola has no
/// word for (a fourth server type, a row that said none).
ServiceKey? tracearrServiceOf(TracearrServerType type) => switch (type) {
  TracearrServerType.plex => ServiceKey.plex,
  TracearrServerType.jellyfin => ServiceKey.jellyfin,
  TracearrServerType.emby => ServiceKey.emby,
  TracearrServerType.unknown => null,
};

/// How a stream reaches the viewer, read from the two decisions Tracearr
/// states for it, as a media server's own session says it: a track converted
/// is a transcode, one passed through inside a new container a direct stream,
/// and a row with no decision at all is a direct play (nothing says otherwise).
///
/// Tracearr's own verdict (`is_transcode`) counts too: it can say transcode
/// where neither decision does (a hardware path), and never the reverse.
StreamPlayMethod tracearrPlayMethodOf(TracearrQuality quality) {
  final decisions = [quality.videoDecision, quality.audioDecision];
  if (quality.isTranscode || decisions.contains(TracearrDecision.transcode)) {
    return StreamPlayMethod.transcode;
  }
  if (decisions.contains(TracearrDecision.copy)) {
    return StreamPlayMethod.directStream;
  }
  return StreamPlayMethod.directPlay;
}

/// One live stream of Tracearr as the playback row every surface draws.
///
/// A series is the headline and the episode the detail, as on a media
/// server's own row, so the Home's `Anna · Night Shift · S1 E2` reads the same
/// from either source. The artwork stays a path on Tracearr's image proxy
/// (`resolveTracearrImage` makes it an address with the connection's reach):
/// never an address with a credential in it, which the image cache would name
/// the file by.
///
/// The bitrate is Tracearr's, in kilobits a second, and is the encoder's
/// target only for a transcode: for anything else it describes the file, so it
/// is nominal, as on a media server's own row.
StreamSession tracearrStreamSession(TracearrStream stream) {
  final media = stream.media;
  final quality = stream.quality;
  final method = tracearrPlayMethodOf(quality);
  final isEpisode =
      media.type == TracearrMediaType.episode &&
      (media.showTitle?.trim().isNotEmpty ?? false);
  final length = media.durationMs;
  final at = stream.progressMs;
  final kbps = quality.bitrate;
  final reasons = method == StreamPlayMethod.directPlay
      ? const <String>[]
      : [
          for (final reason in quality.transcode?.reasons ?? const <String>[])
            tracearrReasonWords(reason),
        ];
  return StreamSession(
    id: stream.id,
    userName: stream.person.name.trim(),
    title: isEpisode ? media.showTitle!.trim() : tracearrMediaTitleOf(media),
    subtitle: _subtitleOf(media, isEpisode: isEpisode),
    deviceLabel: joinDisplayParts([
      stream.device.product,
      stream.device.player ?? stream.device.device ?? stream.device.platform,
    ]),
    posterPath: media.posterUrl,
    playMethod: method,
    transcodeReasons: reasons,
    bitrate: kbps == null ? null : kbps * 1000,
    bitrateIsNominal: method != StreamPlayMethod.transcode,
    progress: stream.progress,
    isPaused: stream.isPaused,
    remaining: length == null || length <= 0
        ? null
        : Duration(milliseconds: (length - at).clamp(0, length)),
    itemId: media.ids.ratingKey,
    titleKey: tracearrMediaKeyOf(media),
  );
}

String? _subtitleOf(TracearrMedia media, {required bool isEpisode}) {
  if (isEpisode) {
    final code = formatPartialEpisodeCode(
      season: media.seasonNumber,
      episode: media.episodeNumber,
    );
    final name = media.title.trim();
    final joined = [?code, if (name.isNotEmpty) name].join(dotSeparator);
    return joined.isEmpty ? null : joined;
  }
  return switch (media.type) {
    TracearrMediaType.movie => media.year?.toString(),
    TracearrMediaType.track => () {
      final line = joinDisplayParts([media.artist, media.album]);
      return line.isEmpty ? null : line;
    }(),
    _ => null,
  };
}
