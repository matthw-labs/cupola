import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderBase;

import 'package:cupola/core/capability/connection_capability.dart';
import 'package:cupola/core/lifecycle/gated_poll.dart';
import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/plex/presentation/plex_capability.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_activity_row.dart';
import 'package:cupola/features/stream/presentation/stream_activity_merge.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_sessions_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_stream_session.dart';

export 'package:cupola/features/stream/domain/stream_activity_row.dart';

/// A connection whose sessions could not be read, as the note
/// names it, and the failure, which the note classifies: a server that did
/// not answer and one that refused the token are said differently.
typedef StreamOfflineSource = ({
  ServiceKey service,
  String instanceId,
  String title,
  Object error,
});

/// One connection of a service that says who is playing: a media server, or
/// Tracearr.
typedef StreamConnection = ({ServiceKey service, String instanceId});

/// What is playing on one named connection of a media server.
///
/// A Tracearr connection reads the streams it sees
/// ([tracearrStreamsForProvider]) as sessions, the connection in view
/// collapsing onto the Live list.
///
/// The lens's own connection collapses onto the service's sessions provider
/// ([StreamBackend.sessions]: `jellyfinSessionsProvider`,
/// `plexSessionsProvider`), so the service's own Now playing page and Activity
/// read one cache and an override of either still reaches both. Every other
/// connection asks its own client. Read by both [streamActivityProvider] and
/// [streamActivityOfflineProvider], so a second Jellyfin is asked once.
final streamSessionsForProvider =
    FutureProvider.family<List<StreamSession>, StreamConnection>((
      ref,
      key,
    ) async {
      // Tracearr is not a media server: it has no backend, and never reaches
      // one. Its own arm reads its streams and says them as sessions.
      if (key.service == ServiceKey.tracearr) {
        final streams = await ref.watch(
          tracearrStreamsForProvider(key.instanceId).future,
        );
        return streams.streams.map(tracearrStreamSession).toList();
      }
      final backend = streamBackendOf(key.service);
      final lens = ref.watch(activeInstanceProvider(key.service))?.id ?? '';
      if (key.instanceId.isEmpty || key.instanceId == lens) {
        return ref.watch(backend.sessions.future);
      }
      return ref.watch(backend.clientFor(key.instanceId)).getSessions();
    }, retry: noProviderRetry);

/// How often a media server's own pages read its sessions again while seen.
const streamSessionsInterval = Duration(seconds: 15);

/// The poll that keeps one connection's sessions current, for the media
/// server's Overview and its playback tab to watch while they are the page on
/// screen (`watchWhileLive`).
///
/// It reads again the one request behind the connection's answer: for the
/// lens the cache [streamSessionsForProvider] collapses onto (which carries
/// that family with it), so the room's figure, its Now playing and its light,
/// which all read that one answer, move together; for any other connection
/// the family itself. Skipped while that read is still out, as the Home's
/// (`readAgainUnlessInFlight`). Not the lens's family beside its cache: it
/// waits on the cache, so it reads as loading whenever the cache is, and
/// asking it skipped the tick that should have read the cache again.
///
/// The lens's cache lives as long as the app, so a room opened after the Home
/// read it finds an answer of any age: the poll then reads again at once
/// rather than an interval later, or the room said `0 streams` over a
/// playback that had started since. A room opened cold is loading its own
/// read, and the in-flight skip leaves that one alone.
final streamSessionsPollProvider = Provider.autoDispose
    .family<void, StreamConnection>((ref, key) {
      // Tracearr's list is moved by the live feed and by reading it again,
      // which is the notifier's own `refresh`: invalidating a read over that
      // list would hand back what it already holds.
      final isTracearr = key.service == ServiceKey.tracearr;

      // Asked on every tick and never once at build: the lens moves while the
      // poll lives (a room or the Stack keeps it), and a tick that remembered
      // the lens it was built under would refresh the connection that left the
      // view and leave the one that entered it unread.
      bool inView() {
        final lens = ref.read(activeInstanceProvider(key.service))?.id ?? '';
        return key.instanceId.isEmpty || key.instanceId == lens;
      }

      ProviderBase<AsyncValue<Object?>> source() {
        if (isTracearr) {
          return inView()
              ? tracearrLiveProvider
              : tracearrStreamsForProvider(key.instanceId);
        }
        if (!inView()) return streamSessionsForProvider(key);
        return streamBackendOf(key.service).sessions;
      }

      final read = source();
      ref.gatedPoll(
        id: 'stream.sessions.${key.service.name}.${key.instanceId}',
        interval: streamSessionsInterval,
        dueNow: ref.exists(read) && !ref.read(read).isLoading,
        onTick: () {
          if (isTracearr && inView()) {
            unawaited(ref.read(tracearrLiveProvider.notifier).refresh());
          } else {
            ref.readAgainUnlessInFlight([source()]);
          }
        },
      );
    });

