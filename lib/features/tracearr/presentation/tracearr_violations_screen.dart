import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_paging.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_violations_provider.dart';

const _service = ServiceKey.tracearr;

/// Violations: the rules that were broken, newest first, a page at a time.
///
/// Opens on the ones nobody has looked at, with a pill to see every one.
/// Severity is said in words (`Low`, `Warning`, `High`) and the row is blue, as
/// everywhere: a rule was broken, which is the person's to read, and nothing
/// Cupola reaches has stopped working. What a violation carries (its places,
/// its addresses) never reaches a row. The detail sheet with the typed render
/// of each known rule, the actions Tracearr took, and Acknowledge and Dismiss
/// are what this file grows into. Its state is
/// [tracearrViolationsListProvider] and the scope it reads.
class TracearrViolationsScreen extends ConsumerWidget {
  const TracearrViolationsScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(currentSettingsProvider).isServiceConfigured(_service)) {
      return NotConfiguredPlaceholder.forService(_service);
    }
    final scope = ref.watch(tracearrViolationScopeProvider);
    final violations = ref.watch(tracearrViolationsListProvider);
    final rows = violations.asData?.value;
    final unseen = scope == TracearrViolationScope.unseen;
    return ServiceListPage<TracearrViolation>.unsummarised(
      service: _service,
      topPadding: topPadding,
      // Outside the state ladder: the other scope is what a person reaches for
      // when this one is empty or did not answer.
      header: SelectionPills<TracearrViolationScope>(
        values: TracearrViolationScope.values,
        selected: scope,
        labelBuilder: (value) => value.label,
        onSelected: ref.read(tracearrViolationScopeProvider.notifier).choose,
      ),
      value: violations.whenData((data) => data.items),
      serviceName: 'Tracearr violations',
      emptyIcon: Icons.flag_outlined,
      emptyTitle: unseen ? 'Nothing unseen' : 'No violations',
      emptyMessage: unseen
          ? 'Every violation Tracearr recorded has been acknowledged.'
          : 'Tracearr has not recorded a rule being broken.',
      onRetry: () => ref.invalidate(tracearrViolationsListProvider),
      footer: rows == null
          ? null
          : TracearrLoadMore(
              rows: rows,
              noun: 'violations',
              onLoadMore: () =>
                  ref.read(tracearrViolationsListProvider.notifier).loadMore(),
            ),
      rowBuilder: (violation) => _ViolationRow(violation: violation),
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
    return ServiceRecordRow(
      icon: Icons.flag_outlined,
      // Blue until somebody has looked; an acknowledged one has been read.
      tone: violation.isAcknowledged ? StatusTone.neutral : StatusTone.info,
      title: title,
      detail: detail,
      trailing: severity,
      semanticLabel: joinSpokenParts([title, severity, detail]),
    );
  }
}
