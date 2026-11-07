import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/presentation/connection_in_view.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The lens: which connection this screen is looking through, and the way to
/// change it.
///
/// **It names the connection in view, not always the lens.** A visit to a
/// media server opened on one of its connections (a row on Home, a library
/// tile) reads that connection on every tab without moving the lens, and the
/// header says which: [ConnectionInView]. Choosing a connection in the sheet
/// puts it in view for the rest of the visit as well as moving the lens, as it
/// always did. Outside such a visit it is the lens, as before.
///
/// **Renders nothing at all while the service has one connection**, which is
/// the whole of the "you do not pay for the fold until you need it" rule. On
/// the overwhelmingly common install this widget is an empty box and the app
/// bar is the one that shipped before instances existed.
///
/// ## Why this is not the picker that was removed
///
/// The dashboard used to carry a chevron next to the title opening a list of
/// all nineteen services. The Portal replaced it and it was deleted, which is
/// what freed this spot. The two are not the same control and must not become
/// it: the Portal answers *where do I go*, this answers *which one of these am
/// I looking at*. The boundary is one rule: **this never lists another
/// service.** The day a row here points at Sonarr, the duplicate the Portal
/// just removed is back.
class InstanceLensBadge extends ConsumerWidget {
  const InstanceLensBadge({super.key, required this.service});

  final ServiceKey service;

  /// The pill's own tint of the accent.
  static const double _pillAlpha = 0.15;

  /// The connection the pill names: the one in view when the visit has one,
  /// else the lens.
  ServiceInstance? _shown(WidgetRef ref, ConnectionInView? view) {
    final inView = view?.instanceId ?? '';
    if (inView.isNotEmpty) {
      final instance = ref.watch(
        currentSettingsProvider.select((s) => s.instanceById(inView)),
      );
      if (instance != null) return instance;
    }
    return ref.watch(activeInstanceProvider(service));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(hasMultipleInstancesProvider(service))) {
      return const SizedBox.shrink();
    }
    final view = ConnectionInView.maybeOf(context, service);
    final active = _shown(ref, view);
    if (active == null) return const SizedBox.shrink();

    // The app's one rule for naming a connection: a connection the user never
    // named reads `Radarr 2`, never its id.
    final label = ref.watch(connectionNameProvider(active.id)) ?? service.title;
    // The label is the accent on its own tint, so it is walked against the
    // composite it lands on: the pill over the lit header band on a desktop
    // window, over the plain surface on a phone. Raw Radarr amber on its tint
    // is under 2:1 on paper.
    final ink = ServiceTheme.onTint(
      service.accent,
      surface: ServiceBandSurface.of(context),
      tintAlpha: _pillAlpha,
    );

