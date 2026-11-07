import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/episode_code.dart';

void main() {
  test(
    'an episode reads S2\u00A0E4: no padding, a space between the halves',
    () {
      expect(formatEpisodeCode(2, 4), 'S2\u00A0E4');
      expect(formatEpisodeCode(12, 104), 'S12\u00A0E104');
      expect(formatEpisodeCode(0, 3), 'S0\u00A0E3');
    },
  );

  test('a season and an episode alone read S2 and E4', () {
    expect(formatSeasonCode(2), 'S2');
    expect(formatEpisodeOrdinal(4), 'E4');
  });

  test('formatArrEpisodeCode needs both numbers', () {
    expect(formatArrEpisodeCode(2, 4), 'S2\u00A0E4');
    expect(formatArrEpisodeCode(2, null), isNull);
    expect(formatArrEpisodeCode(null, 4), isNull);
  });

  test('formatPartialEpisodeCode says whichever half is known', () {
    expect(formatPartialEpisodeCode(season: 2, episode: 4), 'S2\u00A0E4');
    expect(formatPartialEpisodeCode(season: 2), 'S2');
    expect(formatPartialEpisodeCode(episode: 4), 'E4');
    expect(formatPartialEpisodeCode(), isNull);
  });

  test('a run reads S2\u00A0E6–E10, with the en dash and no spaces', () {
    expect(formatEpisodeRange(2, [6, 7, 8, 9, 10]), 'S2\u00A0E6–E10');
    expect(formatEpisodeRange(2, [10, 6]), 'S2\u00A0E6–E10');
    expect(formatEpisodeRange(1, [1, 2]), 'S1\u00A0E1–E2');
    expect(formatEpisodeRange(2, [4]), 'S2\u00A0E4');
    expect(formatEpisodeRange(2, [4, 4]), 'S2\u00A0E4');
    expect(formatEpisodeRange(2, const []), isNull);
  });
}
