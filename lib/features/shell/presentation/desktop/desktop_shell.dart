import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/core/providers/navigation_refresh_provider.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/features/activity/data/selected_download.dart';
import 'package:cupola/features/settings/data/connection_test_command.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/nav_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/shell/domain/command_deck_entry.dart';
import 'package:cupola/features/shell/domain/inspector_state.dart';
import 'package:cupola/features/shell/domain/screen_search.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';
import 'package:cupola/features/shell/domain/window_history.dart';
import 'package:cupola/features/shell/presentation/desktop/command_deck.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_nav_rail.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_downloads_poll.dart';
import 'package:cupola/features/shell/presentation/desktop/desktop_rail_services.dart';
import 'package:cupola/features/shell/presentation/desktop/in_flight_glance.dart';
import 'package:cupola/features/shell/presentation/desktop/inspector_pane.dart';
import 'package:cupola/features/shell/presentation/desktop/shortcuts_sheet.dart';
import 'package:cupola/core/platform/desktop_window.dart';
import 'package:cupola/features/shell/presentation/desktop/window_chrome.dart';

/// The window: chrome, sidebar, content, inspector.
///
/// The whole of the desktop layer's structure, and the only place that knows
/// the assembly. One strip across the top says which page this is and holds
/// the way to anything; the sidebar says which section and which room; the
/// page says the rest.
///
/// The content itself is the *unmodified* branch navigator. Nothing here wraps
/// pages in a desktop-only container, because every screen also has to be a
/// phone screen; the desktop layouts live in the screens' own shared widgets,
/// where both form factors can see them.
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({
    super.key,
    required this.navigationShell,
    required this.currentTab,
    required this.destinations,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.onSettings,
  });

  final Widget navigationShell;

  /// The branch on screen, Settings included, which [selectedIndex] cannot
  /// say: it is no tab of the bar.
  final NavTab currentTab;

  /// The person's bar, and where [currentTab] sits in it (-1 for none).
  final List<FloatingNavDestination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final VoidCallback onSettings;

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell>
    with SingleTickerProviderStateMixin {
  /// Created eagerly in [initState], not as a `late final` initialiser: on a
  /// shell that is torn down before the deck is ever opened, the *first* access
  /// would be the one in [dispose], and creating a ticker during unmount trips
  /// the deactivated-ancestor assert. The Portal on the phone side carries the
  /// same note for the same reason.
  late final AnimationController _deck;
  bool _deckOpen = false;
  String? _lastLocation;

  @override
  void initState() {
    super.initState();
    _deck = AnimationController(vsync: this, duration: AppAnimation.durationSm);
  }

  @override
  void dispose() {
    _deck.dispose();
    super.dispose();
  }

  void _openDeck() {
    if (_deckOpen) {
      _closeDeck();
      return;
    }
    setState(() => _deckOpen = true);
    _deck.forward();
  }

  void _closeDeck() {
    if (!_deckOpen) return;
    _deck.reverse().whenComplete(() {
      if (mounted) setState(() => _deckOpen = false);
    });
  }

  /// `⌘⌥→`: the next configured service, wrapping, skipping what is not set up.
  void _cycleService(int delta) {
    final settings = ref.read(currentSettingsProvider);
    final configured = ServiceKey.values
        .where(settings.isServiceConfigured)
        .toList(growable: false);
    if (configured.isEmpty) return;

    final location = GoRouterState.of(context).uri.path;
    final segments = Uri.parse(location).pathSegments;
    final current = segments.length > 1
        ? configured.indexWhere((s) => s.routeParam == segments[1])
        : -1;
    // From anywhere that is not a service, the gesture means "the first one":
    // forwards from the start, backwards from the end.
    final next = current < 0
        ? (delta > 0 ? 0 : configured.length - 1)
        : (current + delta) % configured.length;
    GoRouter.of(
      context,
    ).go('${NavTab.stack.routePath}/${configured[next].routeParam}');
  }

  /// `⌘R`: ask again, whatever "again" means on the tab you are standing on.
  ///
  /// Settings used to map to `null` here, which made the shortcut a deliberate
  /// no-op on a quarter of the app, and stayed a no-op after Settings grew a
  /// real "Test all" command, so the strip's own Refresh-all chip advertised a
  /// shortcut that did nothing on the pane where the user most wants it. The two
  /// are one sentence, *ask every server again*, so they spend the same
  /// command, defined once in `connection_test_command.dart`; re-implementing it
  /// here is how the button and the shortcut would start disagreeing about what
  /// "every" covers.
  ///
  /// The announcement comes with it. The work is invisible on a pane of
  /// nineteen rows: the ones that re-enter their checking state are usually
  /// off screen, and a command whose only feedback is below the fold is a
  /// command people press twice.
  void _refreshAll() {
    final section = widget.currentTab.refreshSection;
    if (section != null) {
      ref.triggerNavigationRefresh(section);
    } else {
      final message = testAllConnectionsAnnouncement(testAllConnections(ref));
      SnackBarHelper.info(context, message);
    }
  }

  /// `⌘[`, the toolbar's back arrow, a mouse's back button: one step back
  /// through where this window has been.
  void _goBack() {
    final target = ref.read(windowHistoryProvider.notifier).back();
    if (target != null) GoRouter.of(context).go(target);
  }

  void _goForward() {
    final target = ref.read(windowHistoryProvider.notifier).forward();
    if (target != null) GoRouter.of(context).go(target);
  }

  /// The mouse's own back and forward buttons, wherever the pointer is.
  void _onPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) return;
    if (event.buttons & kBackMouseButton != 0) _goBack();
    if (event.buttons & kForwardMouseButton != 0) _goForward();
  }

  void _searchThisScreen() {
    final node = ref.read(screenSearchFocusProvider);
    // No field on this screen means the shortcut does nothing, deliberately.
    // Sending the user somewhere else would be a navigation they did not ask
    // for, triggered by a key they pressed for a field they were looking at.
    node?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // A narrow window folds the sidebar and closes the inspector, whatever
    // the person chose; a wide one folds the sidebar only if they did.
    final narrow = AppBreakpoints.isCompactDesktop(context);
    final compact = narrow || ref.watch(sidebarFoldedProvider);
    final chromeHeight = WindowChrome.heightFor(compact: narrow);
    final inspector = ref.watch(inspectorStateProvider);
    // The requester's window: her sections, no services, no inspector, whose
    // activity is the operator's, and no command deck, which reaches every
    // room and connection by name.
    final requester = ref.watch(shellAudienceProvider) == Audience.requester;
    // What the chrome draws from, read again on its own clock; a requester has
    // no downloads to draw.
    if (!requester) ref.watch(desktopDownloadsPollProvider);
    final railWidth = DesktopNavRail.widthFor(compact: compact);
    // A Mac's full sidebar runs the window's height, the traffic lights in
    // its head, and the toolbar starts at its edge. Folded, the sidebar is too
    // narrow for the lights: the toolbar spans the window again.
    final tallSidebar =
        DesktopWindow.style == WindowChromeStyle.macos && !compact;

    // Recents for the deck, recorded here because this is the one widget that
    // sees every location change in the window.
    final uri = GoRouterState.of(context).uri;
    final location = uri.path;
    final room = requester ? null : _roomOf(location);
    // The pane opens on a choice and on nothing else: with no download chosen
    // there is nothing for it to show, and its switch is dimmed.
    final chosen = ref.watch(selectedDownloadProvider) != null;
    final inspectorShown = !requester && chosen && inspector.open && !narrow;
    if (_lastLocation != location) {
      _lastLocation = location;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        noteVisit(ref, location);
        ref.read(windowHistoryProvider.notifier).visit(uri.toString());
      });
    }

    return Shortcuts(
      shortcuts: ShellShortcuts.map,
      child: Actions(
        actions: <Type, Action<Intent>>{
          OpenCommandDeckIntent: CallbackAction<OpenCommandDeckIntent>(
            onInvoke: (_) {
              if (!requester) _openDeck();
              return null;
            },
          ),
          ToggleInspectorIntent: CallbackAction<ToggleInspectorIntent>(
            onInvoke: (_) {
              if (requester || !chosen) return null;
              ref.read(inspectorStateProvider.notifier).toggle();
              return null;
            },
          ),
          GoToSectionIntent: CallbackAction<GoToSectionIntent>(
            onInvoke: (intent) {
              if (intent.index < widget.destinations.length) {
                widget.onDestinationSelected(intent.index);
              }
              return null;
            },
          ),
          OpenSettingsIntent: CallbackAction<OpenSettingsIntent>(
            onInvoke: (_) {
              widget.onSettings();
              return null;
            },
          ),
          CycleServiceIntent: CallbackAction<CycleServiceIntent>(
            onInvoke: (intent) {
              if (!requester) _cycleService(intent.delta);
              return null;
            },
          ),
          RefreshAllIntent: CallbackAction<RefreshAllIntent>(
            onInvoke: (_) {
              _refreshAll();
              return null;
            },
          ),
          SearchThisScreenIntent: CallbackAction<SearchThisScreenIntent>(
            onInvoke: (_) {
              _searchThisScreen();
              return null;
            },
          ),
          // Escape. Enabled only while the deck is up: with no enabled action
          // for the intent the shortcut reports the key as unhandled, so escape
          // goes on to clear a field or close a dialog exactly as before.
          CloseOverlayIntent: _CloseOverlayAction(
            enabled: _deckOpen,
            onClose: _closeDeck,
          ),
          GoBackIntent: CallbackAction<GoBackIntent>(
            onInvoke: (_) {
              _goBack();
              return null;
            },
          ),
          GoForwardIntent: CallbackAction<GoForwardIntent>(
            onInvoke: (_) {
              _goForward();
              return null;
            },
          ),
          ToggleSidebarIntent: CallbackAction<ToggleSidebarIntent>(
            onInvoke: (_) {
              // In a narrow window the sidebar is folded by the width, and a
              // toggle that changed nothing on screen would only store a
              // surprise for the day the window is widened.
              if (!narrow) ref.read(sidebarFoldedProvider.notifier).toggle();
              return null;
            },
          ),
          ShowShortcutsIntent: CallbackAction<ShowShortcutsIntent>(
            onInvoke: (_) {
              showShortcutsSheet(context, requester: requester);
              return null;
            },
          ),
        },
        child: Semantics(
          // The desktop shell is a composite control surface. Without an
          // explicit semantic boundary Flutter is free to merge its chrome
          // into the route's surrounding container; on macOS that collapses
          // the rail and deck out of the native AX hierarchy even though they
          // remain painted and hit-testable. The page navigator keeps its own
          // route semantics below this boundary.
          container: true,
          explicitChildNodes: true,
          child: Scaffold(
            // The route navigator publishes a scopesRoute semantics node. In
            // a Column that node sits after the desktop chrome and macOS drops
            // the earlier siblings from its AX hierarchy. The base route is
            // therefore painted first and the chrome is overlaid afterwards;
            // the screen does not move, but every desktop control is now after
            // the active route in semantics order as well as on screen.
            body: Listener(
              onPointerDown: _onPointerDown,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Positioned(
                    top: chromeHeight,
                    left: railWidth,
                    right: 0,
                    bottom: 0,
                    child: Row(
                      children: [
                        Expanded(child: widget.navigationShell),
                        if (inspectorShown) ...[
                          const InspectorSplitHandle(),
                          SizedBox(
                            width: inspector.width,
                            child: const InspectorPane(),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: tallSidebar ? railWidth : 0,
                    right: 0,
                    height: chromeHeight,
                    child: WindowChrome(
                      inspectorOpen: inspectorShown,
                      inspectorAvailable: chosen,
                      sidebarFolded: compact && !narrow,
                      besideSidebar: tallSidebar,
                      onCommandDeck: requester ? null : _openDeck,
                    ),
                  ),
                  Positioned(
                    top: tallSidebar ? 0 : chromeHeight,
                    left: 0,
                    width: railWidth,
                    bottom: 0,
                    child: DesktopNavRail(
                      compact: compact,
                      header: tallSidebar ? const SidebarHead() : null,
                      selectedIndex: widget.selectedIndex,
                      destinations: widget.destinations,
                      onDestinationSelected: widget.onDestinationSelected,
                      settings: FloatingNavDestination(
                        icon: NavTab.settings.icon,
                        selectedIcon: NavTab.settings.selectedIcon,
                        railIcon: NavTab.settings.railIcon,
                        label: NavTab.settings.label,
                      ),
                      settingsSelected: widget.currentTab == NavTab.settings,
                      onSettings: widget.onSettings,
                      services: requester
                          ? const []
                          : ref.watch(desktopRailServicesProvider),
                      stackFigure: requester
                          ? null
                          : ref.watch(desktopStackFigureProvider),
                      // What is in flight, except on Activity, where the page
                      // is the whole of it.
                      footer: requester || widget.currentTab == NavTab.activity
                          ? null
                          : InFlightGlance(
                              onOpen: () => GoRouter.of(
                                context,
                              ).go(NavTab.activity.routePath),
                            ),
                      selectedService: room,
                      onService: (service) => GoRouter.of(
                        context,
                      ).go(ServiceRoutes.forService(service)),
                    ),
                  ),
                  if (_deckOpen)
                    Positioned(
                      top: chromeHeight,
                      left: railWidth,
                      right: 0,
                      bottom: 0,
                      child: _DeckOverlay(
                        animation: _deck,
                        onClose: _closeDeck,
                        scrim: colorScheme.surfaceContainerLowest,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Escape while an overlay is up. Disabled otherwise, which is the whole point:
/// a disabled action is skipped by the dispatcher instead of swallowing the key.
/// The service whose room [location] is in, or null outside the rooms.
ServiceKey? _roomOf(String location) {
  final segments = Uri.parse(location).pathSegments;
  if (segments.length < 2 || '/${segments.first}' != NavTab.stack.routePath) {
    return null;
  }
  for (final service in ServiceKey.values) {
    if (service.routeParam == segments[1]) return service;
  }
  return null;
}

class _CloseOverlayAction extends Action<CloseOverlayIntent> {
  _CloseOverlayAction({required this.enabled, required this.onClose});

  final bool enabled;
  final VoidCallback onClose;

  @override
  bool get isActionEnabled => enabled;

  @override
  void invoke(CloseOverlayIntent intent) => onClose();
}

/// The deck's descent, plus the click-anywhere-else that closes it.
///
/// A scrim rather than a blur, at a low alpha: the room behind stays legible
/// because the panel is a *switcher*, and half of choosing where to go is
/// seeing what you are leaving.
class _DeckOverlay extends StatelessWidget {
  const _DeckOverlay({
    required this.animation,
    required this.onClose,
    required this.scrim,
  });

  final Animation<double> animation;
  final VoidCallback onClose;
  final Color scrim;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: FadeTransition(
            opacity: animation,
            child: GestureDetector(
              onTap: onClose,
              child: ColoredBox(color: scrim.withValues(alpha: 0.62)),
            ),
          ),
        ),
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760, maxHeight: 520),
            // A scope of its own, autofocused: the page underneath already
            // holds the focus of the shell's scope, so without a new scope the
            // field's own `autofocus` is ignored and the deck opens untypable.
            child: FocusScope(
              autofocus: true,
              child: CommandDeckTransition(
                animation: animation,
                child: CommandDeck(onClose: onClose),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
