import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/core/widgets/page_title.dart';
import 'package:cupola/features/activity/data/activity_answered.dart';
import 'package:cupola/features/activity/data/activity_live.dart';
import 'package:cupola/features/activity/domain/activity_readout.dart'
    show activityAnswerLine;
import 'package:cupola/features/activity/domain/activity_tab.dart';
import 'package:cupola/features/activity/presentation/activity_page.dart'
    show needsYouMeta;
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';
import 'package:cupola/features/activity/presentation/widgets/import_done_card.dart';
import 'package:cupola/features/activity/presentation/widgets/needs_you_cards.dart';
import 'package:cupola/features/activity/presentation/widgets/violation_rows.dart';
import 'package:cupola/features/home/data/answered_requests.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';

/// Needs you, whole: every fault on a card of its own with its evidence and
/// its way out, then the requests that wait.
///
/// Under the title, what it holds (`3 faults · 2 requests`) and who was asked:
/// `All 12 services answered at 20:53`, or which did not, in their tone. The
/// Home's Review opens it, and so does the heading on All.
class ActivityNeedsYouPage extends ConsumerStatefulWidget {
  const ActivityNeedsYouPage({super.key});

  @override
  ConsumerState<ActivityNeedsYouPage> createState() =>
      _ActivityNeedsYouPageState();
}

class _ActivityNeedsYouPageState extends ConsumerState<ActivityNeedsYouPage> {
  @override
  Widget build(BuildContext context) {
    final decisions = ref.watch(dashboardDecisionsProvider);
    final coverage = decisions.coverage;
    final answeredAt = ref.watch(activityAnsweredAtProvider);
    final answered = ref.watch(answeredRequestsProvider);
    final entries = faultEntriesOf(
      decisions.decisions.where((decision) => decision.isFault),
    );
    final waiting = [
      for (final decision in decisions.decisions)
        if (decision.kind == DecisionKind.pendingRequest &&
            !answered.containsKey(decision.id))
          decision,
    ];
    final requests = [...waiting, for (final a in answered.values) ?a.decision];
    final flagged = violationsOf(decisions.decisions);
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final blue = statusToneColor(scheme, StatusTone.info, surface: room.slab);
    final note = coverageNote(coverage);
    final report = ref.watch(importReportProvider);

    Widget slab(List<Widget> children) => Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.md,
        AppSpacing.gutter,
        0,
      ),
      child: ActivitySlab(children: children),
    );

    // Said only once every source answered: before then, or with one
    // silent, nothing on the page is not nothing wrong.
    final nothing =
        report == null &&
        entries.isEmpty &&
        requests.isEmpty &&
        flagged.count == 0 &&
        coverage.pending.isEmpty &&
        coverage.failed.isEmpty;

    return AmbientScaffold(
      appBar: const GlassAppBar.inPage(pageTitle: 'Needs you'),
      body: RefreshIndicator(
        onRefresh: () => refreshActivity(ref, ActivityTab.all),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(
            bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            _Heading(
              faults: entries.length,
              requests: waiting.length,
              violations: flagged.count,
              violationsFloor: flagged.floor,
              answeredLine:
                  note == null &&
                      coverage.answered.isNotEmpty &&
                      coverage.pending.isEmpty
                  ? activityAnswerLine(
                      coverage,
                      at: answeredAt,
                      services: true,
                    )?.text
                  : null,
              note: note == null
                  ? null
                  : HomeCoverageNote(note: note, coverage: coverage),
            ),
            if (report != null)
              slab([ImportDoneCard(report: report, whole: true)]),
            for (final entry in entries)
              slab([
                NeedsYouCard(
                  key: ValueKey(entry.id),
                  entry: entry,
                  whole: true,
                ),
              ]),
            if (flagged.count > 0) slab(violationRowsOf(flagged, blue)),
            if (requests.isNotEmpty)
              slab(requestRowsOf(requests, answered, blue)),
            if (nothing)
              const AppEmptyState(
                icon: Icons.check_circle_outline_rounded,
                title: 'Nothing needs you',
                message:
                    'A download that stops, a disk that reports errors, a '
                    'request that waits for an answer or a rule broken at its '
                    'worst appears here.',
              ),
          ],
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading({
    required this.faults,
    required this.requests,
    this.violations = 0,
    this.violationsFloor = false,
    this.answeredLine,
    this.note,
  });

  final int faults;
  final int requests;
  final int violations;
  final bool violationsFloor;
  final String? answeredLine;
  final Widget? note;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    final amber = statusToneColor(
      scheme,
      StatusTone.warning,
      surface: room.slab,
    );
    final blue = statusToneColor(scheme, StatusTone.info, surface: room.slab);
    final style = AppType.label;
    final meta = needsYouMeta(
      faults: faults,
      requests: requests,
      violations: violations,
      violationsFloor: violationsFloor,
    );

    Widget dot(Color color) => Container(
      width: 7,
      height: 7,
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(shape: BoxShape.circle, color: color),
    );

    final lines = [
      if (meta.isNotEmpty)
        Semantics(
          label: meta.replaceAll(dotSeparator, ', '),
          excludeSemantics: true,
          child: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xxs,
            children: [
              if (faults > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    dot(amber),
                    Text(
                      faults == 1 ? '1 fault' : '$faults faults',
                      style: style.copyWith(color: amber),
                    ),
                  ],
                ),
              if (violations > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    dot(blue),
                    Text(
                      violationsFloor
                          ? '${Lexicon.floor(violations)} violations'
                          : violations == 1
                          ? '1 violation'
                          : '$violations violations',
                      style: style.copyWith(color: blue),
                    ),
                  ],
                ),
              if (requests > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    dot(blue),
                    Text(
                      requests == 1 ? '1 request' : '$requests requests',
                      style: style.copyWith(color: blue),
                    ),
                  ],
                ),
            ],
          ),
        ),
      if (answeredLine case final line?) ...[
        const SizedBox(height: AppSpacing.xxs),
        Text(line, style: AppType.meta.copyWith(color: room.inkSecondary)),
      ],
      if (note case final note?) ...[
        const SizedBox(height: AppSpacing.xs),
        note,
      ],
    ];
    // The page's name, and under it what waits: the faults and the requests.
    return PageTitle(
      'Needs you',
      summary: lines.isEmpty
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: lines,
            ),
    );
  }
}
