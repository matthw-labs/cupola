import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_paging.dart';

/// Which violations the tab lists: the ones nobody has looked at, which is
/// where it opens, or every one Tracearr recorded.
enum TracearrViolationScope {
  unseen('Unseen'),
  all('All');

  const TracearrViolationScope(this.label);

  final String label;
}

/// The scope the Violations tab is on. Not remembered across launches: the
/// tab opens on what needs a look.
final tracearrViolationScopeProvider =
    NotifierProvider<TracearrViolationScopeNotifier, TracearrViolationScope>(
      TracearrViolationScopeNotifier.new,
    );

class TracearrViolationScopeNotifier extends Notifier<TracearrViolationScope> {
  @override
  TracearrViolationScope build() => TracearrViolationScope.unseen;

  void choose(TracearrViolationScope scope) => state = scope;
}

/// The Violations tab's state: newest first, a page at a time, narrowed by the
/// scope. A scope that changes rebuilds the list from its first page, since
/// the server does the narrowing.
final tracearrViolationsListProvider =
    AsyncNotifierProvider<
      TracearrViolationsList,
      TracearrRows<TracearrViolation>
    >(TracearrViolationsList.new, retry: noProviderRetry);

class TracearrViolationsList extends TracearrPagedList<TracearrViolation> {
  @override
  Future<TracearrPage<TracearrViolation>> fetch(
    TracearrClient client,
    String? cursor,
  ) {
    final scope = ref.read(tracearrViolationScopeProvider);
    return client.getViolations(
      cursor: cursor,
      filter: scope == TracearrViolationScope.unseen
          ? const TracearrViolationFilter.unseen()
          : const TracearrViolationFilter(),
    );
  }

  @override
  Future<TracearrRows<TracearrViolation>> build() {
    // Watched, so a new scope re-runs the build and reads from the top.
    ref.watch(tracearrViolationScopeProvider);
    return super.build();
  }
}
