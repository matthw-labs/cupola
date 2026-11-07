import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/features/media/presentation/media_split.dart';
import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_identity.dart';
import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/utils/a11y_announce.dart';
import 'package:cupola/core/widgets/front_room.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/floating_nav_rail.dart';
import 'package:cupola/features/release_search/presentation/release_search_lifecycle.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/portal_hints.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';
import 'package:cupola/features/shell/domain/shell_branches.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';
import 'package:cupola/features/shell/presentation/activity_badge.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_shell.dart';
import 'package:cupola/features/shell/presentation/desktop/window_chrome.dart';
import 'package:cupola/features/shell/presentation/portal_announcement.dart';
import 'package:cupola/features/shell/presentation/portal_coach_mark.dart';
import 'package:cupola/features/shell/presentation/service_portal.dart';

/// Main shell screen with floating bottom navigation.
///
/// Uses a custom [FloatingBottomNavBar] with rounded corners and floating design.
/// Outlined icons for unselected state and filled icons for selected state.
class ShellScreen extends ConsumerStatefulWidget {
  /// The four branch navigators, and the tab index that says which one shows.
  ///
  /// Carries a `GlobalKey` of its own, so crossing the rail breakpoint
  /// re-parents it instead of rebuilding it: every branch's stack survives a
  /// resize, which the single-navigator shell could not offer.
  final StatefulNavigationShell navigationShell;

  const ShellScreen({super.key, required this.navigationShell});

  /// The tab bar's accessibility action that opens the Portal. Worded as the
  /// coach mark words the gesture: *Swipe up to open the Portal*.
  static const openPortalAction = CustomSemanticsAction(
    label: 'Open the Portal',
  );

  /// Width at or above which a *touch* shell moves its navigation from the
  /// bottom bar to a side rail. See [AppBreakpoints.touchRail] for the number
  /// and the reasoning.
  ///
  /// A desktop window never reaches it: at [AppBreakpoints.desktopMobile] and
  /// above it gets the window shell, and below that it is narrower than any
  /// rail threshold, so it always gets the bottom bar.

