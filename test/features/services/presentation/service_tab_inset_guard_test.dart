import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../test_helpers/code_scan.dart';

/// Every screen the router hosts under a service's tab bar clears the glass
/// bars on a notched phone, or says why it does not need to.
///
/// The router hands each hosted tab `topPadding: _serviceTabTopPadding`: the
/// service band plus the tab bar, **without** the status bar's inset, which the
/// band consumes but does not remove from `MediaQuery`. A screen with no
/// `SafeArea` and no app bar must add `MediaQuery.paddingOf(context).top`
/// itself, or its first row starts under the tab bar on every phone with a
/// notch. A desktop window has no inset, so nothing there ever shows it.
///
/// `service_tab_inset_test.dart` measures that, one case per screen, on a phone
/// with a 62pt status bar. A case exists only for the screens somebody
/// remembered to add, and the next hosted screen is the one nobody remembers.
/// This guard closes that: it reads the router, collects the class of every
/// widget handed the constant, and holds each to one of two things.
///
/// - **A case.** The class is constructed in the inset test with
///   `topPadding: _hostedTopPadding`, the value the router hands it.
/// - **An excuse**, in [_excused]: a reason that is true of the code. A reason
///   names a mechanism (see [_anchors]) that the guard finds in the class's own
///   file, so deleting the `SafeArea` that a reason leans on turns the excuse
///   into a failure instead of leaving it to say something false.
///
/// A source scan, because the regression is a new `ServiceHomeScreen` branch
/// in a diff that builds, analyzes and passes every other test while one
/// screen starts under the bar. It reads the router through `code_scan.dart`,
/// so a comment that names the constant is not a use of it.
void main() {
  final router = codeOf(File('lib/core/router.dart').readAsStringSync());
  final insetTest = codeOf(
    File(
      'test/features/services/presentation/service_tab_inset_test.dart',
    ).readAsStringSync(),
  );
  final hosted = _hostedClasses(router);
  final lib = libCode();

  test('the router hands the constant to a large set of screens', () {
    // Not vacuous: a rename of the constant, or a spelling the scan cannot
    // read, would otherwise leave an empty set and a green guard. Today it is
    // 78 constructions of 57 classes.
    expect(
      hosted.sites.length,
      greaterThan(50),
      reason:
          'The scan found only ${hosted.sites.length} constructions handed '
          '`topPadding: _serviceTabTopPadding`. If the constant was renamed or '
          'the tabs are built another way, teach the guard the new spelling.',
    );
    expect(hosted.classes.length, greaterThan(40));
  });

  test('every use of the constant is a construction the guard reads', () {
    // A screen handed the constant through a variable or a function would not
    // be a `topPadding: _serviceTabTopPadding` on a widget and would escape.
    final uses = RegExp(r'\b_serviceTabTopPadding\b').allMatches(router).length;
    expect(
      uses - 1, // the declaration
      hosted.sites.length,
      reason:
          '`_serviceTabTopPadding` is used in a way other than '
          '`topPadding: _serviceTabTopPadding` on a widget. Hand it to the '
          'screen directly so the guard sees the class, or extend the guard.',
    );
    expect(
      hosted.unreadable,
      isEmpty,
      reason:
          'No class could be read for these (a helper function, or a call '
          'the walk back does not understand): ${hosted.unreadable}',
    );
  });

  test('every hosted class has a case in the inset test, or an excuse', () {
    final missing = [
      for (final name in hosted.classes)
        if (!_hasCase(insetTest, name) && !_excused.containsKey(name)) name,
    ];
    expect(
      missing,
      isEmpty,
      reason:
          '${missing.join(', ')} is hosted under a service tab bar with '
          '`topPadding: _serviceTabTopPadding`, which leaves the status bar\'s '
          'inset to the screen, and nothing proves it takes it. Add a case to '
          'test/features/services/presentation/service_tab_inset_test.dart '
          '(construct the screen with `topPadding: _hostedTopPadding` and '
          'check its first content clears the tab bar), or, if the screen '
          'cannot start under it, excuse it in `_excused` with a reason that '
          'is true of the code.',
    );
  });

  test('the page the Overviews share has a case in the inset test', () {
    // The excuses of the `*OverviewScreen` classes lean on it: take the case
    // away and fourteen screens are excused by a page nothing measures.
    expect(_hasCase(insetTest, 'ServiceOverviewPage'), isTrue);
  });

  test('an excuse names a class that is still hosted, and still needs it', () {
    final stale = [
      for (final name in _excused.keys)
        if (!hosted.classes.contains(name))
          '$name is no longer constructed with `_serviceTabTopPadding`'
        else if (_hasCase(insetTest, name))
          '$name has a case in the inset test now',
    ];
    expect(
      stale,
      isEmpty,
      reason: 'Remove these entries from `_excused`: ${stale.join('; ')}.',
    );
  });

  test('an excuse leans on a mechanism the class still has', () {
    final broken = <String>[];
    for (final MapEntry(key: name, value: reason) in _excused.entries) {
      final declarations = [
        for (final file in lib)
          if (RegExp('\\bclass $name\\b').hasMatch(file.code)) file,
      ];
      if (declarations.length != 1) {
        broken.add(
          '$name is declared in ${declarations.length} files, not one',
        );
        continue;
      }
      final code = declarations.single.code;
      final named = _anchors.entries.where((a) => reason.contains(a.key));
      if (named.isEmpty) {
        broken.add(
          '$name: the reason names none of ${_anchors.keys.join(', ')}, so '
          'the guard cannot check it',
        );
      }
      for (final MapEntry(key: mechanism, value: anchor) in named) {
        if (!anchor.present.hasMatch(code) || anchor.absent.hasMatch(code)) {
          broken.add(
            '$name: its reason names $mechanism, which '
            '${declarations.single.path} no longer has',
          );
        }
      }
    }
    expect(
      broken,
      isEmpty,
      reason:
          'An excuse says something the code no longer does. Add a case to '
          'the inset test, or give the class a true reason.',
    );
  });

  group('the scan', () {
    test('reads the class of a construction, named or not, across lines', () {
      const planted = '''
const a = Alpha(topPadding: _serviceTabTopPadding);
final b = Beta.named(
  showAppBar: false,
  topPadding: _serviceTabTopPadding,
);
final c = Gamma(child: Delta(a: 1, topPadding: _serviceTabTopPadding));
final d = helper(topPadding: _serviceTabTopPadding);
// final e = Epsilon(topPadding: _serviceTabTopPadding);
final f = 'Zeta(topPadding: _serviceTabTopPadding)';
const _serviceTabTopPadding = 1;
''';
      final read = _hostedClasses(codeOf(planted));
      expect(read.classes, {'Alpha', 'Beta', 'Delta'});
      expect(read.sites.length, 4);
      expect(read.unreadable, hasLength(1));
    });

    test('a case is a construction handed the hosted padding', () {
      const planted = '''
child: const Alpha(topPadding: _hostedTopPadding),
child: const Beta.named(showAppBar: false, topPadding: _hostedTopPadding),
child: const Gamma(topPadding: 0),
child: const Delta(),
// child: const Epsilon(topPadding: _hostedTopPadding),
final name = 'Zeta(topPadding: _hostedTopPadding)';
''';
      final code = codeOf(planted);
      expect(_hasCase(code, 'Alpha'), isTrue);
      expect(_hasCase(code, 'Beta'), isTrue);
      expect(_hasCase(code, 'Gamma'), isFalse);
      expect(_hasCase(code, 'Delta'), isFalse);
      expect(_hasCase(code, 'Epsilon'), isFalse);
      expect(_hasCase(code, 'Zeta'), isFalse);
      expect(_hasCase(code, 'Alph'), isFalse);
    });
  });
}

