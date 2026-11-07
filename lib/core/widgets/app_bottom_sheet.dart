import 'package:flutter/material.dart';

import 'package:cupola/core/app_breakpoints.dart';
import 'package:cupola/core/app_elevation.dart';
import 'package:cupola/core/app_gradients.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/sheet_utils.dart';

/// Canonical drag handle for Cupola bottom sheets (36×4, subtle).
class AppSheetHandle extends StatelessWidget {
  const AppSheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 36,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        decoration: BoxDecoration(
          color: Theme.of(
            context,
          ).colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
          borderRadius: AppRadius.borderRadiusFull,
        ),
      ),
    );
  }
}

/// Shared sheet header: optional accent icon tile, title + subtitle, and an
/// optional trailing widget / close button.
class AppSheetHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Color? accent;
  final Widget? trailing;
  final bool showClose;

  const AppSheetHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.accent,
    this.trailing,
    this.showClose = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final accentColor = accent ?? colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (icon != null) ...[
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: AppRadius.borderRadiusMd,
            ),
            // The glyph is measured against its 14% tile over the sheet's
            // own container, not painted in the raw brand byte.
            child: Icon(
              icon,
              size: 20,
              color: ServiceTheme.onTint(
                accentColor,
                surface: CupolaRoom.of(context).raised,
                tintAlpha: 0.14,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleLarge!.weight(FontWeight.w600),
              ),
              if (subtitle != null && subtitle!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  subtitle!,
                  // Capped structurally, not just by callers. The subtitle is
                  // where a service-supplied media title lands, and an
                  // unbounded one grows the header until it pushes the list it
                  // is introducing out of a short viewport (a small macOS
                  // window, or a phone with the keyboard up: the phone cannot
                  // be short by rotating any more, but it can be by typing). A
                  // caller-side `truncateTitle` is the right first line of
                  // defence and cannot fix that on its own.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
        if (showClose)
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          ),
      ],
    );
  }
}

/// Premium bottom-sheet container used across the app.
///
/// Provides one canonical chrome: drag handle, optional [AppSheetHeader],
/// the room's raised step, top radius [AppRadius.sheet], [AppElevation.sheet], an optional service-accent
/// glow behind the header, safe-area handling and keyboard avoidance.
///
/// Use [AppBottomSheet.show] for min-content forms/pickers, or
/// [AppBottomSheet.showScrollable] for large, drag-to-resize lists.
///
/// Where there is room ([AppBreakpoints.sheetsAreDialogs]: 720 wide, on a
/// tablet as on a desktop) neither rises from the bottom: a form or a picker
/// is a dialog centred at [SheetUtils.formWidth], a long list a tall one at
/// [SheetUtils.listWidth], with the same header, always with its close
/// button, and closed by Esc or a click outside ([SheetInDialog]). The
/// caller's body is the same.
class AppBottomSheet extends StatelessWidget {
  final String? title;
  final String? subtitle;
  final IconData? icon;
  final Color? accent;
  final Widget? headerTrailing;
  final bool showClose;
  final bool showHandle;

  /// The sheet body. For draggable sheets this is provided a [ScrollController]
  /// via [showScrollable]; for min-content sheets it is scrolled internally.
  final Widget child;
  final EdgeInsetsGeometry bodyPadding;

  /// When set, the body is wrapped in [Expanded] + a scroll view driven by this
  /// controller (draggable mode). When null, the sheet is min-content.
  final ScrollController? scrollController;

  const AppBottomSheet({
    super.key,
    required this.child,
    this.title,
    this.subtitle,
    this.icon,
    this.accent,
    this.headerTrailing,
    this.showClose = false,
    this.showHandle = true,
    this.bodyPadding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      0,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    this.scrollController,
  });

  bool get _hasHeader => title != null && title!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final draggable = scrollController != null;
    final inDialog = SheetInDialog.of(context);
    final showHandle = this.showHandle && !inDialog;
    // A pointer has no edge to swipe a dialog away from.
    final showClose = this.showClose || inDialog;

