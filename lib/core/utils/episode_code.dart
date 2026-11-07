/// The one spelling of an episode code: the brand book's `S2 E4`, and
/// `S2 E6–E10` for a run.
///
/// Every place the app names an episode by its numbers spells it here: a row,
/// a headline, an ordinal in a season's list, a season pill. No zero padding
/// and a space between the halves, so the season and the episode read as two
/// numbers. The space is a no-break one ([episodeCodeSpace]), so a wrapped
/// title never ends a line with `S2` and starts the next with `E4`.
/// `S02E04` is how a release or a file spells it, and those are machine
/// strings, drawn as they came and never rewritten into this.
///
/// `test/core/utils/episode_code_guard_test.dart` scans `lib/` for a code
/// spelled anywhere else.
library;

import 'package:cupola/core/utils/unit_space.dart';

/// The space between a code's halves: U+00A0, so `S2 E4` never splits.
const String episodeCodeSpace = unitSpace;

/// A code as [formatEpisodeCode] spells it, or as a server's subtitle carries
/// it with a plain space: `S2 E4`, and a run's tail `–E10` when present.
final RegExp episodeCodePattern = RegExp('S\\d+[ $unitSpace]E\\d+(?:–E?\\d+)?');

/// `S2`, or `S0` for the specials, which callers that have a word for them
/// (*Specials*, *Sp*) say instead.
String formatSeasonCode(int season) => 'S$season';

/// `E4`: an episode inside a season the reader already knows.
String formatEpisodeOrdinal(int episode) => 'E$episode';

/// `S2 E4`, its halves joined by [episodeCodeSpace].
String formatEpisodeCode(int season, int episode) =>
    '${formatSeasonCode(season)}$episodeCodeSpace${formatEpisodeOrdinal(episode)}';

/// `S2 E4`, or null unless both numbers are known.
String? formatArrEpisodeCode(int? season, int? episode) {
  if (season == null || episode == null) return null;
  return formatEpisodeCode(season, episode);
}

/// `S2 E4`, or `S2` / `E4` with whichever half is known; null with neither.
///
/// For the media servers, whose specials routinely arrive without an episode
/// number and whose loose files without a season.
String? formatPartialEpisodeCode({int? season, int? episode}) {
  if (season == null && episode == null) return null;
  return [
    if (season != null) formatSeasonCode(season),
    if (episode != null) formatEpisodeOrdinal(episode),
  ].join(episodeCodeSpace);
}

/// `S2 E6–E10` for a run of episodes, `S2 E4` for one, null for none.
///
/// The en dash, with no spaces, between the first and the last episode; a
/// multi-episode file is a contiguous run.
String? formatEpisodeRange(int season, Iterable<int> episodes) {
  final sorted = episodes.toSet().toList()..sort();
  if (sorted.isEmpty) return null;
  if (sorted.length == 1) return formatEpisodeCode(season, sorted.single);
  return '${formatEpisodeCode(season, sorted.first)}'
      '–${formatEpisodeOrdinal(sorted.last)}';
}

/// `S1 and S2 E1–E2`: each season's runs, a gap starting a new run, and a
/// season whole ([sizes] says how many episodes it has) by its code alone.
String? episodeRunsLine(
  Map<int, List<int>> bySeason, {
  Map<int, int> sizes = const {},
}) {
  final seasons = <String>[];
  for (final MapEntry(key: season, value: numbers) in bySeason.entries) {
    if (numbers.isEmpty) continue;
    final size = sizes[season];
    if (size != null &&
        numbers.length == size &&
        numbers.first == 1 &&
        numbers.last == size) {
      seasons.add(formatSeasonCode(season));
      continue;
    }
    final runs = <List<int>>[];
    for (final number in numbers) {
      if (runs.isNotEmpty && number == runs.last.last + 1) {
        runs.last.add(number);
      } else {
        runs.add([number]);
      }
    }
    final first = formatEpisodeRange(season, runs.first)!;
    seasons.add(
      [
        first,
        for (final run in runs.skip(1))
          run.length == 1
              ? formatEpisodeOrdinal(run.single)
              : '${formatEpisodeOrdinal(run.first)}'
                    '–${formatEpisodeOrdinal(run.last)}',
      ].join(', '),
    );
  }
  if (seasons.isEmpty) return null;
  if (seasons.length == 1) return seasons.single;
  return '${seasons.sublist(0, seasons.length - 1).join(', ')} and '
      '${seasons.last}';
}
