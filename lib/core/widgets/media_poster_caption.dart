import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';

/// The two lines under a poster on a wall: the title, then what tells two
/// titles of one name apart (the year).
///
/// One spelling for every wall that names its posters: the arrs' library
/// (`MediaBrowseScaffold`) and a media server's (its library and the
/// Activity's Recently added). A poster with no artwork is only its kind's
/// glyph, so without these lines a wall of them is a wall of blanks.
///
/// Each line is one line, ellipsised; the subtitle is left out when empty.
/// The caption speaks nothing of its own: the tile it sits under is one button
/// named by the full title, since the visible one may be cut.
class MediaPosterCaption extends StatelessWidget {
  const MediaPosterCaption({
    super.key,
    required this.title,
    this.subtitle = '',
    this.centered = false,
  });

  final String title;
  final String subtitle;

  /// Centred under a circular portrait (Lidarr's artists).
  final bool centered;

  /// The gap between the poster and the caption.
  static const double gap = AppSpacing.xs;

  static TextStyle _titleStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .labelSmall!
      .weight(FontWeight.w600)
      .copyWith(color: Theme.of(context).colorScheme.onSurface);

  static TextStyle _subtitleStyle(BuildContext context) => Theme.of(context)
      .textTheme
      .labelSmall!
      .copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

  /// How tall [gap] and both lines are at the context's reading size,
  /// measured: what a grid of fixed cells adds under a poster so the caption
  /// is never clipped, however large the text is set. Whole points, rounded
  /// up.
  static double heightOf(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final direction = Directionality.of(context);
    double line(TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Ag', style: style),
        textDirection: direction,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final height = painter.height;
      painter.dispose();
      return height;
    }

    return (gap + line(_titleStyle(context)) + line(_subtitleStyle(context)))
        .ceilToDouble();
  }

  /// A grid of captioned 2 : 3 posters, [columns] across [width]: each cell
  /// is the poster at the width the row leaves it and [heightOf] under it,
  /// `gridGap` between cells.
  static SliverGridDelegateWithFixedCrossAxisCount gridDelegate(
    BuildContext context, {
    required double width,
    required int columns,
  }) {
    final tile = (width - AppSpacing.gridGap * (columns - 1)) / columns;
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: columns,
      mainAxisExtent: tile * 3 / 2 + heightOf(context),
      crossAxisSpacing: AppSpacing.gridGap,
      mainAxisSpacing: AppSpacing.gridGap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final align = centered ? TextAlign.center : TextAlign.start;
    return ExcludeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: centered
            ? CrossAxisAlignment.center
            : CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: align,
            style: _titleStyle(context),
          ),
          if (subtitle.isNotEmpty)
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: align,
              style: _subtitleStyle(context),
            ),
        ],
      ),
    );
  }
}