    final header = _hasHeader
        ? Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.lg,
              showHandle ? 0 : AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.md,
            ),
            child: AppSheetHeader(
              title: title!,
              subtitle: subtitle,
              icon: icon,
              accent: accent,
              trailing: headerTrailing,
              showClose: showClose,
            ),
          )
        : null;

    // Draggable mode: [child] is already a scrollable wired to
    // [scrollController]; give it the remaining space, inside [bodyPadding]
    // (it was dropped here, and a sheet that asked for a margin drew its rows
    // against the screen's edge). Min-content mode: scroll [child] internally
    // so it can't overflow with the keyboard open.
    final Widget body = draggable
        ? Expanded(
            child: Padding(padding: bodyPadding, child: child),
          )
        : Flexible(
            child: SingleChildScrollView(padding: bodyPadding, child: child),
          );

    final column = Column(
      mainAxisSize: draggable ? MainAxisSize.max : MainAxisSize.min,
      children: [if (showHandle) const AppSheetHandle(), ?header, body],
    );

    // The dialog is the panel: its corners, its edge, its scrim and its own
    // way out of the keyboard's way. The glow stays the sheet's.
    if (inDialog) {
      return Stack(
        children: [
          if (accent != null) _glow(accent!),
          Padding(
            padding: EdgeInsets.only(
              top: _hasHeader ? AppSpacing.sm : AppSpacing.lg,
            ),
            child: column,
          ),
        ],
      );
    }

    final content = draggable
        ? column
        : ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.92,
            ),
            child: column,
          );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      // The brand book's sheet: the raised step of the room, `radius.sheet`
      // (30) at the top and `shadow.sheet` cast upwards. It drew the slab's
      // step at 16 under `level3`.
      // Continuous corners, the theme's own sheet shape.
      child: DecoratedBox(
        decoration: ShapeDecoration(
          color: CupolaRoom.of(context).raised,
          shape: const RoundedSuperellipseBorder(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppRadius.sheet),
            ),
          ),
          shadows: AppElevation.sheet(colorScheme),
        ),
        child: ClipRSuperellipse(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
          // The sheet paints its own fill above the route's Material, so
          // ink drawn there (a ListTile's tap, its selected tint) would be
          // hidden under it. A transparent Material of the sheet's own puts
          // every row's ink back on top of the fill.
          child: Material(
            type: MaterialType.transparency,
            child: Stack(
              children: [
                if (accent != null) _glow(accent!),
                SafeArea(top: false, child: content),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The service's glow behind the header.
  static Widget _glow(Color accent) => Positioned(
    top: 0,
    left: 0,
    right: 0,
    height: 140,
    child: IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppGradients.serviceGlow(
            accent,
            center: Alignment.topCenter,
            radius: 1.1,
          ),
        ),
      ),
    ),
  );

  /// Shows a min-content bottom sheet (forms, pickers). The [builder] result is
  /// scrolled internally so it can never overflow with the keyboard open.
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    String? title,
    String? subtitle,
    IconData? icon,
    Color? accent,
    Widget? headerTrailing,
    bool showClose = false,
    bool showHandle = true,
    bool isDismissible = true,
    bool enableDrag = true,
    EdgeInsetsGeometry? bodyPadding,
  }) {
    final padding =
        bodyPadding ??
        const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          0,
          AppSpacing.lg,
          AppSpacing.lg,
        );
    return SheetUtils.showCupolaModalSheet<T>(
      context: context,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: Colors.transparent,
      builder: (context) => AppBottomSheet(
        title: title,
        subtitle: subtitle,
        icon: icon,
        accent: accent,
        headerTrailing: headerTrailing,
        showClose: showClose,
        showHandle: showHandle,
        bodyPadding: padding,
        child: Builder(builder: builder),
      ),
    );
  }

  /// Shows a large, drag-to-resize sheet. [builder] receives a
  /// [ScrollController] which MUST be attached to the returned scrollable for
  /// drag-to-expand to work.
  static Future<T?> showScrollable<T>({
    required BuildContext context,
    required Widget Function(BuildContext context, ScrollController controller)
    builder,
    String? title,
    String? subtitle,
    IconData? icon,
    Color? accent,
    Widget? headerTrailing,
    bool showClose = false,
    double initialSize = 0.6,
    double minSize = 0.4,
    double maxSize = 0.95,
    bool isDismissible = true,
    bool enableDrag = true,
    EdgeInsetsGeometry? bodyPadding,
  }) {
    // A dialog has no drag: the list is given a scroll of its own, at the
    // dialog's full height.
    if (AppBreakpoints.sheetsAreDialogs(context)) {
      return SheetUtils.showCupolaModalSheet<T>(
        context: context,
        isDismissible: isDismissible,
        dialogWidth: SheetUtils.listWidth,
        tall: true,
        builder: (context) => _OwnScroll(
          builder: (context, scrollController) => AppBottomSheet(
            title: title,
            subtitle: subtitle,
            icon: icon,
            accent: accent,
            headerTrailing: headerTrailing,
            showClose: showClose,
            scrollController: scrollController,
            bodyPadding: bodyPadding ?? EdgeInsets.zero,
            child: builder(context, scrollController),
          ),
        ),
      );
    }
    return SheetUtils.showCupolaModalSheet<T>(
      context: context,
      isDismissible: isDismissible,
      enableDrag: enableDrag,
      backgroundColor: Colors.transparent,
      builder: (context) => DraggableScrollableSheet(
        initialChildSize: initialSize,
        minChildSize: minSize,
        maxChildSize: maxSize,
        expand: false,
        builder: (context, scrollController) => AppBottomSheet(
          title: title,
          subtitle: subtitle,
          icon: icon,
          accent: accent,
          headerTrailing: headerTrailing,
          showClose: showClose,
          scrollController: scrollController,
          bodyPadding: bodyPadding ?? EdgeInsets.zero,
          child: builder(context, scrollController),
        ),
      ),
    );
  }
}

/// Owns the scroll a dialog gives a sheet's list in place of the drag.
class _OwnScroll extends StatefulWidget {
  const _OwnScroll({required this.builder});

  final Widget Function(BuildContext context, ScrollController controller)
  builder;

  @override
  State<_OwnScroll> createState() => _OwnScrollState();
}

class _OwnScrollState extends State<_OwnScroll> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _controller);
}
