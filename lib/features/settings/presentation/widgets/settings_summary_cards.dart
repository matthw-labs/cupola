import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/release_search/data/release_search_transport.dart';
import 'package:cupola/features/release_search/domain/release_search_reach.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/release_search/presentation/release_search_settings_provider.dart';
import 'package:cupola/features/release_search/presentation/widgets/search_headroom_card.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/service_verification.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/connections_readout.dart';
import 'package:cupola/features/settings/domain/regions.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/presentation/widgets/cert_trust_content.dart';
import 'package:cupola/features/settings/presentation/widgets/requester_settings_rows.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_app_rows.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_section_label.dart';
import 'package:cupola/features/settings/presentation/widgets/test_all_connections_button.dart';
import 'package:cupola/features/shell/domain/portal_hints.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';
import 'package:cupola/demo/presentation/demo_settings_card.dart';

/// The six cards of the settings summary, and the rule all six obey: **print
/// only what is wrong.**
///
/// A settings index that lists every preference at its current value is an
/// inventory, and nobody audits an inventory. Each card here leads with one
/// readout and then says nothing at all unless something about that area is
/// actually worth acting on: a service that is not answering, a pinned
/// certificate no service reaches any more, a notification permission the OS is
/// refusing, a setting that does not do what its name suggests. A quiet card is
/// the useful answer, not a missing one.
///
/// Every state word comes from `describeConnection` and every colour from
/// `statusToneColor`, for the reason the vocabulary exists: the summary, the
/// connections list and the connection form must not describe one failure three
/// different ways.
///
/// **After the six, three cards that are doors rather than readouts:**
/// Onboarding, About and Danger zone. Those rows are not pages, so the rail
/// cannot carry them, and while only the phone index built them a window this
/// wide had no way to the licence page, the feedback address, the donation
/// sheet, the onboarding replay or Reset. They are the phone's own rows
/// (`settings_app_rows.dart`) under the phone's own labels, in the phone's
/// order; Reset keeps its confirmation.
class SettingsSummaryPane extends ConsumerWidget {
  const SettingsSummaryPane({super.key, required this.padding, this.heading});

  final EdgeInsetsGeometry padding;

  /// The page's name over the cards (`PageTitle`), or null.
  final Widget? heading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The requester's pane holds what her phone's index holds (the spec of
    // the requester, § 6.2), in the pane's grammar.
    if (ref.watch(shellAudienceProvider) == Audience.requester) {
      return ListView(
        padding: padding,
        children: [
          ?heading,
          const DemoSettingsCard(),
          const RequesterAccountCard(),
          const SizedBox(height: AppSpacing.xl),
          const _RegionSummaryCard(),
          const SizedBox(height: AppSpacing.xl),
          const _AppearanceSummaryCard(),
          const SizedBox(height: AppSpacing.xl),
          _SummaryCard(
            label: 'About',
            children: settingsAboutRows(context, audience: Audience.requester),
          ),
          const SizedBox(height: AppSpacing.xl),
          const SettingsGroupCard(children: [SetUpAServiceRow()]),
        ],
      );
    }
    final offersCode = SettingsAnotherDeviceRow.offeredFor(
      ref.watch(currentSettingsProvider),
    );
    return ListView(
      padding: padding,
      children: [
        ?heading,
        const DemoSettingsCard(),
        const ConnectionsSummaryCard(),
        const SizedBox(height: AppSpacing.xl),
        const _TrustedCertificatesSummaryCard(),
        const SizedBox(height: AppSpacing.xl),
        const _BackgroundSearchSummaryCard(),
        const SizedBox(height: AppSpacing.xl),
        const _RegionSummaryCard(),
        const SizedBox(height: AppSpacing.xl),
        const _AppearanceSummaryCard(),
        const SizedBox(height: AppSpacing.xl),
        const _HintsSummaryCard(),
        const SizedBox(height: AppSpacing.xl),
        _SummaryCard(
          label: 'Onboarding',
          children: [
            const SettingsRevisitOnboardingRow(),
            if (offersCode) const SettingsAnotherDeviceRow(),
          ],
        ),
        const SizedBox(height: AppSpacing.xl),
        const _AboutSummaryCard(),
        const SizedBox(height: AppSpacing.xl),
        const _SummaryCard(
          label: 'Danger zone',
          children: [SettingsResetAppDataRow()],
        ),
      ],
    );
  }
}

/// About: the same four rows the phone index draws.
class _AboutSummaryCard extends StatelessWidget {
  const _AboutSummaryCard();

  @override
  Widget build(BuildContext context) {
    return _SummaryCard(label: 'About', children: settingsAboutRows(context));
  }
}

