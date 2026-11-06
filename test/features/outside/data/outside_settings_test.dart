import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/outside/data/outside_settings.dart';
import 'package:cupola/features/outside/domain/outside_notices.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';

/// The switches, kept where the run with the app away reads them.
void main() {
  Future<(ProviderContainer, SharedPreferences)> world(
    Map<String, Object> stored,
  ) async {
    SharedPreferences.setMockInitialValues(stored);
    final prefs = await SharedPreferences.getInstance();
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);
    return (container, prefs);
  }

  test('none is on until the person turns one on', () async {
    final (container, _) = await world({});
    expect(container.read(outsideNoticeKindsProvider), isEmpty);
  });

  test('a switch turned on is kept, and read back', () async {
    final (container, prefs) = await world({});
    await container
        .read(outsideNoticeKindsProvider.notifier)
        .set(OutsideNoticeKind.readyToWatch, on: true);
    expect(container.read(outsideNoticeKindsProvider), {
      OutsideNoticeKind.readyToWatch,
    });
    expect(prefs.getStringList(OutsideNoticeKinds.key), ['readyToWatch']);
    final (again, _) = await world({
      OutsideNoticeKinds.key: ['readyToWatch', 'somethingElse'],
    });
    expect(again.read(outsideNoticeKindsProvider), {
      OutsideNoticeKind.readyToWatch,
    });
  });

  test('a switch turned off leaves the other as it was', () async {
    final (container, prefs) = await world({
      OutsideNoticeKinds.key: ['needsYou', 'readyToWatch'],
    });
    await container
        .read(outsideNoticeKindsProvider.notifier)
        .set(OutsideNoticeKind.needsYou, on: false);
    expect(prefs.getStringList(OutsideNoticeKinds.key), ['readyToWatch']);
  });

  test(
    'Flagged is kept by its name, and leaves the others as they were',
    () async {
      final (container, prefs) = await world({
        OutsideNoticeKinds.key: ['needsYou'],
      });
      await container
          .read(outsideNoticeKindsProvider.notifier)
          .set(OutsideNoticeKind.flagged, on: true);
      expect(prefs.getStringList(OutsideNoticeKinds.key), [
        'needsYou',
        'flagged',
      ]);
      final (again, _) = await world({
        OutsideNoticeKinds.key: ['flagged'],
      });
      expect(again.read(outsideNoticeKindsProvider), {
        OutsideNoticeKind.flagged,
      });
    },
  );
}
