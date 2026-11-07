import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/async_value_kept.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/role_gate.dart';
import 'package:cupola/core/capability/role_gate_copy.dart';
import 'package:cupola/core/capability/role_gate_provider.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/discover/data/seerr_service.dart';
import 'package:cupola/features/discover/domain/models/seerr_admin_models.dart';
import 'package:cupola/features/discover/domain/seerr_grant.dart';
import 'package:cupola/features/discover/presentation/discover_provider.dart';
import 'package:cupola/features/discover/presentation/widgets/seerr_not_set_up.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

class SeerrIssuesScreen extends ConsumerStatefulWidget {
  const SeerrIssuesScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  ConsumerState<SeerrIssuesScreen> createState() => _SeerrIssuesScreenState();
}

class _SeerrIssuesScreenState extends ConsumerState<SeerrIssuesScreen> {
  SeerrIssueFilter _filter = SeerrIssueFilter.open;

  @override
  Widget build(BuildContext context) {
    // The lens's Seerr, which these pages read: a signed-out one reads signed
    // out before anything is asked of it.
    if (!watchSeerrConfigured(ref)) {
      return NotConfiguredPlaceholder.forService(ServiceKey.seerr);
    }
    // An account that may not see the issues is told so, and nothing is
    // asked of the server: it would refuse.
    final blocked = _SeerrBlockedTab.of(
      ref,
      SeerrAbility.viewIssues,
      icon: Icons.report_problem_outlined,
      topPadding: widget.topPadding,
    );
    if (blocked != null) return blocked;
    // Seeing the issues is not resolving them: where the server would refuse
    // (anybody else's issue without MANAGE_ISSUES), Resolve reads dimmed with
    // why, never a tap that fails.
    final gate = ref.watch(roleGateProvider(''));
    final accountUserId = ref.watch(seerrAccountUserIdProvider(''));
    final issues = ref.watch(seerrIssuesProvider(_filter));
    final partial = issues.asData?.value;
    return ServiceListPage<SeerrIssue>.unsummarised(
      service: ServiceKey.seerr,
      value: issues.whenDataKept((result) => result.items),
      serviceName: 'Seerr issues',
      onRetry: () => ref.invalidate(seerrIssuesProvider(_filter)),
      emptyIcon: Icons.report_problem_outlined,
      emptyTitle: 'No issues',
      emptyMessage: 'Seerr has no issues in this view.',
      topPadding: widget.topPadding,
      // Top only: the pills carry the gutter themselves, so a side inset here
      // put them a second gutter in from the rows below.
      header: Padding(
        padding: const EdgeInsets.only(top: AppSpacing.md),
        child: SelectionPills<SeerrIssueFilter>(
          values: SeerrIssueFilter.values,
          selected: _filter,
          labelBuilder: (filter) => filter.label,
          onSelected: (value) => setState(() => _filter = value),
        ),
      ),
      banner: partial != null && partial.isPartial
          ? FaultBand.partial(
              message:
                  'Seerr returned ${partial.items.length} of '
                  '${partial.total} issues; later pages are unavailable.',
              onRetry: () => ref.invalidate(seerrIssuesProvider(_filter)),
            )
          : null,
      rowBuilder: (issue) => _IssueCard(
        issue: issue,
        // The record's own status, not the filter that fetched it: keyed on
        // the filter, the "All" tab offered Resolve on nothing at all, open
        // issues included.
        onResolve: issue.isOpen ? () => _resolve(issue) : null,
        resolve: gate.resolveIssueAction(
          own:
              issue.createdBy?.id != null &&
              issue.createdBy?.id == accountUserId,
        ),
      ),
    );
  }

  Future<void> _resolve(SeerrIssue issue) async {
    // Asked first: the check glyph sat at the end of every row and resolved
    // on the tap, closing the issue for whoever reported it. It can be
    // reopened, but only from Seerr's own web UI, so it is not a free click.
    final reporter = issue.createdBy?.displayName;
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.check_circle_outline_rounded,
      title: 'Resolve this issue?',
      message: [
        '${issue.media?.title ?? 'Unknown media'}\u00A0· ${issue.issueTypeLabel}'
            '${reporter == null ? '' : ', reported by $reporter'}.',
        'Seerr marks it resolved; it can be reopened from Seerr.',
      ].join('\n\n'),
      confirmLabel: 'Resolve issue',
      enterConfirms: true,
    );
    if (!result.confirmed || !mounted) return;

    // A write, so the failure surfaces. Unguarded, a token that had lost
    // `MANAGE_ISSUES` threw out of the button callback: nothing invalidated,
    // nothing said, and the row still open, indistinguishable from a tap that
    // never registered.
    try {
      await ref.read(seerrServiceProvider).resolveIssue(issue.id);
      ref.invalidate(seerrIssuesProvider(_filter));
      if (!mounted) return;
      SnackBarHelper.success(context, 'Issue resolved');
    } catch (error) {
      if (!mounted) return;
      SnackBarHelper.error(
        context,
        'Could not resolve the issue',
        detail: error,
      );
    }
  }
}

