import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/room_art.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/title_light.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/data/jellyfin_client.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/plex/presentation/plex_capability.dart';
import 'package:cupola/features/plex/presentation/plex_provider.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_semantics.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';
import 'package:cupola/features/stream/presentation/stream_session_poster.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_message_prompt.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_session_card.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_session_slab.dart';

/// Who is watching, right now: the one thing only a media server knows.
///
/// **A section rather than a screen, and that is the point of the file.** Every
/// other domain in Cupola answers questions about objects (is this film owned,
/// grabbed, subtitled, on disk); Jellyfin and Plex are the only source of
/// subject-and-time state: who is watching, where they stopped, what is next
/// for them. That belongs at the top of the service's Overview, above whatever
/// readouts the board grows, and it is built here so the Overview composes it
/// instead of rewriting three controls whose rules took a live server to learn.
///
/// **The caller passes the sessions and therefore owns the configuration
/// check.** A media server that is not set up has no sessions to be idle about,
/// and a `FutureProvider` that throws "not configured" is a *failed* provider
/// that retries on a backoff no waiting changes. So the host reads
/// `jellyfinSessionsProvider` / `plexSessionsProvider` only once
/// `isServiceConfigured` says there is something to read.
///
/// **What this deliberately does not have: a total.** An earlier design opened
/// on an aggregate "egress" figure, on the theory that streams are the mirror of
/// the download rate. That figure does not exist. Jellyfin reports a bitrate only
/// while transcoding. A direct play carries none, so the only number available
/// is the source file's own, and Plex's `Session.bandwidth` is a reservation
/// made by its streaming brain. Summing those adds two different units together
/// and presents the result as the box's outbound traffic, which would be
/// fabricated. Per-session figures live on the cards, where
/// `StreamSession.bitrateIsNominal` can say what they actually are.
///
/// **Idle is the majority state and is built first.** Nobody watching is not an
/// empty state and not a failure: it is a quiet room, and on a home server it is
/// the normal condition. It gets one line.
class StreamNowPlayingSection extends ConsumerWidget {
  /// The playbacks as cards, for the page that lists them (a media server's
  /// Activity tab).
  const StreamNowPlayingSection({
    super.key,
    required this.service,
    required this.sessions,
    this.instanceId = '',
  }) : _slab = false;

  /// The region of a media server's Overview: a slab lit by the first title,
  /// with the way to the tab that lists the playbacks. One playback is drawn
  /// large with its picture ([StreamSessionFeature]), several as lines
  /// ([StreamSessionLine]); each keeps the controls the server allows.
  const StreamNowPlayingSection.slab({
    super.key,
    required this.service,
    required this.sessions,
    this.instanceId = '',
  }) : _slab = true;

  final bool _slab;

  final ServiceKey service;

  /// The connection [sessions] were read from, and where Stop, Pause and
  /// Message go; empty is the active one.
  final String instanceId;
  final AsyncValue<List<StreamSession>> sessions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // A Plex token refused the sessions may be a shared account's, which is
    // not a fault: only the owner's token sees who is watching. The probe
    // says whose it is; until it has, the region keeps loading rather than
    // drawing a refusal it may take back a moment later.
    var value = sessions;
    var ownerOnly = false;
    if (service == ServiceKey.plex && sessions.hasError && !sessions.hasValue) {
      switch (plexSessionsRefusal(
        ref,
        instanceId.isEmpty
            ? capabilityConnectionId(ref, ServiceKey.plex)
            : instanceId,
        sessions.error,
      )) {
        case PlexSessionsRefusal.ownerOnly:
          ownerOnly = true;
        case PlexSessionsRefusal.pending:
          value = const AsyncLoading<List<StreamSession>>();
        case PlexSessionsRefusal.failure:
          break;
      }
    }

