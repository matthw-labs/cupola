import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/data/tracearr_violation_owner.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_paging.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

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

/// The severity the tab is narrowed to, or null for every one. The server
/// does the narrowing, like the scope: a downloaded page is never trimmed
/// here, since a page that filters to nothing would read as "no violations"
/// while later pages hold plenty.
final tracearrViolationSeverityProvider =
    NotifierProvider<TracearrViolationSeverityNotifier, TracearrSeverity?>(
      TracearrViolationSeverityNotifier.new,
    );

class TracearrViolationSeverityNotifier extends Notifier<TracearrSeverity?> {
  @override
  TracearrSeverity? build() => null;

  void choose(TracearrSeverity? severity) => state = severity;
}

final RegExp _uuid = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{12}$',
);

/// The person a link names (`?user=`), or null for no filter.
///
/// Tracearr answers a 400 to a `user_id` that is not a UUID, which the tab
/// would show as a failure of Tracearr. A link with anything else in it (an
/// old link, a hand-written one) opens the tab unfiltered instead.
String? tracearrUserParam(String? value) {
  final id = value?.trim() ?? '';
  return _uuid.hasMatch(id) ? id : null;
}

/// The Violations tab's state: newest first, a page at a time, narrowed by the
/// scope, the severity and, from a link, one person ([userId], null for
/// everyone). A filter that changes rebuilds the list from its first page,
/// since the server does the narrowing.
final tracearrViolationsListProvider =
    AsyncNotifierProvider.family<
      TracearrViolationsList,
      TracearrRows<TracearrViolation>,
      String?
    >(TracearrViolationsList.new, retry: noProviderRetry);

class TracearrViolationsList extends TracearrPagedList<TracearrViolation> {
  TracearrViolationsList(this.userId);

  /// Tracearr's id for the person the list is narrowed to, or null.
  final String? userId;

  @override
  Future<TracearrPage<TracearrViolation>> fetch(
    TracearrClient client,
    String? cursor,
  ) {
    final scope = ref.read(tracearrViolationScopeProvider);
    final severity = ref.read(tracearrViolationSeverityProvider);
    return client.getViolations(
      cursor: cursor,
      filter: TracearrViolationFilter(
        userId: userId,
        severity: severity,
        acknowledged: scope == TracearrViolationScope.unseen ? false : null,
      ),
    );
  }

  @override
  Future<TracearrRows<TracearrViolation>> build() {
    // Watched, so a new filter re-runs the build and reads from the top.
    ref.watch(tracearrViolationScopeProvider);
    ref.watch(tracearrViolationSeverityProvider);
    return super.build();
  }
}

/// The name of the person a filter names, for the line that says the list is
/// narrowed. Null when Tracearr does not know the id or did not answer: the
/// line then says `this person`, which is true and costs nothing.
final tracearrViolationUserNameProvider =
    FutureProvider.family<String?, String>((ref, userId) async {
      final user = await ref.watch(tracearrClientProvider).getUser(userId);
      final name = user?.displayName.trim() ?? '';
      return name.isEmpty ? null : name;
    }, retry: noProviderRetry);

/// Which violation, on which connection: the key of one detail read.
/// [instanceId] is empty for the lens.
typedef TracearrViolationKey = ({String id, String instanceId});

/// One violation with the actions Tracearr took, or null when it is gone.
///
/// Read through the connection the link named (or the lens), so a card in
/// Needs you that came off a second Tracearr opens on that one.
final tracearrViolationProvider =
    FutureProvider.family<TracearrViolation?, TracearrViolationKey>(
      (ref, key) => ref
          .watch(tracearrClientForProvider(key.instanceId))
          .getViolation(key.id),
      retry: noProviderRetry,
    );

/// The owner's two writes for a connection (empty id: the lens), or null while
/// no owner is signed in on it.
///
/// Null here is what dims Acknowledge and Dismiss and sends their tap to the
/// connection's settings. The owner's sign-in lot overrides this body with the
/// owner client it builds from the connection's reach, which is the only
/// change the violation screens need.
final tracearrViolationOwnerProvider =
    Provider.family<TracearrViolationOwner?, String>((ref, instanceId) => null);
