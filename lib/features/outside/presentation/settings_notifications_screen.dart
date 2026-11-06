import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/notice_line.dart';
import 'package:cupola/core/widgets/settings_switch_row.dart';
import 'package:cupola/core/widgets/page_title.dart';
import 'package:cupola/features/outside/data/outside_settings.dart';
import 'package:cupola/features/outside/domain/outside_notices.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart'
    show notificationPermissionProvider, releaseSearchNotificationsProvider;
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_master_detail.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';

/// Settings › Notifications: the things Cupola tells, each
/// off until the person turns it on, the permission asked for at that moment
/// and never at launch, and the platform's own honesty about when it checks.
///
/// A phone's page only: a desktop has no background run to tell anything
/// from (`outsidePlatformProvider`), and no row leads here there.
class SettingsNotificationsScreen extends ConsumerStatefulWidget {
  const SettingsNotificationsScreen({super.key});

  @override
  ConsumerState<SettingsNotificationsScreen> createState() =>
      _SettingsNotificationsScreenState();
}

class _SettingsNotificationsScreenState
    extends ConsumerState<SettingsNotificationsScreen> {
  OutsideNoticeKind? _asking;

  /// Asks the OS **first**, then records what it answered, so a refused
  /// permission never leaves a switch claiming to be on: the order Background
  /// search keeps for its own.
  Future<void> _toggle(OutsideNoticeKind kind, bool wanted) async {
    final kinds = ref.read(outsideNoticeKindsProvider.notifier);
    if (!wanted) {
      await kinds.set(kind, on: false);
      return;
    }
    setState(() => _asking = kind);
    var granted = false;
    try {
      granted = await ref
          .read(releaseSearchNotificationsProvider)
          .requestPermission();
    } catch (_) {
      granted = false;
    }
    if (!mounted) return;
    setState(() => _asking = null);
    await kinds.set(kind, on: granted);
    ref.invalidate(notificationPermissionProvider);
    if (!granted && mounted) {
      SnackBarHelper.error(
        context,
        'Notifications are turned off for Cupola in system settings.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final platform = ref.watch(outsidePlatformProvider);
    final requester = ref.watch(shellAudienceProvider) == Audience.requester;
    final seerr = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.seerr),
      ),
    );
    final tracearr = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.isServiceConfigured(ServiceKey.tracearr),
      ),
    );
    final kinds = ref.watch(outsideNoticeKindsProvider);
    // The switch stays while it is on even if Tracearr is gone, so it can be
    // turned off: a run keeps being asked for while any switch is on.
    final flagged =
        !requester && (tracearr || kinds.contains(OutsideNoticeKind.flagged));
    // Only when one is on: a permission nobody asked for being off is not a
    // fault, it is the default.
    final blocked =
        kinds.isNotEmpty &&
        ref.watch(notificationPermissionProvider).value == false;
    final ios = platform == TargetPlatform.iOS;

    return AmbientScaffold(
      appBar: const GlassAppBar.inPage(pageTitle: 'Notifications'),
      body: SettingsMasterDetail(
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            0,
            AppSpacing.lg,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            const PageTitle.flush('Notifications'),
            if (blocked) ...[
              NoticeLine(
                tone: StatusTone.warning,
                title: 'Notifications are blocked',
                sentence: ios
                    ? 'iOS Settings has notifications off for Cupola, so '
                          'these switches cannot reach you.'
                    : 'Android has notifications off for Cupola, so these '
                          'switches cannot reach you.',
                actions: [
                  noticeAction(
                    context,
                    ios ? 'Open Settings' : 'Open app settings',
                    () => unawaited(LocalNetworkPermission.openSettings()),
                    fill: StatusTone.warning,
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            SettingsGroupCard(
              children: [
                if (!requester)
                  SettingsSwitchRow(
                    icon: Icons.priority_high_rounded,
                    title: OutsideNoticeKind.needsYou.label,
                    description:
                        'When a download is stuck, an import waits, or a disk '
                        'or a key fails.',
                    value: kinds.contains(OutsideNoticeKind.needsYou),
                    busy: _asking == OutsideNoticeKind.needsYou,
                    onChanged: (on) => _toggle(OutsideNoticeKind.needsYou, on),
                  ),
                // Arrivals are Seerr's to know: without it there is nothing
                // this switch could ever say.
                if (seerr)
                  SettingsSwitchRow(
                    icon: Icons.play_circle_outline_rounded,
                    title: OutsideNoticeKind.readyToWatch.label,
                    description: requester
                        ? 'When something you asked for arrives.'
                        : 'When something someone asked for arrives.',
                    value: kinds.contains(OutsideNoticeKind.readyToWatch),
                    busy: _asking == OutsideNoticeKind.readyToWatch,
                    onChanged: (on) =>
                        _toggle(OutsideNoticeKind.readyToWatch, on),
                  ),
                // Violations are Tracearr's to know, and it is the owner's
                // alone: a requester never sees the word.
                if (flagged)
                  SettingsSwitchRow(
                    icon: Icons.flag_outlined,
                    title: 'Flagged by Tracearr',
                    description: 'When someone breaks a rule Tracearr watches.',
                    value: kinds.contains(OutsideNoticeKind.flagged),
                    busy: _asking == OutsideNoticeKind.flagged,
                    onChanged: (on) => _toggle(OutsideNoticeKind.flagged, on),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                0,
              ),
              child: Text(
                [
                  ios
                      ? 'Cupola checks in the background when iOS allows it, '
                            'which can be hours apart.'
                      : 'Cupola checks about every 15 minutes. Android may '
                            'wait longer while the phone is idle.',
                  if (!requester)
                    'A service that is only out of reach never sends one.',
                  // Tracearr never stops watching; Cupola only reads when
                  // the system wakes it, so a violation can wait for that.
                  if (flagged)
                    'Tracearr watches around the clock, but Cupola reads '
                        'what it flagged only when the phone wakes it.',
                ].join(' '),
                style: note,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Settings' row to [SettingsNotificationsScreen], saying what is on: the
/// operator's and the requester's index both carry it, on a phone.
class SettingsNotificationsRow extends ConsumerWidget {
  const SettingsNotificationsRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(outsidePlatformProvider) == null) {
      return const SizedBox.shrink();
    }
    final kinds = ref.watch(outsideNoticeKindsProvider);
    return SettingsCard.grouped(
      leading: const Icon(Icons.notifications_none_rounded),
      title: 'Notifications',
      subtitle: kinds.isEmpty
          ? 'Off'
          : [
              for (final kind in OutsideNoticeKind.values)
                if (kinds.contains(kind)) kind.label,
            ].join(dotSeparator),
      semanticHint: 'opens the notification switches',
      onTap: () => context.push('/settings/notifications'),
    );
  }
}
