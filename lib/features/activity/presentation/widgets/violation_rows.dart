/// What Needs you draws for Tracearr's violations: one blue line that counts
/// them, then a row each saying the rule, the person and when. Not cards of
/// faults: a rule was broken by a person and nothing stopped working, so the
/// tone is blue and there is no remedy, only the door to the violation.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart'
    show HomeRowArt;
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The violations among [decisions], newest first, at most
/// [kNeedsYouViolationCap] of them, and whether the list is a floor.
///
/// The source reads one past the cap, so a longer list is told apart from one
/// that ends there: `count` is then the cap and [floor] is true, and the
/// heading says `5+`, never `6`.
({List<DashboardDecision> shown, int count, bool floor}) violationsOf(
  Iterable<DashboardDecision> decisions,
) {
  final all = [
    for (final decision in decisions)
      if (decision.kind == DecisionKind.violation) decision,
  ];
  // Newest first: the read was of the newest, so the ones shown are the latest
  // the owner has not looked at.
  all.sort((a, b) {
    final atA = a.occurredAt;
    final atB = b.occurredAt;
    if (atA == null || atB == null) {
      return atA == null && atB == null ? 0 : (atA == null ? 1 : -1);
    }
    return atB.compareTo(atA);
  });
  final floor = all.length > kNeedsYouViolationCap;
  final shown = all.take(kNeedsYouViolationCap).toList(growable: false);
  return (shown: shown, count: shown.length, floor: floor);
}

/// `3 violations to review`, `5+ violations to review`.
String violationsWaitLine(int count, {bool floor = false}) {
  final figure = floor ? Lexicon.floor(count) : '$count';
  return '$figure ${count == 1 && !floor ? 'violation' : 'violations'} '
      'to review';
}

/// The line that counts them and the rows, for Needs you's blue group. Empty
/// when there are none.
List<Widget> violationRowsOf(
  ({List<DashboardDecision> shown, int count, bool floor}) violations,
  Color blue,
) {
  if (violations.count == 0) return const [];
  return [
    Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Semantics(
        header: true,
        label: violations.floor
            ? 'At least ${violationsWaitLine(violations.count)}'
            : violationsWaitLine(violations.count),
        excludeSemantics: true,
        child: Row(
          children: [
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(shape: BoxShape.circle, color: blue),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                violationsWaitLine(violations.count, floor: violations.floor),
                style: AppType.label.copyWith(color: blue),
              ),
            ),
          ],
        ),
      ),
    ),
    for (final (index, decision) in violations.shown.indexed)
      ViolationDecisionRow(
        key: ValueKey(decision.id),
        decision: decision,
        divided: index > 0,
      ),
  ];
}

/// One violation waiting for a look: the rule, then who and when, and the
/// whole row opens the violation. No trailing control: the page it opens is
/// where the owner acknowledges or dismisses it, and a second door to the same
/// page would only be a second thing to find.
class ViolationDecisionRow extends ConsumerWidget {
  const ViolationDecisionRow({
    super.key,
    required this.decision,
    this.divided = false,
  });

  final DashboardDecision decision;
  final bool divided;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final at = decision.occurredAt;
    final line = joinDisplayParts([
      decision.detail,
      if (at != null) askedAgo(at, now: DateTime.now()),
    ]);
    Future<void> open() => openDecision(context, ref, decision);

    return DecoratedBox(
      key: ValueKey('violation-${decision.id}'),
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: room.hair)) : null,
      ),
      child: Semantics(
        container: true,
        button: true,
        label: decision.title,
        value: spokenFromDotted(line),
        hint: 'opens the violation',
        onTap: open,
        child: InkWell(
          onTap: open,
          excludeFromSemantics: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
              child: ExcludeSemantics(
                child: Row(
                  children: [
                    HomeRowArt(posterUrl: null, icon: decision.service.icon),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            decision.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.row
                                .weight(FontWeight.w600)
                                .copyWith(color: room.ink),
                          ),
                          Text(
                            line,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.meta.copyWith(
                              color: room.inkSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: room.inkSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
