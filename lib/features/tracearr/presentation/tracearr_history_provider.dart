import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/activity/domain/activity_history.dart'
    show activityDayLabel;
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_history_filters.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_paging.dart';

/// The clock History's periods and day headings read, replaceable in tests.
final tracearrClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// The History tab's state: what was watched, newest first, a page at a time,
/// narrowed by [tracearrHistoryFiltersProvider].
///
/// Every filter is the server's: a change rebuilds the list from its first
/// page, and a next page that answers after the filter moved on is dropped
/// (`TracearrPagedList`). Nothing is ever trimmed from the pages already read,
/// which would show an empty list while older pages held plenty.
final tracearrHistoryProvider =
    AsyncNotifierProvider<
      TracearrHistoryList,
      TracearrRows<TracearrHistoryEntry>
    >(TracearrHistoryList.new, retry: noProviderRetry);

class TracearrHistoryList extends TracearrPagedList<TracearrHistoryEntry> {
  @override
  Future<TracearrRows<TracearrHistoryEntry>> build() {
    // Watched, so a new filter re-runs the build and reads from the top.
    ref.watch(tracearrHistoryFiltersProvider);
    return super.build();
  }

  @override
  Future<TracearrPage<TracearrHistoryEntry>> fetch(
    TracearrClient client,
    String? cursor,
  ) => client.getHistory(
    cursor: cursor,
    filter: ref
        .read(tracearrHistoryFiltersProvider)
        .toQuery(ref.read(tracearrClockProvider)()),
  );
}

/// One day of History: its heading and its viewings, newest first.
typedef TracearrHistoryDay = ({
  DateTime day,
  String label,
  List<TracearrHistoryEntry> entries,
});

/// [entries], newest first as Tracearr lists them, grouped by the day they
/// started on, **on this device's calendar**: a viewing at 23:50 UTC is
/// tomorrow's for someone an hour east of it, and the heading says the day
/// they lived.
///
/// Grouped by running along the list, not by sorting it: pages are read in
/// order, so a day continued on the next page is the same section and never
/// a second heading with its name. A viewing with no start time goes with the
/// one before it (or today's, first in the list), so it keeps its place.
List<TracearrHistoryDay> tracearrDaysOf(
  List<TracearrHistoryEntry> entries, {
  required DateTime now,
}) {
  final days = <TracearrHistoryDay>[];
  DateTime? current;
  for (final entry in entries) {
    final started = entry.startedAt?.toLocal();
    final day = started == null ? (current ?? _dayOf(now)) : _dayOf(started);
    if (current == null || day != current) {
      current = day;
      days.add((
        day: day,
        label: activityDayLabel(day, now: now),
        entries: <TracearrHistoryEntry>[],
      ));
    }
    days.last.entries.add(entry);
  }
  return days;
}

DateTime _dayOf(DateTime at) {
  final local = at.toLocal();
  return DateTime(local.year, local.month, local.day);
}
