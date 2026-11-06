import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/platform/browser_opener.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/core/widgets/notice_line.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/seerr_server_facts.dart';
import 'package:cupola/features/discover/presentation/seerr_sign_in_notice.dart';
import 'package:cupola/features/settings/presentation/widgets/seerr_sign_in_flow.dart';

/// The steps of a [SeerrSignInFlow] as they are drawn: the notice the last
/// step ended with, then the ways in, the password form, the waits on Plex
/// and on a Quick Connect code.
///
/// [start] is what the flow shows before it asks anything, and differs by
/// where it is drawn: the connection's form says Continue, or who is signed
/// in; the first run asks where the Seerr is. [title] is what the server
/// calls itself, for its headings.
///
/// The waits ask again only while this is on screen and the app is in
/// front: coming back from the browser or from a Jellyfin app, the gate's
/// catch-up asks at once.
class SeerrSignInSteps extends ConsumerWidget {
  const SeerrSignInSteps({
    super.key,
    required this.flow,
    required this.start,
    required this.onUseApiKey,
    required this.onCheckAddress,
    required this.onUseHttps,
    this.heading,
  });

  final SeerrSignInFlow flow;

  /// The style of the steps' headings ("Sign in to Jellyseerr"): a section's
  /// title inside a form, by default; the page's own headline where the
  /// sign-in is the whole page.
  final TextStyle? heading;

  /// What the flow shows at [SeerrSignInStage.start], under its notice.
  final List<Widget> Function(BuildContext context) start;

  /// The server has every way in off: the key is what is left.
  final VoidCallback onUseApiKey;

  /// Something other than Seerr answered at the address.
  final VoidCallback onCheckAddress;

  /// The address is `http://` off the local network.
  final VoidCallback onUseHttps;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListenableBuilder(
      listenable: flow,
      builder: (context, _) => VisibilityPoller(
        id: 'seerr.signIn.plex',
        interval: seerrPlexPollEvery,
        enabled: flow.waitingOnPlex,
        onTick: flow.onPlexTick,
        child: VisibilityPoller(
          id: 'seerr.signIn.quickConnect',
          interval: seerrQuickConnectPollEvery,
          enabled: flow.waitingOnCode,
          onTick: flow.onQuickConnectTick,
          child: _content(context, ref),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, WidgetRef ref) {
    final stage = flow.stage;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The password form places its notice under its own title, beside the
        // fields it is about; every other stage leads with it.
        if (flow.notice case final notice?
            when stage != SeerrSignInStage.form) ...[
          SeerrSignInNoticeLine(
            notice: notice,
            actions: _noticeActions(context, notice),
          ),
          const SizedBox(height: AppSpacing.md),
        ],
        ...switch (stage) {
          SeerrSignInStage.start => start(context),
          SeerrSignInStage.asking => [const SeerrSignInBusy('Asking Seerr')],
          SeerrSignInStage.methods => _methods(context),
          SeerrSignInStage.form => _passwordForm(context, ref),
          SeerrSignInStage.signingIn => [const SeerrSignInBusy('Signing in')],
          SeerrSignInStage.plex => _plexWaiting(context),
          SeerrSignInStage.quickConnect => _quickConnectWaiting(context),
        },
      ],
    );
  }

  TextStyle _heading(ThemeData theme) =>
      heading ?? theme.textTheme.titleSmall!.weight(FontWeight.w600);

  List<Widget> _noticeActions(BuildContext context, SeerrSignInNotice notice) {
    final others = flow.offered.length;
    return [
      if (notice.kind == SeerrSignInNoticeKind.turnedOff)
        seerrSignInAction(
          context,
          'Use the API key',
          onUseApiKey,
          fill: notice.tone,
        ),
      if (notice.kind == SeerrSignInNoticeKind.notSeerr ||
          notice.kind == SeerrSignInNoticeKind.noSecureConnection ||
          notice.kind == SeerrSignInNoticeKind.didNotAnswer)
        seerrSignInAction(
          context,
          'Check the address',
          onCheckAddress,
          fill: notice.kind == SeerrSignInNoticeKind.didNotAnswer
              ? null
              : notice.tone,
        ),
      // Declined is a choice: the certificate again, to look at and trust.
      if (notice.kind == SeerrSignInNoticeKind.certificateDeclined &&
          flow.retry != null)
        seerrSignInAction(
          context,
          'Show the certificate',
          flow.retry!,
          fill: notice.tone,
        ),
      if (notice.kind == SeerrSignInNoticeKind.plexTimedOut)
        seerrSignInAction(
          context,
          'Start again',
          flow.startPlex,
          fill: notice.tone,
        ),
      if (notice.kind == SeerrSignInNoticeKind.codeExpired)
        seerrSignInAction(
          context,
          'Get a new code',
          flow.startQuickConnect,
          fill: notice.tone,
        ),
      if (notice.kind == SeerrSignInNoticeKind.accountNotAllowed && others > 1)
        seerrSignInAction(context, 'Sign in another way', flow.showMethods),
      if (notice.retryHelps && flow.retry != null)
        seerrSignInAction(
          context,
          Lexicon.retry,
          flow.retry!,
          // Beside silence, text in ink; for a fault, its amber fill.
          fill: notice.tone == StatusTone.warning ? notice.tone : null,
        ),
    ];
  }

