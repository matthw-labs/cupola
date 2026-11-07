import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_navigation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_watched.dart';

/// Watched by: who has watched this title, from Tracearr, on a Media page.
///
/// A person a row: their plays, how much of it they got through and when they
/// last did, a series counting its distinct episodes. A row leads to the
/// person's page in Tracearr.
///
/// **Only when Tracearr answered.** A Tracearr that is not set up, that did not
/// answer, or that does not know the title draws nothing at all: not knowing
/// is not "nobody", and a section that said so would be a claim about viewers
/// the app never asked. A title Tracearr knows and nobody has played says
/// `Nobody has watched it`.
class MediaWatchedBy extends ConsumerWidget {
  const MediaWatchedBy({super.key, required this.mediaKey, this.now});

  final MediaKey mediaKey;

  /// The clock the days are counted against; tests set it.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref
        .watch(currentSettingsProvider)
        .isServiceConfigured(ServiceKey.tracearr)) {
      return const SizedBox.shrink();
    }
    final watchers = ref.watch(tracearrWatchedByProvider(mediaKey)).value;
    if (watchers == null) return const SizedBox.shrink();
    final clock = now ?? DateTime.now();
    final people = tracearrWatchedPeople(watchers);
    final room = CupolaRoom.of(context);
    if (people.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const MediaHeading('Watched by'),
          Text(
            'Nobody has watched it',
            style: AppType.meta.copyWith(color: room.inkTertiary),
          ),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MediaHeading(
          'Watched by',
          trailing: tracearrWatchedTally(people, now: clock),
        ),
        MediaGroup(
          children: [
            for (final person in people)
              _WatcherRow(
                person: person,
                detail: tracearrWatcherDetail(
                  person,
                  series: !mediaKey.isMovie,
                  now: clock,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _WatcherRow extends StatelessWidget {
  const _WatcherRow({required this.person, required this.detail});

  final TracearrWatchedPerson person;
  final String detail;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final id = person.personId;
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    person.name,
                    style: AppType.row.copyWith(color: room.ink),
                  ),
                  Text(
                    detail,
                    style: AppType.meta
                        .weight(FontWeight.w400)
                        .copyWith(color: room.inkTertiary),
                  ),
                ],
              ),
            ),
            if (id != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: room.inkTertiary,
              ),
            ],
          ],
        ),
      ),
    );
    return MergeSemantics(
      child: Semantics(
        button: id != null,
        label: '${person.name}, ${spokenFromDotted(detail)}',
        child: id == null
            ? body
            : InkWell(
                onTap: () => openTracearrPerson(context, id),
                child: body,
              ),
      ),
    );
  }
}

/// The line the removal of a title says of who watched it, from what the
/// page already read: `Watched by 3 people · last 12 days ago` or `Nobody has
/// watched it`. Null unless Tracearr answered for the title (not set up, not
/// answered, not known, or not read yet): the sheet then says nothing, since
/// not knowing is never "nobody".
String? mediaWatchedByNote(WidgetRef ref, MediaKey key, {DateTime? now}) {
  if (!ref
      .read(currentSettingsProvider)
      .isServiceConfigured(ServiceKey.tracearr)) {
    return null;
  }
  final watchers = ref.read(tracearrWatchedByProvider(key)).value;
  if (watchers == null) return null;
  return tracearrWatchedLine(
    tracearrWatchedPeople(watchers),
    now: now ?? DateTime.now(),
  );
}
