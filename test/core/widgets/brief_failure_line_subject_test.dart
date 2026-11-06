import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/widgets/brief_failure_line.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Who a brief failure line says it cannot reach: the player the person
/// watches with by its own name, anything else as the server behind the page.
void main() {
  String headlineOf(ServiceKey? service) => BriefFailureLine.wordsFor(
    ServiceFailureReason.unreachable,
    service: service,
  ).headline;

  for (final service in mediaServers) {
    test('${service.name} is named', () {
      expect(headlineOf(service), Lexicon.cantReach(service.title));
    });
  }

  test('a service that is no media server is the server', () {
    for (final service in ServiceKey.values.where((s) => !s.isMediaServer)) {
      expect(
        headlineOf(service),
        Lexicon.cantReach('the server'),
        reason: service.name,
      );
    }
    expect(headlineOf(null), Lexicon.cantReach('the server'));
  });
}