  List<Widget> _methods(BuildContext context) {
    final facts = flow.facts!;
    final theme = Theme.of(context);
    if (flow.cleartextGate) {
      return [
        SeerrSignInNoticeLine(
          notice: SeerrSignInNotice.notEncrypted,
          actions: [
            seerrSignInAction(
              context,
              'Use https',
              onUseHttps,
              fill: SeerrSignInNotice.notEncrypted.tone,
            ),
            seerrSignInAction(context, 'Continue anyway', flow.acceptCleartext),
          ],
        ),
      ];
    }
    return [
      Text('Sign in to ${facts.title}', style: _heading(theme)),
      const SizedBox(height: AppSpacing.md),
      for (final method in flow.offered) ...[
        SeerrSignInPrimary(
          label: seerrMethodLabel(method),
          onPressed: () => flow.choose(method),
        ),
        const SizedBox(height: AppSpacing.sm),
      ],
      Text(
        "Your password goes only to ${flow.host}. Cupola doesn't keep it.",
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  List<Widget> _passwordForm(BuildContext context, WidgetRef ref) {
    final facts = flow.facts!;
    final method = flow.method!;
    final theme = Theme.of(context);
    final local = method == SeerrSignInMethod.local;
    // Seerr's own page, at the address the server was read at: away from
    // home, the one at home would not open.
    final forgot = local
        ? (facts.emailEnabled
              ? Uri.tryParse(
                  '${UrlUtils.normalizeBaseUrl(flow.readAt)}/resetpassword',
                )
              : null)
        : Uri.tryParse(facts.jellyfinForgotPasswordUrl ?? '');
    final serverName = facts.jellyfinServerName;
    void send() {
      if (flow.readyToSend) FocusScope.of(context).unfocus();
      flow.signInWithPassword();
    }

    return [
      Text('Sign in to ${facts.title}', style: _heading(theme)),
      if (!local && serverName != null) ...[
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Use the account you watch with on $serverName.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      const SizedBox(height: AppSpacing.md),
      // A refused password reads under the title it answers ("Sign in to
      // Jellyseerr"), next to the fields to change, not above the heading.
      if (flow.notice case final notice?) ...[
        SeerrSignInNoticeLine(
          notice: notice,
          actions: _noticeActions(context, notice),
        ),
        const SizedBox(height: AppSpacing.md),
      ],
      TextField(
        controller: flow.login,
        decoration: InputDecoration(labelText: local ? 'Email' : 'Username'),
        keyboardType: local ? TextInputType.emailAddress : TextInputType.text,
        autocorrect: false,
        textInputAction: TextInputAction.next,
        autofillHints: [local ? AutofillHints.email : AutofillHints.username],
      ),
      const SizedBox(height: AppSpacing.md),
      SeerrSignInPasswordField(controller: flow.password, onSubmitted: send),
      const SizedBox(height: AppSpacing.md),
      SeerrSignInPrimary(label: 'Sign in', onPressed: send),
      if (forgot != null && UrlUtils.isLaunchableWebUrl(forgot.toString()))
        seerrSignInAction(
          context,
          'Forgot your password?',
          () => ref.read(browserOpenerProvider).open(forgot),
        ),
      if (flow.offered.length > 1)
        seerrSignInAction(context, 'Sign in another way', flow.showMethods),
    ];
  }

  List<Widget> _plexWaiting(BuildContext context) {
    final theme = Theme.of(context);
    return [
      Text('Finish signing in with Plex', style: _heading(theme)),
      const SizedBox(height: AppSpacing.xs),
      Text(
        'Approve Cupola on the Plex page, then come back here.',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: AppSpacing.md),
      SeerrSignInPrimary(
        label: 'Open the Plex page again',
        onPressed: flow.openPlexPage,
      ),
      seerrSignInAction(context, 'Cancel', flow.cancel),
    ];
  }

  List<Widget> _quickConnectWaiting(BuildContext context) {
    final theme = Theme.of(context);
    final code = flow.code;
    if (code == null) return [const SeerrSignInBusy('Asking Seerr')];
    return [
      Semantics(
        label: 'Code ${code.code.split('').join(' ')}',
        excludeSemantics: true,
        child: Text(
          code.code,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium!.weight(FontWeight.w600),
        ),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(
        "Open Jellyfin on a device where you're signed in, then enter this "
        'code under Quick Connect.',
        style: theme.textTheme.bodyMedium,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: AppSpacing.md),
      seerrSignInAction(context, 'Cancel', flow.cancel),
    ];
  }
}

/// What a way in is called on its button.
String seerrMethodLabel(SeerrSignInMethod method) => switch (method) {
  SeerrSignInMethod.plex => 'Continue with Plex',
  SeerrSignInMethod.jellyfin => 'Sign in with Jellyfin',
  SeerrSignInMethod.jellyfinQuickConnect => 'Sign in with a code from Jellyfin',
  SeerrSignInMethod.emby => 'Sign in with Emby',
  SeerrSignInMethod.local => 'Sign in with email',
};

/// The sign-in's password field: obscured, with a show toggle. Shared with
/// the Tracearr owner's sign-in, whose form is the same two fields.
class SeerrSignInPasswordField extends StatefulWidget {
  const SeerrSignInPasswordField({
    super.key,
    required this.controller,
    required this.onSubmitted,
  });

  final TextEditingController controller;
  final VoidCallback onSubmitted;

  @override
  State<SeerrSignInPasswordField> createState() =>
      _SeerrSignInPasswordFieldState();
}

class _SeerrSignInPasswordFieldState extends State<SeerrSignInPasswordField> {
  bool _show = false;

  @override
  Widget build(BuildContext context) => TextField(
    controller: widget.controller,
    decoration: InputDecoration(
      labelText: 'Password',
      suffixIcon: IconButton(
        icon: Icon(
          _show ? Icons.visibility_off_rounded : Icons.visibility_rounded,
        ),
        tooltip: _show ? 'Hide password' : 'Show password',
        onPressed: () => setState(() => _show = !_show),
      ),
    ),
    obscureText: !_show,
    autocorrect: false,
    enableSuggestions: false,
    textInputAction: TextInputAction.done,
    autofillHints: const [AutofillHints.password],
    onSubmitted: (_) => widget.onSubmitted(),
  );
}

/// The sign-in's busy primary: the step under way, not tappable.
class SeerrSignInBusy extends StatelessWidget {
  const SeerrSignInBusy(this.label, {super.key});

  final String label;

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: null,
    style: FilledButton.styleFrom(
      visualDensity: VisualDensity.standard,
      minimumSize: const Size(64, 44),
    ),
    icon: const SizedBox.square(
      dimension: 16,
      child: CircularProgressIndicator(strokeWidth: 2),
    ),
    label: Text(label),
  );
}

/// The sign-in's primary, in ink.
class SeerrSignInPrimary extends StatelessWidget {
  const SeerrSignInPrimary({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => FilledButton(
    onPressed: onPressed,
    style: FilledButton.styleFrom(
      visualDensity: VisualDensity.standard,
      minimumSize: const Size(64, 44),
    ),
    child: Text(label),
  );
}

/// A verb of the sign-in: a [noticeAction].
Widget seerrSignInAction(
  BuildContext context,
  String label,
  VoidCallback onPressed, {
  StatusTone? fill,
}) => noticeAction(context, label, onPressed, fill: fill);

/// One notice of the sign-in, the quiet way a failure line is ([NoticeLine]).
class SeerrSignInNoticeLine extends StatelessWidget {
  const SeerrSignInNoticeLine({
    super.key,
    required this.notice,
    required this.actions,
  });

  final SeerrSignInNotice notice;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => NoticeLine(
    tone: notice.tone,
    title: notice.title,
    sentence: notice.sentence,
    actions: actions,
  );
}
