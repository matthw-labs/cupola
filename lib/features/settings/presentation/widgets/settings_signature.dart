import 'package:flutter/material.dart';

import 'package:cupola/core/app_identity.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/service_ring.dart';

/// Cupola's signature at the foot of Settings on a phone: the mark, the claim
/// and the line that says which Cupola this is (`Cupola 1.1.0-beta · Apache-2.0`).
///
/// The one place the claim stands once the app is set up, and the phone's only
/// readout of the version, for the operator and the requester alike. The wide
/// window keeps the identity line alone at the foot of its rail, where a mark
/// and a sentence would crowd the index.
///
/// It quotes [OnePunchline.claim] and [kAppIdentityLine] rather than spelling
/// either: the brand's words live once.
class SettingsSignature extends StatelessWidget {
  const SettingsSignature({super.key});

  /// What a screen reader says for it, once: the claim, then which Cupola.
  static const spoken =
      '${OnePunchline.claim} $kAppName $kAppRelease, $kAppLicence.';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: spoken,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(
          top: AppSpacing.xxl,
          bottom: AppSpacing.md,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CupolaMark.sized(40),
            const SizedBox(height: AppSpacing.md),
            // The display face, as the claim is set on the Welcome, at the
            // size of a section heading rather than a screen's.
            Text(
              OnePunchline.claim,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge!.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              kAppIdentityLine,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelSmall!.copyWith(
                color: CupolaThemeColors.of(context).dimText,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
