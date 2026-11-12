import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/features/media/domain/quality_words.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode_file.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';

/// What Manage says of a series that one Sonarr holds: the lines of its
/// closed rows, and one line for each season.

/// Files & quality, closed: `13 files · 720p WEB, 1080p WEB`. Before the
/// files are read, Sonarr's own count and size, `13 files · 8.3 GB`;
/// `No file yet` with none.
String mediaSeriesFilesSummary(
  SonarrSeries series,
  Iterable<SonarrEpisodeFile>? files,
) {
  final count = files?.length ?? series.episodeFileCount ?? 0;
  if (count == 0) return 'No file yet';
  final qualities = files == null ? '' : mediaQualitiesOf(files);
  final size = series.sizeOnDisk;
  return [
    countLabel(count, 'file'),
    if (qualities.isNotEmpty) qualities else if (size > 0) formatBytes(size),
  ].join(dotSeparator);
}

/// History, closed: the episode imported last and when,
/// `Last imported S2 E3 · Mon 5 Oct`; empty before the files are read, and
/// with none.
String mediaSeriesLastImport(
  List<SonarrEpisode> episodes,
  Map<int, SonarrEpisodeFile>? files, {
  DateTime? now,
}) {
  if (files == null) return '';
  SonarrEpisode? last;
  DateTime? at;
  for (final episode in episodes) {
    final added = files[episode.episodeFileId]?.dateAdded;
    if (added != null && (at == null || added.isAfter(at))) {
      last = episode;
      at = added;
    }
  }
  if (last == null || at == null) return '';
  return 'Last imported '
      '${formatArrEpisodeCode(last.seasonNumber, last.episodeNumber)}\u00A0· '
      '${formatShortDate(at.toLocal().toIso8601String(), now: now)}';
}

/// The qualities [files] are in, the commonest first: `720p WEB, 1080p WEB`;
/// past two, how many more, `720p WEB, 1080p WEB +1`.
String mediaQualitiesOf(Iterable<SonarrEpisodeFile> files) {
  final counts = <String, int>{};
  for (final file in files) {
    final name = file.qualityName;
    if (name == null || name.isEmpty) continue;
    final words = qualityWords(name);
    counts[words] = (counts[words] ?? 0) + 1;
  }
  final ranked = counts.keys.toList()
    ..sort((a, b) {
      final byCount = counts[b]!.compareTo(counts[a]!);
      return byCount != 0 ? byCount : a.compareTo(b);
    });
  final shown = ranked.take(2).join(', ');
  return ranked.length > 2 ? '$shown +${ranked.length - 2}' : shown;
}

/// One season as Manage draws it: whether Sonarr monitors it, and what it
/// holds, `3 of 10 on disk · 720p WEB, 1080p WEB`.
class MediaSeasonFiles {
  const MediaSeasonFiles({
    required this.number,
    required this.label,
    required this.monitored,
    required this.detail,
    required this.aired,
  });

  final int number;

  /// `Season 2`, `Specials`.
  final String label;

  final bool monitored;
  final String detail;

  /// At least one of its episodes has aired: there is something to search
  /// for.
  final bool aired;
}

/// The seasons of [series] that have episodes, in Sonarr's order with the
/// specials last, each with what it holds. [files] add the qualities once
/// they are read.
List<MediaSeasonFiles> mediaSeasonFilesOf(
  SonarrSeries series,
  List<SonarrEpisode> episodes, {
  Map<int, SonarrEpisodeFile>? files,
  DateTime? now,
}) {
  final clock = now ?? DateTime.now();
  return [
    for (final season in series.seasonList)
      if ((season.totalEpisodeCount ?? 0) > 0 ||
          episodes.any((e) => e.seasonNumber == season.seasonNumber))
        _seasonFiles(
          season.seasonNumber,
          label: season.label,
          monitored: season.monitored,
          episodes: [
            for (final episode in episodes)
              if (episode.seasonNumber == season.seasonNumber) episode,
          ],
          statsOnDisk: season.episodeFileCount,
          statsTotal: season.totalEpisodeCount,
          files: files,
          now: clock,
        ),
  ];
}

MediaSeasonFiles _seasonFiles(
  int number, {
  required String label,
  required bool monitored,
  required List<SonarrEpisode> episodes,
  required int? statsOnDisk,
  required int? statsTotal,
  required Map<int, SonarrEpisodeFile>? files,
  required DateTime now,
}) {
  final total = episodes.isEmpty ? (statsTotal ?? 0) : episodes.length;
  final aired = episodes.isEmpty
      ? total
      : episodes.where((e) => e.hasAiredAt(now)).length;
  final onDisk = episodes.isEmpty
      ? (statsOnDisk ?? 0)
      : episodes.where((e) => e.hasFile).length;
  final held = files == null
      ? const <SonarrEpisodeFile>[]
      : [for (final episode in episodes) ?files[episode.episodeFileId]];
  final qualities = mediaQualitiesOf(held);
  final detail = aired == 0 && onDisk == 0
      ? '${countLabel(total, 'episode')}\u00A0· not aired'
      : [
          '$onDisk of ${aired < onDisk ? onDisk : aired} on disk',
          if (qualities.isNotEmpty) qualities,
        ].join(dotSeparator);
  return MediaSeasonFiles(
    number: number,
    label: label,
    monitored: monitored,
    detail: detail,
    aired: aired > 0,
  );
}
