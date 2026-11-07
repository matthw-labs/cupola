/// Continue watching: what somebody started and did not finish.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/features/home/data/featured.dart';
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/home/data/last_known/featured_last_known.dart';
import 'package:cupola/features/home/data/home_layout_provider.dart';
import 'package:cupola/features/home/data/last_known/continue_watching_last_known.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/home/domain/continue_watching.dart';
import 'package:cupola/features/home/domain/featured.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/settings_return.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';

/// Continue watching: up to three titles started and not finished, on every
/// media server, each opening its page.
///
/// Absent when nothing is in progress and every server answered, when its
/// only title is already Featured's first slide, and without a media server
/// (Set up next names one). A server whose household member nobody chose
/// asks who you are, once.
class HomeContinueWatchingModule extends ConsumerWidget {
  const HomeContinueWatchingModule({super.key});

  static const _title = 'Continue watching';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final services = HomeModule.continueWatching.services
        .where(settings.isServiceConfigured)
        .toList(growable: false);
    if (services.isEmpty) return const SizedBox.shrink();

    // The live answer, or until it comes the last drawing (a cold start).
    final read = ref.watchOrLastKnown(
      homeResumeProvider,
      continueWatchingLastKnown,
    );
    final live = read.live;
    final known = read.asOf;
    final resume = read.value;
    SourceCoverage silentOf(Object? error) => SourceCoverage.merge([
      for (final service in services) SourceCoverage.failure(service, error),
    ]);
    void retry() => ref.invalidate(homeResumeProvider);
    if (resume == null) {
      if (live.hasError) {
        return HomeModuleFrame.silent(
          title: _title,
          coverage: silentOf(live.error),
          onRetry: retry,
        );
      }
      return const HomeModuleFrame.loading(title: _title);
    }

    // The live read failed, or answered with no server answering: a drawing
    // stands over it, in the live read's words.
    final liveFailed = live.hasError || read.silent;
    SourceCoverage failure() =>
        read.silent ? live.value!.coverage : silentOf(live.error);

    final coverage = resume.coverage;
    final asking = resume.viewerMissing.isEmpty
        ? null
        : _WhoAreYou(
            service: _askingService(settings, resume.viewerMissing.first),
            instanceId: resume.viewerMissing.first,
            name: resume.viewerMissing.length > 1
                ? null
                : settings.connectionName(resume.viewerMissing.first),
          );
    // Featured already leads with its only title: said once is enough.
    if (asking == null &&
        coverage.failed.isEmpty &&
        resume.rows.length == 1 &&
        _featuredLeadsWith(ref, resume.rows.single)) {
      return const SizedBox.shrink();
    }
    if (resume.rows.isEmpty && asking == null) {
      // A last drawing with nothing in it says nothing: loading, as if there
      // were none.
      if (known != null) {
        return liveFailed
            ? HomeModuleFrame.silent(
                title: _title,
                coverage: failure(),
                onRetry: retry,
              )
            : const HomeModuleFrame.loading(title: _title);
      }
      if (coverage.failed.isEmpty) return const SizedBox.shrink();
      return HomeModuleFrame.silent(
        title: _title,
        coverage: coverage,
        onRetry: retry,
      );
    }

    final shown = resume.rows
        .take(continueWatchingRowLimit)
        .toList(growable: false);
    final servers = {
      for (final row in shown) row.service.title,
      if (asking != null) asking.service.title,
    }.join(dotSeparator);
    final note = coverage.failed.isEmpty
        ? null
        : coverageFailureSentence(coverage);
    // The question about who you are is of the settings, not of a drawing:
    // only the titles are dated.
    final drawnAsOf = shown.isEmpty ? null : known;
    List<Widget> rows() => [
      for (final (index, row) in shown.indexed)
        ContinueWatchingRow(
          key: ValueKey('${row.instanceId}/${row.item.id}'),
          row: row,
          divided: index > 0,
        ),
      if (asking != null) ...[
        if (shown.isNotEmpty) const SizedBox(height: AppSpacing.sm),
        asking,
      ],
    ];

    // The last drawing whose live read failed: the rows it knew, at full ink,
    // over the failure in its own words.
    if (known != null && liveFailed) {
      return LastKnownMark(
        asOf: drawnAsOf,
        checking: false,
        child: HomeModuleFrame.silent(
          title: _title,
          coverage: failure(),
          onRetry: retry,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows(),
          ),
        ),
      );
    }

    return LastKnownMark(
      asOf: drawnAsOf,
      checking: true,
      child: HomeModuleFrame(
        title: _title,
        subtitle: servers,
        semanticLabel: joinSpokenParts([_title, ?note]),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (note != null) HomeCoverageNote(note: note, coverage: coverage),
            ...rows(),
            const SizedBox(height: AppSpacing.xs),
          ],
        ),
      ),
    );
  }
}

