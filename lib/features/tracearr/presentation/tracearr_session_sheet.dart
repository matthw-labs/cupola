import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_image.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_navigation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_person_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_session.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_stop.dart';

/// Opens the detail of one viewing over the page it was tapped on: a stream
/// playing now (Live, the Overview) or one from History.
///
/// One sheet for both, so a viewing reads the same wherever it is opened. It
/// holds what the row has no room for (source against output, why it
/// transcodes, the hardware, the speed, the subtitles, the bitrate) and the
/// three things a person does with a viewing: open its title, go to the person,
/// and, for a stream that is playing and a Tracearr that can, stop it.
///
/// [context] is the page's own, and [ref] its: the actions leave the sheet
/// first and then act from the page, so a title opened from here lands under
/// the tab the sheet was opened on, and Back returns to it. They must be the
/// screen's and not the tapped row's: a stream that stops while the sheet is
/// open, or a list that is read again, unmounts its rows, and an action run
/// from a row that is gone would close the sheet and do nothing.
///
/// [onPersonPage] is the person whose own page the sheet is opened on, if it is
/// one: the door to that person is left out, since it would open the page it
/// is on.
Future<void> showTracearrSession(
  BuildContext context,
  WidgetRef ref,
  TracearrSession session, {
  String? onPersonPage,
}) {
  final client = ref.read(tracearrClientProvider);
  final poster = resolveTracearrImage(session.media.posterUrl, client.baseUri);
  return AppBottomSheet.showScrollable<void>(
    context: context,
    title: tracearrMediaTitleOf(session.media),
    subtitle: joinDisplayParts([
      tracearrPersonOf(session.person),
      session.device.name,
    ]),
    icon: Icons.play_circle_outline_rounded,
    headerTrailing: ServiceOverviewArt(
      posterUrl: poster?.toString(),
      title: tracearrMediaTitleOf(session.media),
      httpHeaders: poster == null ? null : client.imageHeaders,
    ),
    initialSize: 0.7,
    bodyPadding: const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      0,
      AppSpacing.lg,
      AppSpacing.lg,
    ),
    builder: (sheet, scroll) => SingleChildScrollView(
      controller: scroll,
      child: TracearrSessionBody(
        session: session,
        onClose: () => Navigator.of(sheet).pop(),
        host: context,
        hostRef: ref,
        onPersonPage: onPersonPage,
      ),
    ),
  );
}

/// What the detail sheet holds under its header: public so the design catalog
/// can draw the sheet in place, as a modal on the root navigator is off its
/// sheet.
class TracearrSessionBody extends ConsumerWidget {
  const TracearrSessionBody({
    super.key,
    required this.session,
    required this.onClose,
    required this.host,
    required this.hostRef,
    required this.onPersonPage,
  });

  final TracearrSession session;
  final VoidCallback onClose;

  /// The page the sheet was opened from, and its ref: what the actions act
  /// from once the sheet has left.
  final BuildContext host;
  final WidgetRef hostRef;

  /// The person whose page this is opened on, or null.
  final String? onPersonPage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = tracearrSheetGroupsOf(session, now: DateTime.now());
    final person = ref.watch(
      tracearrPersonIdProvider((
        id: session.person.id,
        name: session.person.name,
      )),
    );
    final found = person.asData?.value;
    final personId = found == onPersonPage ? null : found;
    // An episode is opened by its series, which Tracearr names by its own id:
    // one read turns that into the series' TMDB or TheTVDB id.
    final showId = session.media.type == TracearrMediaType.episode
        ? session.media.ids.showMediaId
        : null;
    final series = showId == null
        ? null
        : ref.watch(tracearrSeriesKeyProvider(showId)).asData?.value;
    final key = session.mediaKey ?? series;
    final canStop = session.isLive && ref.watch(tracearrCanStopProvider);
    final who = tracearrPersonOf(session.person);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The groups of the title page (`MediaGroup` under a `MediaHeading`),
        // so a viewing reads like the title it is of: when first, then how
        // it played, then where.
        for (final (index, group) in groups.indexed) ...[
          if (group.heading case final heading?)
            MediaHeading(heading)
          else if (index > 0)
            const SizedBox(height: AppSpacing.md),
          MediaGroup(
            children: [
              for (final fact in group.rows)
                _Fact(label: fact.label, value: fact.value),
            ],
          ),
        ],
        const SizedBox(height: AppSpacing.section),
        if (key != null)
          FilledButton.icon(
            style: HeaderActionRow.expandedButtonStyle(context),
            onPressed: () {
              onClose();
              if (host.mounted) host.openMedia(key);
            },
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Open title'),
          ),
        if (personId != null) ...[
          if (key != null) const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            style: _outlined(context),
            onPressed: () {
              onClose();
              if (host.mounted) openTracearrPerson(host, personId);
            },
            icon: const Icon(Icons.person_outline_rounded),
            label: Text('Go to $who'),
          ),
        ],
        if (canStop) ...[
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            style: _outlined(context),
            onPressed: () {
              onClose();
              if (host.mounted) {
                stopTracearrStream(host, hostRef, session);
              }
            },
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop stream'),
          ),
        ],
      ],
    );
  }
}

/// The 44pt floor an outlined action reaches, at standard density so a
/// desktop's compact one does not take it back.
ButtonStyle _outlined(BuildContext context) => OutlinedButton.styleFrom(
  minimumSize: const Size(double.infinity, HeaderActionRow.buttonHeight),
  visualDensity: VisualDensity.standard,
);

/// One fact: its label, and its words at the row's end, read as one
/// sentence. Words that do not fit on that one line (why a stream
/// transcodes, the hardware) go under the label instead, left-aligned, so a
/// long value reads as a sentence rather than a ragged right edge; so do
/// they all past 1.4 times the reading size, as the title page's rows do.
class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final labelStyle = AppType.meta.copyWith(color: room.inkSecondary);
    final valueStyle = AppType.row.copyWith(color: room.ink);
    return Semantics(
      container: true,
      label: '$label, $value',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final scaler = MediaQuery.textScalerOf(context);
              double widthOf(String text, TextStyle style) => (TextPainter(
                text: TextSpan(text: text, style: style),
                textDirection: Directionality.of(context),
                textScaler: scaler,
                maxLines: 1,
              )..layout()).width;
              final fits =
                  !mediaStacked(context) &&
                  widthOf(label, labelStyle) +
                          AppSpacing.lg +
                          widthOf(value, valueStyle) <=
                      constraints.maxWidth;
              final name = Text(label, style: labelStyle);
              if (!fits) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    name,
                    const SizedBox(height: 2),
                    Text(value, style: valueStyle),
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  name,
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Text(
                      value,
                      style: valueStyle,
                      textAlign: TextAlign.end,
                      maxLines: 1,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
