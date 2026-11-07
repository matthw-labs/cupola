import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_image.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_media_stats.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_open.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_overview_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_session.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_session_sheet.dart';

/// The first tab of Tracearr's room: what the guardian sees at a glance.
///
/// The readouts above (streams now, today, unseen, servers) are
/// `serviceKpiProvider`'s. Under them four regions, each loading and failing
/// on its own, so a Tracearr that answers its servers and not its violations
/// still draws three and says so in the fourth:
///
///  * **Monitored servers**, with what Tracearr last saw of each. Tracearr's
///    `unknown` is a dash, never a state, and a server whose token Tracearr
///    holds was refused is amber with the remedy that only the owner can do,
///    in Tracearr;
///  * **Playing now**, the first three streams of Live, from the same list and
///    kept moving the same way while this page is on screen; each is a door to
///    the stream's detail;
///  * **Latest violations**, headed so, since its link to the Violations tab
///    would otherwise say the same word twice; the newest, in words and blue; each is a door to the
///    violation's own page;
///  * **Most watched this week**, left out altogether on a Tracearr older than
///    3.1.4, which has no such read.
///
/// **It draws neither the app bar nor the tab bar**: the service home owns
/// them and floats them above this page, which reserves their room with
/// [topPadding]. A violation row opens its detail.
class TracearrOverviewScreen extends StatelessWidget {
  const TracearrOverviewScreen({
    super.key,
    this.topPadding = ServiceOverviewPage.hostedTopPadding,
  });

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return ServiceOverviewPage(
      service: ServiceKey.tracearr,
      topPadding: topPadding,
      refresh: _refresh,
      sections: (ref) => const [
        SizedBox(height: 8),
        _ServersSection(),
        _PlayingSection(),
        _ViolationsSection(),
        _TopWeekSection(),
      ],
    );
  }
}

/// What a pull re-reads besides the readout (`ServiceOverviewPage`).
void _refresh(WidgetRef ref) {
  ref.invalidate(tracearrServersProvider);
  ref.invalidate(tracearrLiveProvider);
  ref.invalidate(tracearrLatestViolationsProvider);
  ref.invalidate(tracearrTopWeekProvider);
}

const _service = ServiceKey.tracearr;

// ─── 1. Monitored servers ───────────────────────────────────────────────────

class _ServersSection extends ConsumerWidget {
  const _ServersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final servers = ref.watch(tracearrServersProvider);
    return ServiceOverviewSection(
      service: _service,
      title: 'Monitored servers',
      subtitle: switch (servers.asData?.value) {
        final value? => countLabel(_monitored(value).length, 'server'),
        null => null,
      },
      child: AsyncValueWidget<TracearrServers>.section(
        value: servers,
        service: _service,
        consequence: 'the servers it watches are not shown',
        loadingLabel: 'Loading monitored servers',
        onRetry: () => ref.invalidate(tracearrServersProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (data) => _monitored(data).isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.dns_outlined,
          label: 'Tracearr watches no server yet',
        ),
        data: (data) => Column(
          children: [
            for (final server in _monitored(data)) _ServerRow(server: server),
          ],
        ),
      ),
    );
  }
}

/// The servers Tracearr polls. One kept only for its history is not watched,
/// so it is neither listed nor counted.
List<TracearrServer> _monitored(TracearrServers servers) => [
  for (final server in servers.servers)
    if (!server.historical) server,
];

/// What a server reads as, in the lexicon's words: Tracearr's own `unknown` is
/// a dash and not a state.
({String word, StatusTone? tone}) tracearrServerState(TracearrServer server) {
  if (server.isUnauthorized) {
    return (word: "Refused Tracearr's token", tone: StatusTone.warning);
  }
  return switch (server.status) {
    TracearrServerStatus.up => (
      word: StateWord.answering.label,
      tone: StateWord.answering.tone,
    ),
    TracearrServerStatus.down => (
      word: '${StateWord.didNotAnswer.label} Tracearr',
      tone: StateWord.didNotAnswer.tone,
    ),
    TracearrServerStatus.unknown => (word: Lexicon.noFigure, tone: null),
  };
}