    if (_slab) return _slabOf(context, ref, value, ownerOnly: ownerOnly);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The header carries the page inset itself.
        const SectionHeader(title: 'Now playing', showChevron: false),
        if (ownerOnly)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: PlexOwnerOnlyNote(),
          )
        else
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: AsyncValueWidget<List<StreamSession>>(
              value: value,
              serviceName: service.title,
              instanceId: instanceId,
              onRetry: () => refreshStreamSessions(ref, service, instanceId),
              isEmpty: (list) => list.isEmpty,
              emptyBuilder: const _IdleRoom(),
              data: (list) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < list.length; i++)
                    Padding(
                      padding: EdgeInsets.only(
                        bottom: i == list.length - 1 ? 0 : AppSpacing.md,
                      ),
                      child: StaggeredEntrance(
                        index: i,
                        child: _litCard(
                          ref,
                          list[i],
                          (poster, headers, light) => StreamSessionCard(
                            session: list[i],
                            accent: service.accent,
                            posterUrl: poster,
                            posterHeaders: headers,
                            light: light,
                            onStop: _stopHandler(context, ref, list[i]),
                            onTogglePause: _pauseHandler(context, ref, list[i]),
                            onMessage: _messageHandler(context, ref, list[i]),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// The Overview's slab: see [StreamNowPlayingSection.slab].
  Widget _slabOf(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<List<StreamSession>> value, {
    required bool ownerOnly,
  }) {
    final tab = switch (service) {
      ServiceKey.plex => ServiceTab.activities,
      ServiceKey.jellyfin || ServiceKey.emby => ServiceTab.activity,
      _ => throw ArgumentError.value(
        service.name,
        'service',
        'has no playback tab',
      ),
    };
    final first = value.value?.firstOrNull;
    return ServiceOverviewSection(
      service: service,
      title: 'Now playing',
      destination: tabsFor(service)?.contains(tab) ?? false ? tab : null,
      light: first == null ? null : _lightOf(ref, first),
      child: ownerOnly
          ? const PlexOwnerOnlyNote()
          : AsyncValueWidget<List<StreamSession>>(
              value: value,
              serviceName: service.title,
              instanceId: instanceId,
              onRetry: () => refreshStreamSessions(ref, service, instanceId),
              isEmpty: (list) => list.isEmpty,
              emptyBuilder: const _IdleRoom(),
              data: (list) => list.length == 1
                  ? StreamSessionFeature(
                      session: list.single,
                      picture: _pictureOf(ref, list.single, wide: true),
                      onStop: _stopHandler(context, ref, list.single),
                      onTogglePause: _pauseHandler(context, ref, list.single),
                      onMessage: _messageHandler(context, ref, list.single),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < list.length; i++) ...[
                          if (i > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.md,
                              ),
                              child: Divider(
                                height: 1,
                                color: CupolaRoom.of(context).hair,
                              ),
                            ),
                          StreamSessionLine(
                            session: list[i],
                            picture: _pictureOf(ref, list[i], wide: false),
                            onStop: _stopHandler(context, ref, list[i]),
                            onTogglePause: _pauseHandler(context, ref, list[i]),
                            onMessage: _messageHandler(context, ref, list[i]),
                          ),
                        ],
                      ],
                    ),
            ),
    );
  }

  /// The public poster the arrs hold for [session]'s title, or null.
  String? _publicPosterOf(WidgetRef ref, StreamSession session) {
    final title = streamSessionTitleOf(service, instanceId, session);
    return title == null
        ? null
        : ref.watch(streamSessionPosterProvider(title)).value;
  }

  /// The light of [session]'s title: from its public poster only.
  RoomArt? _lightOf(WidgetRef ref, StreamSession session) {
    final public = _publicPosterOf(ref, session);
    return public == null
        ? null
        : ref.watch(titleLightProvider(public)).value?.art;
  }

  /// What [session] is drawn with in the slab: the server's wide artwork
  /// through its key, else the public poster, else the server's poster.
  StreamSessionPicture? _pictureOf(
    WidgetRef ref,
    StreamSession session, {
    required bool wide,
  }) {
    final client = ref.watch(
      streamClientForProvider((service: service, instanceId: instanceId)),
    );
    final width = wide ? _featureWidth : _lineWidth;
    final backdrop = session.backdropPath;
    if (backdrop != null && backdrop.isNotEmpty) {
      if (client.imageFor(backdrop, width: width) case final source?) {
        return (url: source.url, headers: source.headers);
      }
    }
    if (_publicPosterOf(ref, session) case final public?) {
      return (url: public, headers: null);
    }
    final poster = session.posterPath;
    if (poster == null || poster.isEmpty) return null;
    final source = client.imageFor(poster, width: width);
    return source == null ? null : (url: source.url, headers: source.headers);
  }

  /// How wide the slab's pictures are asked for, at three pixels a point:
  /// the one playback across the slab, a line's thumbnail.
  static const int _featureWidth = 1080;
  static const int _lineWidth = 336;

  /// [session]'s card, given its poster and its light: the public poster the
  /// arrs hold for its title, which it glows with, else the server's own
  /// artwork through its key, which lights nothing.
  Widget _litCard(
    WidgetRef ref,
    StreamSession session,
    Widget Function(
      String? poster,
      Map<String, String>? headers,
      RoomArt? light,
    )
    card,
  ) {
    final title = streamSessionTitleOf(service, instanceId, session);
    final public = title == null
        ? null
        : ref.watch(streamSessionPosterProvider(title)).value;
    if (public != null) {
      return card(
        public,
        null,
        ref.watch(titleLightProvider(public)).value?.art,
      );
    }
    final path = session.posterPath;
    final own = path == null || path.isEmpty
        ? null
        : ref
              .watch(
                streamClientForProvider((
                  service: service,
                  instanceId: instanceId,
                )),
              )
              .imageFor(path, width: _posterWidth);
    return card(own?.url, own?.headers, null);
  }

  /// How wide the server's own artwork is asked for: the card's 36pt poster
  /// at three pixels a point.
  static const int _posterWidth = 108;

  /// The stop control, or null when stopping is not available.
  ///
  /// Plex gates termination behind Plex Pass, and answers a server without it
  /// with a 401 that has nothing to do with the token. Reading the flag first
  /// means the control is simply absent rather than present-and-misleading, and
  /// a user who taps it never gets sent off to re-paste a credential that was
  /// fine. A session with no server-side id cannot be terminated at all, which is
  /// a real Plex shape, not a defensive guard.
  ///
  /// **Through [plexStopOfferedProvider], the one gate Activity reads too.**
  /// Each surface used to derive its own, and they disagreed: this one treated
  /// a sheet still loading as available, Activity as refused, so the same
  /// session had Stop here and none there. This section reads the lens, which is
  /// the connection its sessions come from.
  VoidCallback? _stopHandler(
    BuildContext context,
    WidgetRef ref,
    StreamSession session,
  ) {
    if (session.id.isEmpty) return null;

    if (service == ServiceKey.plex &&
        !ref.watch(plexStopOfferedProvider(instanceId))) {
      return null;
    }

    return () => _confirmStop(context, ref, session);
  }

  /// Pause / resume, and only on a server that speaks the MediaBrowser API
  /// ([ServiceKeyExtension.speaksMediaBrowser]).
  ///
  /// `/Sessions/{id}/Playing/Pause` is a Jellyfin remote-control command relayed
  /// over the WebSocket the server already holds to that client. Plex has no
  /// equivalent this app can reach: its player routes address the client
  /// directly on the LAN, so the board keeps **stop alone** there rather than
  /// drawing two controls that would fail. Absent, not dimmed: a dimmed control
  /// promises a way to enable it, and there is none.
  VoidCallback? _pauseHandler(
    BuildContext context,
    WidgetRef ref,
    StreamSession session,
  ) {
    if (!service.speaksMediaBrowser || session.id.isEmpty) return null;
    return () => _togglePause(context, ref, session);
  }

  /// Send a line of text to the player. Only where [_pauseHandler] is, for the
  /// same reason.
  VoidCallback? _messageHandler(
    BuildContext context,
    WidgetRef ref,
    StreamSession session,
  ) {
    if (!service.speaksMediaBrowser || session.id.isEmpty) return null;
    return () => _sendMessage(context, ref, session);
  }

  /// The client that takes Pause and Message for this connection: the
  /// MediaBrowser one (Jellyfin's or Emby's), because those commands are not on `StreamServerClient` (Plex has no
  /// counterpart). Only reached behind [_pauseHandler] and [_messageHandler],
  /// so a service that cannot is a bug and says so rather than being handed
  /// another server's client.
  MediaBrowserClient _remoteOf(WidgetRef ref) {
    if (!service.speaksMediaBrowser) {
      throw UnsupportedError('${service.name} takes no remote control');
    }
    return ref.read(
      mediaBrowserProvidersOf(service).client.forConnection(instanceId),
    );
  }

  /// Pausing asks nobody: it is the one control here that is instantly
  /// reversible by the person it happens to, and a confirm on it would be
  /// ceremony. Stopping and messaging both ask, because neither is.
  Future<void> _togglePause(
    BuildContext context,
    WidgetRef ref,
    StreamSession session,
  ) async {
    final client = _remoteOf(ref);
    try {
      if (session.isPaused) {
        await client.unpauseSession(session.id);
      } else {
        await client.pauseSession(session.id);
      }
      // Re-read rather than flipping `isPaused` here: the 204 means the command
      // was dispatched to the client, not that the client acted on it.
      refreshStreamSessions(ref, service, instanceId);
    } catch (error) {
      if (!context.mounted) return;
      final failed = session.isPaused
          ? 'Could not resume playback'
          : 'Could not pause playback';
      SnackBarHelper.error(
        context,
        '$failed. ${writeFailureReason(service, error)}',
        cause: error,
      );
    }
  }

  Future<void> _sendMessage(
    BuildContext context,
    WidgetRef ref,
    StreamSession session,
  ) async {
    final text = await showStreamMessagePrompt(
      context: context,
      userName: session.userName,
      playerLabel: session.deviceLabel,
    );
    if (text == null || !context.mounted) return;

    try {
      await _remoteOf(ref).sendMessage(session.id, text: text);
      if (!context.mounted) return;
      // "Sent", never "delivered": the server relays it and the client decides
      // whether it has anywhere to draw it. Claiming delivery would be the same
      // overstatement the stop dialog's note exists to avoid.
      SnackBarHelper.success(context, 'Message sent to ${session.userName}');
    } catch (error) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        'Could not send the message. '
        '${writeFailureReason(service, error)}',
        cause: error,
      );
    }
  }

  Future<void> _confirmStop(
    BuildContext context,
    WidgetRef ref,
    StreamSession session,
  ) async {
    final result = await showAppConfirmDialog(
      context: context,
      title: 'Stop playback?',
      // Both servers only *dispatch* a stop, and the viewer can simply press
      // play again, so the sentence says that rather than anything about
      // undoing. Overstating it would make an ordinary courtesy feel like a
      // purge.
      message:
          '${streamStopSessionPrompt(userName: session.userName, title: session.title)} '
          'They can start it again straight away.',
      icon: Icons.stop_circle_outlined,
      confirmLabel: 'Stop playback',
    );
    if (!result.confirmed || !context.mounted) return;

    try {
      final client = ref.read(
        streamClientForProvider((service: service, instanceId: instanceId)),
      );
      await client.stopSession(session.id);
      // Both servers only *dispatch* a stop: Jellyfin's 204 means "sent to the
      // client", which may ignore it. So the board re-reads rather than removing
      // the row optimistically and claiming something it cannot know.
      refreshStreamSessions(ref, service, instanceId);
    } catch (error) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        'Could not stop playback. ${writeFailureReason(service, error)}',
        cause: error,
      );
    }
  }
}

