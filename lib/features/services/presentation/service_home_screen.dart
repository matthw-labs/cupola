import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/utils/side_pane_route.dart';
import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/route_utils.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/glass_app_bar.dart';
import 'package:cupola/core/widgets/service_mark_tile.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_room_light.dart';
import 'package:cupola/features/services/presentation/widgets/instance_lens_badge.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The band every service screen lives under: the back plate, the service's
/// identity (its mark in a tile and its name), and one trailing action.
///
/// The dot + title used to be a button opening a dropdown picker of all
/// nineteen services (the dashboard's own switcher). The Portal made it a
/// second, worse copy of the same instrument (drag the nav bar up from
/// anywhere, land on the real matrix), so the picker is gone and the title
/// went back to being what it looks like: the name of the room you are in.
/// Screen-reader users switch through the accessible path that always
/// existed (Services tab → matrix) since the Portal's drag is gesture-only.
class ServiceHomeScreen extends StatelessWidget {
  final ServiceKey service;
  final Widget child;
  final Widget? trailingAction;

  /// Whether to draw the band at all.
  ///
  /// The band is drawn above every branch navigator, so unlike the tab bar
  /// (which a pushed page simply covers), it cannot be hidden by the page that
  /// wants it gone, and has to be told. A pushed detail brings its own back
  /// control, floated top left, and two chevrons in one corner is what this
  /// answers.
  ///
  /// Defaults to true so the fourteen screens that host this band directly,
  /// with no tabs under them, are untouched.
  final bool showAppBar;

  const ServiceHomeScreen({
    super.key,
    required this.service,
    required this.child,
    this.trailingAction,
    this.showAppBar = true,
  });

  /// [showAppBar], or a tab's root on screen beside a tablet's pane: the
  /// title is pushed under the tab as on a phone, but drawn beside it, so the
  /// root it was opened from keeps its band.
  bool _bandShown(BuildContext context) {
    if (showAppBar) return true;
    final beside = SidePaneScope.hostNameOf(context);
    return beside != null && isServiceTabRoot(service, beside);
  }

  /// The room the band occupies measured from the very top of the screen,
  /// the top inset included.
  ///
  /// **The band is the one that consumes the inset.** It is `Positioned(top: 0)`
  /// under a `SafeArea`, so on a phone with a notch or a cutout it is a status
  /// bar taller than [kToolbarHeight]. Anything floated underneath it (the
  /// service tab bar) has to start at this, not at [kToolbarHeight], or it is
  /// laid out an inset too high and the band is drawn straight over it. The
  /// default test surface has no inset, which is exactly why that overlap can
  /// be invisible for as long as nobody pumps one.
  static double bandHeightOf(BuildContext context) =>
      kToolbarHeight + MediaQuery.paddingOf(context).top;

  /// Whether this service's screens are drawn under the band at all.
  ///
  /// Not in the desktop shell, for a service on the tab model. The window
  /// chrome already names the room (its breadcrumb is the URL), and the deck
  /// carries the fleet, so a band holding back, name and one action was the
  /// phone's app bar drawn inside a shell that had said all of it: 222pt of
  /// chrome over a 900pt window, 45% of a 720×450 one. The tab row becomes the
  /// header instead ([ServiceTabBar.header]). TrueNAS has no tab row, so it
  /// keeps its band everywhere; a desktop window narrowed into the phone layout
  /// gets the band back with it.
  static bool drawsBand(BuildContext context, ServiceKey service) =>
      !AppBreakpoints.isDesktopShell(context) || tabsFor(service) == null;

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        // Every tab of the service is one room, lit by what leads it: the
        // tabs take this light ([RoomLightScope]), and the band and the tab
        // bar, which float over them, frost this same room.
        final light = ref.watch(serviceRoomLightProvider(service));
        return RoomLightScope(
          accent: light?.light,
          art: light?.art,
          child: AmbientBackground(
            accent: light?.light,
            art: light?.art,
            accentDuration: AppAnimation.light,
            child: _framed(context),
          ),
        );
      },
    );
  }

  Widget _framed(BuildContext context) {
    if (!_bandShown(context) || !drawsBand(context, service)) return child;

    // The room fills the screen, and the band spans it, whatever the page
    // under it measures.
    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          // Glass band instead of an opaque surface strip, so the hosted
          // screen's ambient gradient reads continuously behind the app bar
          // and scrolling content frosts underneath. Whole to its edge when
          // the tab row's glass carries on under it.
          child: tabsFor(service) == null
              ? GlassSurface(child: _band())
              : GlassSurface.continued(child: _band()),
        ),
      ],
    );
  }

  Widget _band() => SafeArea(
    bottom: false,
    child: _ServiceDashboardAppBar(
      service: service,
      trailingAction: trailingAction,
    ),
  );
}

class _ServiceDashboardAppBar extends ConsumerWidget {
  final ServiceKey service;
  final Widget? trailingAction;

  const _ServiceDashboardAppBar({required this.service, this.trailingAction});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);

    // The room's identity, as a service room heads itself: the back plate,
    // the service's mark in its tile and its name in the room's face. The
    // band keeps the phone's toolbar height, so every hosted screen keeps the
    // room it reserves under it.
    return SizedBox(
      height: kToolbarHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        child: Row(
          children: [
            Tooltip(
              message: 'Back to Stack',
              child: MediaPlate(
                label: 'Back to Stack',
                icon: Icons.chevron_left_rounded,
                iconSize: 26,
                // Back to Stack, as it says, when there is no page to pop:
                // the service's own location was this very page, so the
                // button did nothing on a service opened with nothing
                // beneath it.
                onTap: () => RouteUtils.popOrGo(context, ServiceRoutes.stack),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            ServiceMarkTile(icon: service.icon, size: 36),
            const SizedBox(width: AppSpacing.sm),
            // Flexible, and the badge beside it is not: when the bar runs
            // out of room the *service name* is what gives way. Which service
            // you are in you already know: you navigated here. Which
            // connection you are reading is the part that has to stay legible,
            // and it is the shorter string anyway. The name and badge share
            // one Expanded, so the name is the only flexible child of its own
            // row, and the trailing action sits on the gutter.
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      service.title,
                      key: ValueKey('service-home-title-${service.routeParam}'),
                      style: AppType.feature.copyWith(color: room.ink),
                      textScaler: TextScaleMetrics.clampedScalerOf(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                  InstanceLensBadge(service: service),
                ],
              ),
            ),
            if (trailingAction != null)
              trailingAction!
            else
              IconButton(
                // The secondary ink, like every glyph on the band: the band is
                // monochrome, the service is named beside it.
                icon: Icon(
                  Symbols.vital_signs_rounded,
                  color: room.inkSecondary,
                ),
                onPressed: () => context.go('/activity'),
                tooltip: 'Activity',
              ),
          ],
        ),
      ),
    );
  }
}
