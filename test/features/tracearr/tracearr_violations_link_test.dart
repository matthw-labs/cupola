import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_violations_screen.dart';

import '../../test_helpers/settings_scope.dart';

/// Where a notification of several violations lands: the Violations tab, on
/// the Tracearr the link names.
void main() {
  test('the link names the connection and the tab', () {
    expect(
      ServiceRoutes.tracearrViolationsOn('tracearr-2'),
      '/stack/tracearr/violations?i=tracearr-2',
    );
    expect(
      ServiceRoutes.tracearrViolationsOn('tracearr-2'),
      startsWith(ServiceRoutes.tracearrViolations),
    );
  });

  Future<ProviderContainer> open(
    WidgetTester tester,
    String? instanceId,
  ) async {
    final container = ProviderContainer(
      overrides: [
        ...await settingsScopeOverrides(
          configured: const [ServiceKey.tracearr, ServiceKey.radarr],
          customize: (settings) => settings.copyWithInstance(
            const ServiceInstance(
              id: 'tracearr-2',
              service: ServiceKey.tracearr,
              label: '4K',
              url: 'https://four-k.test',
              credential: 'k',
            ),
          ),
        ),
        tracearrClientProvider.overrideWithValue(_Quiet()),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.darkTheme(),
          home: Scaffold(
            body: TracearrViolationsScreen(instanceId: instanceId),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  String? lens(ProviderContainer container) =>
      container.read(activeInstanceProvider(ServiceKey.tracearr))?.id;

  testWidgets('brings the Tracearr a notification came off under the lens', (
    tester,
  ) async {
    final container = await open(tester, null);
    expect(lens(container), 'tracearr');
    final other = await open(tester, 'tracearr-2');
    expect(lens(other), 'tracearr-2');
  });

  testWidgets('a link with no connection leaves the lens where it is', (
    tester,
  ) async {
    final container = await open(tester, null);
    expect(lens(container), 'tracearr');
  });

  testWidgets('an id that is not one of Tracearr\'s is ignored', (
    tester,
  ) async {
    final container = await open(tester, 'radarr');
    expect(lens(container), 'tracearr');
    final gone = await open(tester, 'a-connection-removed-since');
    expect(lens(gone), 'tracearr');
  });
}

class _Quiet extends TracearrClient {
  _Quiet() : super(baseUrl: 'http://tracearr.test', apiKey: 'trr_pub_test');

  @override
  Future<TracearrPage<TracearrViolation>> getViolations({
    String? cursor,
    int pageSize = 25,
    TracearrViolationFilter filter = const TracearrViolationFilter(),
  }) async => const TracearrPage(items: []);
}