/// The widgets handed `topPadding: _serviceTabTopPadding` in [code] (the
/// router, through [codeOf]).
({Set<String> classes, List<String> sites, List<String> unreadable})
_hostedClasses(String code) {
  final classes = <String>{};
  final sites = <String>[];
  final unreadable = <String>[];
  final hand = RegExp(r'\btopPadding:\s*_serviceTabTopPadding\b');
  for (final match in hand.allMatches(code)) {
    final line = '\n'.allMatches(code.substring(0, match.start)).length + 1;
    sites.add('router.dart:$line');
    final name = _constructorOf(code, match.start);
    if (name == null) {
      unreadable.add('router.dart:$line');
    } else {
      classes.add(name);
    }
  }
  return (classes: classes, sites: sites, unreadable: unreadable);
}

/// The class whose constructor call holds the argument at [offset]: walk back
/// to the `(` that opens the call, then read the name before it, dropping a
/// named constructor (`Screen.array(` is `Screen`). Null for anything that is
/// not an upper-case name, such as a helper function.
String? _constructorOf(String code, int offset) {
  var depth = 0;
  for (var i = offset - 1; i >= 0; i--) {
    final c = code[i];
    if (c == ')' || c == ']' || c == '}') depth++;
    if (c == '(' || c == '[' || c == '{') {
      if (depth > 0) {
        depth--;
        continue;
      }
      if (c != '(') return null;
      final before = code.substring(0, i);
      final read = RegExp(
        r'(?<![\w$])([A-Z]\w*)(?:\.[A-Za-z_]\w*)?\s*$',
      ).firstMatch(before);
      return read?.group(1);
    }
  }
  return null;
}

