/// What is left of the Dashboard's regions on the Home: the row a decision
/// draws (Needs you's lead, the Requests module's rows).
///
/// The modules themselves (Arrived, Downloads, Requests, Now playing) are
/// drawn on their own, in `lib/features/home/presentation/widgets/`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/cross_service_action.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/discover/domain/models/seerr_request.dart';
import 'package:cupola/features/dockge/domain/models/dockge_agent.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/npm/domain/models/npm_models.dart';
import 'package:cupola/features/npm/presentation/npm_capability.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_indexer_actions.dart';
import 'package:cupola/features/prowlarr/presentation/prowlarr_provider.dart';
import 'package:cupola/features/requests/presentation/widgets/request_answer_controls.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/core/platform/browser_opener.dart';

/// One thing waiting on a human.
///
/// The row body links to the item; the trailing control is the decision. They
/// are never the same destination: a row where "open it" and "do it" are one
/// gesture is a row you cannot inspect before acting.
///
/// Requests draws it for the requests that wait; every other kind (a stall,
/// a blocked import, an indexer, a stack, a certificate) keeps its control
/// here for the list of everything that needs the operator, which Needs you
/// leads to and Activity will draw.
class DecisionRow extends ConsumerWidget {
  const DecisionRow({
    super.key,
    required this.decision,
    this.divided = false,
    this.outcome,
    this.request,
  }) : _stacked = false;

  /// The row of a page that lists every fault (Activity): the control under
  /// the words, at their start, so neither the words nor the control is cut
  /// to make room for the other.
  const DecisionRow.stacked({
    super.key,
    required this.decision,
    this.divided = false,
    this.outcome,
    this.request,
  }) : _stacked = true;

  final bool _stacked;

  final DashboardDecision decision;

  /// What happened to it once answered here (`Approved · sent to Radarr`):
  /// the row says so in place of its detail, without its controls.
  final String? outcome;

  /// The waiting request itself, when the caller read it whole: Approve
  /// names the server it goes to without reading it again.
  final SeerrRequest? request;

  /// Whether a hairline separates it from the row above: every row of a
  /// module but its first.
  final bool divided;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (decision.kind == DecisionKind.pendingRequest) {
      return _RequestRow(
        decision: decision,
        divided: divided,
        outcome: outcome,
        request: request,
      );
    }
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    // Faults are amber; a pending request is backlog and stays neutral. The tone
    // decides the marker's colour and nothing else: the row is not filled or
    // bordered in it, because six amber rows would be a wall.
    final tone = decision.isFault
        ? StatusTone.warning
        : decision.kind == DecisionKind.violation
        ? StatusTone.info
        : StatusTone.neutral;
    final toneColor = statusToneColor(
      colorScheme,
      tone,
      surface: colorScheme.surfaceContainer,
    );

    Future<void> open() => openDecision(context, ref, decision);