class SeerrUsersScreen extends ConsumerWidget {
  const SeerrUsersScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The lens's Seerr, which these pages read: a signed-out one reads signed
    // out before anything is asked of it.
    if (!watchSeerrConfigured(ref)) {
      return NotConfiguredPlaceholder.forService(ServiceKey.seerr);
    }
    // The users are the operator's to manage: an account that may not is
    // told so, and the list is not read.
    final blocked = _SeerrBlockedTab.of(
      ref,
      SeerrAbility.manageUsers,
      icon: Icons.people_outline_rounded,
      topPadding: topPadding,
    );
    if (blocked != null) return blocked;
    final users = ref.watch(seerrUsersProvider);
    final partial = users.asData?.value;
    return ServiceListPage<SeerrUser>.unsummarised(
      service: ServiceKey.seerr,
      value: users.whenDataKept((result) => result.items),
      serviceName: 'Seerr users',
      onRetry: () => ref.invalidate(seerrUsersProvider),
      emptyIcon: Icons.people_outline_rounded,
      emptyTitle: 'No users',
      emptyMessage: 'Seerr returned no users.',
      topPadding: topPadding,
      banner: partial != null && partial.isPartial
          ? FaultBand.partial(
              message:
                  'Seerr returned ${partial.items.length} of '
                  '${partial.total} users; later pages are unavailable.',
              onRetry: () => ref.invalidate(seerrUsersProvider),
            )
          : null,
      rowBuilder: (user) => _UserCard(user: user),
    );
  }
}

/// A tab of the Seerr room the lens's account may not use: why, in place of
/// the list, and no read the server would refuse.
///
/// The operator reads it about the account (`Your account on Seerr can't
/// see issues.`); a household member, who has no Seerr room in their app,
/// reads it about themselves.
class _SeerrBlockedTab extends StatelessWidget {
  const _SeerrBlockedTab({
    required this.reason,
    required this.icon,
    required this.topPadding,
  });

  /// The tab for [ability] on the lens's Seerr, or null when the account may.
  static Widget? of(
    WidgetRef ref,
    SeerrAbility ability, {
    required IconData icon,
    required double topPadding,
  }) {
    final verdict = ref.watch(roleGateProvider('')).operatorAction(ability);
    if (verdict.acts) return null;
    return _SeerrBlockedTab(
      reason: switch (verdict) {
        Dimmed(:final reason) => reason,
        _ => RoleGateCopy.youCannot(ability),
      },
      icon: icon,
      topPadding: topPadding,
    );
  }

  final String reason;
  final IconData icon;
  final double topPadding;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      top: topPadding + MediaQuery.paddingOf(context).top,
    ),
    child: AppEmptyState(icon: icon, title: reason),
  );
}

class _IssueCard extends StatelessWidget {
  const _IssueCard({
    required this.issue,
    this.onResolve,
    this.resolve = const Live(),
  });

  final SeerrIssue issue;
  final VoidCallback? onResolve;

  /// What the role gate says about Resolve on this connection.
  final GateVerdict resolve;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final title = issue.media?.title ?? 'Unknown media';
    final reporter = issue.createdBy?.displayName ?? 'Unknown reporter';
    final status = issue.isResolved ? 'Resolved' : 'Open';
    return AppCard.outlined(
      semanticLabel: title,
      semanticValue: '$status, ${issue.issueTypeLabel}, reported by $reporter',
      backgroundColor: colorScheme.surfaceContainer,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.report_problem_outlined,
            color: statusToneColor(
              colorScheme,
              issue.tone,
              surface: colorScheme.surfaceContainer,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.weight(FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  joinDisplayParts([
                    issue.issueTypeLabel,
                    reporter,
                    issue.commentCount == 0
                        ? null
                        : '${issue.commentCount} comments',
                  ]),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          if (onResolve case final onResolve?)
            RoleGatedAction.builder(
              verdict: resolve,
              onTap: onResolve,
              builder: (context, onPressed, annotate) => IconButton(
                tooltip: 'Resolve issue',
                onPressed: onPressed,
                icon: annotate(const Icon(Icons.check_circle_outline_rounded)),
              ),
            ),
        ],
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  const _UserCard({required this.user});

  final SeerrUser user;

  @override
  Widget build(BuildContext context) {
    final initial = user.displayName.substring(0, 1).toUpperCase();
    return AppCard.outlined(
      semanticLabel: user.displayName,
      semanticValue: '${user.requestCount ?? '—'} requests',
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: ServiceKey.seerr.accent.withValues(alpha: 0.15),
            child: Text(initial),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.displayName,
                  style: Theme.of(
                    context,
                  ).textTheme.titleMedium?.weight(FontWeight.w600),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  user.email ?? '—',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
          Text(
            '${user.requestCount ?? '—'} requests',
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ],
      ),
    );
  }
}
