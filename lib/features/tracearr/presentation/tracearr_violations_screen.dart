import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_paging.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_violations_provider.dart';

const _service = ServiceKey.tracearr;

/// Violations: the rules that were broken, newest first, a page at a time.
///
/// Opens on the ones nobody has looked at, with a pill to see every one and a
/// row of pills for the severity, both asked of the server. [userId] is the
/// person a link narrows it to (`?user=`, which the Users tab leads with): a
/// line above the list says so and takes the filter off. A value that is not
/// a Tracearr user id is ignored, since the server answers it with a 400.
///
/// Severity is said in words (`Low`, `Warning`, `High`) and the row is blue,
/// as everywhere: a rule was broken, which is the person's to read, and
/// nothing Cupola reaches has stopped working. An acknowledged one has been
/// read and rests. What a violation carries (its places, its addresses) never
/// reaches a row; a row opens the violation's own page
/// (`TracearrViolationScreen`). Its state is
/// [tracearrViolationsListProvider] and the filters it reads.
class TracearrViolationsScreen extends ConsumerStatefulWidget {
  const TracearrViolationsScreen({super.key, this.topPadding = 0, this.userId});

  final double topPadding;

  /// Tracearr's id for the person the tab is narrowed to, as the link gave it.
  final String? userId;

  @override
  ConsumerState<TracearrViolationsScreen> createState() =>
      _TracearrViolationsScreenState();
}

class _TracearrViolationsScreenState
    extends ConsumerState<TracearrViolationsScreen> {
  /// The person the list is narrowed to. Seeded from the link and moved by it
  /// when the link changes; taking the filter off sets it to null and stays
  /// until another link names somebody.
  String? _user;

  @override
  void initState() {
    super.initState();
    _user = tracearrUserParam(widget.userId);
  }

  @override
  void didUpdateWidget(TracearrViolationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId) {
      _user = tracearrUserParam(widget.userId);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(currentSettingsProvider).isServiceConfigured(_service)) {
      return NotConfiguredPlaceholder.forService(_service);
    }
    final scope = ref.watch(tracearrViolationScopeProvider);
    final severity = ref.watch(tracearrViolationSeverityProvider);
    final violations = ref.watch(tracearrViolationsListProvider(_user));
    final rows = violations.asData?.value;
    final unseen = scope == TracearrViolationScope.unseen;
    final narrowed = severity != null || _user != null;
    return ServiceListPage<TracearrViolation>.unsummarised(
      service: _service,
      topPadding: widget.topPadding,
      // Outside the state ladder: the other scope is what a person reaches for
      // when this one is empty or did not answer.
      header: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SelectionPills<TracearrViolationScope>(
            values: TracearrViolationScope.values,
            selected: scope,
            labelBuilder: (value) => value.label,
            onSelected: ref
                .read(tracearrViolationScopeProvider.notifier)
                .choose,
          ),
          // Whole, not a row to scroll: four answers, and a severity scrolled
          // off the edge is one that cannot be chosen.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: SelectionPills<TracearrSeverity?>.wrap(
              values: const [
                null,
                TracearrSeverity.low,
                TracearrSeverity.warning,
                TracearrSeverity.high,
              ],
              selected: severity,
              labelBuilder: (value) =>
                  value == null ? 'Any severity' : tracearrSeverityWord(value),
              onSelected: ref
                  .read(tracearrViolationSeverityProvider.notifier)
                  .choose,
            ),
          ),
          if (_user case final user?)
            _UserFilterLine(
              userId: user,
              onClear: () => setState(() => _user = null),
            ),
        ],
      ),
      value: violations.whenData((data) => data.items),
      serviceName: 'Tracearr violations',
      emptyIcon: Icons.flag_outlined,
      emptyTitle: narrowed
          ? 'No violations match'
          : unseen
          ? 'Nothing unseen'
          : 'No violations',
      emptyMessage: narrowed
          ? 'Nothing Tracearr recorded fits these filters.'
          : unseen
          ? 'Every violation Tracearr recorded has been acknowledged.'
          : 'Tracearr has not recorded a rule being broken.',
      onRetry: () => ref.invalidate(tracearrViolationsListProvider(_user)),
      footer: rows == null
          ? null
          : TracearrLoadMore(
              rows: rows,
              noun: 'violations',
              onLoadMore: () => ref
                  .read(tracearrViolationsListProvider(_user).notifier)
                  .loadMore(),
            ),
      rowBuilder: (violation) => _ViolationRow(violation: violation),
    );
  }
}

/// `Only Anna's violations`, and the way back to everyone's. The name is read
/// from Tracearr; until it is, or if it cannot be, the line says `this person`.
class _UserFilterLine extends ConsumerWidget {
  const _UserFilterLine({required this.userId, required this.onClear});

  final String userId;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final name = ref.watch(tracearrViolationUserNameProvider(userId)).value;
    final line = name == null
        ? 'Only violations of this person'
        : "Only $name's violations";
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              line,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: CupolaThemeColors.of(context).dimText,
              ),
            ),
          ),
          TextButton(
            onPressed: onClear,
            style: TextButton.styleFrom(minimumSize: const Size(56, 44)),
            child: const Text('Show everyone'),
          ),
        ],
      ),
    );
  }
}

class _ViolationRow extends StatelessWidget {
  const _ViolationRow({required this.violation});

  final TracearrViolation violation;

  @override
  Widget build(BuildContext context) {
    final title = violation.rule.name.trim().isEmpty
        ? 'Violation'
        : violation.rule.name.trim();
    final created = violation.createdAt;
    final detail = joinDisplayParts([
      tracearrPersonOf(violation.person),
      tracearrServerOf(violation.server),
      created == null ? null : formatRelativeDateTime(created),
      violation.isAcknowledged ? 'Acknowledged' : null,
    ]);
    final severity = tracearrSeverityWord(violation.severity);
    return PressableScale(
      onTap: () => context.push(ServiceRoutes.tracearrViolation(violation.id)),
      semanticHint: 'opens the violation',
      child: ServiceRecordRow(
        icon: Icons.flag_outlined,
        // Blue until somebody has looked; an acknowledged one has been read.
        tone: violation.isAcknowledged ? StatusTone.neutral : StatusTone.info,
        title: title,
        detail: detail,
        trailing: severity,
        semanticLabel: joinSpokenParts([title, severity, detail]),
      ),
    );
  }
}
