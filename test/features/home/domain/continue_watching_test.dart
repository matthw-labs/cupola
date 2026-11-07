import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/home/domain/continue_watching.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

/// The words of the Home's Continue watching.
void main() {
  StreamItem item({
    required String title,
    String? subtitle,
    StreamItemKind kind = StreamItemKind.episode,
    int? year,
    int? runtimeMs,
    int? resumeOffsetMs,
  }) => StreamItem(
    id: title,
    title: title,
    subtitle: subtitle,
    kind: kind,
    posterPath: null,
    year: year,
    runtimeMs: runtimeMs,
    isPlayed: false,
    resumeOffsetMs: resumeOffsetMs,
    unplayedChildCount: null,
    seasonNumber: kind == StreamItemKind.episode ? 2 : null,
    episodeNumber: kind == StreamItemKind.episode ? 3 : null,
  );

  // Jellyfin's episode: the series and its code in the subtitle.
  final jellyfinEpisode = item(
    title: 'The Second Cycle',
    subtitle: 'Cosmos Laundromat\u00A0· S2\u00A0E3',
    runtimeMs: 1500000,
    resumeOffsetMs: 1200000,
  );
  // Plex's: the series alone.
  final plexEpisode = item(
    title: 'The Second Cycle',
    subtitle: 'Cosmos Laundromat',
  );
  final movie = item(
    title: 'Sintel',
    kind: StreamItemKind.movie,
    year: 2010,
    runtimeMs: 900000,
    resumeOffsetMs: 300000,
  );

  test('an episode is called by its series, and says its code and name', () {
    for (final item in [jellyfinEpisode, plexEpisode]) {
      expect(resumeTitle(item), 'Cosmos Laundromat');
      expect(resumeDetail(item), 'S2\u00A0E3\u00A0· The Second Cycle');
    }
  });

  test('a movie by its title, then its year', () {
    expect(resumeTitle(movie), 'Sintel');
    expect(resumeDetail(movie), '2010');
  });

  test('how long is left, only when both halves are known', () {
    expect(resumeLeft(jellyfinEpisode), '5\u00A0min left');
    expect(resumeLeft(movie), '10\u00A0min left');
    expect(resumeLeft(plexEpisode), isNull);
  });
}
