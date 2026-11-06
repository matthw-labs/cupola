import 'package:flutter/material.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/room_art.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';

/// One section of Activity: its name over a slab of rows.
///
/// The name sits on the page, above the slab, with what the section counts at
/// its end (`4 moving · 1 stuck`); when [onOpen] is given the count leads to
/// the section's own view, with a chevron. A section with nothing to say is
/// not drawn: the page decides that, never an empty slab.
class ActivitySection extends StatelessWidget {
  const ActivitySection({
    super.key,
    required this.title,
    required this.children,
    this.meta,
    this.onOpen,
    this.openHint,
    this.semanticLabel,
    this.slabPadding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    this.light,
  });

  /// The picture of the light of the section's first title: its slab glows
  /// with it. Null for an unlit slab.
  final RoomArt? light;

  /// The section's name: `Downloads`, `Finished today`.
  final String title;

  /// What it counts, at the end of the name's line: `4 moving · 1 stuck`.
  final String? meta;

  /// Where the count leads.
  final VoidCallback? onOpen;

  /// Where [onOpen] leads, to a screen reader: `Opens Downloads`.
  final String? openHint;

  /// The heading as a screen reader says it, when the name and the count are
  /// not the whole sentence.
  final String? semanticLabel;

  final EdgeInsets slabPadding;

  /// The rows, on the slab.
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final metaStyle = AppType.meta.copyWith(color: room.inkSecondary);
    final open = onOpen;
    final count = meta == null
        ? null
        : Text(
            meta!,
            style: open == null
                ? metaStyle
                : metaStyle.weight(FontWeight.w600).tabular,
          );
    final large = MediaQuery.textScalerOf(context).scale(10) >= 13;
    final titleText = Text(
      title,
      style: AppType.section.copyWith(color: room.ink),
    );
    final heading = Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.gutter,
        AppSpacing.section,
        AppSpacing.gutter,
        AppSpacing.md,
      ),
      child: Semantics(
        header: true,
        label: semanticLabel ?? [title, ?meta].join(', '),
        button: open != null,
        hint: openHint,
        onTap: open,
        excludeSemantics: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // At a large reading size, or when the count is longer than what
            // the name leaves of the line (`3 faults · 2 violations · 3
            // requests` on a phone), the count goes under the name: beside
            // it, the name broke inside its words or the count ran past the
            // page.
            final stacked =
                large ||
                (meta != null &&
                    !_fitsBeside(
                      context,
                      title: title,
                      meta: meta!,
                      led: open != null,
                      width: constraints.maxWidth,
                    ));
            return Flex(
              direction: stacked ? Axis.vertical : Axis.horizontal,
              crossAxisAlignment: stacked
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                if (stacked) titleText else Expanded(child: titleText),
                if (count != null) ...[
                  if (!stacked) const SizedBox(width: AppSpacing.md),
                  if (open == null)
                    count
                  else
                    InkWell(
                      onTap: open,
                      borderRadius: AppRadius.borderRadiusSm,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 44),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Under the name, at a large size, the count wraps
                            // rather than run past the page.
                            if (stacked) Flexible(child: count) else count,
                            const SizedBox(width: AppSpacing.xxs),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 16,
                              color: room.inkSecondary,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        heading,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
          child: ActivitySlab(
            padding: slabPadding,
            light: light,
            children: children,
          ),
        ),
      ],
    );
  }
}

/// The slab Activity's rows sit on.
class ActivitySlab extends StatelessWidget {
  const ActivitySlab({
    super.key,
    required this.children,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
    this.light,
  });

  final List<Widget> children;
  final EdgeInsets padding;

  /// See [ActivitySection.light].
  final RoomArt? light;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: room.slab,
        borderRadius: AppRadius.borderRadiusSlab,
        border: Border.all(color: room.hair),
      ),
      child: ClipRRect(
        borderRadius: AppRadius.borderRadiusSlab,
        child: Stack(
          children: [
            if (light != null) Positioned.fill(child: SlabLight(art: light)),
            Padding(
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A line of rows inside a slab that leads on: `All 48 requests` and what it
/// counts, with a chevron, over a hairline.
class ActivitySlabLink extends StatelessWidget {
  const ActivitySlabLink({
    super.key,
    required this.label,
    required this.onTap,
    this.meta,
    this.divided = true,
  });

  final String label;
  final String? meta;
  final VoidCallback onTap;

  /// Whether a hairline separates it from the rows above.
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final labelText = Text(
      label,
      style: AppType.label.copyWith(color: room.inkSecondary),
    );
    final metaStyle = AppType.meta.copyWith(color: room.inkTertiary);
    // At a large reading size the count goes under the label, whole: beside
    // it, what was left of the line cut the count inside its words.
    final stacked = MediaQuery.textScalerOf(context).scale(10) >= 13;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: room.hair)) : null,
      ),
      child: Semantics(
        button: true,
        // The dot between the counts is for the eye: said aloud it is a pause.
        label: [
          label,
          if (meta case final meta?) spokenFromDotted(meta),
        ].join(', '),
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Row(
              children: [
                if (stacked)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          labelText,
                          if (meta case final meta?)
                            Text(meta, style: metaStyle),
                        ],
                      ),
                    ),
                  )
                else ...[
                  Expanded(child: labelText),
                  if (meta case final meta?) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: metaStyle,
                      ),
                    ),
                  ],
                ],
                const SizedBox(width: AppSpacing.xxs),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: room.inkSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether [meta] fits on the line of [title], with the gap between them and,
/// for a count that leads on ([led]), its chevron: measured as it will be set,
/// at the reader's text size. A few points of slack keep a count that only
/// just fits beside the name from wrapping under it on rounding.
bool _fitsBeside(
  BuildContext context, {
  required String title,
  required String meta,
  required bool led,
  required double width,
}) {
  final room = CupolaRoom.of(context);
  final scaler = MediaQuery.textScalerOf(context);
  final direction = Directionality.of(context);
  double measure(String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: direction,
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final result = painter.width;
    painter.dispose();
    return result;
  }

  final metaStyle = AppType.meta.copyWith(color: room.inkSecondary);
  final countWidth = measure(
    meta,
    led ? metaStyle.weight(FontWeight.w600).tabular : metaStyle,
  );
  final chevron = led ? 16 + AppSpacing.xxs : 0;
  return measure(title, AppType.section) +
          AppSpacing.md +
          countWidth +
          chevron +
          4 <=
      width;
}
