import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/data/seerr_accounts.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_section_label.dart';

/// The requester's account card: who she is signed in as on each Seerr she
/// asks, and the players she watches with when she set one up herself.
///
/// It takes the place of the operator's connections card. She runs nothing,
/// so a count of services set up out of nineteen is not a fact about her;
/// the one thing that can be wrong for her is the session, and it reads here
/// as it does on the Home: `You were signed out`, blue.
class RequesterAccountCard extends ConsumerWidget {
  const RequesterAccountCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connections = ref.watch(
      currentSettingsProvider.select(
        (settings) => [
          for (final instance in settings.instances)
            if (instance.isConfigured || instance.isSignedOut)
              if (instance.service == ServiceKey.seerr &&
                      instance.account != null ||
                  instance.service.isMediaServer)
                instance,
        ],
      ),
    );
    if (connections.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionLabel('Account'),
        const SizedBox(height: AppSpacing.sm),
        SettingsGroupCard(
          children: [
            for (final connection in connections)
              if (connection.service == ServiceKey.seerr)
                _AccountRow(connection: connection)
              else
                _PlayerRow(connection: connection),
          ],
        ),
      ],
    );
  }
}

/// `Signed in as Anna` over `Casa Requests · nas.home.arpa`, her initial in
/// the tile. The server's own name is the one service name she reads, and
/// only here and when she signs in.
class _AccountRow extends ConsumerWidget {
  const _AccountRow({required this.connection});

  final ServiceInstance connection;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final account = connection.account!;
    final title =
        ref
            .watch(seerrServerFactsProvider(connection.id))
            .whenOrNull(data: (facts) => facts.title) ??
        ServiceKey.seerr.title;
    final host = UrlUtils.hostInProse(
      ServiceKey.seerr.extractHost(connection.url) ?? '',
    );
    final name = account.displayName.trim();
    final signedIn = account.isSignedIn;
    final line = signedIn
        ? Lexicon.signedInAs(name.isEmpty ? account.login : name)
        : Lexicon.youWereSignedOut;
    final where = host.isEmpty ? title : '$title\u00A0· $host';
    final tone = statusToneColor(
      colorScheme,
      StatusTone.info,
      surface: colorScheme.surfaceContainer,
    );
    return SettingsCard.grouped(
      leading: signedIn && name.isNotEmpty
          ? Text(
              name.characters.first.toUpperCase(),
              style: AppType.row.copyWith(color: colorScheme.onSurface),
            )
          : Icon(
              signedIn ? Icons.person_outline_rounded : Icons.logout_rounded,
            ),
      title: line,
      subtitle: where,
      accentColor: signedIn ? null : tone,
      semanticLabel: '$line. $where',
      semanticHint: 'opens your account',
      onTap: () => context.push(
        ServiceRoutes.settingsAccountFor(instanceId: connection.id),
      ),
    );
  }
}

/// A player she watches with, set up by her: its name and where it is, the
/// door to its form.
class _PlayerRow extends StatelessWidget {
  const _PlayerRow({required this.connection});

  final ServiceInstance connection;

  @override
  Widget build(BuildContext context) {
    final service = connection.service;
    final host = UrlUtils.hostInProse(
      service.extractHost(connection.url) ?? '',
    );
    return SettingsCard.grouped(
      leading: Icon(service.icon),
      title: service.title,
      subtitle: host.isEmpty ? null : host,
      semanticHint: 'opens its settings',
      onTap: () => context.push(
        ServiceRoutes.settingsForConnection(service, connection.id),
      ),
    );
  }
}

/// The one way from the requester's app into the operator's: setting up a
/// service of her own (spec of the requester, D-6). Last, and quiet; once one
/// is set up, who the app is for follows by itself.
class SetUpAServiceRow extends StatelessWidget {
  const SetUpAServiceRow({super.key});

  @override
  Widget build(BuildContext context) {
    return SettingsCard.grouped(
      leading: const Icon(Icons.add_rounded),
      title: 'Set up a service',
      subtitle: 'For a server you run yourself',
      accentColor: Theme.of(context).colorScheme.onSurfaceVariant,
      semanticHint: 'opens the list of services',
      onTap: () => context.push(ServiceRoutes.settingsConnections),
    );
  }
}
