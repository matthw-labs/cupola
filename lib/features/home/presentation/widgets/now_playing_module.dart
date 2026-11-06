/// Now playing: who is watching what, on which screen, right now.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/domain/now_playing.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';

/// Now playing: every playback on every media server, one row each.
///
/// Absent when nobody is watching and every server answered, and without a
/// media server (Set up next names one). A server that did not answer
/// keeps the module in its place: nobody watching there is not known.
class HomeNowPlayingModule extends ConsumerWidget {
  const HomeNowPlayingModule({super.key});

  static const _title = 'Now playing';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(currentSettingsProvider);
    final services = HomeModule.nowPlaying.services
        .where(settings.isServiceConfigured)
        .toList(growable: false);
    if (services.isEmpty) return const SizedBox.shrink();

    // The last answer stands while the next one is read.
    final read = ref.watch(streamActivityProvider);
    final sessions = read.value;
    if (sessions == null) {
      if (read.hasError) {
        return HomeModuleFrame.silent(
          title: _title,
          coverage: SourceCoverage.merge([
            for (final service in services)
              SourceCoverage.failure(service, read.error),
          ]),
          onRetry: () => _retry(ref),
        );
      }
      return const HomeModuleFrame.loading(title: _title);
    }

    final offline = ref.watch(streamActivityOfflineProvider).value ?? const [];
    final silent = SourceCoverage.merge([
      for (final source in offline)
        SourceCoverage.failure(
          source.service,
          source.error,
          instanceId: source.instanceId,
          name: settings.connectionName(source.instanceId),
        ),
    ]);
    if (sessions.isEmpty) {
      if (offline.isEmpty) return const SizedBox.shrink();
      return HomeModuleFrame.silent(
        title: _title,
        coverage: silent,
        onRetry: () => _retry(ref),
      );
    }

    final shown = sessions.take(nowPlayingRowLimit).toList(growable: false);
    final servers = {
      for (final row in sessions) row.service.title,
    }.join(dotSeparator);
    final note = offline.isEmpty ? null : coverageFailureSentence(silent);

    return HomeModuleFrame(
      title: _title,
      subtitle: servers,
      semanticLabel: joinSpokenParts([
        _title,
        sessions.length == 1 ? '1 playing' : '${sessions.length} playing',
        ?note,
      ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null) HomeCoverageNote(note: note, coverage: silent),
          for (final (index, row) in shown.indexed)
            NowPlayingRow(
              key: ValueKey('${row.instanceId}-${row.session.id}'),
              row: row,
              divided: index > 0,
            ),
          if (sessions.length > shown.length)
            HomeModuleLink(
              label: 'See all ${sessions.length}',
              onTap: () => _openSessions(context, shown.first),
            ),
        ],
      ),
    );
  }

  static void _retry(WidgetRef ref) {
    ref.invalidate(streamSessionsForProvider);
    ref.invalidate(streamActivityProvider);
  }
}

/// One playback: who, what, on which screen and how long is left, over an
/// ink bar.
class NowPlayingRow extends ConsumerWidget {
  const NowPlayingRow({super.key, required this.row, this.divided = false});

  final StreamActivityRow row;

  /// Whether a hairline separates it from the row above.
  final bool divided;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final session = row.session;
    final title = nowPlayingTitle(session);
    final line = nowPlayingLine(session);

    void open() => _openSessions(context, row);

    return Semantics(
      container: true,
      button: true,
      label: title,
      value: spokenFromDotted(line),
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
              child: Row(
                children: [
                  _Initial(initial: nowPlayingInitial(session)),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.row
                              .weight(FontWeight.w600)
                              .copyWith(color: room.ink),
                        ),
                        if (line.isNotEmpty)
                          Text(
                            line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.meta.tabular.copyWith(
                              color: room.inkSecondary,
                            ),
                          ),
                        if (session.progress case final progress?) ...[
                          const SizedBox(height: 7),
                          // Ink: how far somebody got is not a status.
                          HomeRowBar(value: progress, color: room.ink),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The disc with who is watching's initial.
class _Initial extends StatelessWidget {
  const _Initial({required this.initial});

  final String initial;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: room.fillControl,
        shape: BoxShape.circle,
      ),
      child: Text(
        initial,
        style: AppType.label.weight(FontWeight.w600).copyWith(color: room.ink),
      ),
    );
  }
}

/// The media server's page of playbacks, on the connection serving [row].
void _openSessions(BuildContext context, StreamActivityRow row) {
  context.go(
    ServiceRoutes.streamActivity(row.service, instanceId: row.instanceId),
  );
}
