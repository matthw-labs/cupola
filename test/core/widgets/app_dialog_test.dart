import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// Every ink the dialog paints: text, glyphs (an `Icon` is a `RichText` too)
/// and the fill of every `Material`, which is where a button's background
/// lands.
List<Color> _inksIn(WidgetTester tester) {
  final dialog = find.byType(AlertDialog);
  final inks = <Color>[];
  for (final paragraph in tester.renderObjectList<RenderParagraph>(
    find.descendant(of: dialog, matching: find.byType(RichText)),
  )) {
    void visit(InlineSpan span) {
      final color = span.style?.color;
      if (color != null) inks.add(color);
      if (span is TextSpan) span.children?.forEach(visit);
    }

    visit(paragraph.text);
  }
  for (final material in tester.widgetList<Material>(
    find.descendant(of: dialog, matching: find.byType(Material)),
  )) {
    final color = material.color;
    if (color != null && color.a > 0) inks.add(color);
  }
  return inks;
}

/// Red in every form the app knows how to paint it: the scheme's error and
/// error container, the palette constant, and the tone's walked inks on the
/// dialog and on the 10% wash the old danger note sat on. (`onError` and
/// `onErrorContainer` are inks *for* red grounds (white in dark), so they are
/// not red themselves and would only match the dialog's own label ink.)
Set<Color> _reds(ThemeData theme) {
  final scheme = theme.colorScheme;
  final dialogSurface =
      theme.dialogTheme.backgroundColor ?? scheme.surfaceContainerHigh;
  return {
    scheme.error,
    scheme.errorContainer,
    AppColors.error,
    statusToneFill(scheme, StatusTone.error),
    statusToneColor(scheme, StatusTone.error),
    statusToneColor(scheme, StatusTone.error, surface: dialogSurface),
    statusToneColor(
      scheme,
      StatusTone.error,
      surface: dialogSurface,
      tintAlpha: 0.10,
    ),
  };
}

/// A hue check under the exact set, so a red walked some new way is caught
/// too. The brand indigo, the neutrals and the barrier all sit well outside it.
bool _isReddish(Color color) {
  final hsl = HSLColor.fromColor(color.withValues(alpha: 1));
  return (hsl.hue < 20 || hsl.hue > 340) &&
      hsl.saturation > 0.45 &&
      hsl.lightness > 0.2 &&
      hsl.lightness < 0.85;
}