    return Semantics(
      button: true,
      container: true,
      enabled: true,
      label: 'Lens: $label',
      hint: 'changes which ${service.title} this screen reads',
      onTap: () => _showLensSheet(context, ref, service, view),
      child: ExcludeSemantics(
        child: InkWell(
          onTap: () => _showLensSheet(context, ref, service, view),
          borderRadius: AppRadius.borderRadiusPill,
          child: ConstrainedBox(
            // The pill is 24pt so it sits inside a 22pt title without pushing the
            // bar around; the tap target is the full bar height regardless.
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
              child: Center(
                widthFactor: 1,
                child: Container(
                  height: 24,
                  padding: const EdgeInsets.only(left: 10, right: 6),
                  decoration: BoxDecoration(
                    color: service.accent.withValues(alpha: _pillAlpha),
                    borderRadius: AppRadius.borderRadiusPill,
                    border: Border.all(
                      color: service.accent.withValues(alpha: 0.40),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(label, style: AppTheme.chrome(context, color: ink)),
                      Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 14,
                        color: ink,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _showLensSheet(
  BuildContext context,
  WidgetRef ref,
  ServiceKey service,
  ConnectionInView? view,
) {
  // Configured only. The sheet is the one control that *persists* a lens, so a
  // row here for a connection with no address is an offer to point the whole
  // app at nothing, and `select` writes to disk, so the app would come back up
  // that way at the next cold start, showing a NotConfiguredPlaceholder with
  // the working connection two centimetres away in the same sheet.
  //
  // A Seerr account that signed out is not nothing: it has its address and a
  // way back, and its row says `Signed out`. Leaving it out would hide the
  // connection the lens may well be resting on.
  final instances = [
    for (final instance
        in ref.read(currentSettingsProvider).instancesOf(service))
      if (instance.isConfigured || instance.isSignedOut) instance,
  ];
  final lensId = ref.read(activeInstanceProvider(service))?.id;
  // The one ticked is the one the screen reads: the connection in view when
  // the visit has one, else the lens.
  final inView = view?.instanceId ?? '';
  final shownId = inView.isNotEmpty ? inView : lensId;

  return AppBottomSheet.show<void>(
    context: context,
    title: service.title,
    subtitle: instances.length == 2
        ? 'Two connections. Pick the one to read.'
        : '${instances.length} connections. Pick the one to read.',
    icon: service.icon,
    builder: (sheetContext) => _LensOptions(
      service: service,
      instances: instances,
      shownId: shownId,
      lensId: lensId,
      view: view,
    ),
  );
}

class _LensOptions extends ConsumerWidget {
  const _LensOptions({
    required this.service,
    required this.instances,
    required this.shownId,
    required this.lensId,
    required this.view,
  });

  final ServiceKey service;
  final List<ServiceInstance> instances;

  /// The connection the screen reads now: the ticked row.
  final String? shownId;

  /// The connection the lens rests on.
  final String? lensId;

  /// The visit the sheet was opened from, when there is one: it is told the
  /// choice, so the rest of the visit reads it.
  final ConnectionInView? view;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SettingsGroupCard(
      children: [
        for (final instance in instances) _row(context, ref, instance),
      ],
    );
  }

  Widget _row(BuildContext context, WidgetRef ref, ServiceInstance instance) {
    final colorScheme = Theme.of(context).colorScheme;
    // Whether this connection answers, before the user points the whole app
    // at it: the probe's own answer for this connection, in the connection
    // vocabulary. Moving the lens onto a server that did not answer used to
    // look exactly like moving it onto one that did. The same shape as a
    // Connections row: the glyph in its tone always, the cause in words ahead
    // of the address when there is one, and the word spoken either way.
    final reachability = _reachabilityOf(ref, instance);
    final tone = statusToneColor(
      colorScheme,
      reachability.tone,
      surface: colorScheme.surfaceContainer,
    );
    final host = service.extractHost(instance.url) ?? instance.url;
    // The label is the identity; the service name is already the sheet's
    // title and repeating it in every row says nothing.
    final title =
        ref.watch(connectionNameProvider(instance.id)) ?? service.title;
    return SettingsCard.grouped(
      leading: Icon(service.icon),
      title: title,
      // One sentence, the cause said once.
      semanticLabel: '$title, ${reachability.label}, $host',
      subtitleLeading: Icon(reachability.icon, size: 14, color: tone),
      subtitleLeadingLabel: reachability.label,
      subtitle: reachability.needsAttention
          ? joinDisplayParts([reachability.label, host])
          : host,
      subtitleColor: reachability.needsAttention ? tone : null,
      accentColor: service.accent,
      trailing: instance.id == shownId
          ? Icon(
              Icons.check_rounded,
              color: ServiceTheme.onTint(
                service.accent,
                surface: colorScheme.surfaceContainer,
                tintAlpha: 0,
              ),
            )
          : null,
      semanticHint: instance.id == shownId
          ? 'currently being read'
          : 'reads ${service.title} through this connection instead',
      onTap: () async {
        Navigator.of(context).pop();
        // The choice is the visit's first, then the lens's: a connection in
        // view that is not the lens is chosen again to make it the lens too.
        view?.show(instance.id);
        if (instance.id == lensId) return;
        await ref
            .read(activeInstancesProvider.notifier)
            .select(service, instance.id);
      },
    );
  }

  /// [instance]'s reachability, from the probe that already ran for it.
  ///
  /// Read, never asked again: `instanceSummaryProvider` is the one probe per
  /// connection the matrix and the band read too, so the sheet and the card
  /// beside it cannot disagree about the same server.
  ConnectionPresentation _reachabilityOf(
    WidgetRef ref,
    ServiceInstance instance,
  ) {
    final summary = ref.watch(
      instanceSummaryProvider((service: service, instanceId: instance.id)),
    );
    // The gateway too, so a connection behind one reads the same words as
    // the matrix cell beside it.
    return describeConnection(
      service,
      status: switch (summary) {
        // Saved without its key: not asked, and said as not set up.
        AsyncData(:final value) when value.isNotSetUp =>
          ServiceConnectionStatus.notConfigured,
        AsyncData(:final value) =>
          value.isOnline
              ? ServiceConnectionStatus.connected
              : ServiceConnectionStatus.disconnected,
        AsyncError() => ServiceConnectionStatus.disconnected,
        _ => ServiceConnectionStatus.checking,
      },
      reason: switch (summary) {
        AsyncData(:final value) => value.failureReason,
        AsyncError(:final error) => classifyConnectionFailure(error),
        _ => null,
      },
      gateway: switch (summary) {
        AsyncData(:final value) => value.failure?.gateway,
        AsyncError(:final error) => accessGatewayOf(error),
        _ => null,
      },
    );
  }
}