/// The stack's connections as one readout: every service set up, how it
/// answered, and the ones not set up. The Connections card leads with it and
/// the Settings page's line under its name says it again in short.
final connectionsReadoutProvider = Provider.autoDispose<ConnectionsReadout>((
  ref,
) {
  final settings = ref.watch(currentSettingsProvider);
  final states = <ServiceKey, ConnectionPresentation>{};
  final notSetUp = <ServiceKey>[];
  // Counted by the Stack's rule (`foldedServiceHealthProvider`): a service
  // that answered with a refusal or a fault answered. Its fault is still
  // named in its group.
  var answered = 0;
  for (final service in ServiceKey.values) {
    if (!settings.hasServiceConnection(service)) {
      notSetUp.add(service);
      continue;
    }
    final async = ref.watch(serviceDiagnosisProvider(service));
    final diagnosis = async.isLoading ? null : async.asData?.value;
    final reason = diagnosis?.reason;
    if (diagnosis?.status == ServiceConnectionStatus.connected ||
        (reason != null &&
            !failureDidNotAnswer(reason) &&
            reason != ServiceFailureReason.sessionEnded)) {
      answered++;
    }
    states[service] = describeConnection(
      service,
      // Loading is a state of its own in the vocabulary, and a provider that
      // threw says exactly what a failed probe says: we could not confirm it.
      status: async.isLoading
          ? ServiceConnectionStatus.checking
          : (async.asData?.value.status ??
                ServiceConnectionStatus.disconnected),
      reason: async.asData?.value.reason,
      gateway: async.asData?.value.gateway,
    );
  }
  return ConnectionsReadout.from(
    states: states,
    notSetUp: notSetUp,
    answeringServices: answered,
  );
});

/// The connections card: the count, then only the connections that are wrong.
///
/// Shared by the summary pane and the phone index rather than drawn twice:
/// the phone's header card and the window's first card are the same statement
/// about the same stack, and two implementations of it would be two chances to
/// count "set up" differently.
class ConnectionsSummaryCard extends ConsumerWidget {
  const ConnectionsSummaryCard({super.key});

  /// The most not-yet-configured services to name before the count carries it
  /// alone. On a fresh install every service is unset, and nineteen names is
  /// not a to-do list, it is wallpaper.
  static const int _maxNamedUnset = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final readout = ref.watch(connectionsReadoutProvider);
    final notSetUp = readout.notSetUp;

    return _SummaryCard(
      label: 'Connections',
      action: const TestAllConnectionsButton(),
      children: [
        SettingsCard.grouped(
          leading: const Icon(Icons.hub_rounded),
          title: readout.summary,
          accentColor: statusToneColor(colorScheme, readout.tone),
          semanticLabel: readout.summary,
          semanticHint: 'opens the connections list',
          onTap: () => context.push('/settings/connections'),
        ),
        for (final group in readout.faults)
          _GroupRow(group: group, onTap: () => _openGroup(context, group)),
        if (notSetUp.isNotEmpty && notSetUp.length <= _maxNamedUnset)
          _GroupRow(
            group: ConnectionGroup(
              // Through the vocabulary rather than around it: "Not set up" is
              // what `describeConnection` calls a service with no address, and
              // this card must not coin a second phrase for it.
              presentation: describeConnection(
                notSetUp.first,
                status: ServiceConnectionStatus.notConfigured,
              ),
              services: notSetUp,
            ),
            onTap: () => context.push('/settings/connections'),
          ),
      ],
    );
  }

  /// One failing service opens its own form; several open the list, because
  /// there is no one form that would answer for all of them.
  void _openGroup(BuildContext context, ConnectionGroup group) {
    if (group.services.length == 1) {
      context.push('/settings/service/${group.services.single.routeParam}');
      return;
    }
    context.push('/settings/connections');
  }
}

/// One row for one connection state: the services in it, and the vocabulary's
/// word for what they are doing.
class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.group, required this.onTap});

  final ConnectionGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The card is an elevated container, so the tone has to be walked against
    // *that* surface rather than the page behind it.
    final tone = statusToneColor(
      colorScheme,
      group.presentation.tone,
      surface: colorScheme.surfaceContainer,
    );

    return SettingsCard.grouped(
      leading: Icon(group.presentation.icon),
      title: group.names,
      subtitle: group.presentation.label,
      subtitleColor: tone,
      accentColor: tone,
      semanticLabel: '${group.names}, ${group.presentation.label}',
      semanticHint: group.services.length == 1
          ? 'opens the ${group.services.single.title} connection settings'
          : 'opens the connections list',
      onTap: onTap,
    );
  }
}

/// Trusted certificates: how many origins are pinned, and any pin nothing uses.
class _TrustedCertificatesSummaryCard extends ConsumerWidget {
  const _TrustedCertificatesSummaryCard();