/// Whether Featured is on the Home and its first slide is [row].
bool _featuredLeadsWith(WidgetRef ref, ResumeRow row) {
  if (!ref.watch(homeLayoutProvider).shown.contains(HomeModule.featured)) {
    return false;
  }
  // Featured's drawn slides at a cold start, so a title it leads with is not
  // drawn here first and then taken away when its live slides come.
  final slides =
      ref.watch(featuredProvider).value ??
      ref.watch(homeLastKnownProvider(featuredLastKnown))?.value
          as List<FeaturedSlide>?;
  final first = slides?.firstOrNull;
  return first is FeaturedResume &&
      first.row.instanceId == row.instanceId &&
      first.row.item.id == row.item.id;
}

/// One title in progress: its picture, its name, the episode, how long is
/// left, over an ink bar.
class ContinueWatchingRow extends ConsumerWidget {
  const ContinueWatchingRow({
    super.key,
    required this.row,
    this.divided = false,
  });

  final ResumeRow row;

  /// Whether a hairline separates it from the row above.
  final bool divided;

  static const Size thumb = Size(112, 63);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final item = row.item;
    final title = resumeTitle(item);
    final detail = resumeDetail(item);
    final left = resumeLeft(item);
    final server = ref.watch(
      streamBackendOf(row.service).clientFor(row.instanceId),
    );
    final image = item.posterPath == null
        ? null
        : server.imageFor(item.posterPath!, width: 360);

    // At a large reading size the words take the slab's width under the
    // picture, rather than a third of it beside.
    final stacked = MediaQuery.textScalerOf(context).scale(1) > 1.3;
    final picture = ClipRRect(
      borderRadius: AppRadius.borderRadiusSm,
      child: SizedBox.fromSize(
        size: thumb,
        child: image == null
            ? ColoredBox(
                color: room.fillQuiet,
                child: Icon(
                  row.service.icon,
                  size: 20,
                  color: room.inkSecondary,
                ),
              )
            : ContentCard(imageUrl: image.url, httpHeaders: image.headers),
      ),
    );
    final words = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppType.row.weight(FontWeight.w600).copyWith(color: room.ink),
        ),
        if (detail.isNotEmpty)
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
        if (left != null)
          Text(
            left,
            maxLines: 1,
            style: AppType.meta.tabular
                .weight(FontWeight.w600)
                .copyWith(color: room.ink),
          ),
        if (item.resumeProgress case final progress?) ...[
          const SizedBox(height: 7),
          // Ink: how far somebody got is not a status.
          HomeRowBar(value: progress, color: room.ink),
        ],
      ],
    );

    Future<void> open() => openResume(context, row);

    return Semantics(
      container: true,
      button: true,
      label: title,
      value: joinSpokenParts([
        spokenFromDotted(detail),
        ?left,
        if (item.resumeProgress case final progress?)
          '${(progress * 100).round()} percent watched',
      ]),
      onTap: open,
      child: InkWell(
        onTap: open,
        excludeFromSemantics: true,
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: divided
                  ? Border(top: BorderSide(color: room.hair))
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.row),
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(alignment: Alignment.centerLeft, child: picture),
                        const SizedBox(height: AppSpacing.sm),
                        words,
                      ],
                    )
                  : Row(
                      children: [
                        picture,
                        const SizedBox(width: AppSpacing.md),
                        Expanded(child: words),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The service whose connection [instanceId] is, which a server that asks who
/// you are speaks as. A connection removed since the read falls back to the
/// first service that asks.
ServiceKey _askingService(SettingsModel settings, String instanceId) =>
    settings.instanceById(instanceId)?.service ??
    mediaServers.firstWhere((s) => s.needsViewerSelection);

/// The question a media server with no household member chosen asks, once:
/// `Which Jellyfin user are you?`, to the connection's form where the picker
/// is.
class _WhoAreYou extends ConsumerWidget {
  const _WhoAreYou({
    required this.service,
    required this.instanceId,
    required this.name,
  });

  /// The service asking, named in the question.
  final ServiceKey service;

  final String instanceId;

  /// What tells the connection apart, while the service has more than one.
  final String? name;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final server = [service.title, ?name].join(' ');
    final question = 'Which $server user are you?';
    const line = 'A server key sees every user; pick yours once';
    return Semantics(
      button: true,
      label: question,
      hint: line,
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadius.borderRadiusMd,
        onTap: () => openSettings(
          context,
          ref,
          to: ServiceRoutes.settingsForConnection(service, instanceId),
        ),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            borderRadius: AppRadius.borderRadiusMd,
            border: Border.all(color: room.hair),
          ),
          child: Row(
            children: [
              Icon(
                Icons.person_outline_rounded,
                size: 20,
                color: room.inkSecondary,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      question,
                      style: AppType.row
                          .weight(FontWeight.w600)
                          .copyWith(color: room.ink),
                    ),
                    Text(
                      line,
                      style: AppType.meta.copyWith(color: room.inkSecondary),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: room.inkSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A row's page: a movie's or a series' Media page with the connection it is
/// on leading, an episode's on its series' page at its season, else the
/// item's own page on its server (`OpenMedia.openStreamItem`).
Future<void> openResume(BuildContext context, ResumeRow row) =>
    context.openStreamItem(row.service, row.item, instanceId: row.instanceId);