/// Nobody watching.
///
/// Not `AppEmptyState` with a "nothing here" glyph and not an error: the server
/// answered, and an idle media server is the normal daily condition rather than a
/// state the user needs to fix. One quiet line, in the same register the
/// `/services` outage notice uses for a fault that is normal for the product.
///
/// **A dashed rule, and that is the whole shape of it.** A well (a filled box
/// with a centred glyph and a sentence) is how this surface reads when
/// something is missing, and nothing is missing here. The dash says the region
/// exists and is empty by nature, the way an outline on a plan says "this space
/// is reserved" rather than "this space failed".
class _IdleRoom extends StatelessWidget {
  const _IdleRoom();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: Row(
        children: [
          Icon(Icons.nights_stay_outlined, size: 16, color: color),
          const SizedBox(width: AppSpacing.sm),
          // The sentence takes the line before the dash does: at an even
          // split it broke in two beside half a line of scenery.
          Flexible(
            flex: 4,
            child: Text(
              streamIdleMessage,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // The dash carries no information, so it is hidden from the screen
          // reader: `streamIdleMessage` already says the room is quiet, and a
          // second node announcing a line would only lengthen the sentence.
          Expanded(
            child: ExcludeSemantics(
              child: CustomPaint(
                // A height rather than a `SizedBox.shrink`: a `CustomPaint`
                // with no child takes its size from the parent, and inside a
                // `Row` that is an unbounded cross axis.
                size: const Size.fromHeight(1),
                painter: _DashedRulePainter(
                  // Dimmer than the text it trails, because it is scenery: at
                  // the text's own weight it reads as a divider between two
                  // regions, and there is only one region here.
                  color: color.withValues(alpha: 0.4),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The hairline that trails the idle sentence.
///
/// Local to this file on purpose. There is no dashed primitive in
/// `lib/core/widgets/`, and one line on one screen does not earn a shared
/// widget. The moment a second surface wants dashes, this is what moves.
class _DashedRulePainter extends CustomPainter {
  const _DashedRulePainter({required this.color});

  final Color color;

  /// Dash and gap, in logical pixels. Even-length dashes on an even gap read as
  /// a deliberate rule; anything finer disappears on a low-density display.
  static const double _dash = 4;
  static const double _gap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final y = size.height / 2;
    for (var x = 0.0; x < size.width; x += _dash + _gap) {
      final end = (x + _dash).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, y), Offset(end, y), paint);
    }
  }

  @override
  bool shouldRepaint(_DashedRulePainter oldDelegate) =>
      oldDelegate.color != color;
}
