import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_paging.dart';

/// Whether the Users tab also lists people whose every account was removed from
/// the servers. Off: Tracearr does not list them either, and the tab opens on
/// the people who are still there. Not remembered across launches, like the
/// Violations scope: it is a look at the past, not a preference.
final tracearrIncludeRemovedProvider =
    NotifierProvider<TracearrIncludeRemovedNotifier, bool>(
      TracearrIncludeRemovedNotifier.new,
    );

class TracearrIncludeRemovedNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

/// The Users tab's state: the people Tracearr knows, a page at a time.
///
/// Removed people are left out unless asked for
/// ([tracearrIncludeRemovedProvider]): the server does the filtering
/// (`include_removed`), and a page is never trimmed after it was counted. The
/// choice rebuilds the list from its first page.
final tracearrUsersListProvider =
    AsyncNotifierProvider<TracearrUsersList, TracearrRows<TracearrUser>>(
      TracearrUsersList.new,
      retry: noProviderRetry,
    );

class TracearrUsersList extends TracearrPagedList<TracearrUser> {
  @override
  Future<TracearrRows<TracearrUser>> build() {
    ref.watch(tracearrIncludeRemovedProvider);
    return super.build();
  }

  @override
  Future<TracearrPage<TracearrUser>> fetch(
    TracearrClient client,
    String? cursor,
  ) => client.getUsers(
    cursor: cursor,
    includeRemoved: ref.read(tracearrIncludeRemovedProvider),
  );
}
