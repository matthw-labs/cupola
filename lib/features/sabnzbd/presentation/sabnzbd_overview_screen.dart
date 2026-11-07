import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/async_value_kept.dart';

import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_overview_provider.dart';
import 'package:cupola/features/sabnzbd/presentation/sabnzbd_provider.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The first tab of SABnzbd's service home.
///
/// Overview alone carries the identity block and the readouts: Queue, History
/// and Servers are each one kind of record, and then the two regions this
/// client can actually fill: **what is downloading now**, and **what finished
/// today, failures first**.
///
/// **Queue before History**, which is the board's order and the spine's: the
/// service's own work first, history last. On the wide artboard the queue is
/// the main column and history sits under it; on the narrow one the body is
/// composed fault card → queue → history, and the fault card, the disk-space
/// warning this client cannot fetch, is the only thing the board puts above
/// the queue. An earlier draft of this file had them the other way round and
/// described that as the board's order; it is not, and the description was the
/// worse half of the mistake.
///
/// **Servers now live on a dedicated tab**, backed by the configured server
/// reads and their independent volume report. The Overview does not duplicate
/// that table. Warnings remain absent because the current client does not ask
/// SABnzbd for the warning document; a fabricated disk-space alert would be
/// worse than an explicit omission.
///
/// **It draws neither the app bar nor the tab bar.** `ServiceHomeScreen` owns
/// the first and `ServiceTabScaffold` the second, both floated above this page
/// as glass bands so the ambient gradient reads continuously behind them; this
/// screen reserves the room with [topPadding] instead.
///
/// Sections load and fail independently: a SABnzbd that answers `mode=queue`
/// and not `mode=history` still draws its queue, and the region that could not
/// load says so in its own slot rather than taking the page down.
class SabnzbdOverviewScreen extends StatelessWidget {
  const SabnzbdOverviewScreen({
    super.key,
    this.topPadding = ServiceOverviewPage.hostedTopPadding,
  });

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return ServiceOverviewPage(
      service: ServiceKey.sabnzbd,
      topPadding: topPadding,
      kpis: (ref) =>
          ref.watch(sabnzbdQueueProvider).whenDataKept(sabnzbdOverviewReadouts),
      refresh: _refresh,
      sections: (ref) => [const _QueueSection(), const _HistoryTodaySection()],
    );
  }
}

/// What a pull re-reads besides the readout (`ServiceOverviewPage`).
void _refresh(WidgetRef ref) {
  // The two fetches, then the two derivations. Invalidating only the
  // derivations would recompute them over the cached payloads and leave
  // the page showing the same figures after a deliberate pull.
  ref.invalidate(sabnzbdQueueProvider);
  ref.invalidate(sabnzbdOverviewHistoryPageProvider);
  ref.invalidate(sabnzbdOverviewQueueProvider);
  ref.invalidate(sabnzbdOverviewHistoryProvider);
}

// ─── 1. Queue ───────────────────────────────────────────────────────────────

/// A section's failure in the header's words: `did not answer`, `refused
/// the key`, classified, so a refusal is never read as silence.
String _failureWord(Object? error) => Lexicon.inline(
  failureLabel(
    classifyConnectionFailure(error),
    credential: refusedCredentialOf(ServiceKey.sabnzbd),
    gateway: accessGatewayOf(error),
  ),
);

/// What is downloading now.
///
/// The board labels this region `Queue 4 · drag to reorder`. The handle is
/// **not** drawn: SABnzbd can reorder a queue (`mode=switch`), `SabnzbdClient`
/// cannot, and a drag that silently does nothing is the worst of the three
/// options. The words go with it: a caption promising a gesture that is not
/// wired is the same lie one step quieter.
class _QueueSection extends ConsumerWidget {
  const _QueueSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(sabnzbdOverviewQueueProvider);
    final data = section.asData?.value;

