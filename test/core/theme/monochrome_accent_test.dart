import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The brand book's principle 3, held on the source: **colour is information.** The room is
/// monochrome; colour reaches a pixel from the content (a title's light) and
/// from the five status tones, and from nothing else. A service's mark, tab,
/// room and buttons carry no hue, and the chrome has no section colours.
///
/// The switch is one getter: `ServiceKey.accent` is the neutral lamp for every
/// service, so every surface that used to be tinted by a service is lit by the
/// lamp instead, and a label asked of it resolves to the room's ink. These
/// scans keep the brand colours from finding their way back into paint by
/// another door: `AppColors.radarr` read straight and `brandAccent` handed to
/// a button. They are source scans for the same reason
/// `neutral_destructive_test.dart` is: the regression is one plausible line in
/// a diff, and it looks fine on the screen it was written for.
void main() {
  final libFiles = Directory('lib')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.startsWith('lib/core/generated/'))
      .toList(growable: false);

  /// Source with comment lines blanked, so a doc comment explaining the rule
  /// may name what it forbids. Lines keep their numbers.
  String codeOf(File file) => file
      .readAsLinesSync()
      .map((line) => line.trimLeft().startsWith('//') ? '' : line)
      .join('\n');

  int lineAt(String source, int offset) =>
      '\n'.allMatches(source.substring(0, offset)).length + 1;

  /// The argument list opened by the `(` at [open], parentheses balanced.
  String argumentsFrom(String source, int open) {
    var depth = 0;
    for (var i = open; i < source.length; i++) {
      final c = source[i];
      if (c == '(') depth++;
      if (c == ')') {
        depth--;
        if (depth == 0) return source.substring(open, i + 1);
      }
    }
    return source.substring(open);
  }

  /// Where the palette and the registry live: the only files that may name the
  /// brand colours as such.
  const palette = {
    'lib/core/theme.dart',
    'lib/features/settings/domain/service_key.dart',
  };

  test('lib/ has files to scan', () {
    expect(libFiles, isNotEmpty);
  });

  test('every service paints the lamp', () {
    for (final service in ServiceKey.values) {
      expect(service.accent, AppColors.lamp, reason: service.name);
    }
  });

  test('a brand colour is read only where the colour is the information', () {
    // The allowed readers, each with the reason a hue is the information
    // there and nothing else carries it.
    const informational = {
      // Chart series: six lines on one graph are told apart by colour, and
      // the palette borrows brand bytes for it. A categorical palette is its
      // own axis: the dataviz pass replaces it; until then it is data.
      'lib/features/truenas/presentation/reporting/truenas_reporting_screen.dart',
    };
    final brand = RegExp(
      r'\bbrandAccent\b|DesignTokens\.colorService[A-Z]\w*|'
      r'AppColors\.(?:seerr|radarr|sonarr|lidarr|qbittorrent|transmission|'
      r'nginxProxyManager|bazarr|truenas|dockge|prowlarr|readarr|sabnzbd|'
      r'nzbget|unraid|jellyfin|plex|emby)\b',
    );
    final offenders = <String>[];
    for (final file in libFiles) {
      if (palette.contains(file.path) || informational.contains(file.path)) {
        continue;
      }
      final source = codeOf(file);
      for (final hit in brand.allMatches(source)) {
        offenders.add(
          '${file.path}:${lineAt(source, hit.start)}  ${hit.group(0)}',
        );
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          'A service is painted with ServiceKey.accent (the lamp), never its '
          'brand colour:\n${offenders.join('\n')}',
    );
  });

  test('no button is filled with a service accent', () {
    // A service accent is the lamp, and a lamp-filled button is a grey button
    // that reads as disabled. The primary is the ink button, the theme's own
    // FilledButton, and a secondary is the ghost.
    final opener = RegExp(
      r'\b(?:FilledButton|TextButton|OutlinedButton|ElevatedButton|IconButton|'
      r'FloatingActionButton)\.styleFrom\(|\bButtonStyle\(|'
      r'\bexpandedButtonStyle\(|\biconOnlyButtonStyle\(|'
      r'\bFloatingActionButton(?:\.extended)?\(',
    );
    final fill = RegExp(
      r'\b(?:backgroundColor|disabledBackgroundColor)\s*:\s*'
      r'[^,)]*(?:\.accent\b|\baccent\b|\baccentColor\b)',
    );
    final offenders = <String>[];
    for (final file in libFiles) {
      final source = codeOf(file);
      for (final match in opener.allMatches(source)) {
        final body = argumentsFrom(source, match.end - 1);
        final hit = fill.firstMatch(body);
        if (hit == null) continue;
        offenders.add(
          '${file.path}:${lineAt(source, match.start)}  ${hit.group(0)}',
        );
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('the navigation chrome never names an accent', () {
    // The bar, the rail, the window strip, the inspector and the shell draw
    // the selected state as the room's strong fill under the primary ink, and
    // a count as the ink disc. Nothing in them may take a colour per section
    // or per service, so they may not even carry one.
    const chrome = [
      'lib/core/widgets/floating_bottom_nav_bar.dart',
      'lib/features/settings/domain/nav_tab.dart',
      'lib/features/shell/presentation/shell_screen.dart',
      'lib/features/shell/presentation/desktop/desktop_nav_rail.dart',
      'lib/features/shell/presentation/desktop/window_chrome.dart',
      'lib/features/shell/presentation/desktop/inspector_pane.dart',
    ];
    final accent = RegExp(r'\baccent\w*\b|\.accent\b', caseSensitive: false);
    final offenders = <String>[];
    for (final path in chrome) {
      final file = File(path);
      expect(file.existsSync(), isTrue, reason: path);
      final source = codeOf(file);
      for (final hit in accent.allMatches(source)) {
        offenders.add('$path:${lineAt(source, hit.start)}  ${hit.group(0)}');
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