/// Every configured connection of the media servers, in registry and then
/// the user's order, with what a row calls it.
List<({StreamConnection key, String? name})> _streamConnections(Ref ref) {
  final settings = ref.watch(currentSettingsProvider);
  return [
    for (final service in sessionServices)
      for (final instance in settings.configuredInstancesOf(service))
        (
          key: (service: service, instanceId: instance.id),
          name: settings.connectionName(instance.id),
        ),
  ];
}

/// The names of each service's connections that have one, lower-cased: what
/// a Tracearr server's own name is compared with when it is told which of
/// two connections of a service a stream is on
/// (`SettingsModel.connectionName` is null for a service with only one).
Map<ServiceKey, Set<String>> _connectionNames(Ref ref) {
  final settings = ref.watch(currentSettingsProvider);
  final names = <ServiceKey, Set<String>>{};
  for (final service in mediaServers) {
    for (final instance in settings.configuredInstancesOf(service)) {
      final name = settings.connectionName(instance.id)?.trim().toLowerCase();
      if (name != null && name.isNotEmpty) {
        (names[service] ??= {}).add(name);
      }
    }
  }
  return names;
}

/// Whether a connection whose sessions read failed is a Plex holding a shared
/// account's token: not a server that is down or refused, one whose sessions
/// only the owner sees. Asks the probe.
Future<bool> _ownerOnly(Ref ref, StreamConnection key, Object error) async =>
    key.service == ServiceKey.plex &&
    await plexSessionsOwnerOnly(
      () => ref.watch(connectionCapabilityProvider(key.instanceId).future),
      error,
    );

