import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/data/tracearr_owner_accounts.dart';
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

/// Whether [value] is spelt like one of Tracearr's ids, which are UUIDs. The
/// server answers a 400 to anything else where an id is asked for, and a 400
/// reads as a failure of Tracearr when the id is only a bad link.
bool isTracearrId(String value) => _uuid.hasMatch(value.trim());

/// The person a link names (`?user=`), or null for no filter.
///
/// Tracearr answers a 400 to a `user_id` that is not a UUID, which the tab
/// would show as a failure of Tracearr. A link with anything else in it (an
/// old link, a hand-written one) opens the tab unfiltered instead.
String? tracearrUserParam(String? value) {
  final id = value?.trim() ?? '';
  return isTracearrId(id) ? id : null;
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
///
/// An id that is not spelt like Tracearr's is a violation that is not there,
/// answered with no request: the server would call it a 400, and an old link
/// or a bad notification payload would read as a failure of Tracearr with a
/// Retry that cannot succeed.
final tracearrViolationProvider =
    FutureProvider.family<TracearrViolation?, TracearrViolationKey>((ref, key) {
      if (!isTracearrId(key.id)) return Future.value();
      return ref
          .watch(tracearrClientForProvider(key.instanceId))
          .getViolation(key.id);
    }, retry: noProviderRetry);

/// The owner's two writes for a connection (empty id: the lens), or null while
/// no owner is signed in on it.
///
/// The owner's client, built from the connection's route (`watchTransport`,
/// so the address, the gateway's access and the pin are the ones that answer
/// now) with the bearer held in the connection's owner session. Null here is
/// what dims Acknowledge and Dismiss and sends their tap to the connection's
/// settings. Rebuilt, and the old client closed, when the session or the
/// route changes; a session the server ended is emptied in storage and the
/// provider answers null again (blue `Signed out of Tracearr`, never a fault).
///
/// Not configured, or no session: null, with nothing watched below it.
final tracearrViolationOwnerProvider =
    Provider.family<TracearrViolationOwner?, String>((ref, instanceId) {
      final transport = watchTransport(
        ref,
        ServiceKey.tracearr,
        instanceId: instanceId,
      );
      if (!transport.configured) return null;
      final token = ref.watch(
        currentSettingsProvider.select(
          (settings) =>
              settings.instanceById(transport.instanceId)?.owner?.token ?? '',
        ),
      );
      if (token.isEmpty) return null;
      final client = ref.watch(tracearrOwnerClientFactoryProvider)(
        reach: (
          url: transport.url,
          access: transport.access,
          pin: transport.pin,
        ),
        token: token,
        events: tracearrOwnerEvents(ref, transport.instanceId, token: token),
        onlyAtHome: transport.onlyAtHomeOf(ServiceKey.tracearr),
      );
      ref.onDispose(client.close);
      return client;
    });

/// The connections whose Tracearr answered that it has no route for the owner's
/// writes, by id: the controls leave every violation page for the rest of the
/// run, since the next page would ask the same server the same question.
/// Not remembered across launches: an upgraded Tracearr gets another try.
final tracearrOwnerRoutesAbsentProvider =
    NotifierProvider<TracearrOwnerRoutesAbsent, Set<String>>(
      TracearrOwnerRoutesAbsent.new,
    );

class TracearrOwnerRoutesAbsent extends Notifier<Set<String>> {
  @override
  Set<String> build() => const {};

  void mark(String instanceId) {
    if (state.contains(instanceId)) return;
    state = {...state, instanceId};
  }
}
