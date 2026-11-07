import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:window_manager/window_manager.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_identity.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/capability/audience.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/platform/desktop_window.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart'
    show FloatingNavBarMetrics;
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/data/activity_answered.dart';
import 'package:cupola/features/activity/domain/activity_readout.dart'
    show activityAnswerLine;
import 'package:cupola/features/services/domain/service_tab.dart'
    show isServiceTabRoot;
import 'package:cupola/features/services/domain/source_coverage.dart'
    show coverageFailureSentence;
import 'package:cupola/features/services/presentation/services_provider.dart'
    show dashboardDecisionsProvider;
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/shell_breadcrumb.dart';
import 'package:cupola/features/shell/domain/shell_shortcuts.dart';
import 'package:cupola/features/shell/domain/window_history.dart';

/// The window's top strip: one interior, three shells.
///
/// The only part of the app that knows which operating system it is running on,
/// and it may only use that knowledge for three things: where the window
/// buttons go, how tall the strip is, and which modifier the labels print.
/// Colour, type, spacing, icons and motion are never per-OS, and a change here
/// that touches any of them is a bug however good it looks on one platform.
///
/// The strip is also the window's *title*: the breadcrumb is the title, never
/// duplicated elsewhere, which is why the crumbs are links and not a label.
///
/// One strip, the window's only one: the title, on Activity who of its
/// sources answered and when, the way to anything (⌘K) and the inspector's
/// switch. What the deck strip under it used to carry went to where it is
/// read: the room to the sidebar's lit row and the page's own header, the
/// stack's health to the sidebar's lights and Stack.
class WindowChrome extends ConsumerWidget {
  const WindowChrome({
    super.key,
    required this.inspectorOpen,
    this.onCommandDeck,
    this.sidebarFolded = false,
    this.inspectorAvailable = false,
    this.besideSidebar = false,
  });

  /// Drives the inspector switch's tone. Passed rather than watched so the
  /// strip has exactly one reason to rebuild that is not its own.
  final bool inspectorOpen;

  /// Whether the person folded the sidebar: the switch's name says the way
  /// back. Passed, as [inspectorOpen] is, so the strip reads no setting.
  final bool sidebarFolded;

  /// Whether there is a choice for the inspector to show: without one its
  /// switch is dimmed and inert.
  final bool inspectorAvailable;

  /// Opens the command deck; null for the requester's window, which has none.
  final VoidCallback? onCommandDeck;

  /// Whether the strip starts at the sidebar's edge rather than the window's:
  /// a Mac's full sidebar runs the window's height and holds the traffic
  /// lights and its own switch ([SidebarHead]), so the strip leaves no room
  /// for either.
  final bool besideSidebar;

  /// The drawn height on Windows and Linux.
  static const double height = 44;

  /// The drawn height on a Mac, compact or not: the unified toolbar's band the
  /// runner sets up (`MainFlutterWindow`), the traffic lights centred in it.
  static const double macosHeight = 52;

  /// The compact window's strip. Six points shorter, and its chips lose their
  /// labels rather than their tone; the shortcut stays, because the strip is
  /// the only place a pointer-only user meets it, and the tooltip still says
  /// the whole name.
  static const double compactHeight = 38;

  static double heightFor({required bool compact}) =>
      DesktopWindow.style == WindowChromeStyle.macos
      ? macosHeight
      : compact
      ? compactHeight
      : height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Width alone, like [WindowDragStrip]: the strip only ever paints inside a
    // desktop window, so the platform half of the shell test adds nothing.
    final compact =
        MediaQuery.sizeOf(context).width < AppBreakpoints.desktopCompact;
    final uri = GoRouterState.of(context).uri;
    final location = uri.path;
    final crumbs = ShellBreadcrumb.of(location);
    final lens = _lensFor(ref, uri);
    // The inspector follows the stack's activity, which is the operator's.
    final requester = ref.watch(shellAudienceProvider) == Audience.requester;

