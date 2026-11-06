import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/sample_age.dart';
import 'package:cupola/core/utils/unit_space.dart';

import '../../test_helpers/copy_scan.dart';

/// Between a figure and its unit goes a no-break space: `4.4 GB`, `4.2 MB/s`,
/// `9 h` and `41 °C` never split across two lines, and a column of them keeps
/// every figure beside its unit.
///
/// The space is `unitSpace` (U+00A0) in `lib/core/utils/unit_space.dart`, and
/// `withUnit` joins a figure to its unit. This guard reads the copy (the string
/// literals of `lib/`, as the compiler reads them; comments and code are not
/// copy) and fails on a figure, one plain space, and a unit **symbol**:
/// `B` `KB` `MB` `GB` `TB` `PB` (with `/s`), `bps` forms, `Hz` forms, `ms`,
/// `s`, `min`, `h`, `d`, `°C`, `°F`.
///
/// What it covers, and what it does not:
///
///  * A unit spelled out as a word in a sentence (`3 days`, `6 minutes`) is
///    prose and breaks like prose; so is a count noun (`12 albums`). The rule
///    is for symbols, which read as one thing with their figure.
///  * A compact duration with no space at all (`1h 5m`, `4m 30s`) has nothing to
///    break; it is not this guard's business.
///  * A unit joined from two interpolations (`'$value $unit'`) cannot be read
///    from the source. The one such place is `byte_format.dart`, which the test
///    below holds by what it prints.
///  * The percent sign takes no space at all (`percent_format_guard_test.dart`).
///
/// What may stay is in [_allowed] with the reason.
void main() {
  final files = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'))
      .where((file) => !file.path.startsWith('lib/core/generated/'))
      .toList(growable: false);

  test('the guard has copy to scan', () {
    final count = files.fold<int>(
      0,
      (sum, file) => sum + copyOf(file.path, file.readAsStringSync()).length,
    );
    // A scan that silently found nothing would pass every check below.
    expect(count, greaterThan(5000));
  });

  test('no copy in lib/ puts a plain space between a figure and a unit', () {
    final offenders = [
      for (final file in files)
        for (final literal in copyOf(file.path, file.readAsStringSync()))
          if (_plainSpaced.hasMatch(literal.prose) && !_isAllowed(literal))
            '${literal.path}:${literal.line}  "${literal.prose}"',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'A figure and its unit are one thing: join them with '
          '`withUnit(figure, unit)` (a no-break space, U+00A0), so `4.4 GB`, '
          '`12 min` and `41 °C` never split. A literal where the space is '
          'right goes in _allowed with its reason.',
    );
  });

  test('no copy in lib/ glues a time unit to its figure (12m, 1h 5m, 4m)', () {
    // The brand book's vocabulary is `12 min`, `2 h 30 min`, `48 s`, `3 d`:
    // `formatTimeSpan` in duration_format.dart writes it. A compact `12m` is a
    // second spelling, and one cell could read `4.4 GB · 12m left`.
    final offenders = [
      for (final file in files)
        for (final literal in copyOf(file.path, file.readAsStringSync()))
          if (_gluedUnit.hasMatch(literal.prose) && !_isGluedAllowed(literal))
            '${literal.path}:${literal.line}  "${literal.prose}"',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'A span is `formatTimeSpan(Duration)` (or `withUnit(figure, unit)` '
          'for one figure): `12 min`, `2 h 30 min`, never `12m` or `1h 5m`. A '
          'literal that is not a duration goes in _gluedAllowed with its '
          'reason.',
    );
  });

  test('the glued-unit scan catches a compact span; a plural reads the same', () {
    const planted = r'''
final a = '${m}m left';
final b = '${h}h ${m}m';
final c = '4m 30s';
final d = '${d}d';
final e = '${ms}ms';
final f = '12 min left';
final g = withUnit(m, 'min');
final h = 'about ${x} minutes';
final i = '${noun}s';
final j = 'load 1m';
final k = '404s';
''';
    expect(
      [
        for (final literal in copyOf('lib/zz_planted.dart', planted))
          if (_gluedUnit.hasMatch(literal.prose)) literal.line,
      ],
      [1, 2, 3, 4, 5, 9, 10, 11],
      reason:
          'a figure straight against d, h, m, ms or s; a plural is allow-listed',
    );
  });

  test('no source line carries an invisible no-break space or joiner', () {
    // A no-break space typed into a file is indistinguishable from a space in
    // every editor and diff; it is `unitSpace` or an escape, so it can be seen.
    final offenders = [
      for (final file in [
        ...files,
        ...Directory('test')
            .listSync(recursive: true)
            .whereType<File>()
            .where((file) => file.path.endsWith('.dart')),
      ])
        for (final (index, line) in file.readAsLinesSync().indexed)
          if (line.contains('\u00A0') || line.contains(wordJoiner))
            '${file.path}:${index + 1}',
    ];
    expect(
      offenders,
      isEmpty,
      reason:
          'Write it as unitSpace, or as the escape, never as the character.',
    );
  });

  test('byte_format.dart prints the no-break space, whatever the unit', () {
    // It builds its unit from a ladder at run time, which no scan of its
    // literals can see: hold it by what it prints.
    final printed = <String>[
      formatBytes(0),
      formatBytes(512),
      formatBytes(1536),
      formatBytes(4700000000),
      formatBytes(152 * 1024 * 1024 * 1024),
      formatBytesPerSecond(4404019),
      formatBytesPerSecond(120 * 1024 * 1024),
      formatMegabytes(798),
      formatKilobytesPerSecond(512),
      formatBytesOfTotal(1024 * 1024 * 1024, 4 * 1024 * 1024 * 1024),
      formatBytesOfTotal(300, 512),
    ];
    for (final text in printed) {
      expect(text, matches(_figureUnitSpaced), reason: text);
      expect(text, isNot(matches(_plainSpaced)), reason: text);
    }
  });

  test('the age formatters print it too', () {
    expect(formatDurationAge(const Duration(minutes: 12)), '12\u00A0min ago');
    expect(formatDurationAge(const Duration(hours: 2)), '2\u00A0h ago');
  });

  test('withUnit joins a figure to its unit with unitSpace', () {
    expect(unitSpace, '\u00A0');
    expect(unitSpace.codeUnits, [0xA0]);
    expect(withUnit(4.4, 'GB'), '4.4\u00A0GB');
    expect(withUnit(12, 'min'), '12\u00A0min');
    expect(withUnit('0', 'B/s'), '0\u00A0B/\u2060s');
  });

  test('the scan catches a plain space before a unit and passes the rest', () {
    const planted = r'''
final a = '$minutes min ago';
final b = '${size} GB';
final c = '4.2 MB/s';
final d = '9 h left';
final e = '41 °C';
final f = '$count d';
final g = '${(x * 2).round()} ms';
final h = '$minutes\u00A0min ago';
final i = '4.4\u00A0GB';
final j = withUnit(minutes, 'min');
// final k = '$minutes min ago' in a comment is not copy.
final l = '3 days ago';
final m = '12 albums';
final n = '$minutes mins';
final o = '1h 5m';
final p = 'Plan B';
final q = '$count s'
    'tuff';
''';
    final literals = copyOf('lib/zz_planted.dart', planted);
    expect(
      [
        for (final literal in literals)
          if (_plainSpaced.hasMatch(literal.prose)) literal.line,
      ],
      [1, 2, 3, 4, 5, 6, 7],
      reason: 'a figure, one plain space, a unit symbol',
    );
  });

  test('every allow-list entry still matches something', () {
    final unused = [
      for (final entry in [..._allowed, ..._gluedAllowed])
        if (!File(entry.file).existsSync() ||
            !copyOf(
              entry.file,
              File(entry.file).readAsStringSync(),
            ).any((literal) => literal.prose == entry.literal))
          '${entry.file}  "${entry.literal}"',
    ];
    expect(unused, isEmpty);
  });
}

