import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/async_value_kept.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_navigation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_paging.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_person_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_users_provider.dart';

const _service = ServiceKey.tracearr;

/// Users: the people Tracearr knows, one row each, with a chip for every kind
/// of server they have an account on, and a door to the person's page.
///
/// A person is one across every server, so a household member with a Plex
/// account and a Jellyfin one is one row with two chips. People whose every
/// account was removed are not listed, as Tracearr does not list them, until
/// `Include removed` is on: they are then listed with the kinds they had.
/// Its state is [tracearrUsersListProvider].
class TracearrUsersScreen extends ConsumerWidget {
  const TracearrUsersScreen({super.key, this.topPadding = 0});

  final double topPadding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(currentSettingsProvider).isServiceConfigured(_service)) {
      return NotConfiguredPlaceholder.forService(_service);
    }
    final users = ref.watch(tracearrUsersListProvider);
    final removed = ref.watch(tracearrIncludeRemovedProvider);
    final rows = users.asData?.value;
    return ServiceListPage<TracearrUser>.unsummarised(
      service: _service,
      topPadding: topPadding,
      // Outside the state ladder: the toggle is what a person reaches for when
      // the list is empty or did not answer.
      header: Padding(
        padding: SelectionPills.gutter,
        child: Align(
          alignment: AlignmentDirectional.centerStart,
          child: SelectionPill(
            label: 'Include removed',
            selected: removed,
            onTap: () =>
                ref.read(tracearrIncludeRemovedProvider.notifier).set(!removed),
          ),
        ),
      ),
      value: users.whenDataKept((data) => data.items),
      serviceName: 'Tracearr users',
      emptyIcon: Icons.people_outline_rounded,
      emptyTitle: 'No users',
      emptyMessage:
          'People appear here once Tracearr has seen them on a '
          'server it watches.',
      onRetry: () => ref.invalidate(tracearrUsersListProvider),
      footer: rows == null
          ? null
          : TracearrLoadMore(
              rows: rows,
              noun: 'users',
              onLoadMore: () =>
                  ref.read(tracearrUsersListProvider.notifier).loadMore(),
            ),
      rowBuilder: (user) => _UserRow(user: user),
    );
  }
}

/// The kinds of server a person has an account on, each once and in the order
/// Tracearr listed them: the same person on two Jellyfins is still a Jellyfin.
/// A person with no account left lists the kinds they had.
List<String> tracearrAccountKinds(TracearrUser user) {
  final active = user.activeAccounts;
  final accounts = active.isEmpty ? user.accounts : active;
  return {
    for (final account in accounts) ?tracearrServerTypeWord(account.serverType),
  }.toList(growable: false);
}

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});

  final TracearrUser user;

  @override
  Widget build(BuildContext context) {
    final name = tracearrPersonName(user);
    final active = user.activeAccounts;
    final kinds = tracearrAccountKinds(user);
    final detail = user.accounts.isEmpty || active.isNotEmpty
        ? ''
        : 'Removed from every server';
    final trailing = active.isEmpty
        ? 'No account'
        : countLabel(active.length, 'account');
    return PressableScale(
      onTap: () => openTracearrPerson(context, user.id),
      semanticHint: 'opens the person',
      child: ServiceRecordRow(
        icon: Icons.person_outline_rounded,
        tone: StatusTone.neutral,
        title: name,
        detail: detail,
        trailing: trailing,
        footer: kinds.isEmpty
            ? null
            : Wrap(
                spacing: AppSpacing.xs,
                runSpacing: AppSpacing.xs,
                children: [for (final kind in kinds) GenreChip(genre: kind)],
              ),
        semanticLabel: [
          name,
          if (kinds.isNotEmpty) kinds.join(', '),
          trailing,
          if (detail.isNotEmpty) detail,
        ].join(', '),
      ),
    );
  }
}
