import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/app_error_state.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/notice_line.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/page_title.dart';
import 'package:cupola/core/widgets/service_overview.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/connection_in_view.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/data/tracearr_owner_accounts.dart';
import 'package:cupola/features/tracearr/data/tracearr_violation_owner.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_open.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_owner_notice.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_overview_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_violations_provider.dart';

const _service = ServiceKey.tracearr;

/// What a dimmed Acknowledge or Dismiss says it wants.
const String kTracearrOwnerHint = 'Sign in to Tracearr as the owner';

/// One violation: the rule and the stream behind it, what Tracearr did about
/// it, what the rule saw, and the two things only the owner can do.
///
/// **A route inside the Tracearr shell, resolved from the path alone**
/// (`/stack/tracearr/violations/:id`), so a card in Needs you and a
/// notification open it cold. [instanceId] is the connection the link came off
/// (`?i=`); a stale one reads the lens.
///
/// **What the rule saw is typed, for the rules we know** (impossible travel:
/// the two places, the distance and the time between; concurrent streams: how
/// many and the limit), and for any other rule it is nothing but a way to open
/// Tracearr. The free-form data holds addresses and places that belong to the
/// person, so a key and a value are never drawn raw. The places this page
/// does show are the point of the first rule; none of them reaches a log, a
/// `toString` or a failure's text.
///
/// **A failed automatic action is a fault, amber, with what failed.** A
/// skipped one is Tracearr's choice and rests. The violation itself is blue
/// until somebody has looked, whatever its severity.
///
/// **Acknowledge and Dismiss are the owner's** (`TracearrViolationOwner`). With
/// no owner signed in both are drawn dimmed and still tappable, with the hint
/// [kTracearrOwnerHint], and a tap leads to the connection's settings where
/// the owner signs in; never `Semantics(enabled: false)`. An answer that says
/// this Tracearr cannot do it takes the controls off the page and leaves the
/// rest.
class TracearrViolationScreen extends ConsumerStatefulWidget {
  const TracearrViolationScreen({
    super.key,
    required this.violationId,
    this.instanceId,
  });

  final String violationId;

  /// The Tracearr connection the link named, or null for the lens.
  final String? instanceId;

  @override
  ConsumerState<TracearrViolationScreen> createState() =>
      _TracearrViolationScreenState();
}

