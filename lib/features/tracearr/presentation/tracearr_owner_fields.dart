import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/core/widgets/notice_line.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/presentation/widgets/seerr_sign_in_steps.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_section_label.dart';
import 'package:cupola/features/tracearr/data/tracearr_owner_accounts.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_owner_session.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_owner_notice.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_owner_sign_in_flow.dart';

/// The owner's access, inside a Tracearr connection's own settings: signing
/// in as the owner, signed in, and signed out.
///
/// An addition to the connection's public key, never instead of it: the key
/// reads everything, and the owner's session only adds the two writes the
/// public API has no route for (Acknowledge and Dismiss on a violation).
/// Optional, and drawn only for a saved connection that works, since the
/// sign-in goes through that connection's own route.
///
/// The sign-in is [TracearrOwnerSignInFlow]; this draws it and adds what only
/// a saved connection has: who is signed in, signing out, and the blue
/// `Signed out of Tracearr` of a session that ended, never a fault.
class TracearrOwnerFields extends ConsumerStatefulWidget {
  const TracearrOwnerFields({super.key, required this.connectionId});

  final String connectionId;

  @override
  ConsumerState<TracearrOwnerFields> createState() =>
      _TracearrOwnerFieldsState();
}

class _TracearrOwnerFieldsState extends ConsumerState<TracearrOwnerFields> {
  late final TracearrOwnerSignInFlow _flow = TracearrOwnerSignInFlow(
    ref: ref,
    connectionId: widget.connectionId,
  );