    // A row of its module's slab: no card of its own inside the slab, a
    // hairline above every row but the first.
    return DecoratedBox(
      key: ValueKey('decision-${decision.id}'),
      decoration: BoxDecoration(
        border: divided
            ? Border(top: BorderSide(color: CupolaRoom.of(context).hair))
            : null,
      ),
      child: Semantics(
        container: true,
        button: true,
        label: decision.title,
        value: outcome != null
            ? spokenFromDotted(outcome!)
            : decisionRowSpokenValue(
                serviceTitle: decision.service.title,
                detail: decision.detail,
                actionLabel: decisionActionLabel(
                  decision.kind,
                  target: decision.actionTarget,
                  renewable: decision.renewable,
                ),
              ),
        onTap: open,
        child: InkWell(
          onTap: open,
          // The name and the tap are the node above's.
          excludeFromSemantics: true,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
            child: Flex(
              direction: _stacked ? Axis.vertical : Axis.horizontal,
              mainAxisSize: _stacked ? MainAxisSize.min : MainAxisSize.max,
              crossAxisAlignment: _stacked
                  ? CrossAxisAlignment.stretch
                  : CrossAxisAlignment.center,
              children: [
                // Everything the row's own label already speaks.
                Flexible(
                  flex: _stacked ? 0 : 1,
                  fit: _stacked ? FlexFit.loose : FlexFit.tight,
                  child: ExcludeSemantics(
                    child: Row(
                      children: [
                        SizedBox(
                          width: 38,
                          height: 54,
                          child: decision.posterUrl.isEmpty
                              ? _GlyphPlate(
                                  icon: decision.service.icon,
                                  tone: toneColor,
                                )
                              : _HeroContentCard(
                                  heroTag: null,
                                  imageUrl: decision.posterUrl,
                                ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                decision.title,
                                maxLines: _stacked ? 3 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium?.weight(
                                  FontWeight.w600,
                                ),
                              ),
                              Text(
                                outcome ?? decision.detail,
                                maxLines: _stacked ? 4 : 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: decision.isFault && outcome == null
                                      ? toneColor
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Not excluded: these are the point of the row.
                if (outcome == null)
                  if (_stacked)
                    Padding(
                      padding: const EdgeInsets.only(
                        top: AppSpacing.xs,
                        left: 38 + AppSpacing.sm,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: DecisionControl(decision: decision),
                      ),
                    )
                  else
                    DecisionControl(decision: decision),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Opens the place [decision] is fixed today: where its row leads. Needs
/// you's Review goes here too.
Future<void> openDecision(
  BuildContext context,
  WidgetRef ref,
  DashboardDecision decision,
) async {
  final route = decision.route;
  if (route == null) return;
  // A page that reads the lens opens on the connection the row came off: see
  // [DecisionKindRank.opensUnderLens].
  if (decision.kind.opensUnderLens) {
    await bringUnderLens(ref, decision.service, decision.instanceId);
    if (!context.mounted) return;
  }
  // A title's own page opens under this tab.
  await context.pushMounted(route);
}

/// A decision's control: the row's trailing button, or ([DecisionControl.fill])
/// the amber fill a fault's card leads its remedies with.
///
/// Both are gated alike: a write the credential may not make is dimmed with
/// the reason, a control on a service with no connection is dimmed and names
/// it. Never hidden, never `Semantics(enabled: false)`.
class DecisionControl extends ConsumerWidget {
  const DecisionControl({super.key, required this.decision})
    : _fill = false,
      label = null;

  /// The fill, full width, labelled [label] when the card names the remedy
  /// otherwise than the row does (`Review 18`).
  const DecisionControl.fill({super.key, required this.decision, this.label})
    : _fill = true;

  final DashboardDecision decision;
  final String? label;
  final bool _fill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final required = decision.requiresService;
    final label =
        this.label ??
        decisionActionLabel(
          decision.kind,
          target: decision.actionTarget,
          renewable: decision.renewable,
          remedy: decision.remedy,
        );

    // Renewing is a write on the certificates of one NPM account, and a
    // view-only account cannot make it: the same gate the Certificates tab
    // draws its own Renew through, so Home never offers what the page beyond
    // it would dim. Dimmed rather than hidden, like every write a credential
    // may not make: the certificate still needs somebody, and the toast says
    // which account can do it. An uploaded certificate has no Renew to gate:
    // its control only opens the certificates, which any account may read.
    if (decision.kind == DecisionKind.expiringCertificate &&
        decision.renewable) {
      return CapabilityGatedAction.builder(
        service: ServiceKey.nginxProxyManager,
        // Empty means the lens, which is the connection the certificates
        // were read through.
        connectionId: decision.instanceId.isNotEmpty
            ? decision.instanceId
            : capabilityConnectionId(ref, ServiceKey.nginxProxyManager),
        resource: NpmResource.certificates.key,
        hint: npmCapabilityHint,
        blockedMessage: npmBlockedMessage(NpmResource.certificates),
        onTap: () => runDecision(context, ref, decision),
        builder: (context, onPressed, annotate) => _DecisionActionButton(
          label: label,
          onPressed: onPressed,
          annotate: annotate,
          fill: _fill,
        ),
      );
    }

    if (required == null) {
      return _DecisionActionButton(
        label: label,
        onPressed: () => runDecision(context, ref, decision),
        fill: _fill,
      );
    }

    // Dimmed but tappable, never `Semantics(enabled: false)`: the shared
    // cross-service cell. Hiding or disabling the control would hide the fact
    // with it, and the fact (that this stall can only be touched in a client
    // this stack has no connection to) is what the page is for. Its toast's
    // one action opens that client's settings.
    return CrossServiceAction.builder(
      target: required,
      blockedMessage: decisionUnavailableToast(decision.kind, required),
      onTap: () => runDecision(context, ref, decision),
      builder: (context, onPressed, annotate) => _DecisionActionButton(
        label: label,
        onPressed: onPressed,
        annotate: annotate,
        fill: _fill,
      ),
    );
  }
}

/// What the trailing control does, per kind.
///
/// Two of the six are real writes from here: approve and decline are handled by
/// [DecisionControl] above, and Start and Test are below, because both are a
/// single confirmed call this app already owns. The other three *navigate to
/// where the act happens*: a manual import is a three-station wizard, opening a
/// stalled transfer is by design a jump into its client (decision 30: resume in
/// place needs a downloadId-to-hash bridge no client has), and `Renew` opens
/// the Certificates tab, which owns renewal and its confirmation: the call
/// reaches Let's Encrypt, and a renewal fired from a row on Home is one
/// mis-tap from spending the account's rate limits.
Future<void> runDecision(
  BuildContext context,
  WidgetRef ref,
  DashboardDecision decision,
) async {
  switch (decision.kind) {
    case DecisionKind.pendingRequest:
      return;
    case DecisionKind.violation:
      // The violation's own page, where the owner answers it.
      return openDecision(context, ref, decision);
    case DecisionKind.stalledDownload:
      // A service's page reads its lens, so the client this transfer is on
      // is brought under the lens first: with two qBittorrent, "Open in
      // qBittorrent" on the seedbox's stall opened the one at home.
      final target = decision.actionTarget;
      await bringUnderLens(ref, target, decision.actionInstanceId);
      if (!context.mounted) return;
      context.go(ServiceRoutes.forService(target));
    case DecisionKind.importBlocked:
      // Where the wizard does not exist, the control said "Open in …" and
      // goes there. Otherwise: the Review of every blocked download on the
      // connection the records came off, one or eighteen, each read by the
      // client's id for it.
      if (!decision.service.supportsManualImport) {
        context.go(ServiceRoutes.forService(decision.service));
        return;
      }
      context.push(
        manualImportLocation(
          manualImportBlockedPath,
          decision.service,
          instanceId: decision.instanceId,
        ),
      );
    case DecisionKind.failedImport:
      context.push(
        manualImportLocation(
          manualImportBrowsePath,
          decision.service,
          targetId: decision.actionId,
          instanceId: decision.instanceId,
        ),
      );
    case DecisionKind.failingIndexer:
      // On the Prowlarr the indexer failed on: an indexer id is one
      // server's, and the lens's list would test another indexer, or none.
      final id = decision.actionId;
      if (id == null) return;
      final indexers = await ref.read(
        prowlarrIndexersForProvider(decision.instanceId).future,
      );
      final indexer = indexers.where((each) => each.id == id).firstOrNull;
      if (!context.mounted || indexer == null) return;
      await testIndexerFlow(
        context,
        ref,
        indexer,
        instanceId: decision.instanceId,
      );
    case DecisionKind.storageAlert:
      // The server's own page where the alert is (TrueNAS's dashboard,
      // Unraid's array or notifications), on the server that raised it:
      // the page reads the lens.
      await bringUnderLens(ref, decision.service, decision.instanceId);
      if (!context.mounted) return;
      context.go(decision.route ?? ServiceRoutes.truenasDashboard);
    case DecisionKind.serviceHealth:
      // The \*arr's own status page, in the browser: a health check is
      // fixed in the \*arr's settings, which this app does not carry.
      // At the address the connection is reached at now: away from home,
      // the one at home would not open.
      final base = ref.read(connectionReachProvider(decision.instanceId))?.url;
      final page = base == null ? null : Uri.tryParse(base);
      if (page == null) return;
      await ref
          .read(browserOpenerProvider)
          .open(
            page.replace(
              path: '${page.path.replaceAll(RegExp(r'/+$'), '')}/system/status',
            ),
          );
    case DecisionKind.connectionFault:
      // The remedy its cause names is in the connection's form; where asking
      // again is the remedy, the probe is asked again.
      final route = decision.route;
      if (decision.remedy != null && route != null) {
        await context.pushMounted(route);
        return;
      }
      ref.invalidate(
        instanceSummaryProvider((
          service: decision.service,
          instanceId: decision.instanceId,
        )),
      );
    case DecisionKind.expiringCertificate:
      // The Certificates tab, where Renew and its confirmation are, and where
      // an uploaded certificate is listed for replacing: the service's root
      // is its Overview, which offers no writes at all. It reads the lens, so
      // the certificate's own NPM is brought under it first.
      await bringUnderLens(
        ref,
        ServiceKey.nginxProxyManager,
        decision.instanceId,
      );
      if (!context.mounted) return;
      context.go(ServiceRoutes.npmCertificates);
  }
}

/// Brings connection [instanceId] of [service] under the lens, for a page that
/// reads the lens and takes no `?i=`.
///
/// Nothing for the lens itself, for an empty id, or for a connection since
/// removed. A Dockge connection opens on its hub: the agent the lens was
/// looking through belongs to the connection it leaves, and a decision read
/// off another connection was read off its hub.
Future<void> bringUnderLens(
  WidgetRef ref,
  ServiceKey service,
  String instanceId,
) async {
  if (instanceId.isEmpty ||
      instanceId == ref.read(activeInstanceProvider(service))?.id ||
      ref.read(currentSettingsProvider).instanceById(instanceId) == null) {
    return;
  }
  await ref.read(activeInstancesProvider.notifier).select(service, instanceId);
  if (service == ServiceKey.dockge) {
    ref
        .read(dockgeSelectedAgentProvider.notifier)
        .select(DockgeAgent.local.endpoint);
  }
}

/// A 38×54 plate carrying the source's glyph, for a decision with no artwork.
class _GlyphPlate extends StatelessWidget {
  const _GlyphPlate({required this.icon, required this.tone});

  final IconData icon;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: AppRadius.borderRadiusSm,
      ),
      child: Icon(icon, size: 18, color: tone),
    );
  }
}

/// The single trailing control on a decision row.
class _DecisionActionButton extends StatelessWidget {
  const _DecisionActionButton({
    required this.label,
    required this.onPressed,
    this.annotate,
    this.fill = false,
  });

  final String label;
  final VoidCallback onPressed;

  /// The fault's one amber fill, full width, rather than a quiet text button.
  final bool fill;

  /// The dim and hint of a cross-service gate, applied to the label inside
  /// the button. Null for a decision with no other service to reach.
  final Widget Function(Widget content)? annotate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (fill) {
      return SizedBox(
        width: double.infinity,
        child: FilledButton(
          onPressed: onPressed,
          style: remedyFillStyle(context),
          child: (annotate ?? (content) => content)(Text(label)),
        ),
      );
    }

    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        // Brand indigo, never the fault's amber: the cure must not be painted
        // as alarming as the disease.
        foregroundColor: colorScheme.primary,
        // No `visualDensity: compact` here, unlike the alert band's pair: the
        // density is applied *to* the minimum size, so compact turns a declared
        // 44 into a measured 40 and quietly drops the control under both
        // platforms' floors.
        minimumSize: const Size(56, 44),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      // The hint is annotated from INSIDE the button, not from a `Semantics`
      // wrapped around it. A button is a semantic boundary, so an annotation
      // above it either creates a second node the reader has to step through or
      // is dropped entirely; an annotation on its child merges into the button's
      // own node, which is where "requires qBittorrent" has to be heard.
      child: (annotate ?? (content) => content)(
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.weight(FontWeight.w600),
        ),
      ),
    );
  }
}

/// A request that waits: who asked and when, then Approve in ink and Decline
/// beside it, the two the same width under the words. Once answered here, the
/// row says what happened in their place.
///
/// Neither button takes a tone: a request is somebody waiting politely, and
/// declining one is not a fault.
class _RequestRow extends ConsumerWidget {
  const _RequestRow({
    required this.decision,
    required this.divided,
    required this.outcome,
    required this.request,
  });

  final DashboardDecision decision;
  final bool divided;
  final String? outcome;
  final SeerrRequest? request;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final asked = decision.occurredAt;
    final line =
        outcome ??
        joinDisplayParts([
          decision.detail,
          if (asked != null) askedAgo(asked, now: DateTime.now()),
        ]);

    Future<void> open() => openDecision(context, ref, decision);

    return DecoratedBox(
      key: ValueKey('decision-${decision.id}'),
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: room.hair)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              container: true,
              button: true,
              label: decision.title,
              value: spokenFromDotted(line),
              onTap: open,
              child: InkWell(
                onTap: open,
                excludeFromSemantics: true,
                child: ExcludeSemantics(
                  child: Row(
                    children: [
                      HomeRowArt(
                        posterUrl: decision.posterUrl,
                        icon: decision.service.icon,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              decision.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.row
                                  .weight(FontWeight.w600)
                                  .copyWith(color: room.ink),
                            ),
                            Text(
                              line,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: AppType.meta.copyWith(
                                color: room.inkSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (outcome == null && decision.actionId != null)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.sm,
                  left: HomeRowArt.width + AppSpacing.sm,
                ),
                child: RequestAnswerControls.row(
                  // The Seerr the request came off: the module reads every
                  // one, and a request id is per server.
                  instanceId: decision.instanceId,
                  requestId: decision.actionId!,
                  title: decision.title,
                  decision: decision,
                  request: request,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// When a request was made, as its row says it: `2 h ago`, `yesterday`, the
/// weekday within the week, then the date (`Tue 29 Sep`): [formatDayWords].
String askedAgo(DateTime at, {required DateTime now}) =>
    formatDayWords(at, now: now);

class _HeroContentCard extends StatelessWidget {
  final String? heroTag;
  final String imageUrl;

  const _HeroContentCard({required this.heroTag, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    final card = ContentCard(imageUrl: imageUrl, paneTag: heroTag);
    // Only fly a Hero when there is both a tag AND an image on this end. An
    // empty image would produce a blank/orphaned Hero whose destination has no
    // matching poster, which shows up as a fade instead of a shared-element
    // flight.
    if (heroTag == null || heroTag!.isEmpty || imageUrl.isEmpty) {
      return card;
    }

    return Hero(
      tag: heroTag!,
      transitionOnUserGestures: MediaPosterCard.flightOnUserGestures,
      child: card,
    );
  }
}