    return ServiceOverviewSection(
      service: ServiceKey.sabnzbd,
      title: 'Queue',
      // `4 jobs · 18.6 GB left · paused`. Paused is stated, never coloured: the
      // user pressed it, and it is the one fact the readout band cannot show
      // now that Speed reads a legitimate `0 B/s`.
      //
      // `not answering` rather than an em dash after a failure, and no subtitle
      // at all while it loads, for the reason the History header gives: the
      // header is spoken as "Queue, <subtitle>", and a dash is heard as nothing
      // or as "em dash" (where the job count is simply not known yet, saying
      // nothing is the truthful shape).
      subtitle: section.hasError && data == null
          ? _failureWord(section.error)
          : data == null
          ? null
          : joinDisplayParts([
              data.total == 1 ? '1 job' : '${data.total} jobs',
              data.sizeLeftLabel,
              if (data.paused) StateWord.stopped.inline,
            ]),
      destination: ServiceTab.queue,
      child: AsyncValueWidget<SabnzbdQueueSection>.section(
        value: section,
        service: ServiceKey.sabnzbd,
        consequence: 'its queue is not shown',
        loadingLabel: 'Loading the queue',
        onRetry: () => ref.invalidate(sabnzbdQueueProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (value) => value.rows.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.download_done_rounded,
          label: 'Nothing in the queue',
        ),
        data: (value) => Column(
          children: [for (final row in value.rows) _QueueRow(row: row)],
        ),
      ),
    );
  }
}

class _QueueRow extends StatelessWidget {
  const _QueueRow({required this.row});

  final SabnzbdQueueRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(
      colorScheme,
      row.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: row.spoken,
      leading: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 5),
        decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
      ),
      title: row.name,
      // A failed job is the reason this section is on the page at all; a queued
      // one, or one par2 is repairing on its way to done, is not, and only the
      // fault takes the ink.
      titleColor: row.isFault ? tone : null,
      detail: row.detail,
      // The progress figure the board draws on the right of each row. The
      // per-job *rate* beside it on the board is not here: SABnzbd reports one
      // rate for the whole queue, so a per-row one could only be invented.
      trailing: row.percentLabel,
    );
  }
}

// ─── 2. History today ───────────────────────────────────────────────────────

/// What finished today, failures first.
class _HistoryTodaySection extends ConsumerWidget {
  const _HistoryTodaySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final section = ref.watch(sabnzbdOverviewHistoryProvider);
    final data = section.asData?.value;

    return ServiceOverviewSection(
      service: ServiceKey.sabnzbd,
      title: 'History',
      // `today · 12 completed · 1 failed`, over the whole window rather than
      // over the four rows drawn.
      //
      // The `+` is the honest half: SABnzbd answers a page, and when that page
      // never reached yesterday the counts are a floor rather than the day, so
      // the header reads `today · 100+ completed` instead of a total the fetch
      // cannot stand behind. See `SabnzbdHistorySection.dayCovered`.
      //
      // A word, never an em dash, in the two states with no counts: the header
      // is read out as "History, <subtitle>", and "History, em dash" is what a
      // listener gets where a viewer at least sees a skeleton. `today` is true
      // while it loads, and `not answering` is true after it failed. The
      // failure clause disappears at zero: `0 failed` is the normal state of a
      // healthy day and does not deserve a place in a header.
      subtitle: section.hasError && data == null
          ? _failureWord(section.error)
          : data == null
          ? 'today'
          : joinDisplayParts([
              'today',
              '${data.completed}${data.dayCovered ? '' : '+'} completed',
              if (data.failed > 0)
                '${data.failed}${data.dayCovered ? '' : '+'} failed',
            ]),
      destination: ServiceTab.history,
      child: AsyncValueWidget<SabnzbdHistorySection>.section(
        value: section,
        service: ServiceKey.sabnzbd,
        consequence: "today's downloads are not shown",
        loadingLabel: "Loading today's downloads",
        onRetry: () => ref.invalidate(sabnzbdOverviewHistoryPageProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (value) => value.rows.isEmpty,
        // Nothing failed and nothing is missing: the day has simply been quiet,
        // and saying so is not an error state.
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.history_rounded,
          label: 'Nothing finished today',
        ),
        data: (value) => Column(
          children: [for (final entry in value.rows) _HistoryRow(entry: entry)],
        ),
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry});

  final SabnzbdHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a raw `AppColors.*`: the walk is what keeps
    // amber legible on the light theme's paper, where the raw token sits at
    // 2.4:1.
    final tone = statusToneColor(
      colorScheme,
      entry.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: entry.spoken,
      // A dot rather than a glyph per state. SABnzbd's status vocabulary is
      // open-ended (it gains words between releases), and an icon table that
      // has to guess for an unknown one draws a picture that is wrong rather
      // than absent. The state is in the detail line as a word, so the colour
      // is a scan marker and not the only channel.
      leading: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 5),
        decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
      ),
      title: '${entry.name}\u00A0· ${entry.event}',
      // Only a fault colours its title. A completed row is the resting state of
      // this section and wearing green ink would make a quiet day look like an
      // announcement.
      titleColor: entry.failed ? tone : null,
      detail: entry.detail,
    );
  }
}