/// Whether [insetTest] (through [codeOf]) constructs [name] with the padding
/// the router hands it. A construction with another padding proves nothing
/// about the inset, and a name in a title or a comment is not a construction.
bool _hasCase(String insetTest, String name) => callsOf(
  'inset_test',
  insetTest,
  RegExp('\\b$name(?:\\.[A-Za-z_]\\w*)?\\('),
).any((call) => call.named['topPadding'] == '_hostedTopPadding');

/// What a reason in [_excused] may lean on, and how the guard finds it in the
/// class's own file: [present] must match its code and [absent] must not.
({RegExp present, RegExp absent}) _anchor(String present, [String? absent]) =>
    (present: RegExp(present), absent: RegExp(absent ?? r'(?!)'));

final Map<String, ({RegExp present, RegExp absent})> _anchors = {
  // The body is a `SafeArea` that takes the status bar's inset, so the
  // page's own `topPadding` starts below it. Not one that turned the top off.
  'SafeArea': _anchor(r'\bSafeArea\(', r'\bSafeArea\(\s*top:\s*false'),
  // The page reserves the room the bands take with a `SizedBox` of
  // `topPadding`, below the `SafeArea` that took the inset.
  'SizedBox': _anchor(r'\bSizedBox\(\s*height:\s*topPadding\b'),
  // An Overview hands `topPadding` to `ServiceOverviewPage`, whose body is a
  // `SafeArea` that takes the inset and pads its one scroll view by it (the
  // page has its own case in the inset test: see the test that says so).
  'ServiceOverviewPage': _anchor(
    r'\bServiceOverviewPage\(\s*service:\s*[\w.]+,\s*topPadding:\s*topPadding\b',
  ),
  // An Overview of its own, with no page behind it (Stream's), hands
  // `topPadding` to its one scroll view, which pads its column by it, below
  // the `SafeArea` that took the inset.
  'ServiceOverviewScroll': _anchor(
    r'\bServiceOverviewScroll\(\s*topPadding:\s*topPadding\b',
  ),
  // The screen hands `topPadding` to the shared browse scaffold, whose header
  // adds the inset itself (measured by the Radarr Library case).
  'MediaBrowseScaffold': _anchor(
    r'\bMediaBrowseScaffold<[^>]+>\([\s\S]*?\btopPadding:\s*topPadding\b',
  ),
};

const String _safeAreaOverview =
    'its body is a SafeArea, which takes the inset, and the page reserves '
    'the room the bands take by handing topPadding to ServiceOverviewScroll';

const String _overviewPage =
    'it hands topPadding to ServiceOverviewPage, which has its own case in '
    'the inset test';

const String _safeAreaDashboard =
    'its body is a SafeArea, which takes the inset, and the dashboard '
    'reserves the room the bands take with a SizedBox of topPadding';

/// Hosted screens with no case of their own, each with the reason they need
/// none. A reason is true of the class's code: read it before copying one.
const Map<String, String> _excused = {
  'BazarrOverviewScreen': _overviewPage,
  'DockgeOverviewScreen': _overviewPage,
  'LidarrOverviewScreen': _overviewPage,
  'NpmOverviewScreen': _overviewPage,
  'NzbgetOverviewScreen': _overviewPage,
  'ProwlarrOverviewScreen': _overviewPage,
  'QbittorrentOverviewScreen': _overviewPage,
  'RadarrOverviewScreen': _overviewPage,
  'ReadarrOverviewScreen': _overviewPage,
  'SabnzbdOverviewScreen': _overviewPage,
  'SeerrOverviewScreen': _overviewPage,
  'SonarrOverviewScreen': _overviewPage,
  'StreamOverviewScreen': _safeAreaOverview,
  'TracearrOverviewScreen': _overviewPage,
  'TransmissionOverviewScreen': _overviewPage,
  'UnraidOverviewScreen': _overviewPage,
  'NzbgetScreen': _safeAreaDashboard,
  'SabnzbdScreen': _safeAreaDashboard,
  'TransmissionScreen': _safeAreaDashboard,
  'SeriesScreen':
      'it hands topPadding straight to MediaBrowseScaffold, whose header adds '
      'the inset, as the Radarr Library case measures',
  'MusicScreen':
      'it hands topPadding straight to MediaBrowseScaffold, whose header adds '
      'the inset, as the Radarr Library case measures',
};
