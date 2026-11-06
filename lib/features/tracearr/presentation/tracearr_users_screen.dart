import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_paging.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_users_provider.dart';

const _service = ServiceKey.tracearr;

/// Users: the people Tracearr knows, one row each, with the kinds of server
/// they have an account on.
///
/// A person is one across every server, so a household member with a Plex
/// account and a Jellyfin one is one row. People whose every account was
/// removed are not listed, as Tracearr does not list them. The person's page
/// (their figures for 7 and 30 days and all time, their favourite genres,
/// their recent history and their violations) is what this file grows into.
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
    final rows = users.asData?.value;
    return ServiceListPage<TracearrUser>.unsummarised(
      service: _service,
      topPadding: topPadding,
      value: users.whenData((data) => data.items),
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

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});

  final TracearrUser user;

  @override
  Widget build(BuildContext context) {
    final name = user.displayName.trim().isEmpty
        ? 'Unnamed user'
        : user.displayName.trim();
    final accounts = user.activeAccounts;
    // The kinds, each once and in the order Tracearr listed them: the same
    // person on two Jellyfins is still a Jellyfin.
    final kinds = <String>{
      for (final account in accounts)
        ?tracearrServerTypeWord(account.serverType),
    };
    final detail = accounts.isEmpty
        ? 'No account left on a server'
        : kinds.isEmpty
        ? countLabel(accounts.length, 'account')
        : kinds.join(', ');
    final trailing = countLabel(accounts.length, 'account');
    return ServiceRecordRow(
      icon: Icons.person_outline_rounded,
      tone: StatusTone.neutral,
      title: name,
      detail: detail,
      trailing: trailing,
      semanticLabel: '$name, $detail, $trailing',
    );
  }
}