/// The unit symbols the rule covers, as a pattern. Bytes and byte rates, bit
/// rates, hertz, the time symbols and degrees.
const _unit =
    r'(?:[KMGTP]i?B(?:/s)?|B(?:/s)?|[KMGk]?bps|[kMG]?Hz|ms|s|min|h|d|°[CF])';

/// A figure (a digit, or an interpolation) and one plain space before a unit
/// symbol: the shape the rule forbids.
final _plainSpaced = RegExp('[0-9$copyHole] $_unit(?![A-Za-z0-9])');

/// A figure and a no-break space before a unit symbol: the shape it asks for.
final _figureUnitSpaced = RegExp('[0-9]\u00A0$_unit');

/// A figure (a digit, or an interpolation) straight against a time unit symbol:
/// the compact spelling the brand book's vocabulary replaces.
final _gluedUnit = RegExp('[0-9$copyHole](?:d|h|m|ms|min|s)(?![A-Za-z0-9])');

/// Literals that end in a unit-looking letter and are not a duration, each with
/// the reason.
const _gluedAllowed = <({String file, String literal, String reason})>[
  (
    file: 'lib/features/bazarr/domain/models/bazarr_models.dart',
    literal: 'Subf2m',
    reason: "a subtitle provider's name, as Bazarr spells it; not two minutes",
  ),
  (
    file: 'lib/core/utils/string_utils.dart',
    literal: '${copyHole}s',
    reason: 'the plural s of countLabel: a noun, not seconds',
  ),
  (
    file: 'lib/features/music/presentation/lidarr_overview_provider.dart',
    literal: '${copyHole}s',
    reason: 'the plural s of a noun in lidarrCountLabel, not seconds',
  ),
  (
    file:
        'lib/features/truenas/presentation/dashboard/truenas_dashboard_screen.dart',
    literal: 'load 1m',
    reason: 'the name of the one-minute load average, a caption and not a span',
  ),
  (
    file: 'lib/features/npm/presentation/npm_screen.dart',
    literal: 'Redirections, 404s and streams',
    reason: 'the plural of an HTTP status, not seconds',
  ),
  (
    file: 'lib/features/discover/domain/catalog_query.dart',
    literal: '${copyHole}s',
    reason: 'a decade, the 1990s: the plural of a year, not seconds',
  ),
  (
    file: 'lib/features/discover/presentation/discover_atrium.dart',
    literal: '1920s to now',
    reason: 'the decades the catalogue runs through, not seconds',
  ),
  (
    file: 'lib/features/tracearr/domain/models/tracearr_media_stats.dart',
    literal: 'alertsLast24h',
    reason:
        "the name of a field of Tracearr's today read, off the wire; never "
        'shown',
  ),
];

bool _isGluedAllowed(CopyLiteral literal) => _gluedAllowed.any(
  (entry) => entry.file == literal.path && entry.literal == literal.prose,
);

/// Literals that put a plain space between a figure and a unit symbol for a
/// reason that is not a measurement shown to a person, each with the reason.
const _allowed = <({String file, String literal, String reason})>[];

bool _isAllowed(CopyLiteral literal) => _allowed.any(
  (entry) => entry.file == literal.path && entry.literal == literal.prose,
);
