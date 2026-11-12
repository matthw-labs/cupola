import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:cupola/core/app_identity.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/service_ring.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/donation_service.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/settings/domain/trademark_notice.dart';
import 'package:cupola/features/settings/presentation/widgets/donation_sheet.dart';

/// The rows about the app rather than about the stack: About, Revisit
/// onboarding, Reset app data.
///
/// **One set, two layouts.** They lived only in the phone index
/// (`SettingsHomeScreen`), so on a window wide enough for the rail, where
/// `/settings` is the summary pane and every other row became a rail section:
/// the licence page, the feedback address, the donation sheet, the onboarding
/// replay and Reset had no door at all. None of them is a page, so none belongs
/// on the rail; the pane shows them as cards in its own grammar, and both
/// layouts build the same rows from here so they cannot drift.

final Uri _githubUri = Uri.parse('https://github.com/matthw-labs/cupola');
final Uri _feedbackUri = Uri(scheme: 'mailto', path: 'matthw.labs@gmail.com');

/// GitHub, Send feedback, Support development, Licenses & trademarks: the
/// four rows of the About group, in that order. The requester's group has no
/// GitHub: source, issues and releases are for whoever runs the app's
/// servers, and she asks for movies.
List<Widget> settingsAboutRows(
  BuildContext context, {
  Audience audience = Audience.operator,
}) {
  final colorScheme = Theme.of(context).colorScheme;
  return [
    if (audience == Audience.operator)
      SettingsCard.grouped(
        leading: const Icon(Icons.code_rounded),
        title: 'GitHub',
        subtitle: 'Source, issues and releases',
        accentColor: colorScheme.onSurfaceVariant,
        semanticHint: 'opens the repository in your browser',
        onTap: () => _launchExternalUri(
          context: context,
          uri: _githubUri,
          failureMessage: 'Unable to open the GitHub repository.',
        ),
      ),
    SettingsCard.grouped(
      leading: const Icon(Icons.feedback_rounded),
      title: 'Send feedback',
      subtitle: 'Email us',
      semanticHint: 'opens your email composer',
      onTap: () => _launchExternalUri(
        context: context,
        uri: _feedbackUri,
        failureMessage: 'Unable to open the email composer.',
      ),
    ),
    SettingsCard.grouped(
      leading: const Icon(Icons.favorite_rounded),
      title: 'Support development',
      subtitle: 'Buy us a coffee',
      onTap: () => _openDonation(context),
    ),
    // The only way into the licence page. `main.dart` registers each bundled
    // font's OFL with the registry, and the OFL's one condition on a bundling
    // binary is that its text travels with it, which it did not, in any
    // build, while nothing in the app opened the page.
    SettingsCard.grouped(
      leading: const Icon(Icons.gavel_rounded),
      title: 'Licenses & trademarks',
      subtitle: 'Open-source licenses and trademark notices',
      accentColor: colorScheme.onSurfaceVariant,
      onTap: () => showLicensePage(
        context: context,
        applicationName: kAppName,
        applicationVersion: kAppRelease,
        applicationIcon: const Padding(
          padding: EdgeInsets.all(AppSpacing.sm),
          child: CupolaMark.sized(56),
        ),
        applicationLegalese: trademarkNotice,
      ),
    ),
  ];
}

/// The way to the code another device copies this one's services from. Built
/// for the operator with at least one connection to hand over: the requester
/// has none, and a device with nothing set up has nothing to copy.
///
/// One row for both layouts, like the rows around it: the phone's index puts
/// it in the group before About and the window's summary in its Onboarding
/// card, the last group before About on either.
///
/// [SettingsAnotherDeviceRow.offeredFor] is when to build it.
class SettingsAnotherDeviceRow extends StatelessWidget {
  const SettingsAnotherDeviceRow({super.key});

  /// Whether [settings] has a connection to hand over: one set up, or a Seerr
  /// account that signed out and keeps its address and login. What the
  /// Welcome's own gate asks (`showsWelcome`).
  static bool offeredFor(SettingsModel settings) =>
      ServiceKey.values.any(settings.hasServiceConnection);

  @override
  Widget build(BuildContext context) {
    return SettingsCard.grouped(
      leading: const Icon(Icons.qr_code_2_rounded),
      title: 'Set up another device',
      subtitle: 'Copy everything to a new phone',
      semanticHint: 'opens a code the other device copies from',
      onTap: () => context.push(ServiceRoutes.settingsAnotherDevice),
    );
  }
}

/// Opens the Welcome again, after asking: nothing set up is touched.
class SettingsRevisitOnboardingRow extends ConsumerWidget {
  const SettingsRevisitOnboardingRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsCard.grouped(
      leading: const Icon(Icons.replay_rounded),
      title: 'Revisit onboarding',
      subtitle: 'See the Welcome again',
      semanticHint: 'opens the Welcome',
      onTap: () => _confirmRevisitOnboarding(context, ref),
    );
  }

  Future<void> _confirmRevisitOnboarding(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.replay_rounded,
      title: 'Revisit onboarding?',
      message:
          "You'll see the Welcome again. Nothing about your services or "
          'settings is changed or removed.',
      confirmLabel: 'Revisit onboarding',
      enterConfirms: true,
    );

    if (!result.confirmed) return;
    if (!context.mounted) return;
    // Pushed, so Back returns here: the Welcome is never redirected away
    // from, and nothing about the connections or the flag changes.
    context.push(ServiceRoutes.welcome);
  }
}

/// Clears every service, credential and preference, behind its confirmation,
/// on both layouts.
class SettingsResetAppDataRow extends ConsumerWidget {
  const SettingsResetAppDataRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsCard.grouped(
      leading: const Icon(Icons.restart_alt_rounded),
      title: 'Reset app data',
      subtitle: 'Clear all services, settings, and restart onboarding',
      // The row's default accent, like every other settings row: red means
      // unreachable and nothing else, and the confirmation says what goes.
      onTap: () => _confirmReset(context, ref),
    );
  }

  Future<void> _confirmReset(BuildContext context, WidgetRef ref) async {
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.restart_alt_rounded,
      title: 'Reset all data?',
      message:
          'This clears all saved services, credentials, and preferences. '
          'Onboarding will restart. This cannot be undone.',
      confirmLabel: 'Reset app data',
    );

    if (!result.confirmed) return;

    try {
      await ref.read(settingsProvider.notifier).resetSettings();
      await markOnboardingIncomplete(ref);
    } catch (e) {
      if (!context.mounted) return;
      SnackBarHelper.error(context, "Could not reset app data.", detail: e);
    }
  }
}

Future<void> _openDonation(BuildContext context) async {
  if (DonationService.usesIAP) {
    final useFallback = await AppBottomSheet.show<bool>(
      context: context,
      title: 'Support Cupola',
      icon: Icons.favorite_rounded,
      builder: (_) => const DonationSheet(),
    );
    // Sheet returned true when IAP products aren't available: open Ko-fi.
    if (useFallback == true && context.mounted) {
      final launched = await DonationService.launchKofi();
      if (!launched && context.mounted) {
        SnackBarHelper.info(context, 'Unable to open the donation page.');
      }
    }
  } else {
    final launched = await DonationService.launchKofi();
    if (!launched && context.mounted) {
      SnackBarHelper.info(context, 'Unable to open the donation page.');
    }
  }
}

Future<void> _launchExternalUri({
  required BuildContext context,
  required Uri uri,
  required String failureMessage,
}) async {
  final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
  if (!launched && context.mounted) {
    SnackBarHelper.info(context, failureMessage);
  }
}