  @override
  ConsumerState<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends ConsumerState<ShellScreen>
    with TickerProviderStateMixin {
  /// One Portal per shell: the machine behind the bar's upward drag.
  ///
  /// Created eagerly in [initState]: as a `late final` initializer its first
  /// access could be [dispose] (rail layout never touches it in build), and
  /// creating a ticker during unmount trips the deactivated-ancestor assert.
  late final ServicePortalController _portal;

  /// The light of the room in front, which the bar and the rail take a sheen
  /// of (`FrontRoomLight`).
  final _frontRoom = FrontRoomLight();

  String? _lastLocation;

  /// The lens map as it was the last time this built.
  ///
  /// Held by identity rather than by value: [ActiveInstancesNotifier] hands out
  /// a fresh `Map` on every `select`, and never otherwise, so `identical` is
  /// exactly the question "did somebody move a lens since the last frame", and
  /// it costs no comparison of nineteen entries to ask it.
  Map<ServiceKey, String>? _lastLenses;
  Timer? _demoTimer;

  @override
  void initState() {
    super.initState();
    _portal = ServicePortalController(vsync: this);
    _portal.onOpened = _onPortalOpened;
    _portal.covering.addListener(_reportBackOwnership);
    WidgetsBinding.instance.addPostFrameCallback((_) => _armDemoBounce());
  }

  /// The Portal has committed to opening, by a finger or by the tab bar's
  /// action.
  void _onPortalOpened() {
    // Using the Portal is the proof the coach mark is no longer needed.
    ref.read(portalHintsProvider.notifier).notePortalUsed();
    // One sentence, once, for whoever cannot see the floor arrive. At the
    // commit rather than when the spring settles: the reader should hear what
    // opened while it opens, and a settle can be cut short by a close.
    announce(
      context,
      portalOpenedAnnouncement(ref.read(portalFloorCensusProvider)),
    );
  }

  /// Back, while the Portal is up, means "put the page back", never "leave
  /// the page".
  ///
  /// A listener on the router's back dispatcher rather than a `PopScope`, and
  /// the difference is the whole fix. go_router offers a back to the deepest
  /// navigator first, so with a room pushed on the Dashboard branch the branch
  /// pops the room *under* the card before anything the shell owns is asked; a
  /// `PopScope` here sits on the shell's own route, which is consulted last.
  /// The dispatcher is asked before any navigator is.
  ///
  /// Asked of [ServicePortalController.isOpenOrEngaged], the same question a
  /// tab tap asks before it closes the Portal, so the two cannot disagree about
  /// whether there is anything to close.
  Future<bool> _handleSystemBack() async {
    if (!_portal.isOpenOrEngaged) return false;
    _portal.closeFromUi();
    return true;
  }

  /// Tells Android whether the app wants the next back gesture.
  ///
  /// With predictive back the system only hands a back to the app when the
  /// framework has said it can use one, and the navigators say so only when
  /// they have a route to pop. On a branch root that is never, so without this
  /// a back over an open Portal would leave the app instead of closing it.
  ///
  /// Dispatched by hand, in the navigators' own currency, because a `PopScope`
  /// on the shell's route would report *its* answer on the way back down too
  /// ("nothing to pop") over a branch that still has a room pushed, and back
  /// would then leave the app from the room. On close this restores exactly
  /// what the navigators would say. A no-op on every other platform.
  void _reportBackOwnership() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      NavigationNotification(
        canHandlePop: _portal.covering.value || GoRouter.of(context).canPop(),
      ).dispatch(context);
    });
  }

  /// Whether this window draws the Portal: the phone layout, bottom bar and
  /// all, the branch [build] reaches after the desktop shell and the rail.
  ///
  /// Both halves, because each alone is wrong somewhere: a desktop window
  /// between the compact artboard (720) and the rail (840) is narrower than
  /// the rail and still draws the desktop shell, which has no bar to lift.
  static bool _portalDrawn(BuildContext context) =>
      !AppBreakpoints.isDesktopShell(context) &&
      MediaQuery.sizeOf(context).width < AppBreakpoints.touchRail;

  /// Whether the one-shot demo may play now, in this window.
  bool _demoCanPlay() =>
      mounted &&
      _portalDrawn(context) &&
      ref.read(shellAudienceProvider) == Audience.operator &&
      !MediaQuery.accessibleNavigationOf(context) &&
      !MediaQuery.disableAnimationsOf(context) &&
      ref.read(portalHintsProvider).demoBouncePending;

  /// The one-shot demo bounce (Settings → Hints re-arms it): only where the
  /// Portal is drawn, never under a screen reader or Reduce Motion, and only
  /// while the Portal is idle. A cancellable timer, not a bare delay: the shell
  /// may be torn down first.
  ///
  /// It is marked seen only when it plays. It used to be marked on the timer
  /// whatever the window was, so a desktop window between 720 and 839 spent the
  /// one demo on a bar it does not draw, and the lesson never came back.
  void _armDemoBounce() {
    if (!_demoCanPlay()) return;
    // A breath after the first frame: the bounce has to read as a gesture of
    // the bar, not as a startup glitch.
    _demoTimer = Timer(const Duration(milliseconds: 700), () {
      // Asked again: the window may have been resized in the breath, and a
      // finger may already be on the bar. Either way the demo stays owed.
      if (!_demoCanPlay() || !_portal.isIdle) return;
      ref.read(portalHintsProvider.notifier).markDemoShown();
      _portal.playDemoBounce();
    });
  }

  @override
  void dispose() {
    _demoTimer?.cancel();
    _portal.covering.removeListener(_reportBackOwnership);
    _portal.dispose();
    _frontRoom.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Straight off the shell, which is the authority: with four stacks the
    // location and the visible branch can disagree: an imperative push from
    // another tab lands on this branch while the path reads like somebody
    // else's, and it is the branch that the bar must agree with.
    //
    // The branch is a [NavTab]; the bar shows the tabs of the person the shell
    // is drawn for ([NavTab.barFor]), so the bar's selection is where that
    // tab sits in it: none, in Settings, which has no place in the bar.
    final currentTab = NavTab.values[widget.navigationShell.currentIndex];
    final audience = ref.watch(shellAudienceProvider);
    final barTabs = NavTab.barFor(audience);
    final selectedIndex = barTabs.indexOf(currentTab);
    final useRail =
        MediaQuery.sizeOf(context).width >= AppBreakpoints.touchRail;
    // The Portal's drag is unusable under a screen reader; there the bar keeps
    // its pure elastic and switching stays on the accessible paths.
    final accessibleNav = MediaQuery.accessibleNavigationOf(context);
    // The Portal is the floor of the services, and the requester's app has
    // none: her bar has no Stack, and every room sends her Home. No drag, no
    // coach mark, no demo bounce.
    final portalOn = !accessibleNav && audience == Audience.operator;

    // Any change to what sits under the card closes an open Portal and drops
    // the stale snapshot. Post-frame: starting animations inside build is not
    // allowed.
    //
    // TWO inputs, not one, and the second is the whole of this hook's
    // multi-instance story. The path is the obvious one. The other is the
    // LENS: a picker cell travelling from Radarr · 4K to Radarr · HD calls
    // `go('/dashboard/radarr')` both times, so `uri.path` is byte-identical
    // across a travel that changes every pixel under the card. Watched here
    // rather than solved at the cell, because this is already the one place
    // that decides the Portal closes because its content moved, and the badge
    // sheet can move a lens too.
    //
    // The path comparison stays on the FULL path; never weaken it to the
    // service's routeParam. A hook keyed on the service alone would hold the
    // Portal open across `/dashboard/radarr` → `/dashboard/radarr/movie/12`.
    //
    // And this hook is only half the story: it is REACTIVE, and closing on an
    // ACTION lives elsewhere. A picker cell closes the Portal itself, through
    // `PortalDismissScope`, because a tap that navigates to the path it is
    // already on without moving the lens moves neither of the two inputs below
    // and is invisible from here. Do not answer that case by widening these
    // conditions. The question this hook asks ("has the content under the card
    // moved, so is the snapshot dead?") is a different one, and it is right.
    final location = GoRouterState.of(context).uri.path;
    final lenses = ref.watch(activeInstancesProvider);
    final pathMoved = _lastLocation != null && _lastLocation != location;
    final lensMoved = _lastLenses != null && !identical(_lastLenses, lenses);
    _lastLenses = lenses;
    if (pathMoved || lensMoved) {
      if (_portal.isOpenOrEngaged) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _portal.handleRouteChanged();
        });
      } else if (pathMoved &&
          // Only where a Portal is drawn: on a rail or in the window shell
          // there is no Portal to have gone through, so a manual switch there
          // is no evidence of need for one, and the count outlives the window
          // (it is persisted) to coach a phone that never saw it.
          _portalDrawn(context) &&
          // Spelled out rather than left to the arithmetic: a lens moving with
          // the path unchanged cannot satisfy the two tests below, but the
          // journey being counted is a *journey*, and it should say so.
          _lastLocation == NavTab.stack.routePath &&
          location.startsWith('${NavTab.stack.routePath}/')) {
        // Stack → service without going through the Portal: exactly the
        // journey the Portal replaces. The coach mark counts these.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(portalHintsProvider.notifier).noteManualJourney();
          }
        });
      }
    }
    _lastLocation = location;

    // Built once, above the layout branch, and handed to whichever navigation
    // this window is wide enough for. The rail used to build its own bare
    // `NavigationRailDestination`s, which is how it ended up as the one surface
    // where a finished search never showed a badge: the channel that has to
    // keep working when notifications are denied, off, or missed.
    // On the page it counts, the number goes: the page says it larger.
    final activity = currentTab == NavTab.activity
        ? null
        : ref.watch(activityBadgeProvider);
    final destinations = barTabs
        .map((tab) => _destinationFor(tab, activity))
        .toList(growable: false);
    void select(int barIndex) =>
        _onItemTapped(barTabs[barIndex], context, currentTab);

    // Outside the branch, so it wraps *both* layouts and survives a resize.
    // Inside the phone branch it was two bugs at once: on macOS and tablet
    // nothing ever observed the app lifecycle: `appInForegroundProvider` stayed
    // permanently true, `noteBackgrounded()` never fired (so a search the OS
    // killed was blamed on the network instead of on leaving the app) and
    // `refreshWindows()` never ran on resume, and dragging a window across
    // 840pt mounted or unmounted the observer mid-session.
    // The window shell, whole, above the touch branches. It is not a third
    // layout of the same shell: it has a chrome strip, a deck and an inspector
    // that no touch build has, and it reaches the branch navigator unmodified;
    // so every screen inside it is still the same screen the phone shows.
    if (AppBreakpoints.isDesktopShell(context)) {
      return ReleaseSearchLifecycle(
        child: DesktopShell(
          navigationShell: widget.navigationShell,
          currentTab: currentTab,
          destinations: destinations,
          selectedIndex: selectedIndex,
          onDestinationSelected: select,
          onSettings: () => _onItemTapped(NavTab.settings, context, currentTab),
        ),
      );
    }

    final Widget touchShell = useRail
        ? Scaffold(
            // The room's own light under the rail, so the strip it floats in
            // continues the page beside it instead of framing it: the page's
            // glow is centred near this same corner, and the two meet at the
            // page's edge within a shade.
            body: AmbientBackground(
              child: Row(
                children: [
                  // SafeArea on the rail side only: on a tablet held on its
                  // side the camera housing and the rounded corner sit on the
                  // leading edge, and the rail was laid out underneath them.
                  // The content keeps its own insets. Only tablets reach this
                  // branch on touch: the phone is portrait-only and never
                  // 840pt wide, but tablets still rotate, so the inset is
                  // real.
                  SafeArea(
                    right: false,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FloatingNavRail.margin,
                      ),
                      // The phone's bar on its side, floating at the middle of
                      // the edge where a thumb holding the tablet reaches it.
                      child: Align(
                        widthFactor: 1,
                        child: FloatingNavRail(
                          selectedIndex: selectedIndex,
                          destinations: destinations,
                          onDestinationSelected: select,
                        ),
                      ),
                    ),
                  ),
                  // A title opened here is drawn beside the page it came
                  // from once the window is wide enough.
                  Expanded(
                    child: MediaSplitLayout(
                      location: GoRouterState.of(context).uri,
                      child: widget.navigationShell,
                    ),
                  ),
                ],
              ),
            ),
          )
        // The phone layout is the only one the Portal exists in, so it is the
        // only one whose back and escape it may claim.
        : BackButtonListener(
            onBackButtonPressed: _handleSystemBack,
            child: Shortcuts(
              // Escape on a keyboard is the desktop window's back, and a
              // desktop window narrower than the compact artboard gets this
              // layout and its Portal. The shell's own intent rather than
              // `DismissIntent`, for the reason `CloseOverlayIntent` gives.
              shortcuts: const <ShortcutActivator, Intent>{
                SingleActivator(LogicalKeyboardKey.escape):
                    CloseOverlayIntent(),
              },
              child: Actions(
                actions: <Type, Action<Intent>>{
                  CloseOverlayIntent: _ClosePortalAction(_portal),
                },
                child: Scaffold(
                  extendBody: true,
                  body:
                      // The Portal is a cover the route system cannot see: it
                      // freezes the page's pixels while leaving its timers
                      // running. Scoping the stage tells whatever polls under
                      // there to stop; see `PageCoverageScope`.
                      PageCoverageScope(
                        covering: _portal.covering,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            PortalStage(
                              controller: _portal,
                              child: widget.navigationShell,
                            ),
                            if (portalOn) PortalCoachMark(controller: _portal),
                          ],
                        ),
                      ),
                  bottomNavigationBar: FloatingBottomNavBar(
                    selectedIndex: selectedIndex,
                    onDestinationSelected: select,
                    destinations: [
                      for (final (index, destination) in destinations.indexed)
                        barTabs[index] == NavTab.stack
                            ? _withPortalAction(destination)
                            : destination,
                    ],
                    verticalDragDelegate: portalOn ? _portal : null,
                  ),
                ),
              ),
            ),
          );

    // A desktop window dragged under the compact artboard paints the phone
    // layout, but it is still a frameless window: something has to carry the
    // traffic-light gutter, the caption buttons and the drag region, or on
    // Windows and Linux it can neither be moved nor closed. The drag strip is
    // that something, and renders nothing on a phone.
    if (!AppBreakpoints.isDesktopPlatform) {
      return ReleaseSearchLifecycle(
        child: FrontRoomScope(light: _frontRoom, child: touchShell),
      );
    }
    return ReleaseSearchLifecycle(
      child: Material(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Column(
          children: [
            const WindowDragStrip(trail: [kAppName]),
            Expanded(
              child: FrontRoomScope(light: _frontRoom, child: touchShell),
            ),
          ],
        ),
      ),
    );
  }

  void _onItemTapped(NavTab tab, BuildContext context, NavTab currentTab) {
    HapticFeedback.selectionClick();

    // A tab tap with the Portal open always closes it; landing on the tab is
    // the rest of the answer. A re-tap on the current tab then stops there:
    // "take me back where I was" must not also fire a refresh.
    final portalWasOpen = _portal.isOpenOrEngaged;
    if (portalWasOpen) _portal.closeFromUi();

    final index = tab.index;

    if (tab == currentTab) {
      if (portalWasOpen) return;

      // "Am I deep in this tab?" asked of the branch's own Navigator rather
      // than by comparing the location to the tab's root path. The comparison
      // was right while one stack meant the location and the visible page could
      // not disagree; with four of them they can, and whether this branch has
      // something to pop is the structural question anyway.
      if (branchNavigatorKeyFor(tab).currentState?.canPop() ?? false) {
        // Take me back where I started. `initialLocation: true` navigates the
        // branch to its root, which pops it and nothing else: a return journey
        // must not also fire a fetch.
        widget.navigationShell.goBranch(index, initialLocation: true);
        return;
      }

      // At the root and scrolled down: back to the top first, as a tap on
      // the status bar does. Only a page already at its top reads again.
      if (_scrollToTop(tab)) return;

      final section = _refreshSectionFor(tab);
      if (section != null) {
        ref.triggerNavigationRefresh(section);
        // A re-tap refresh changes nothing on screen: no spinner, no route
        // change, no focus move, so for a screen-reader user it is otherwise
        // indistinguishable from a no-op. Start only: the shell never learns
        // when the invalidated providers settle, so there is no completion to
        // announce.
        announce(context, 'Refreshing ${tab.label}');
      }
      return;
    }

    // Not announced: switching tabs replaces the whole screen, which is its own
    // feedback. `goBranch`, not `go`: it restores the branch's own stack, which
    // is the entire point of the four navigators.
    widget.navigationShell.goBranch(index);
  }

  /// Scrolls the page on top of [tab] back to its top, and says whether it
  /// had scrolled away from it.
  ///
  /// The page's list is its route's primary scroll view: every vertical list
  /// on a phone adopts the route's `PrimaryScrollController` unless it brings
  /// a controller of its own, which is how the status bar's tap finds it too.
  /// So no page listens for the tap, and none can forget to.
  bool _scrollToTop(NavTab tab) {
    final route = branchTopRouteFor(tab).top;
    final page = route is ModalRoute ? route.subtreeContext : null;
    if (page == null || !page.mounted) return false;
    final controller = PrimaryScrollController.maybeOf(page);
    if (controller == null || !controller.hasClients) return false;
    final away = [
      for (final position in controller.positions)
        if (position.pixels > position.minScrollExtent) position,
    ];
    if (away.isEmpty) return false;
    final still = MediaQuery.disableAnimationsOf(page);
    for (final position in away) {
      if (still) {
        position.jumpTo(position.minScrollExtent);
      } else {
        position.animateTo(
          position.minScrollExtent,
          duration: AppAnimation.durationMd,
          curve: AppAnimation.standardCurve,
        );
      }
    }
    return true;
  }

  /// The screen reader's way into the Portal: an action on the Stack tab.
  ///
  /// A reader cannot perform the drag, so the bar offers the same way in as a
  /// custom action: *Actions available: Open the Portal*. On the Stack tab
  /// because that is where the services are: every room is inside it, so it is
  /// also the tab that is selected whenever a service is on screen. Offered in
  /// every mode the phone bar is in, not only under a screen reader: Voice
  /// Control and Switch Access list custom actions too, and cannot drag either.
  FloatingNavDestination _withPortalAction(FloatingNavDestination destination) {
    return FloatingNavDestination(
      icon: destination.icon,
      selectedIcon: destination.selectedIcon,
      railIcon: destination.railIcon,
      label: destination.label,
      badgeCount: destination.badgeCount,
      badgeTone: destination.badgeTone,
      badgeFloor: destination.badgeFloor,
      badgeSemanticLabel: destination.badgeSemanticLabel,
      customSemanticsActions: {
        ShellScreen.openPortalAction: _portal.openFromUi,
      },
    );
  }

  FloatingNavDestination _destinationFor(NavTab tab, ActivityBadge? activity) {
    // Only Activity carries a number (`activityBadgeProvider`): amber for what
    // needs the person, blue for answers and finished searches waiting. The
    // finished searches are the channel that has to keep working when
    // notifications are denied, off, or missed.
    final badge = tab == NavTab.activity ? activity : null;
    return FloatingNavDestination(
      icon: tab.icon,
      selectedIcon: tab.selectedIcon,
      railIcon: tab.railIcon,
      label: tab.label,
      badgeCount: badge?.count ?? 0,
      badgeTone: badge?.tone,
      badgeFloor: badge?.floor ?? false,
      badgeSemanticLabel: badge?.spoken,
    );
  }

  NavigationSection? _refreshSectionFor(NavTab tab) => tab.refreshSection;
}

/// Escape while the Portal is up. Disabled otherwise, so the key goes on to
/// clear a field or close a dialog exactly as it did before: a disabled action
/// is skipped by the dispatcher instead of swallowing the key.
///
/// Reads the controller at key time rather than a flag captured at build: the
/// Portal opens and closes without rebuilding the shell.
class _ClosePortalAction extends Action<CloseOverlayIntent> {
  _ClosePortalAction(this.portal);

  final ServicePortalController portal;

  @override
  bool get isActionEnabled => portal.isOpenOrEngaged;

  @override
  void invoke(CloseOverlayIntent intent) => portal.closeFromUi();
}
