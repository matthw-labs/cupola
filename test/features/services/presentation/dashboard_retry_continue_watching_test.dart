import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../../test_helpers/settings_scope.dart';

/// A Retry from Needs you on a media server asks Continue watching again: left
/// cached, the module went on saying the server did not answer after the
/// server had.
void main() {
  Future<void> expectRetryReads(
    WidgetTester tester,
    ServiceKey retried, {
    required bool resumeAsksAgain,
  }) async {
    var reads = 0;
    late WidgetRef ref;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...await settingsScopeOverrides(configured: [retried]),
          homeResumeProvider.overrideWith((ref) async {
            reads++;
            return (
              rows: const <ResumeRow>[],
              coverage: SourceCoverage.none,
              viewerMissing: const <String>[],
            );
          }),
        ],
        child: Consumer(
          builder: (context, r, _) {
            ref = r;
            r.watch(homeResumeProvider);
            return const SizedBox();
          },
        ),
      ),
    );
    await tester.pump();
    expect(reads, 1);

    retryDashboardServices(ref, {retried});
    await tester.pump();
    await tester.pump();
    expect(reads, resumeAsksAgain ? 2 : 1, reason: retried.name);
  }

  for (final service in mediaServers) {
    testWidgets('a Retry on ${service.name} reads Continue watching again', (
      tester,
    ) async {
      await expectRetryReads(tester, service, resumeAsksAgain: true);
    });
  }

  testWidgets('a Retry on a service that is no media server leaves it', (
    tester,
  ) async {
    await expectRetryReads(tester, ServiceKey.seerr, resumeAsksAgain: false);
  });
}