class _TracearrViolationScreenState
    extends ConsumerState<TracearrViolationScreen> {
  bool _busy = false;

  Widget _back(BuildContext context) => IconButton(
    icon: const Icon(Icons.chevron_left_rounded),
    onPressed: () =>
        RouteUtils.popOrGo(context, ServiceRoutes.tracearrViolations),
    tooltip: 'Back',
  );

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(currentSettingsProvider);
    if (!settings.isServiceConfigured(_service)) {
      return AmbientScaffold(
        appBar: GlassAppBar.inPage(
          pageTitle: 'Violation',
          leading: _back(context),
        ),
        body: TitledBody(
          title: 'Violation',
          child: NotConfiguredPlaceholder.forService(_service),
        ),
      );
    }
    final instanceId = namedConnectionOf(settings, _service, widget.instanceId);
    final key = (id: widget.violationId, instanceId: instanceId);
    final read = ref.watch(tracearrViolationProvider(key));
    final violation = read.asData?.value;
    final title = violation == null || violation.rule.name.trim().isEmpty
        ? 'Violation'
        : violation.rule.name.trim();
    return AmbientScaffold(
      appBar: GlassAppBar.inPage(pageTitle: title, leading: _back(context)),
      body: read.when(
        loading: () => TitledBody(
          title: title,
          child: const Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => TitledBody(
          title: title,
          child: AppErrorState(
            error: error,
            serviceName: 'Tracearr',
            service: _service,
            instanceId: instanceId,
            onRetry: () => ref.invalidate(tracearrViolationProvider(key)),
          ),
        ),
        data: (data) {
          if (data == null) {
            return TitledBody(
              title: title,
              child: const AppEmptyState(
                icon: Icons.flag_outlined,
                title: 'Violation not found',
                message:
                    'Tracearr no longer has it. The owner may have dismissed '
                    'it.',
              ),
            );
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(tracearrViolationProvider(key));
              await ref.read(tracearrViolationProvider(key).future);
            },
            child: _Body(
              violation: data,
              instanceId: instanceId,
              // Gone for the rest of the run once this Tracearr answered
              // that the writes do not exist (`unavailable`).
              showOwnerControls: !ref.watch(
                tracearrOwnerRoutesAbsentProvider.select(
                  (absent) => absent.contains(instanceId),
                ),
              ),
              onAcknowledge: () => _write(data, instanceId, dismiss: false),
              onDismiss: () => _write(data, instanceId, dismiss: true),
            ),
          );
        },
      ),
    );
  }

  void _toSettings(String instanceId) {
    // The owner signs in on the connection's own settings page.
    context.push(ServiceRoutes.settingsForConnection(_service, instanceId));
  }

  Future<void> _write(
    TracearrViolation violation,
    String instanceId, {
    required bool dismiss,
  }) async {
    if (_busy) return;
    final owner = ref.read(tracearrViolationOwnerProvider(instanceId));
    if (owner == null) {
      _toSettings(instanceId);
      return;
    }
    final verb = dismiss ? 'dismiss' : 'acknowledge';
    if (dismiss) {
      final person = tracearrPersonOf(violation.person);
      final confirmed = await showAppConfirmDialog(
        context: context,
        title: 'Dismiss this violation?',
        message:
            'Tracearr removes it and gives back the trust it cost $person.',
        confirmLabel: 'Dismiss violation',
        cancelLabel: 'Keep it',
      );
      if (!confirmed.confirmed || !mounted) return;
    }
    setState(() => _busy = true);
    final TracearrOwnerOutcome outcome;
    try {
      outcome = dismiss
          ? await owner.dismiss(violation.id)
          : await owner.acknowledge(violation.id);
    } catch (_) {
      // An owner that throws instead of answering is a failure like any other,
      // said without what it threw: that may name the session.
      if (!mounted) return;
      setState(() => _busy = false);
      SnackBarHelper.info(context, 'Could not $verb this violation');
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    switch (outcome) {
      case TracearrOwnerOutcome.done:
        _readAgain();
        if (dismiss) {
          SnackBarHelper.success(context, 'Dismissed');
          RouteUtils.popOrGo(context, ServiceRoutes.tracearrViolations);
        } else {
          SnackBarHelper.success(context, 'Acknowledged');
        }
      case TracearrOwnerOutcome.signedOut:
        SnackBarHelper.withAction(
          context,
          'Signed out of Tracearr',
          actionLabel: Lexicon.signInAgain,
          onAction: () => _toSettings(instanceId),
        );
      case TracearrOwnerOutcome.notOwner:
        SnackBarHelper.info(context, 'Only the owner can $verb');
      case TracearrOwnerOutcome.gone:
        _readAgain();
        SnackBarHelper.info(context, 'Tracearr no longer has this violation');
        if (dismiss) {
          RouteUtils.popOrGo(context, ServiceRoutes.tracearrViolations);
        }
      case TracearrOwnerOutcome.unavailable:
        ref.read(tracearrOwnerRoutesAbsentProvider.notifier).mark(instanceId);
        SnackBarHelper.withAction(
          context,
          'This Tracearr cannot do that from Cupola.',
          actionLabel: 'Open in Tracearr',
          onAction: () => openInTracearr(
            ref,
            tracearrViolationWebPath(violation.id),
            instanceId: instanceId,
          ),
        );
      case TracearrOwnerOutcome.failed:
        SnackBarHelper.info(context, 'Could not $verb this violation');
    }
  }

  /// Everything that showed the violation reads it again: the tab's lists,
  /// the Overview's section and count, and Needs you.
  void _readAgain() {
    ref
      ..invalidate(tracearrViolationProvider)
      ..invalidate(tracearrViolationsListProvider)
      ..invalidate(tracearrUnseenViolationsProvider)
      ..invalidate(tracearrLatestViolationsProvider)
      // The page Needs you reads: the source re-runs on the invalidation
      // below, and would otherwise be handed the cached page that still lists
      // the violation.
      ..invalidate(tracearrFlaggedProvider)
      ..invalidate(dashboardDecisionSourceProvider(DecisionSource.violations));
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.violation,
    required this.instanceId,
    required this.showOwnerControls,
    required this.onAcknowledge,
    required this.onDismiss,
  });

  final TracearrViolation violation;
  final String instanceId;
  final bool showOwnerControls;
  final VoidCallback onAcknowledge;
  final VoidCallback onDismiss;

  /// Whether single sign-on is the only way into this Tracearr and nobody is
  /// signed in as its owner: then there is nothing to offer, dimmed or not.
  /// Unknown (not read yet, or Tracearr did not answer) is false: the dimmed
  /// controls stay, as they were.
  bool _singleSignOnOnly(WidgetRef ref) {
    if (ref.watch(tracearrViolationOwnerProvider(instanceId)) != null) {
      return false;
    }
    return ref
            .watch(tracearrOwnerWaysProvider(instanceId))
            .asData
            ?.value
            .oidcOnly ??
        false;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final surface = colorScheme.surfaceContainerLow;
    Color tone(StatusTone tone) =>
        statusToneColor(colorScheme, tone, surface: surface);

    final title = violation.rule.name.trim().isEmpty
        ? 'Violation'
        : violation.rule.name.trim();
    final created = violation.createdAt;
    final when = created == null ? null : formatRelativeDateTime(created);
    final severity = tracearrSeverityWord(violation.severity);
    final seen = violation.acknowledgedAt;
    final person = tracearrPersonOf(violation.person);
    final server = tracearrServerOf(violation.server);
    // Blue until somebody has looked, whatever the severity: a rule was
    // broken, which is the person's to read. Once read, it rests.
    final stateTone = tone(
      violation.isAcknowledged ? StatusTone.neutral : StatusTone.info,
    );
    final stateWord = seen == null
        ? 'Unseen'
        : 'Acknowledged ${formatRelativeDateTime(seen)}';

    final travel = violation.impossibleTravel;
    final concurrent = violation.concurrentStreams;

    return ServiceOverviewScroll(
      topPadding: 0,
      children: [
        PageTitle(title, summary: Text(joinDisplayParts([severity, when]))),
        ServiceOverviewSection(
          service: _service,
          title: 'Violation',
          child: Column(
            children: [
              ServiceOverviewRow(
                spoken: joinSpokenParts([title, severity, stateWord]),
                leading: Icon(Icons.flag_outlined, size: 18, color: stateTone),
                title: title,
                titleColor: stateTone,
                detail: stateWord,
                trailing: severity,
              ),
              const SizedBox(height: AppSpacing.md),
              ServiceOverviewRow(
                spoken: joinSpokenParts([person, server]),
                leading: Icon(
                  Icons.person_outline_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                title: person,
                detail: server ?? '',
              ),
              const SizedBox(height: AppSpacing.md),
              ServiceOverviewRow(
                spoken: joinSpokenParts([
                  violation.sessionId == null
                      ? 'Not tied to one stream'
                      : 'Triggered by a stream',
                  when,
                ]),
                leading: Icon(
                  Icons.play_circle_outline_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
                title: violation.sessionId == null
                    ? 'Not tied to one stream'
                    : 'Triggered by a stream',
                detail: when ?? '',
              ),
            ],
          ),
        ),
        ServiceOverviewSection(
          service: _service,
          title: 'What Tracearr did',
          child: violation.actions.isEmpty
              ? const ServiceOverviewEmpty(
                  icon: Icons.history_toggle_off_rounded,
                  label: 'Tracearr took no automatic action',
                )
              : Column(
                  children: [
                    for (final (index, action)
                        in violation.actions.indexed) ...[
                      if (index > 0) const SizedBox(height: AppSpacing.md),
                      _ActionRow(action: action, surface: surface),
                    ],
                  ],
                ),
        ),
        ServiceOverviewSection(
          service: _service,
          title: 'What it saw',
          child: travel != null
              ? _TravelRows(travel: travel)
              : concurrent != null
              ? _ConcurrentRows(rule: concurrent)
              : const _UnknownRule(),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (showOwnerControls && _singleSignOnOnly(ref)) ...[
                // Said once, here, with its remedy: a sign-in Cupola cannot
                // finish is not offered as a dimmed control.
                NoticeLine(
                  tone: TracearrOwnerNotice.singleSignOn.tone,
                  title: TracearrOwnerNotice.singleSignOn.title,
                  sentence: TracearrOwnerNotice.singleSignOn.sentence,
                ),
                const SizedBox(height: AppSpacing.md),
              ] else if (showOwnerControls) ...[
                if (!violation.isAcknowledged) ...[
                  _OwnerControl(
                    label: 'Acknowledge',
                    primary: true,
                    instanceId: instanceId,
                    onTap: onAcknowledge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                ],
                _OwnerControl(
                  label: 'Dismiss',
                  primary: false,
                  instanceId: instanceId,
                  onTap: onDismiss,
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              OutlinedButton.icon(
                onPressed: () => openInTracearr(
                  ref,
                  tracearrViolationWebPath(violation.id),
                  instanceId: instanceId,
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 18),
                label: Semantics(
                  hint: 'opens Tracearr in the browser',
                  child: const Text('Open in Tracearr'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Acknowledge or Dismiss: live while an owner is signed in on the connection,
/// dimmed with [kTracearrOwnerHint] and still tappable while none is. The
/// dimmed tap is the owner's sign-in (the connection's settings), decided by
/// the screen's write, so the control is one thing in both states.
class _OwnerControl extends ConsumerWidget {
  const _OwnerControl({
    required this.label,
    required this.primary,
    required this.instanceId,
    required this.onTap,
  });

  final String label;
  final bool primary;
  final String instanceId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final signedIn =
        ref.watch(tracearrViolationOwnerProvider(instanceId)) != null;
    return GatedAffordance.builder(
      enabled: signedIn,
      hint: kTracearrOwnerHint,
      onTap: onTap,
      // The screen's write knows to lead to the settings when no owner is
      // there, so the blocked tap is the same call.
      onBlocked: onTap,
      builder: (context, onPressed, annotate) => primary
          ? FilledButton(onPressed: onPressed, child: annotate(Text(label)))
          : OutlinedButton(onPressed: onPressed, child: annotate(Text(label))),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.action, required this.surface});

  final TracearrViolationAction action;
  final Color surface;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final result = tracearrActionResult(action);
    final word = tracearrActionWord(action.type);
    // The one fault on the page: an action that ran and did not work. Amber,
    // with what failed. A skip is Tracearr's own choice and rests.
    final failed = action.failed;
    final amber = statusToneColor(
      colorScheme,
      StatusTone.warning,
      surface: surface,
    );
    return ServiceOverviewRow(
      spoken: joinSpokenParts([word, result.word, result.why]),
      leading: Icon(
        failed
            ? Icons.warning_amber_rounded
            : action.skipped
            ? Icons.remove_rounded
            : Icons.check_rounded,
        size: 18,
        color: failed ? amber : colorScheme.onSurfaceVariant,
      ),
      title: word,
      titleColor: failed ? amber : null,
      detail: result.why ?? '',
      trailing: result.word,
    );
  }
}

class _TravelRows extends StatelessWidget {
  const _TravelRows({required this.travel});

  final TracearrImpossibleTravel travel;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    final distance = travel.distanceKm;
    final elapsed = travel.elapsed;
    Widget place(String? label, String which) => ServiceOverviewRow(
      spoken: joinSpokenParts([which, label ?? 'Unknown place']),
      leading: Icon(Icons.place_outlined, size: 18, color: muted),
      title: label ?? Lexicon.noFigure,
      detail: which,
    );
    return Column(
      children: [
        place(travel.from?.label, 'First stream'),
        const SizedBox(height: AppSpacing.md),
        place(travel.to?.label, 'Second stream'),
        if (distance != null) ...[
          const SizedBox(height: AppSpacing.md),
          ServiceOverviewRow(
            spoken: joinSpokenParts([
              '${tracearrDistanceWord(distance)} apart',
              if (elapsed != null)
                '${tracearrElapsedWord(elapsed)} between the two streams',
            ]),
            leading: Icon(Icons.straighten_rounded, size: 18, color: muted),
            title: '${tracearrDistanceWord(distance)} apart',
            detail: elapsed == null
                ? ''
                : '${tracearrElapsedWord(elapsed)} between the two streams',
          ),
        ],
      ],
    );
  }
}

class _ConcurrentRows extends StatelessWidget {
  const _ConcurrentRows({required this.rule});

  final TracearrConcurrentStreams rule;

  @override
  Widget build(BuildContext context) {
    return ServiceOverviewRow(
      spoken: tracearrConcurrentWord(rule),
      leading: Icon(
        Icons.stacked_line_chart_rounded,
        size: 18,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      title: '${countLabel(rule.count, 'stream')} at once',
      detail: 'The limit is ${rule.limit}',
    );
  }
}

/// A rule Cupola does not read: only Tracearr can say what it saw.
class _UnknownRule extends StatelessWidget {
  const _UnknownRule();

  @override
  Widget build(BuildContext context) {
    return const ServiceOverviewEmpty(
      icon: Icons.visibility_off_outlined,
      label: 'Only Tracearr shows what this rule saw',
    );
  }
}