/// Every live playback across every connection of the media servers and of
/// Tracearr, most expensive first, each said once.
///
/// **One merged source, built here and never in a widget**, so Now playing,
/// Watching now and everything else that counts playbacks count the same rows.
/// The media servers' own rows come first; what Tracearr sees is folded into
/// them by [mergeTracearrStreams] (a playback both describe is one row, the
/// server's own, enriched; one only Tracearr sees is appended, marked as
/// coming through it). Without a Tracearr connection nothing changes, and
/// with only Tracearr the rows are all its own.
///
/// **Deliberately not a `GlobalActivityItem`, and this is the load-bearing
/// decision on this surface.** Forcing a session into that model needs a
/// `ServiceType`, which is a closed `{movies, series, music, discover}` with no
/// legal value for a media server, and adding one breaks **21 exhaustive
/// switches** across the activity feature, plus 6 more on `GlobalActivityKind`,
/// two of which have `_ =>` fallbacks that would silently mis-route a session row
/// instead of failing to compile. A playing session is also genuinely a different
/// record: it has a person, a device and a delivery method, and none of the queue
/// affordances (retry, blocklist, change category) mean anything for it.
///
/// So the Streaming sub-segment carries its own type end to end. That is why
/// `_ActivitySub.custom` exists.
///
/// Sources degrade independently **while one of them still answers**: an
/// unreachable Jellyfin yields no rows rather than emptying the section, and
/// [streamActivityOfflineProvider] names it beside the sessions Plex did send.
/// That partial answer is honest: every row on screen is a fact, and the
/// silence is named. Tracearr is one of those sources: when it does not
/// answer the media servers' own rows stand, and its silence is named the same
/// way.
///
/// When **no** configured source answered there is no partial answer to show,
/// and this throws the last failure. It used to return `[]`, which the section
/// drew as "Nobody is watching right now" about servers nobody could ask. The
/// offline note never fired either, because the sessions reads swallowed their
/// own failures until they stopped.
///
/// `retry: noProviderRetry` because both sessions providers carry it: a
/// derivation that dropped it would hold the failure through ten backing-off
/// re-runs its sources had already declined.
final streamActivityProvider = FutureProvider<List<StreamActivityRow>>((
  ref,
) async {
  final rows = <StreamActivityRow>[];
  final sightings = <TracearrSightings>[];
  var answered = 0;
  Object? failure;
  StackTrace? failureStack;

  // Every connection, not the lens: a second Jellyfin's viewers are as much
  // the household's as the first one's, and Activity is where they are all
  // counted.
  for (final connection in _streamConnections(ref)) {
    try {
      if (connection.key.service == ServiceKey.tracearr) {
        final seen = await ref.watch(
          tracearrStreamsForProvider(connection.key.instanceId).future,
        );
        answered++;
        sightings.add((
          instanceId: connection.key.instanceId,
          streams: seen.streams,
        ));
        continue;
      }
      final sessions = await ref.watch(
        streamSessionsForProvider(connection.key).future,
      );
      answered++;
      rows.addAll(
        sessions.map(
          (session) => StreamActivityRow(
            service: connection.key.service,
            instanceId: connection.key.instanceId,
            connectionName: connection.name,
            session: session,
          ),
        ),
      );
    } catch (error, stack) {
      // A shared account's Plex is not a failure: only its owner sees who is
      // watching, which Now playing says.
      if (await _ownerOnly(ref, connection.key, error)) continue;
      // Reported through streamActivityOfflineProvider rather than thrown: one
      // dark server must not hide the other's sessions.
      failure = error;
      failureStack = stack;
    }
  }

  if (answered == 0 && failure != null) {
    Error.throwWithStackTrace(failure, failureStack!);
  }

  final merged = sightings.isEmpty
      ? rows
      : mergeTracearrStreams(
          native: rows,
          sightings: sightings,
          connectionNames: _connectionNames(ref),
        );

  // Transcodes first: the rows that are costing the box something are the rows
  // worth reading first, and the per-service order underneath has to stay stable
  // so a bitrate updating in place does not reshuffle the list.
  //
  // Decorated with the source index because `List.sort` is *not* guaranteed
  // stable: Dart insertion-sorts 32 elements or fewer and dual-pivot quicksorts
  // above that, so a cost-only comparator can hand back two direct plays in a
  // different order on each poll. Same pattern, and the same reason, as
  // `servicesQueueProvider`.
  final ordered =
      List.generate(
        merged.length,
        (index) => (index: index, row: merged[index]),
        growable: false,
      )..sort((a, b) {
        final aCost = a.row.session.playMethod.isTranscode ? 0 : 1;
        final bCost = b.row.session.playMethod.isTranscode ? 0 : 1;
        final byCost = aCost.compareTo(bCost);
        if (byCost != 0) return byCost;
        return a.index.compareTo(b.index);
      });

  return ordered.map((entry) => entry.row).toList(growable: false);
}, retry: noProviderRetry);

/// Configured media server connections that did not answer, each named the
/// way the rows name it.
///
/// Separate from [streamActivityProvider] for the reason
/// `servicesSectionOfflineMessage` documents: sources that degrade to `[]` make
/// "nobody is watching" and "the server is down" arrive identically, which sends
/// the user looking for the wrong thing. Naming which source is dark is what makes
/// a merged section safe.
///
/// Never throws, so its retry policy never engages; `noProviderRetry` anyway,
/// because its sources carry it.
final streamActivityOfflineProvider = FutureProvider<List<StreamOfflineSource>>(
  (ref) async {
    final offline = <StreamOfflineSource>[];

    for (final connection in _streamConnections(ref)) {
      try {
        await ref.watch(streamSessionsForProvider(connection.key).future);
      } catch (error) {
        // Answered and refused only the sessions: named in blue on Now playing,
        // never as a server that is down.
        if (await _ownerOnly(ref, connection.key, error)) continue;
        offline.add((
          service: connection.key.service,
          instanceId: connection.key.instanceId,
          title: serviceWithConnection(
            connection.key.service,
            connection.name,
            joiner: ' ',
          ),
          error: error,
        ));
      }
    }

    return offline;
  },
  retry: noProviderRetry,
);
