/// Now playing: who is watching what, on which screen, right now.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/pinned_image_cache.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/artwork_decode.dart';
import 'package:cupola/core/utils/service_routes.dart';
import 'package:cupola/features/home/data/home_live.dart';
import 'package:cupola/features/home/domain/home_module.dart';
import 'package:cupola/features/home/domain/now_playing.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_frame.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_image.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_navigation.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_person_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

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
    final servers = streamServersLabel(sessions);
    final note = offline.isEmpty ? null : nowPlayingOfflineSentence(silent);

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
              // The page that lists what the link counts: a media server's own.
              // A row only Tracearr sees leads to Tracearr's Live, which lists
              // Tracearr's streams and not these, so it is the target only when
              // no row of a media server is left to be one.
              onTap: () => _openSessions(
                context,
                sessions.firstWhere(
                  (row) => !row.isThrough,
                  orElse: () => sessions.first,
                ),
              ),
            ),
        ],
      ),
    );
  }

  static void _retry(WidgetRef ref) {
    // Every source of the list, Tracearr's too: its cached failure would
    // otherwise answer the read again.
    for (final source in homeSessionsSources) {
      ref.invalidate(source);
    }
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
    final line = nowPlayingLine(
      session,
      via: row.isThrough ? row.serverLabel : null,
    );

    void open() => _openSessions(context, row);
    final personId = _personDoor(ref, row);

    return Semantics(
      container: true,
      button: true,
      label: title,
      value: spokenFromDotted(line),
      onTap: open,
      // The door to the person is inside the row's own tap for a screen
      // reader: the visible disc is silenced with the rest of the row.
      customSemanticsActions: {
        if (personId != null)
          CustomSemanticsAction(
            label: 'Open ${session.userName} in Tracearr',
          ): () =>
              openTracearrPerson(context, personId),
      },
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
                  _PersonDisc(row: row, personId: personId),
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

/// The disc with who is watching: Tracearr's picture of them when it said one
/// of the playback, else their initial.
///
/// On a Plex row it is also the way to the person's page in Tracearr, when
/// Tracearr knows who they are: Plex has no Users tab for that door to sit in
/// (Jellyfin's and Emby's rows lead there), so the session row carries it.
/// Nothing is drawn of it otherwise.
///
/// The slot is one width for every row, a disc and the gap that follows it
/// ([_slot]), whether or not it is a button: a door that made its own row wider
/// would push that row's text out of line with the rest of the list. A button
/// takes the whole slot as its target, so it is 44pt without moving anything.
class _PersonDisc extends ConsumerWidget {
  const _PersonDisc({required this.row, required this.personId});

  final StreamActivityRow row;

  /// The Tracearr person the disc leads to, or null where it is no button.
  final String? personId;

  static const double _disc = 36;

  /// The disc and the gap before the text: 44pt, which is also the target of
  /// a door.
  static const double _slot = _disc + AppSpacing.sm;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = row.session;
    final initial = nowPlayingInitial(session);
    Widget disc = _Initial(initial: initial);
    // Only while Tracearr is still set up: a row outlives a connection that
    // was removed, and its client is not built for one that is gone.
    if (row.tracearr case final sight?
        when sight.avatarPath != null &&
            ref
                .watch(currentSettingsProvider)
                .isServiceConfigured(ServiceKey.tracearr)) {
      final client = ref.watch(tracearrClientForProvider(sight.instanceId));
      final avatar = resolveTracearrImage(sight.avatarPath, client.baseUri);
      if (avatar != null) {
        disc = _Initial(
          initial: initial,
          avatarUrl: avatar.toString(),
          avatarHeaders: client.imageHeaders,
        );
      }
    }
    final person = personId;
    final slot = SizedBox(
      width: _slot,
      height: person == null ? _disc : _slot,
      child: Align(alignment: Alignment.centerLeft, child: disc),
    );
    if (person == null) return slot;
    return InkResponse(
      onTap: () => openTracearrPerson(context, person),
      radius: _slot / 2,
      child: slot,
    );
  }
}

/// The Tracearr person a Plex row leads to, or null where there is no door:
/// another server's row, a row only Tracearr sees (its tap is Tracearr's Live
/// already), a Tracearr that is not set up, or a viewer it does not know.
String? _personDoor(WidgetRef ref, StreamActivityRow row) {
  if (row.service != ServiceKey.plex || row.isThrough) return null;
  if (!ref
      .watch(currentSettingsProvider)
      .isServiceConfigured(ServiceKey.tracearr)) {
    return null;
  }
  return ref
      .watch(
        tracearrPersonOfSessionProvider((
          service: row.service,
          userId: row.session.userId,
          name: row.session.userName,
        )),
      )
      .value;
}

/// The disc with who is watching's initial, or their picture over it.
class _Initial extends StatelessWidget {
  const _Initial({required this.initial, this.avatarUrl, this.avatarHeaders});

  final String initial;
  final String? avatarUrl;
  final Map<String, String>? avatarHeaders;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final url = avatarUrl;
    final letter = Text(
      initial,
      style: AppType.label.weight(FontWeight.w600).copyWith(color: room.ink),
    );
    return Container(
      width: 36,
      height: 36,
      alignment: Alignment.center,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: room.fillControl,
        shape: BoxShape.circle,
      ),
      child: url == null
          ? letter
          : ArtworkDecodeBox(
              builder: (context, decode) => CachedNetworkImage(
                imageUrl: url,
                httpHeaders: avatarHeaders,
                cacheManager: pinnedImageCacheFor(url),
                width: 36,
                height: 36,
                memCacheWidth: decode.width,
                memCacheHeight: decode.height,
                fit: BoxFit.cover,
                // The initial stands in while it loads and when it cannot: a
                // person has a letter whether or not Tracearr has a picture.
                placeholder: (context, _) => letter,
                errorWidget: (context, _, _) => letter,
              ),
            ),
    );
  }
}

/// The page of playbacks of the connection serving [row]: the media server's
/// own, or Tracearr's Live for one only Tracearr sees, which has no page of a
/// server Cupola is not connected to.
void _openSessions(BuildContext context, StreamActivityRow row) {
  if (row.isThrough) {
    context.go(ServiceRoutes.tracearrLive);
    return;
  }
  context.go(
    ServiceRoutes.streamActivity(row.service, instanceId: row.instanceId),
  );
}
