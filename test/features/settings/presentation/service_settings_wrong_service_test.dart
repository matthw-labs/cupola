/// A form whose test finds another service of the stack at the address says
/// which one, and offers its form on that address: `This is Emby`, not only
/// "Emby answered, not Jellyfin".
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/router.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';

import '../../../test_helpers/profiles/profiles.dart';

void main() {
  testWidgets('a Jellyfin form pointed at an Emby says so, and Set up Emby '
      'opens Emby\'s form on the same address', (tester) async {
    final harness = await ProfileHarness.start(
      Profiles.p1.withBehaviour(
        WorldIds.jellyfin,
        const ConnectionBehaviour.answersAsOtherService(ServiceKey.emby),
      ),
    );
    final container = harness.container();
    final router = container.read(routerProvider);
    await tester.binding.setSurfaceSize(const Size(430, 2600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          theme: AppTheme.darkTheme(),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
        ),
      ),
    );
    router.go(
      ServiceRoutes.settingsForConnection(
        ServiceKey.jellyfin,
        WorldIds.jellyfin,
      ),
    );
    await harness.settle(tester);

    final test = find.text('Test connection');
    await tester.ensureVisible(test);
    await tester.pumpAndSettle();
    await tester.tap(test);
    await harness.settle(tester);

    expect(find.text('This is Emby'), findsOneWidget);
    expect(
      find.textContaining('Emby answered at nas.home.arpa:8096, not Jellyfin.'),
      findsOneWidget,
    );
    final remedy = find.widgetWithText(FilledButton, 'Set up Emby');
    expect(remedy, findsOneWidget);
    expect(tester.getSize(remedy).height, greaterThanOrEqualTo(44));

    await tester.ensureVisible(remedy);
    await tester.pumpAndSettle();
    await tester.tap(remedy);
    await harness.settle(tester);

    final form = tester.widget<ServiceSettingsScreen>(
      find.byType(ServiceSettingsScreen),
    );
    expect(form.service, ServiceKey.emby);
    expect(form.isNew, isTrue);
    expect(form.prefillUrl, 'http://nas.home.arpa:8096');
    // The address is in the field; the key is never carried over.
    final fields = tester
        .widgetList<EditableText>(find.byType(EditableText))
        .map((field) => field.controller.text);
    expect(fields, contains('http://nas.home.arpa:8096'));
    expect(
      router.state.uri.toString(),
      isNot(contains(WorldConnections.jellyfin.instance.credential)),
    );

    // Past the idle close of the clients the app opened.
    await harness.unmount(tester);
    await tester.pump(const Duration(minutes: 2));
  });
}