    // The strip's words grow with the reading size as far as the sidebar's
    // and the phone bar's do, and no further: its height is the window's,
    // and a title or a key cut short at twice the size says less than one a
    // little smaller.
    final scaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: FloatingNavBarMetrics.maxTextScaleFactor);
    final history = ref.watch(windowHistoryProvider);
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: scaler),
      child: _strip(
        context,
        compact,
        crumbs,
        lens,
        location,
        requester,
        history: history,
        folded: sidebarFolded,
        beside: besideSidebar,
      ),
    );
  }

  Widget _strip(
    BuildContext context,
    bool compact,
    List<Crumb> crumbs,
    ({ServiceKey service, String label})? lens,
    String location,
    bool requester, {
    required WindowHistory history,
    required bool folded,
    required bool beside,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Window chrome',
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.55),
            ),
          ),
        ),
        child: SizedBox(
          height: heightFor(compact: compact),
          child: _DragSurface(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  if (!beside)
                    SizedBox(width: DesktopWindow.leadingButtonGutter),
                  // The sidebar's switch, in a window wide enough to choose:
                  // a narrow one folds it by its width. Beside a full sidebar
                  // the switch is at the sidebar's head.
                  if (!compact && !beside)
                    _StripButton(
                      key: const ValueKey('strip-sidebar'),
                      icon: Symbols.dock_to_left_rounded,
                      label: folded ? 'Show the sidebar' : 'Hide the sidebar',
                      shortcut: ShellShortcuts.sidebar,
                      intent: const ToggleSidebarIntent(),
                    ),
                  _StripButton(
                    key: const ValueKey('strip-back'),
                    icon: Icons.chevron_left_rounded,
                    label: 'Back',
                    shortcut: ShellShortcuts.back,
                    intent: const GoBackIntent(),
                    enabled: history.canGoBack,
                  ),
                  _StripButton(
                    key: const ValueKey('strip-forward'),
                    icon: Icons.chevron_right_rounded,
                    label: 'Forward',
                    shortcut: ShellShortcuts.forward,
                    intent: const GoForwardIntent(),
                    enabled: history.canGoForward,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: _Breadcrumb(crumbs: crumbs)),
                  if (lens != null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    _LensChip(
                      compact: compact,
                      label: 'Lens: ${lens.label}',
                      tooltip:
                          'Showing ${serviceWithConnection(lens.service, lens.label)}. '
                          'Change it from the deck.',
                    ),
                  ],
                  // On Activity the answer line is the way to ask again, and
                  // says who answered; elsewhere a mouse has no pull to
                  // refresh, so the strip offers ⌘R as a button.
                  if (!requester && _readsActivity(location)) ...[
                    const SizedBox(width: AppSpacing.md),
                    const _AnswerLine(),
                  ] else
                    _StripButton(
                      key: const ValueKey('strip-refresh'),
                      icon: Icons.refresh_rounded,
                      label: 'Refresh',
                      shortcut: ShellShortcuts.refreshAll,
                      intent: const RefreshAllIntent(),
                    ),
                  if (onCommandDeck case final open?) ...[
                    SizedBox(width: compact ? AppSpacing.sm : AppSpacing.md),
                    _JumpField(compact: compact, onPressed: open),
                  ],
                  // The pane is laid out only in a full window: a switch for
                  // it in a compact one would do nothing anyone could see.
                  if (!requester && !compact) ...[
                    const SizedBox(width: AppSpacing.sm),
                    _InspectorSwitch(
                      on: inspectorOpen,
                      enabled: inspectorAvailable,
                    ),
                  ],
                  if (DesktopWindow.drawsOwnButtons) ...[
                    const SizedBox(width: AppSpacing.md),
                    const _CaptionButtons(),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The instance the current service is being viewed through, if it has a name.
  ///
  /// Nothing is shown for a single-instance service: an unnamed instance has no
  /// label to print, and a chip reading `Lens: Radarr` while the breadcrumb
  /// already says Radarr is furniture. This is the same "you do not pay for the
  /// fold until you need it" rule the app bar badge follows.
  ({ServiceKey service, String label})? _lensFor(WidgetRef ref, Uri location) {
    final crumbSegments = location.pathSegments;
    if (crumbSegments.length < 2) return null;
    final service = ServiceKey.values.firstWhere(
      (s) => s.routeParam == crumbSegments[1],
      orElse: () => ServiceKey.seerr,
    );
    if (service.routeParam != crumbSegments[1]) return null;
    // A service whose shell mounts `ConnectionInViewScope` (a media server's)
    // names the connection it reads in its own tab header, which reads what the
    // visit has in view. This strip only has the location, which at a tab's
    // root carries the link the tab was opened from or none, and so would name
    // the lens, or a connection chosen since in the lens sheet: a second,
    // wrong, reading beside the right one. A page pushed from a tab is one
    // connection's, and its location says which.
    if (service.mountsConnectionInView &&
        isServiceTabRoot(service, location.path)) {
      return null;
    }
    // The connection the page reads: a detail page opened with `?i=` reads
    // that one, whatever the lens is on.
    final instanceId = locationInstanceId(ref, service, location);
    // The app's one rule for naming a connection: no chip while the service
    // has one, whatever label it kept from a sibling since removed.
    final label = ref.watch(connectionNameProvider(instanceId));
    if (label == null) return null;
    return (service: service, label: label);
  }
}

/// Whether [location] is one of Activity's pages, whose sources the strip's
/// answer line speaks for.
bool _readsActivity(String location) =>
    location == ServiceRoutes.activity ||
    location.startsWith('${ServiceRoutes.activity}/');

/// `All 12 answered at 20:53`: who of the sources Activity reads answered,
/// the same the Home's banner counts, and when the last did. A button: it
/// asks them all again, as ⌘R does, and its tooltip names who did not answer.
class _AnswerLine extends ConsumerStatefulWidget {
  const _AnswerLine();

  @override
  ConsumerState<_AnswerLine> createState() => _AnswerLineState();
}

class _AnswerLineState extends ConsumerState<_AnswerLine> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final coverage = ref.watch(dashboardDecisionsProvider).coverage;
    final line = activityAnswerLine(
      coverage,
      at: ref.watch(activityAnsweredAtProvider),
    );
    if (line == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final dim = CupolaThemeColors.of(context).dimText;
    final color = switch (line.tone) {
      final tone? => statusToneColor(scheme, tone, surface: scheme.surface),
      null => dim,
    };
    final failed = coverage.failed.isEmpty
        ? null
        : coverageFailureSentence(coverage);
    final ask = 'Ask again  ${ShellShortcuts.refreshAll}';
    return Tooltip(
      message: failed == null ? ask : '$failed\n$ask',
      waitDuration: const Duration(milliseconds: 500),
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: failed == null ? line.text : '${line.text}. $failed',
        hint: 'Ask again',
        excludeSemantics: true,
        onTap: _ask,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            onTap: _ask,
            behavior: HitTestBehavior.opaque,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (line.tone != null) ...[
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  line.text,
                  maxLines: 1,
                  style:
                      AppTheme.chrome(
                        context,
                        size: 12,
                        weight: FontWeight.w500,
                        color: color,
                      ).tabular.copyWith(
                        decoration: _hovered ? TextDecoration.underline : null,
                        decorationColor: color,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _ask() => Actions.invoke(context, const RefreshAllIntent());
}

/// The way to anything. A field in shape only: it opens the command deck.
///
/// Drawn as a field rather than as a button because that is what it does: the
/// deck it opens is a search, and a control shaped like its own result is how
/// a command palette teaches itself.
class _JumpField extends StatefulWidget {
  const _JumpField({required this.compact, required this.onPressed});

  final bool compact;
  final VoidCallback onPressed;

  /// The field's width in a full window, room for the words and the key.
  static const double width = 240;

  @override
  State<_JumpField> createState() => _JumpFieldState();
}

class _JumpFieldState extends State<_JumpField> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final dim = CupolaThemeColors.of(context).dimText;
    final compact = widget.compact;
    final words = Text(
      compact ? 'Jump' : 'Jump to…',
      maxLines: 1,
      style: AppTheme.chrome(
        context,
        size: 12,
        weight: FontWeight.w500,
        color: dim,
      ),
    );
    // The key legend, mono as the rail's is, on a cap of its own.
    final key = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppRadius.xs),
      ),
      child: Text(
        ShellShortcuts.commandDeck,
        style: AppTheme.chrome(context, size: 11, color: dim).mono,
      ),
    );
    return Semantics(
      button: true,
      container: true,
      enabled: true,
      label: 'Jump to anything, ${ShellShortcuts.commandDeck}',
      hint: 'Open the command deck',
      onTap: widget.onPressed,
      child: ExcludeSemantics(
        child: Tooltip(
          message: 'Jump to anything  ${ShellShortcuts.commandDeck}',
          waitDuration: const Duration(milliseconds: 500),
          excludeFromSemantics: true,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: TextButton(
              onPressed: widget.onPressed,
              style: ButtonStyle(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const WidgetStatePropertyAll(EdgeInsets.zero),
                minimumSize: WidgetStatePropertyAll(
                  Size(
                    44,
                    compact ? WindowChrome.compactHeight : WindowChrome.height,
                  ),
                ),
                visualDensity: VisualDensity.standard,
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              ),
              child: Container(
                width: compact ? null : _JumpField.width,
                height: compact ? 26 : 30,
                padding: EdgeInsets.only(
                  left: compact ? AppSpacing.sm : AppSpacing.row,
                  right: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(
                    alpha: _hovered ? 0.8 : 0.55,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                  children: [
                    Icon(Icons.search_rounded, size: 14, color: dim),
                    const SizedBox(width: AppSpacing.sm),
                    if (compact) words else Expanded(child: words),
                    const SizedBox(width: AppSpacing.sm),
                    key,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One of the strip's glyph buttons: back, forward, the sidebar's switch,
/// refresh. The strip's full height and 44 wide, around a drawn 30 × 28; a
/// tooltip of its name and key; dimmed and inert while it has nothing to do,
/// as back is at the first page of a window.
///
/// It fires its [intent] rather than a callback, so the button and the key are
/// one action, bound once in the shell.
class _StripButton extends StatefulWidget {
  const _StripButton({
    super.key,
    required this.icon,
    required this.label,
    required this.shortcut,
    required this.intent,
    this.enabled = true,
  });

  final IconData icon;
  final String label;
  final String shortcut;
  final Intent intent;
  final bool enabled;

  @override
  State<_StripButton> createState() => _StripButtonState();
}

class _StripButtonState extends State<_StripButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final enabled = widget.enabled;
    final glyph = enabled
        ? (_hovered ? colorScheme.onSurface : colorScheme.onSurfaceVariant)
        : colorScheme.onSurface.withValues(alpha: 0.28);
    final button = Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      hint: widget.shortcut,
      excludeSemantics: true,
      onTap: enabled ? _fire : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: enabled ? _fire : null,
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 44,
            height: WindowChrome.height,
            child: Center(
              child: Container(
                width: 30,
                height: 28,
                decoration: BoxDecoration(
                  color: enabled && _hovered
                      ? colorScheme.onSurface.withValues(alpha: 0.06)
                      : null,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(widget.icon, size: 20, color: glyph),
              ),
            ),
          ),
        ),
      ),
    );
    if (!enabled) return button;
    return Tooltip(
      message: '${widget.label}  ${widget.shortcut}',
      waitDuration: const Duration(milliseconds: 500),
      excludeFromSemantics: true,
      child: button,
    );
  }

  void _fire() => Actions.maybeInvoke(context, widget.intent);
}

/// The inspector's switch: the pane's own glyph, on the room's strong fill
/// while the pane is open, monochrome like every chip of the strip.
class _InspectorSwitch extends StatefulWidget {
  const _InspectorSwitch({required this.on, required this.enabled});

  final bool on;
  final bool enabled;

  @override
  State<_InspectorSwitch> createState() => _InspectorSwitchState();
}

class _InspectorSwitchState extends State<_InspectorSwitch> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final on = widget.on;
    final enabled = widget.enabled;
    // Nothing chosen, nothing to inspect: the switch says so, dimmed and
    // inert, rather than opening an empty column.
    final label = enabled
        ? 'Inspector, ${ShellShortcuts.inspector}'
        : 'Inspector, nothing chosen';
    final switchControl = Semantics(
      button: true,
      enabled: enabled,
      toggled: on,
      label: label,
      excludeSemantics: true,
      onTap: enabled ? _toggle : null,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: enabled ? _toggle : null,
          behavior: HitTestBehavior.opaque,
          // The strip's full height and 44 wide: the target, around the
          // drawn 34 × 28.
          child: SizedBox(
            width: 44,
            height: WindowChrome.height,
            child: Center(
              child: Container(
                width: 34,
                height: 28,
                decoration: BoxDecoration(
                  color: on
                      ? CupolaRoom.of(context).fillStrong
                      : (enabled && _hovered
                            ? colorScheme.onSurface.withValues(alpha: 0.06)
                            : null),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: enabled
                        ? colorScheme.outline
                        : colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),
                ),
                child: Icon(
                  Icons.view_sidebar_outlined,
                  size: 16,
                  color: on
                      ? colorScheme.onSurface
                      : enabled
                      ? colorScheme.onSurfaceVariant
                      : colorScheme.onSurface.withValues(alpha: 0.28),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return Tooltip(
      message: enabled
          ? 'Inspector  ${ShellShortcuts.inspector}'
          : 'Inspector: choose a download in Activity',
      waitDuration: const Duration(milliseconds: 500),
      excludeFromSemantics: true,
      child: switchControl,
    );
  }

  void _toggle() => Actions.invoke(context, const ToggleInspectorIntent());
}

/// The window's obligations, for a screen the shell does not host.
///
/// Onboarding gates the shell, and a handful of flows live above it on the root
/// navigator, so those screens have no [WindowChrome], and the window's three
/// jobs have to be done by something. This is that something, and annotation
/// `onb1` is explicit that it is load-bearing rather than decoration:
///
///  * on **Windows and Linux** it is the only thing that can move a frameless
///    window, and the only place its caption buttons can be; without it the
///    window cannot be moved and, worse, cannot be closed;
///  * on **macOS** it reserves the traffic-light gutter, so AppKit's buttons
///    have somewhere to sit that is not on top of the beat. It used to render
///    nothing at all here (the old guard bailed on `!drawsOwnButtons`, which is
///    exactly the Mac), so the onboarding walk drew its content under the
///    lights;
///  * on **all three** it carries the trail. Not a window *title*: the Chrome
///    sheet forbids one, but the same breadcrumb the shell prints everywhere
///    else, so the strip above a beat is recognisably the strip above a page.
///
/// Renders nothing on a phone, which has no window to move and no gutter to
/// reserve.
///
/// [trail] is plain strings rather than [Crumb]s, and that is the difference
/// between this strip and the shell's: these crumbs point nowhere. Onboarding
/// gates the shell, so there is no `/dashboard` to send someone to, and a
/// clickable crumb that navigates into a locked app is worse than a label.
class WindowDragStrip extends StatelessWidget {
  const WindowDragStrip({super.key, this.trail = const [kAppName, 'Setup']});

  /// The breadcrumb, outermost first. Defaults to onboarding's, since the setup
  /// walk is the only flow above the shell today; a second one passes its own
  /// rather than teaching this widget about routes it cannot reach.
  final List<String> trail;

  @override
  Widget build(BuildContext context) {
    if (!DesktopWindow.isSupported) return const SizedBox.shrink();
    // Width alone, not [AppBreakpoints.isCompactDesktop]: a window narrow
    // enough for the phone layout still carries this strip, and it is the
    // narrowest window there is, not a full-height one.
    final compact =
        MediaQuery.sizeOf(context).width < AppBreakpoints.desktopCompact;

    return SizedBox(
      // The shell's own heights, through the shell's own helper: 44 full, 38
      // compact, a Mac's 52 at any width. A strip that agreed with the shell by coincidence would stop
      // agreeing the first time one of the two numbers moved.
      height: WindowChrome.heightFor(compact: compact),
      child: _DragSurface(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Row(
            children: [
              // Zero everywhere but macOS, where it is the measured width of
              // the traffic lights plus the design's gap after them.
              SizedBox(width: DesktopWindow.leadingButtonGutter),
              Expanded(
                child: _Breadcrumb(
                  crumbs: [
                    for (final label in trail) (label: label, location: null),
                  ],
                  // 11px dim throughout, per `onb1`. The shell's trail sets its
                  // leaf in onSurface because that leaf is where you are and
                  // the others are links; nothing here is a link, so nothing
                  // here earns the emphasis.
                  size: 11,
                  dim: true,
                ),
              ),
              if (DesktopWindow.drawsOwnButtons) ...[
                const SizedBox(width: AppSpacing.md),
                const _CaptionButtons(),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// The strip's ground moves the window, and a double click on it zooms it as
/// the OS's own title bar does; [child], the strip's content, lies over it.
///
/// The controls are the ground's siblings, not its children: a click on one
/// never reaches the ground's double-click recogniser, which would otherwise
/// hold every click in the strip for the double-click timeout before letting
/// the button have it. What in [child] takes no pointer (the title, the gaps
/// between the controls) lets the press through to the ground, so the window
/// drags from there.
/// The head of a Mac's full sidebar, as tall as the window's toolbar: the
/// traffic lights sit in it, and the switch that hides the sidebar at its end.
/// The window is dragged by it, as by the strip.
class SidebarHead extends StatelessWidget {
  const SidebarHead({super.key});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: WindowChrome.macosHeight,
    child: _DragSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        child: Row(
          children: [
            SizedBox(width: DesktopWindow.leadingButtonGutter),
            const Spacer(),
            _StripButton(
              key: const ValueKey('strip-sidebar'),
              icon: Symbols.dock_to_left_rounded,
              label: 'Hide the sidebar',
              shortcut: ShellShortcuts.sidebar,
              intent: const ToggleSidebarIntent(),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DragSurface extends StatelessWidget {
  const _DragSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const DragToMoveArea(child: SizedBox.expand()),
      child,
    ],
  );
}

/// The trail, and therefore the window title.
class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.crumbs, this.size = 12, this.dim = false});

  final List<Crumb> crumbs;

  /// 12 in the shell's chrome, 11 on the drag strip above a gated flow.
  final double size;

  /// Whether the whole trail prints in the dim tone, leaf included.
  ///
  /// The shell's trail says where you *are* by giving the leaf the full ink and
  /// the ancestors the dim one. A trail whose crumbs are not links has no such
  /// distinction to draw, so it prints as one dim line rather than inventing an
  /// emphasis that means nothing.
  final bool dim;

  @override
  Widget build(BuildContext context) {
    if (crumbs.isEmpty) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final children = <Widget>[];
    for (var i = 0; i < crumbs.length; i++) {
      final crumb = crumbs[i];
      final isLast = i == crumbs.length - 1;
      if (i > 0) {
        children.add(
          // Words and chevrons take no pointer, so the window drags from the
          // title as it does from the OS's own.
          IgnorePointer(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 13,
                color: CupolaThemeColors.of(context).dimText,
              ),
            ),
          ),
        );
      }
      final text = Text(
        crumb.label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.chrome(
          context,
          size: size,
          weight: isLast && !dim ? FontWeight.w600 : FontWeight.w500,
          color: isLast && !dim
              ? colorScheme.onSurface
              : CupolaThemeColors.of(context).dimText,
        ),
      );
      children.add(
        Flexible(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: crumb.location == null || isLast
                ? IgnorePointer(child: text)
                : _CrumbLink(location: crumb.location!, child: text),
          ),
        ),
      );
    }
    return Semantics(
      // The trail spoken as one sentence: three separate labels with chevrons
      // between them is four announcements for one place.
      label: crumbs.map((c) => c.label).join(', '),
      excludeSemantics: true,
      child: Row(children: children),
    );
  }
}

/// An ancestor crumb: a real control, because the title is the navigation.
class _CrumbLink extends StatefulWidget {
  const _CrumbLink({required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  State<_CrumbLink> createState() => _CrumbLinkState();
}

class _CrumbLinkState extends State<_CrumbLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: () => GoRouter.of(context).go(widget.location),
        child: DefaultTextStyle.merge(
          style: TextStyle(
            decoration: _hovered ? TextDecoration.underline : null,
            decorationColor: CupolaThemeColors.of(context).dimText,
          ),
          child: widget.child,
        ),
      ),
    );
  }
}

/// The lens: which connection of a service the page reads, a 28pt readout
/// in the strip (26 compact), on the room's strong fill since it names a
/// choice in force.
///
/// It takes the 12dp interactive radius and not full radius, which in this
/// system means a tag or a piece of metadata, and it is monochrome like the
/// rest of the chrome. A compact window keeps only its glyph; the tooltip
/// still says the whole name.
class _LensChip extends StatelessWidget {
  const _LensChip({
    required this.label,
    required this.tooltip,
    this.compact = false,
  });

  final String label;
  final String tooltip;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      excludeFromSemantics: true,
      child: Semantics(
        label: label,
        excludeSemantics: true,
        child: Container(
          height: compact ? 26 : 28,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: CupolaRoom.of(context).fillStrong,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: colorScheme.outline),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.dns_outlined, size: 14, color: colorScheme.onSurface),
              if (!compact) ...[
                const SizedBox(width: 6),
                Text(
                  label,
                  style: AppTheme.chrome(
                    context,
                    size: 11,
                    weight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Window buttons, where the OS puts them, in the OS's own geometry.
///
/// Drawn by us only where the platform has no opinion about who draws them:
/// macOS keeps AppKit's traffic lights over our strip, because a lookalike is
/// wrong on hover, wrong under Reduce Transparency, and wrong the day the
/// system changes them.
class _CaptionButtons extends StatelessWidget {
  const _CaptionButtons();

  @override
  Widget build(BuildContext context) {
    final gnome = DesktopWindow.style == WindowChromeStyle.gnome;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _CaptionButton(
          icon: Icons.remove_rounded,
          label: 'Minimize',
          gnome: gnome,
          onPressed: windowManager.minimize,
        ),
        SizedBox(width: gnome ? AppSpacing.sm : 0),
        _CaptionButton(
          icon: Icons.crop_square_rounded,
          label: 'Maximize',
          gnome: gnome,
          onPressed: () async {
            if (await windowManager.isMaximized()) {
              await windowManager.unmaximize();
            } else {
              await windowManager.maximize();
            }
          },
        ),
        SizedBox(width: gnome ? AppSpacing.sm : 0),
        _CaptionButton(
          icon: Icons.close_rounded,
          label: 'Close',
          gnome: gnome,
          danger: true,
          onPressed: windowManager.close,
        ),
      ],
    );
  }
}

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({
    required this.icon,
    required this.label,
    required this.gnome,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;

  /// GNOME draws 26pt round buttons; Windows draws 44x44 rectangles, and its
  /// maximise button must keep its own hover; snap layouts open from it.
  final bool gnome;
  final bool danger;
  final VoidCallback onPressed;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final size = widget.gnome ? 26.0 : 44.0;
    // The room's own error, the one `onError` below is paired with: the dark
    // room's byte under paper's white glyph measured about 2:1.
    final hoverColor = widget.danger
        ? statusToneFill(
            colorScheme,
            StatusTone.error,
          ).withValues(alpha: widget.gnome ? 0.24 : 1.0)
        : colorScheme.onSurface.withValues(alpha: 0.08);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Semantics(
        button: true,
        enabled: true,
        label: widget.label,
        child: IconButton(
          tooltip: widget.label,
          onPressed: widget.onPressed,
          padding: EdgeInsets.zero,
          constraints: BoxConstraints.tightFor(
            width: size,
            height: widget.gnome ? size : WindowChrome.height,
          ),
          style: ButtonStyle(
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(widget.gnome ? size : 0),
              ),
            ),
            backgroundColor: WidgetStatePropertyAll(
              _hovered
                  ? hoverColor
                  : (widget.gnome
                        ? colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.6,
                          )
                        : Colors.transparent),
            ),
          ),
          icon: Icon(
            widget.icon,
            size: widget.gnome ? 13 : 15,
            color: _hovered && widget.danger && !widget.gnome
                ? colorScheme.onError
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
