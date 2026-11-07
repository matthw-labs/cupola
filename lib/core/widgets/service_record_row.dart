import 'package:flutter/material.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/status_badge.dart';

/// One record in a service tab's list: a tone-walked glyph, a title over a
/// dim detail line, and a figure on the trailing edge.
///
/// Extracted from the Plex and Jellyfin tab screens, where the same seventy
/// lines were written twice, character for character, in a single pass. Three
/// things in it are load-bearing and all three are the kind that drift apart
/// once there are two copies: the colour comes from [statusToneColor] rather
/// than a raw `AppColors` arm, so the tone is walked for contrast against the
/// surface it lands on; the title and the figure go through [AppTheme]'s named
/// roles rather than a bare `TextStyle(fontSize:)`, which never reaches the
/// `wght` axis of the bundled variable face and renders its default instance
/// whatever weight it asks for; and the row speaks **one** sentence, with
/// [ExcludeSemantics] silencing the parts, which is what keeps a screen reader
/// from reading a title, a detail and a number as three unrelated nodes.
///
/// Not every row in the app is this row. A variant whose detail wraps freely,
/// or whose figure sits on a different type role, is a different row and says
/// so by staying where it is: NZBGet's is exactly that and is deliberately
/// left alone.
class ServiceRecordRow extends StatelessWidget {
  const ServiceRecordRow({
    super.key,
    required IconData this.icon,
    required this.tone,
    required this.title,
    required this.detail,
    required this.trailing,
    required this.semanticLabel,
    this.footer,
  }) : art = null;

  /// A record about a title: its [art] (a poster, `ServiceOverviewArt`) stands
  /// where the glyph does, and the [tone] still colours the trailing figure.
  ///
  /// A named constructor and not an optional widget beside the glyph: a row
  /// has one leading mark, and which one is a decision of the call site.
  const ServiceRecordRow.poster({
    super.key,
    required Widget this.art,
    required this.tone,
    required this.title,
    required this.detail,
    required this.trailing,
    required this.semanticLabel,
    this.footer,
  }) : icon = null;

  final IconData? icon;

  /// What sits under the detail, inside the body: a row of chips (the kinds of
  /// server a person has an account on). Part of the one sentence the row
  /// speaks, so the caller words it into [semanticLabel] and the footer is
  /// silenced with the rest.
  final Widget? footer;

  /// The picture that leads a [ServiceRecordRow.poster].
  final Widget? art;
  final StatusTone tone;
  final String title;
  final String detail;
  final String trailing;

  /// The whole sentence the row speaks. The parts are silenced beneath it.
  final String semanticLabel;

  /// The widest the trailing figure may grow, as a share of the row's content
  /// width. Past it the figure wraps (two lines) and then ellipsises, so the
  /// title always keeps the larger part of the row.
  static const double trailingMaxFraction = 0.4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = statusToneColor(theme.colorScheme, tone);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: ExcludeSemantics(
        child: AppCard.outlined(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: LayoutBuilder(
            builder: (context, constraints) => Row(
              children: [
                art ?? Icon(icon, color: color),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.rowTitle(theme.brightness),
                      ),
                      // A record with nothing to add under its title says so by
                      // leaving the line out, not by holding an empty one.
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          detail,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: CupolaThemeColors.of(context).dimText,
                          ),
                        ),
                      ],
                      if (footer case final footer?) ...[
                        const SizedBox(height: AppSpacing.sm),
                        footer,
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                // Not Flexible: beside an Expanded body a Flexible of the same
                // flex is handed half the free width whether it fills it or
                // not, which floated a short figure mid-row and wrapped the
                // title early. The figure takes its natural width, on the
                // trailing edge, up to a cap so a long one cannot crush the
                // title.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: constraints.maxWidth * trailingMaxFraction,
                  ),
                  child: Text(
                    trailing,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.end,
                    style: AppTheme.data(
                      theme.brightness,
                    ).copyWith(color: color),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
