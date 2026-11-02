import 'package:flutter/material.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/features/qbittorrent/domain/models/parse_utils.dart';
import 'package:cupola/features/truenas/domain/models/pool.dart';
import 'package:cupola/features/truenas/presentation/storage/truenas_storage_providers.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_async_body.dart';
import 'package:cupola/features/truenas/presentation/widgets/truenas_section_scaffold.dart';
import 'package:cupola/features/truenas/presentation/truenas_console_shell.dart';

class TrueNasStorageScreen extends ConsumerWidget {
  const TrueNasStorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pools = ref.watch(truenasPoolsProvider);

    return TrueNasSectionScaffold(
      title: 'Storage',
      body: TrueNasConsoleShell(
        child: TrueNasAsyncBody(
          value: pools,
          onRetry: () => ref.invalidate(truenasPoolsProvider),
          data: (data) => data.isEmpty
              ? const AppEmptyState(
                  icon: Icons.dns_rounded,
                  title: 'No pools',
                  message: 'This system has no storage pools.',
                )
              : ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    AppSpacing.md,
                    AppSpacing.lg,
                    FloatingNavBarMetrics.getScrollViewBottomPadding(context),
                  ),
                  children: [
                    for (final pool in data)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: _PoolCard(pool: pool),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _PoolCard extends StatelessWidget {
  final TrueNasPool pool;
  const _PoolCard({required this.pool});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final used = pool.usedFraction;
    // A degraded pool is amber, not red. The NAS answered: it told us the pool
    // is unhealthy, and red on this canvas is reserved for a host that did not
    // answer at all. `colorScheme.error` here said "unreachable" about a server
    // that was talking to us.
    final warning = statusToneColor(colorScheme, StatusTone.warning);
    final barColor = !pool.sound || (used != null && used >= 0.9)
        ? warning
        // A healthy pool's usage is a reading, not a state: the brand book's usage bar, in
        // the secondary ink.
        : colorScheme.onSurfaceVariant;

    return PressableScale(
      onTap: () => context.push(ServiceRoutes.truenasPool(pool.name)),
      child: AppCard.surfaceOutlined(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  pool.sound ? Icons.check_circle_rounded : Icons.error_rounded,
                  size: 16,
                  color: pool.sound
                      ? statusToneColor(colorScheme, StatusTone.success)
                      : warning,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    pool.name,
                    style: theme.textTheme.titleSmall!.weight(FontWeight.w600),
                  ),
                ),
                Text(
                  pool.stateWord,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            if (used != null) ...[
              const SizedBox(height: AppSpacing.sm),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: used,
                  minHeight: 6,
                  color: barColor,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '${formatPercent(used * 100)} used'
                '${pool.sizeBytes != null ? '\u00A0· ${formatSize(pool.allocatedBytes ?? 0)} / ${formatSize(pool.sizeBytes!)}' : ''}',
                style: theme.textTheme.labelSmall!.tabular.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
