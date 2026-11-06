import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_paging.dart';

/// The Users tab's state: the people Tracearr knows, a page at a time.
///
/// People whose every account was removed are left out, as Tracearr leaves
/// them out of its own list: asked for without `include_removed`, the server
/// does the filtering, and a page is never trimmed after it was counted.
final tracearrUsersListProvider =
    AsyncNotifierProvider<TracearrUsersList, TracearrRows<TracearrUser>>(
      TracearrUsersList.new,
      retry: noProviderRetry,
    );

class TracearrUsersList extends TracearrPagedList<TracearrUser> {
  @override
  Future<TracearrPage<TracearrUser>> fetch(
    TracearrClient client,
    String? cursor,
  ) => client.getUsers(cursor: cursor);
}