  /// Past this many orphans the list itself is the place to work, not a summary.
  static const int _maxNamedOrphans = 3;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final origins = settings.trustedCertificates.keys.toList()..sort();
    // An origin no configured service reaches any more. Not a fault. Nothing
    // is broken and nothing is at risk, but it is the one thing on this pane
    // that cannot be found anywhere else, since the per-service form only ever
    // shows the pin for its own address (ADR-6).
    final orphans = origins
        .where((origin) => settings.servicesSharingOriginOf(origin).isEmpty)
        .toList(growable: false);

    return _SummaryCard(
      label: 'Trusted certificates',
      children: [
        SettingsCard.grouped(
          leading: const Icon(Icons.verified_user_outlined),
          title: switch (origins.length) {
            0 => 'Nothing pinned',
            1 => '1 pinned origin',
            _ => '${origins.length} pinned origins',
          },
          semanticHint: 'opens the trusted certificates list',
          onTap: () => context.push('/settings/certificates'),
        ),
        for (final origin in orphans.take(_maxNamedOrphans))
          _NoteRow(
            icon: Icons.link_off_rounded,
            title: displayOrigin(origin),
            subtitle: 'No configured service uses this address.',
            onTap: () => context.push('/settings/certificates'),
            semanticHint: 'opens the trusted certificates list',
          ),
      ],
    );
  }
}

/// Background search: the two caps, and anything stopping a search reaching
/// past the app.
class _BackgroundSearchSummaryCard extends ConsumerWidget {
  const _BackgroundSearchSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(releaseSearchSettingsProvider);
    // Through the provider, never `Platform`: `flutter_test` runs on a desktop,
    // so reading the host directly would put every test on the desktop branch.
    final platform = ref.watch(releaseSearchPlatformProvider);
    final canRunInBackground = backgroundSearchSupported(platform: platform);

    final caps =
        '${settings.concurrency} at a time\u00A0· give up after '
        '${withUnit(settings.timeout.inMinutes, 'min')}';

    return _SummaryCard(
      label: 'Background search',
      children: [
        SettingsCard.grouped(
          leading: const Icon(Icons.travel_explore_rounded),
          title: canRunInBackground
              ? '${settings.backgroundEnabled ? 'On' : 'Off'}\u00A0· $caps'
              // Not a fault and not a setting: a desktop app is not suspended,
              // so there is nothing here to hand to the OS.
              : 'Not needed here, the app keeps running\u00A0· $caps',
          semanticHint: 'opens background search settings',
          onTap: () => context.push('/settings/background-search'),
        ),
        // Only when the user asked for notifications: a permission nobody wants
        // being un-granted is not a fault, it is the default.
        if (settings.notifyOnFinish &&
            ref.watch(notificationPermissionProvider).value == false)
          const _NoteRow(
            icon: Icons.notifications_off_rounded,
            title: 'Notifications are blocked',
            subtitle: 'Turned off for Cupola in system settings.',
            tone: StatusTone.warning,
          ),
        for (final entry in _foregroundOnly(ref).entries)
          _NoteRow(
            icon: Icons.phonelink_off_rounded,
            title: joinServiceNames(entry.value),
            subtitle: switch (entry.key) {
              ReleaseSearchReach.whileOpenTrustedCert =>
                'Searches run while Cupola is open, the certificate is '
                    'trusted only inside the app.',
              _ =>
                'Searches run while Cupola is open, the address is '
                    'cleartext.',
            },
          ),
      ],
    );
  }

  /// The release-search services whose lens instance cannot hand a search to
  /// the OS, grouped by the reason: the two reasons have different fixes, and
  /// only one of them is something the user can do anything about.
  ///
  /// Configured services only: reach answers for an empty address as readily
  /// as for a real one, and a limit announced about a service that is not set
  /// up is a limit on nothing.
  Map<ReleaseSearchReach, List<ServiceKey>> _foregroundOnly(WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final grouped = <ReleaseSearchReach, List<ServiceKey>>{};
    for (final service in ServiceKey.values.where(
      (service) =>
          SearchHeadroomCard.appliesTo(service) &&
          settings.isServiceConfigured(service),
    )) {
      final reach = ref.watch(releaseSearchLensReachProvider(service));
      if (reach == ReleaseSearchReach.whileOpenTrustedCert ||
          reach == ReleaseSearchReach.whileOpenCleartext) {
        grouped.putIfAbsent(reach, () => []).add(service);
      }
    }
    return grouped;
  }
}

/// Region: the value, and the half of the truth that looks like a filter.
class _RegionSummaryCard extends ConsumerWidget {
  const _RegionSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final region = SettingsModel.normalizeRegion(
      ref.watch(currentSettingsProvider).region,
    );

