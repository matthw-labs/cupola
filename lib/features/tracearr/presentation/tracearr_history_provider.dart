import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_paging.dart';

/// The History tab's state: what was watched, newest first, a page at a time.
///
/// Unfiltered today. The filters (person, server, kind, only watched, period)
/// are applied by the server and never to the pages already read, so each one
/// will narrow [fetch] and rebuild the list from its first page, as the
/// Violations list does for its scope.
final tracearrHistoryProvider =
    AsyncNotifierProvider<
      TracearrHistoryList,
      TracearrRows<TracearrHistoryEntry>
    >(TracearrHistoryList.new, retry: noProviderRetry);

class TracearrHistoryList extends TracearrPagedList<TracearrHistoryEntry> {
  @override
  Future<TracearrPage<TracearrHistoryEntry>> fetch(
    TracearrClient client,
    String? cursor,
  ) => client.getHistory(cursor: cursor);
}
