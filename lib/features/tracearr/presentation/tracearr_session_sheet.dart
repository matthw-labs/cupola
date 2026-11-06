import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
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
/// the tab the sheet was opened on, and Back returns to it.
Future<void> showTracearrSession(
  BuildContext context,
  WidgetRef ref,
  TracearrSession session,
) {
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
      child: _SessionBody(
        session: session,
        onClose: () => Navigator.of(sheet).pop(),
        host: context,
        hostRef: ref,
      ),
    ),
  );
}

class _SessionBody extends ConsumerWidget {
  const _SessionBody({
    required this.session,
    required this.onClose,
    required this.host,
    required this.hostRef,
  });

  final TracearrSession session;
  final VoidCallback onClose;

  /// The page the sheet was opened from, and its ref: what the actions act
  /// from once the sheet has left.
  final BuildContext host;
  final WidgetRef hostRef;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dim = CupolaThemeColors.of(context).dimText;
    final comparison = tracearrComparisonOf(session.quality);
    final facts = tracearrFactsOf(session, now: DateTime.now());
    final how = tracearrHowWords(session.quality);
    final person = ref.watch(
      tracearrPersonIdProvider((
        id: session.person.id,
        name: session.person.name,
      )),
    );
    final personId = person.asData?.value;
    final key = session.mediaKey;
    final canStop = session.isLive && ref.watch(tracearrCanStopProvider);
    final who = tracearrPersonOf(session.person);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Line(label: 'How', value: how),
        const SizedBox(height: AppSpacing.md),
        _Table(rows: comparison, dim: dim),
        const SizedBox(height: AppSpacing.md),
        for (final fact in facts) _Line(label: fact.label, value: fact.value),
        const SizedBox(height: AppSpacing.lg),
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

/// One fact: a label over its words, the pair read as one sentence.
class _Line extends StatelessWidget {
  const _Line({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: '$label, $value',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: Text(
                  label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: CupolaThemeColors.of(context).dimText,
                  ),
                ),
              ),
              Expanded(child: Text(value, style: theme.textTheme.bodyMedium)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Source against output, side by side.
class _Table extends StatelessWidget {
  const _Table({required this.rows, required this.dim});

  final List<TracearrComparison> rows;
  final Color dim;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final head = theme.textTheme.bodySmall?.copyWith(color: dim);
    Widget cell(String text, {TextStyle? style}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Text(text, style: style ?? theme.textTheme.bodyMedium),
    );
    return Semantics(
      container: true,
      label: [
        for (final row in rows)
          '${row.label}, source ${row.source}, output ${row.output}',
      ].join('. '),
      child: ExcludeSemantics(
        child: Table(
          columnWidths: const {
            0: FixedColumnWidth(96),
            1: FlexColumnWidth(),
            2: FlexColumnWidth(),
          },
          children: [
            TableRow(
              children: [
                cell('', style: head),
                cell('Source', style: head),
                cell('Output', style: head),
              ],
            ),
            for (final row in rows)
              TableRow(
                children: [
                  cell(row.label, style: head),
                  cell(row.source),
                  cell(row.output),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