  @override
  void dispose() {
    _flow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final owner = ref.watch(
      currentSettingsProvider.select(
        (settings) => settings.instanceById(widget.connectionId)?.owner,
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SettingsSectionLabel('Owner access'),
        const SizedBox(height: AppSpacing.sm),
        ListenableBuilder(
          listenable: _flow,
          builder: (context, _) => VisibilityPoller(
            id: 'tracearr.owner.plex',
            interval: kTracearrPlexPollEvery,
            enabled: _flow.waitingOnPlex,
            onTick: _flow.onPlexTick,
            child: _content(context, owner),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, TracearrOwnerSession? owner) {
    final stage = _flow.stage;
    final notice = _flow.notice;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (notice != null) ...[
          _line(context, notice),
          const SizedBox(height: AppSpacing.md),
        ],
        ...switch (stage) {
          TracearrOwnerSignInStage.start => _start(context, owner, notice),
          TracearrOwnerSignInStage.asking => [
            const SeerrSignInBusy('Asking Tracearr'),
          ],
          TracearrOwnerSignInStage.form => _passwordForm(context),
          TracearrOwnerSignInStage.signingIn => [
            const SeerrSignInBusy('Signing in'),
          ],
          TracearrOwnerSignInStage.plex => _plexWaiting(context),
        },
      ],
    );
  }

  Widget _line(BuildContext context, TracearrOwnerNotice notice) => NoticeLine(
    tone: notice.tone,
    title: notice.title,
    sentence: notice.sentence,
    actions: [
      if (notice.kind == TracearrOwnerNoticeKind.plexTimedOut &&
          _flow.retry != null)
        seerrSignInAction(
          context,
          'Start again',
          _flow.retry!,
          fill: notice.tone,
        ),
      if (notice.retryHelps && _flow.retry != null)
        seerrSignInAction(
          context,
          Lexicon.retry,
          _flow.retry!,
          // Beside silence, text in ink; for a fault, its amber fill.
          fill: notice.tone == StatusTone.warning ? notice.tone : null,
        ),
    ],
  );

  List<Widget> _start(
    BuildContext context,
    TracearrOwnerSession? owner,
    TracearrOwnerNotice? notice,
  ) {
    final theme = Theme.of(context);
    if (owner != null && owner.isSignedIn) {
      return [_signedInBlock(context, owner)];
    }
    // A notice that says the way is closed (single sign-on, turned off) is
    // the answer: offering the button again would be a promise that fails.
    final closed =
        notice != null &&
        (notice.kind == TracearrOwnerNoticeKind.singleSignOn ||
            notice.kind == TracearrOwnerNoticeKind.turnedOff ||
            notice.kind == TracearrOwnerNoticeKind.notSetUp);
    if (closed) return const [];
    if (owner != null) {
      return [
        if (notice == null) ...[
          NoticeLine(
            tone: TracearrOwnerNotice.signedOut.tone,
            title: TracearrOwnerNotice.signedOut.title,
            sentence: TracearrOwnerNotice.signedOut.sentence,
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        SeerrSignInPrimary(
          label: Lexicon.signInAgain,
          onPressed: () => _flow.begin(again: owner),
        ),
      ];
    }
    return [
      Text(
        'Cupola reads with the key. The owner can also acknowledge and '
        'dismiss violations.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: AppSpacing.md),
      SeerrSignInPrimary(label: 'Sign in as the owner', onPressed: _flow.begin),
    ];
  }

  Widget _signedInBlock(BuildContext context, TracearrOwnerSession owner) {
    final theme = Theme.of(context);
    final name = owner.displayName.isEmpty ? 'the owner' : owner.displayName;
    return Row(
      children: [
        Expanded(
          child: MergeSemantics(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Lexicon.signedInAs(name),
                  style: theme.textTheme.titleSmall!.weight(FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(
                  'Tracearr\u00A0· ${_flow.host}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        OutlinedButton(
          onPressed: _signOut,
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.standard,
            minimumSize: const Size(64, 44),
          ),
          child: const Text(Lexicon.signOut),
        ),
      ],
    );
  }

  Future<void> _signOut() async {
    final result = await showAppConfirmDialog(
      context: context,
      icon: Icons.logout_rounded,
      title: 'Sign out of Tracearr?',
      message:
          'Acknowledge and Dismiss go dim until you sign in as the owner '
          'again.',
      confirmLabel: Lexicon.signOut,
    );
    if (!result.confirmed || !mounted) return;
    await ref.read(tracearrOwnerAccountsProvider).signOut(widget.connectionId);
  }

  List<Widget> _passwordForm(BuildContext context) {
    final theme = Theme.of(context);
    void send() {
      if (_flow.readyToSend) FocusScope.of(context).unfocus();
      _flow.signInWithPassword();
    }

    return [
      Text(
        'Sign in as the owner',
        style: theme.textTheme.titleSmall!.weight(FontWeight.w600),
      ),
      const SizedBox(height: AppSpacing.md),
      TextField(
        controller: _flow.login,
        decoration: const InputDecoration(labelText: 'Name or email'),
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        textInputAction: TextInputAction.next,
        autofillHints: const [AutofillHints.username],
      ),
      const SizedBox(height: AppSpacing.md),
      SeerrSignInPasswordField(controller: _flow.password, onSubmitted: send),
      const SizedBox(height: AppSpacing.md),
      SeerrSignInPrimary(label: 'Sign in', onPressed: send),
      if (_flow.ways?.plex ?? false)
        seerrSignInAction(context, 'Continue with Plex', _flow.startPlex),
      seerrSignInAction(context, 'Cancel', _flow.cancel),
      const SizedBox(height: AppSpacing.xs),
      Text(
        "Your password goes only to ${_flow.host}. Cupola doesn't keep it.",
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  List<Widget> _plexWaiting(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Text(
        'Finish signing in with Plex',
        style: theme.textTheme.titleSmall!.weight(FontWeight.w600),
      ),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Approve Tracearr on the Plex page, then come back here.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: AppSpacing.md),
      SeerrSignInPrimary(
        label: 'Open the Plex page again',
        onPressed: _flow.openPlexPage,
      ),
      seerrSignInAction(context, 'Cancel', _flow.cancel),
    ];
  }
}