Future<void> _open(
  WidgetTester tester,
  ThemeData theme,
  void Function(BuildContext context) open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => open(context),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final brightness in Brightness.values) {
    final theme = brightness == Brightness.light
        ? AppTheme.lightTheme()
        : AppTheme.darkTheme();

    group('showAppConfirmDialog on the ${brightness.name} theme', () {
      testWidgets('a delete paints no red anywhere, ticked or not', (
        tester,
      ) async {
        await _open(
          tester,
          theme,
          (context) => showAppConfirmDialog(
            context: context,
            icon: Icons.delete_outline_rounded,
            title: 'Delete Nosferatu?',
            message: 'This will remove this movie from Radarr.',
            confirmLabel: 'Delete movie',
            confirmLabelFor: (checked) => checked('deleteFiles')
                ? 'Delete movie and files'
                : 'Delete movie',
            options: const [
              AppConfirmOption(
                key: 'deleteFiles',
                label: 'Delete files',
                subtitle:
                    'Deletes the downloaded files from disk. This cannot be '
                    'undone.',
              ),
            ],
          ),
        );

        final reds = _reds(theme);
        void expectNoRed(String when) {
          for (final ink in _inksIn(tester)) {
            expect(reds.contains(ink), isFalse, reason: '$ink $when');
            expect(_isReddish(ink), isFalse, reason: '$ink $when');
          }
        }

        expectNoRed('before ticking');
        await tester.tap(find.byType(Checkbox));
        await tester.pumpAndSettle();
        expectNoRed('with the files option ticked');

        // The glyph is plain title ink, and the confirm is the theme's own
        // button: no style of its own to paint anything with.
        expect(
          tester.widget<Icon>(find.byIcon(Icons.delete_outline_rounded)).color,
          theme.colorScheme.onSurface,
        );
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).style,
          isNull,
        );
        // No banner, no warning glyph: the sentence is the subtitle's.
        expect(find.byIcon(Icons.warning_rounded), findsNothing);
        expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
        expect(
          find.text(
            'Deletes the downloaded files from disk. This cannot be undone.',
          ),
          findsOneWidget,
        );
      });

      testWidgets('the typed confirmation paints no red either', (
        tester,
      ) async {
        await _open(
          tester,
          theme,
          (context) => showAppTypedConfirmDialog(
            context,
            icon: Icons.power_settings_new_rounded,
            title: 'Shut down nas?',
            message: 'Everything on this host stops.',
            phrase: 'nas',
            confirmLabel: 'Shut down server',
          ),
        );

        final reds = _reds(theme);
        for (final ink in _inksIn(tester)) {
          expect(reds.contains(ink), isFalse, reason: '$ink');
          expect(_isReddish(ink), isFalse, reason: '$ink');
        }
        expect(
          tester.widget<FilledButton>(find.byType(FilledButton)).style,
          isNull,
        );
        expect(find.byIcon(Icons.warning_amber_rounded), findsNothing);
      });
    });
  }

  testWidgets('the confirm label follows the options it depends on', (
    tester,
  ) async {
    AppConfirmResult? result;
    await _open(tester, AppTheme.darkTheme(), (context) async {
      result = await showAppConfirmDialog(
        context: context,
        title: 'Remove Metropolis?',
        confirmLabel: 'Remove torrent',
        confirmLabelFor: (checked) => checked('deleteData')
            ? 'Remove and delete files'
            : 'Remove torrent',
        options: const [
          AppConfirmOption(key: 'deleteData', label: 'Also delete the files'),
        ],
      );
    });

    expect(find.widgetWithText(FilledButton, 'Remove torrent'), findsOneWidget);
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(
      find.widgetWithText(FilledButton, 'Remove and delete files'),
      findsOneWidget,
    );
    expect(find.widgetWithText(FilledButton, 'Remove torrent'), findsNothing);

    await tester.tap(find.text('Remove and delete files'));
    await tester.pumpAndSettle();
    expect(result?.confirmed, isTrue);
    expect(result?.option('deleteData'), isTrue);
  });

  testWidgets('the typed confirmation stays inert until the phrase is typed', (
    tester,
  ) async {
    bool? confirmed;
    await _open(tester, AppTheme.darkTheme(), (context) async {
      confirmed = await showAppTypedConfirmDialog(
        context,
        title: 'Take media.example.com offline?',
        message: 'Anyone using it gets a connection error.',
        phrase: 'media.example.com',
        confirmLabel: 'Take offline',
      );
    });

    FilledButton button() =>
        tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button().onPressed, isNull);

    // Trimmed and case-insensitive, because hostnames are.
    await tester.enterText(find.byType(TextField), '  Media.Example.com ');
    await tester.pump();
    expect(button().onPressed, isNotNull);

    await tester.tap(find.text('Take offline'));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
  });

  testWidgets('the typed confirmation opens with its field ready to type in', (
    tester,
  ) async {
    await _open(
      tester,
      AppTheme.darkTheme(),
      (context) => showAppTypedConfirmDialog(
        context,
        title: 'Shut down nas?',
        message: 'Everything on this host stops.',
        phrase: 'nas',
        confirmLabel: 'Shut down server',
      ),
    );

    final focused = FocusManager.instance.primaryFocus?.context;
    expect(focused?.findAncestorWidgetOfExactType<TextField>(), isNotNull);
  });

  testWidgets('a long title is shown whole, and the buttons stay in view', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const name =
        'Big.Buck.Bunny.2008.Remastered.Directors.Cut.2160p.UHD.BluRay.'
        'REMUX.HDR10.HEVC.DTS-HD.MA.7.1-SomeReleaseGroupWithALongName';
    await _open(tester, AppTheme.darkTheme(), (context) {
      showAppConfirmDialog(
        context: context,
        title: 'Remove $name?',
        confirmLabel: 'Remove torrent',
      );
    });

    final title = tester.widget<Text>(find.text('Remove $name?'));
    expect(title.maxLines, isNull);
    expect(title.overflow, isNot(TextOverflow.ellipsis));
    final button = tester.getRect(
      find.widgetWithText(FilledButton, 'Remove torrent'),
    );
    expect(button.bottom, lessThanOrEqualTo(600));
    expect(tester.takeException(), isNull);
  });

  group('Enter on showAppConfirmDialog', () {
    Future<void> openApprove(
      WidgetTester tester,
      void Function(AppConfirmResult result) onResult, {
      bool enterConfirms = true,
    }) => _open(tester, AppTheme.darkTheme(), (context) async {
      onResult(
        await showAppConfirmDialog(
          context: context,
          title: 'Approve this request?',
          confirmLabel: 'Approve request',
          enterConfirms: enterConfirms,
        ),
      );
    });

    testWidgets('runs the confirm when the dialog opts in', (tester) async {
      AppConfirmResult? result;
      await openApprove(tester, (r) => result = r);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(result?.confirmed, isTrue);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('the keypad Enter runs the confirm too', (tester) async {
      AppConfirmResult? result;
      await openApprove(tester, (r) => result = r);

      await tester.sendKeyEvent(LogicalKeyboardKey.numpadEnter);
      await tester.pumpAndSettle();

      expect(result?.confirmed, isTrue);
    });

    testWidgets('does nothing when the dialog did not opt in', (tester) async {
      AppConfirmResult? result;
      await openApprove(tester, (r) => result = r, enterConfirms: false);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(result, isNull);
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('on the focused Cancel it cancels, not confirms', (
      tester,
    ) async {
      AppConfirmResult? result;
      await openApprove(tester, (r) => result = r);

      // Cancel is the first control in the dialog, so one Tab lands on it.
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(result?.confirmed, isFalse);
    });

    testWidgets('on the focused confirm it confirms', (tester) async {
      AppConfirmResult? result;
      await openApprove(tester, (r) => result = r);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();

      expect(result?.confirmed, isTrue);
    });
  });
}