class _ServerRow extends ConsumerWidget {
  const _ServerRow({required this.server});

  final TracearrServer server;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = tracearrServerState(server);
    final tone = statusToneColor(
      colorScheme,
      state.tone ?? StatusTone.neutral,
      surface: colorScheme.surfaceContainerLow,
    );
    final name = server.name.trim().isEmpty ? 'Unnamed server' : server.name;
    final kind = tracearrServerTypeWord(server.type);
    final detail = joinDisplayParts([kind, state.word]);
    return ServiceOverviewRow(
      spoken: joinSpokenParts([name, kind, state.word]),
      leading: Icon(Icons.dns_outlined, size: 18, color: tone),
      title: name,
      detail: detail,
      // Amber is the fault's, and the fault here is the owner's to mend, in
      // Tracearr: the one place Cupola can send them to.
      action: server.isUnauthorized
          ? ServiceOverviewRowAction.remedy(
              label: 'Fix it in Tracearr',
              hint: 'opens Tracearr in the browser',
              onPressed: () => openInTracearr(ref, tracearrServersWebPath),
            )
          : null,
    );
  }
}

// ─── 2. Playing now ─────────────────────────────────────────────────────────

class _PlayingSection extends ConsumerWidget {
  const _PlayingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The same rows as Live, kept moving while this page is the one on screen.
    ref.watchWhileLive(context, tracearrLiveFeedProvider);
    final streams = ref.watch(tracearrLiveProvider);
    return ServiceOverviewSection(
      service: _service,
      title: 'Playing now',
      subtitle: switch (streams.value) {
        final value? => countLabel(value.streams.length, 'stream'),
        null => null,
      },
      destination: ServiceTab.live,
      child: AsyncValueWidget<TracearrStreams>.section(
        value: streams,
        service: _service,
        consequence: 'what is playing is not shown',
        loadingLabel: 'Loading what is playing',
        onRetry: () => ref.invalidate(tracearrLiveProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (data) => data.streams.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.play_circle_outline_rounded,
          label: 'Nothing is playing',
        ),
        data: (data) => Column(
          children: [
            for (final stream in data.streams.take(3))
              _PlayingRow(
                stream: stream,
                // This section's own context and ref open the sheet: the
                // row goes when its stream stops, the section does not.
                onOpen: () => showTracearrSession(
                  context,
                  ref,
                  TracearrSession.live(stream),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A playing stream, a door to its detail. The title and the person are one
/// tap further, in the sheet, which knows whether the ids identify them.
class _PlayingRow extends ConsumerWidget {
  const _PlayingRow({required this.stream, required this.onOpen});

  final TracearrStream stream;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(tracearrClientProvider);
    final poster = resolveTracearrImage(stream.media.posterUrl, client.baseUri);
    final title = tracearrMediaTitleOf(stream.media);
    final detail = joinDisplayParts([
      tracearrPersonOf(stream.person),
      stream.device.name,
      stream.isPaused ? StateWord.paused.label : null,
      tracearrMethodWord(stream.quality),
    ]);
    return ServiceOverviewRow(
      spoken: joinSpokenParts([title, detail]),
      leading: ServiceOverviewArt(
        posterUrl: poster?.toString(),
        title: title,
        httpHeaders: poster == null ? null : client.imageHeaders,
      ),
      title: title,
      detail: detail,
      onTap: onOpen,
      doorHint: 'opens the details',
    );
  }
}

// ─── 3. Violations ──────────────────────────────────────────────────────────

class _ViolationsSection extends ConsumerWidget {
  const _ViolationsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latest = ref.watch(tracearrLatestViolationsProvider);
    final unseen = ref.watch(tracearrUnseenViolationsProvider).asData?.value;
    final count = unseen == null ? null : tracearrUnseenCount(unseen);
    return ServiceOverviewSection(
      service: _service,
      title: 'Latest violations',
      // A floor when more follow the page: the API gives no total.
      subtitle: count == null || count.count == 0
          ? null
          : '${count.isFloor ? Lexicon.floor(count.count) : count.count} unseen',
      destination: ServiceTab.violations,
      child: AsyncValueWidget<TracearrPage<TracearrViolation>>.section(
        value: latest,
        service: _service,
        consequence: 'the latest violations are not shown',
        loadingLabel: 'Loading violations',
        onRetry: () => ref.invalidate(tracearrLatestViolationsProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (data) => data.items.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.flag_outlined,
          label: 'No rule has been broken',
        ),
        data: (data) => Column(
          children: [
            for (final violation in data.items.take(
              kTracearrOverviewViolations,
            ))
              _ViolationRow(violation: violation),
          ],
        ),
      ),
    );
  }
}

class _ViolationRow extends StatelessWidget {
  const _ViolationRow({required this.violation});

  final TracearrViolation violation;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // Blue, whatever the severity: a rule was broken, which is the person's to
    // read, and nothing Cupola reaches has stopped working. An acknowledged
    // one has been read, and rests.
    final tone = statusToneColor(
      colorScheme,
      violation.isAcknowledged ? StatusTone.neutral : StatusTone.info,
      surface: colorScheme.surfaceContainerLow,
    );
    final severity = tracearrSeverityWord(violation.severity);
    final title = violation.rule.name.trim().isEmpty
        ? 'Violation'
        : violation.rule.name.trim();
    final when = violation.createdAt == null
        ? null
        : formatRelativeDateTime(violation.createdAt!);
    final detail = joinDisplayParts([
      tracearrPersonOf(violation.person),
      tracearrServerOf(violation.server),
      when,
    ]);
    return ServiceOverviewRow(
      spoken: joinSpokenParts([title, severity, detail]),
      leading: Icon(Icons.flag_outlined, size: 18, color: tone),
      title: title,
      titleColor: tone,
      detail: detail,
      trailing: severity,
      onTap: () => context.push(ServiceRoutes.tracearrViolation(violation.id)),
      doorHint: 'opens the violation',
    );
  }
}

// ─── 4. Most watched this week ──────────────────────────────────────────────

class _TopWeekSection extends ConsumerWidget {
  const _TopWeekSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final top = ref.watch(tracearrTopWeekProvider);
    // A Tracearr with no such read has no such section, which is not the same
    // as a week nobody watched anything.
    if (top.hasValue && top.requireValue == null) {
      return const SizedBox.shrink();
    }
    return ServiceOverviewSection(
      service: _service,
      title: 'Most watched this week',
      child: AsyncValueWidget<List<TracearrTopMedia>?>.section(
        value: top,
        service: _service,
        consequence: 'the most watched titles are not shown',
        loadingLabel: 'Loading the most watched titles',
        onRetry: () => ref.invalidate(tracearrTopWeekProvider),
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (data) => data == null || data.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.local_fire_department_outlined,
          label: 'Nothing has been watched this week',
        ),
        data: (data) => Column(
          children: [
            for (final title in data ?? const []) _TopRow(media: title),
          ],
        ),
      ),
    );
  }
}

class _TopRow extends StatelessWidget {
  const _TopRow({required this.media});

  final TracearrTopMedia media;

  @override
  Widget build(BuildContext context) {
    final title = media.title.trim().isEmpty ? 'Untitled' : media.title.trim();
    final detail = joinDisplayParts([
      countLabel(media.plays, 'play'),
      countLabel(media.uniqueUsers, 'viewer'),
    ]);
    return ServiceOverviewRow(
      spoken: joinSpokenParts([title, detail]),
      leading: ServiceOverviewArt(posterUrl: null, title: title),
      title: title,
      detail: detail,
    );
  }
}
