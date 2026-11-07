import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/home/data/last_known/resume_row_codec.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';

/// A last drawing of Continue watching is restored for every media server and
/// for no other service: a row quietly dropped on a cold start reads as
/// nothing in progress.
void main() {
  const item = StreamItem(
    id: 'm1',
    title: 'Sintel',
    subtitle: '2010',
    kind: StreamItemKind.movie,
    posterPath: null,
    year: 2010,
    runtimeMs: 888000,
    isPlayed: false,
    resumeOffsetMs: 444000,
    unplayedChildCount: null,
  );

  ResumeRow rowOn(ServiceKey service) => (
    service: service,
    instanceId: '${service.name}-1',
    connectionName: null,
    item: item,
  );

  for (final service in mediaServers) {
    test('a ${service.name} row is read back', () {
      final back = resumeRowFromJson(resumeRowToJson(rowOn(service)));
      expect(back?.service, service);
      expect(back?.instanceId, '${service.name}-1');
    });
  }

  test('a row on a service that is no media server is not read back', () {
    for (final service in ServiceKey.values.where((s) => !s.isMediaServer)) {
      expect(
        resumeRowFromJson(resumeRowToJson(rowOn(service))),
        isNull,
        reason: service.name,
      );
    }
  });
}
