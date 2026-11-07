/// What Continue watching reads: the titles somebody started and did not
/// finish, on every media server.
library;

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';

/// How many titles the module draws.
const continueWatchingRowLimit = 3;

/// One title started and not finished, on the connection that holds it.
typedef ResumeRow = ({
  ServiceKey service,
  String instanceId,
  String? connectionName,
  StreamItem item,
});

/// The rows, in connection order and each server's own order (the most
/// recently played first); which connections answered; and the Jellyfin
/// connections that wait for somebody to say who "you" are.
typedef HomeResume = ({
  List<ResumeRow> rows,
  SourceCoverage coverage,
  List<String> viewerMissing,
});

/// Every media server connection asked what is in progress, together.
///
/// A Jellyfin with no household member chosen is not asked: its resume is
/// user-scoped, and it is listed in [HomeResume.viewerMissing] for the module
/// to ask who you are. A Plex's token is its user. Plex's hub also carries the
/// next episode of a series nobody has started; only what has a position
/// counts as started.
final homeResumeProvider = FutureProvider.autoDispose<HomeResume>((ref) async {
  final settings = ref.watch(currentSettingsProvider);
  final cancelToken = CancelToken();
  ref.onDispose(cancelToken.cancel);
  final missing = <String>[];
  final reads = <Future<(List<ResumeRow>, SourceCoverage)>>[];
  for (final service in mediaServers) {
    final backend = streamBackendOf(service);
    for (final instance in settings.configuredInstancesOf(service)) {
      final name = settings.connectionName(instance.id);
      if (service.needsViewerSelection && instance.viewerId.trim().isEmpty) {
        missing.add(instance.id);
        continue;
      }
      final items = ref
          .watch(backend.clientFor(instance.id))
          .getContinueWatching(
            // Plex's hub also carries the next episode of a series nobody has
            // started, which `isInProgress` drops below, so it is asked for twice
            // what is drawn to still have enough left.
            count: service == ServiceKey.plex
                ? continueWatchingRowLimit * 2
                : continueWatchingRowLimit,
            cancelToken: cancelToken,
          );
      reads.add(
        items.then(
          (items) => (
            [
              for (final item in items)
                if (item.isInProgress)
                  (
                    service: service,
                    instanceId: instance.id,
                    connectionName: name,
                    item: item,
                  ),
            ],
            SourceCoverage.answeredBy(
              service,
              instanceId: instance.id,
              name: name,
            ),
          ),
          onError: (Object error) => (
            const <ResumeRow>[],
            SourceCoverage.failure(
              service,
              error,
              instanceId: instance.id,
              name: name,
            ),
          ),
        ),
      );
    }
  }
  final answers = await Future.wait(reads);
  final seen = <String>{};
  return (
    rows: [
      for (final (rows, _) in answers)
        for (final row in rows)
          if (seen.add('${row.instanceId}/${row.item.id}')) row,
    ],
    coverage: SourceCoverage.merge([for (final (_, c) in answers) c]),
    viewerMissing: missing,
  );
}, retry: noProviderRetry);