    return _SummaryCard(
      label: 'Region',
      children: [
        SettingsCard.grouped(
          leading: const Icon(Icons.language_rounded),
          title: '${commonRegions[region] ?? region} ($region)',
          semanticHint: 'opens the region picker',
          onTap: () => context.push('/settings/region'),
        ),
        // Standing, not conditional: this is the one thing about the setting a
        // user reliably gets wrong, and it is wrong from the moment it is set.
        const _NoteRow(
          icon: Icons.filter_alt_off_rounded,
          title: 'Not a Discover filter',
          subtitle:
              'It reaches release dates, ratings and watch providers, never '
              'which titles Discover returns.',
        ),
      ],
    );
  }
}

/// Appearance: which palette, and the fact that it is the only choice there is.
class _AppearanceSummaryCard extends ConsumerWidget {
  const _AppearanceSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(currentSettingsProvider).themeMode;

    return _SummaryCard(
      label: 'Appearance',
      children: [
        SettingsCard.grouped(
          leading: const Icon(Icons.palette_rounded),
          title: mode.label,
          semanticHint: 'opens the appearance picker',
          onTap: () => context.push('/settings/appearance'),
        ),
        // Says it here because the absence of a Material You switch reads as
        // an omission until you know it is a decision: the interface is
        // monochrome, and its only colour is the artwork's light and the
        // five tones. In the user's words, not the palette's.
        const _NoteRow(
          icon: Icons.colorize_rounded,
          title: 'Lit by what you watch',
          subtitle:
              'The interface stays neutral. Its color comes from the artwork '
              'on screen, never from the system accent.',
        ),
      ],
    );
  }
}

/// Hints: how many gestures still introduce themselves.
class _HintsSummaryCard extends ConsumerWidget {
  const _HintsSummaryCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // One gesture teaches itself today, the Portal, so the count is out of
    // one. The board draws "2 of 5": the other four hints do not exist yet
    // (long-press to select is its own decision), and printing 5 would be the
    // summary inventing features the app does not have.
    final enabled = ref.watch(portalHintsProvider.select((s) => s.enabled));

    return _SummaryCard(
      label: 'Hints',
      children: [
        SettingsCard.grouped(
          leading: const Icon(Icons.tips_and_updates_outlined),
          title: gestureHintsLine(introducing: enabled ? 1 : 0, total: 1),
          semanticHint: 'opens the gesture hint switches',
          onTap: () => context.push('/settings/hints'),
        ),
      ],
    );
  }
}

/// `1 gesture introduces itself` · `2 of 3 gestures introduce themselves`.
///
/// A count and a verb, and the verb agrees with the count rather than with the
/// noun after "of": the line used to read "1 of 1 gestures introduces itself",
/// which is wrong at every count. All of them is said as all of them, and none
/// as none.
String gestureHintsLine({required int introducing, required int total}) {
  if (introducing <= 0) return 'No gesture introduces itself';
  final verb = introducing == 1 ? 'introduces itself' : 'introduce themselves';
  if (introducing >= total) {
    return total == 1
        ? '1 gesture introduces itself'
        : 'All $total gestures introduce themselves';
  }
  return '$introducing of $total gestures $verb';
}

/// A card: its eyebrow, an optional command of its own, and its rows.
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.children,
    this.action,
  });

  final String label;
  final List<Widget> children;

  /// A command that belongs to this card rather than to the pane it opens:
  /// "Test all" is the only one so far. The door is the first row; this is not
  /// a second door.
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The same eyebrow every settings group on the phone index wears, so a
        // card that has a command does not also grow a different kind of
        // heading. The label excludes its own subtree from semantics and the
        // action is its sibling, so the button keeps a focus stop of its own.
        Row(
          children: [
            Expanded(child: SettingsSectionLabel(label)),
            ?action,
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        SettingsGroupCard(children: children),
      ],
    );
  }
}

/// A row that states one fact about the area this card covers.
///
/// Tone defaults to neutral because most of what these cards have to say is a
/// limit rather than a fault: a certificate nobody uses, a setting that does
/// less than its name suggests, and the amber in this system means something
/// is failing right now.
class _NoteRow extends StatelessWidget {
  const _NoteRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.tone = StatusTone.neutral,
    this.onTap,
    this.semanticHint,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final StatusTone tone;
  final VoidCallback? onTap;
  final String? semanticHint;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = statusToneColor(
      colorScheme,
      tone,
      surface: colorScheme.surfaceContainer,
    );

    return SettingsCard.grouped(
      leading: Icon(icon),
      title: title,
      subtitle: subtitle,
      accentColor: color,
      subtitleColor: tone == StatusTone.neutral ? null : color,
      semanticLabel: '$title. $subtitle',
      semanticHint: semanticHint,
      onTap: onTap,
    );
  }
}
