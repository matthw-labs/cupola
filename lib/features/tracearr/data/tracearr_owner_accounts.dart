import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/provider_retry.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';
import 'package:cupola/features/tracearr/data/tracearr_owner_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_owner_session.dart';

/// How long a session may go unread before coming back to the app reads it
/// again: Better Auth moves a session's end 30 days past a request once the
/// session is a day old, so a read a little under a day apart keeps a used
/// session alive without ever reading twice in one sitting.
const Duration kTracearrOwnerRenewEvery = Duration(hours: 20);

/// [TracearrOwnerClient.forReach] as a provider, so a test hands the sign-in
/// and the keeper a client over a stub transport. The default is the one
/// constructor itself.
final tracearrOwnerClientFactoryProvider = Provider<TracearrOwnerClientFactory>(
  (ref) => TracearrOwnerClient.forReach,
);

/// What a client of connection [connectionId], holding the bearer [token],
/// reports about the owner's session: an ended one is emptied in storage.
/// Fire and forget, so a request never waits on the settings write.
///
/// Only [token]'s own session is emptied: the owner may have signed in again
/// while the request was in flight, and the refusal belongs to the old bearer.
TracearrOwnerEvents tracearrOwnerEvents(
  Ref ref,
  String connectionId, {
  required String token,
}) {
  final accounts = ref.read(tracearrOwnerAccountsProvider);
  return TracearrOwnerEvents(
    onSessionEnded: () => unawaited(
      accounts
          .sessionEnded(connectionId, ifToken: token)
          .catchError((Object _) {}),
    ),
  );
}

/// What the app keeps about the owner's session between requests, written to
/// the connection it belongs to. The one place that changes it once signed in,
/// so an ended session and a renewal land the same way from every client that
/// met them.
final tracearrOwnerAccountsProvider = Provider<TracearrOwnerAccounts>(
  TracearrOwnerAccounts.new,
);

class TracearrOwnerAccounts {
  TracearrOwnerAccounts(this._ref, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Ref _ref;
  final DateTime Function() _now;

  TracearrOwnerSession? ownerOf(String connectionId) =>
      _ref.read(currentSettingsProvider).instanceById(connectionId)?.owner;

  /// Finishes a sign-in on connection [connectionId] with the bearer [token]
  /// the way in answered: asks who it is, refuses anyone but the owner (and
  /// ends that session at Tracearr, so a refused member leaves nothing
  /// behind), reads when the session ends, and keeps it. [login] is what the
  /// person typed, empty for Plex.
  ///
  /// Throws [TracearrNotOwner], or what the reads threw.
  Future<void> signedIn(
    String connectionId, {
    required TracearrOwnerKind kind,
    required String login,
    required String token,
  }) async {
    final reach = _reachOf(connectionId);
    final owner = _ref.read(tracearrOwnerClientFactoryProvider)(
      reach: reach,
      token: token,
    );
    try {
      final identity = await owner.whoAmI();
      if (!identity.isOwner) {
        await owner.signOut();
        throw const TracearrNotOwner();
      }
      final read = await owner.session().catchError(
        (Object _) => const TracearrSessionRead(alive: true),
      );
      await _update(
        connectionId,
        (_) => TracearrOwnerSession(
          kind: kind,
          login: login.trim(),
          displayName: identity.name,
          token: token,
          expiresAt: read.expiresAt,
          checkedAt: _now(),
        ),
        orStart: true,
      );
    } finally {
      owner.close();
    }
  }

  /// Signs the owner out of Tracearr, so the session ends there too, then
  /// forgets it here whatever Tracearr said. The login goes with it: the
  /// person chose to leave, so the form starts clean.
  Future<void> signOut(String connectionId) async {
    final owner = ownerOf(connectionId);
    if (owner == null) return;
    if (owner.isSignedIn) {
      final client = _ref.read(tracearrOwnerClientFactoryProvider)(
        reach: _reachOf(connectionId),
        token: owner.token,
      );
      try {
        await client.signOut();
      } finally {
        client.close();
      }
    }
    await _ref.read(settingsProvider.notifier).update((settings) {
      final instance = settings.instanceById(connectionId);
      if (instance?.owner == null) return settings;
      return settings.copyWithInstance(instance!.copyWith(clearOwner: true));
    });
  }

  /// Tracearr no longer knows [connectionId]'s session: the token is emptied
  /// and the connection reads signed out. Everything else stays, so signing in
  /// again is one step.
  ///
  /// With [ifToken], only when that bearer is still the one held: an answer
  /// about an old session must not empty the one the owner signed in with
  /// since.
  Future<void> sessionEnded(String connectionId, {String? ifToken}) => _update(
    connectionId,
    (owner) =>
        ifToken == null || owner.token == ifToken ? owner.signedOut : owner,
  );

  /// Reads the session of [connectionId] once, as Better Auth wants for it to
  /// be renewed, when it was last read longer ago than
  /// [kTracearrOwnerRenewEvery] (always, with [force]). Quiet: a Tracearr that
  /// does not answer leaves the session as it was; one that says it knows none
  /// ends it. Never dials a connection reached only at home while away.
  Future<void> renew(String connectionId, {bool force = false}) async {
    final settings = _ref.read(currentSettingsProvider);
    final instance = settings.instanceById(connectionId);
    final owner = instance?.owner;
    if (instance == null || owner == null || !owner.isSignedIn) return;
    final checked = owner.checkedAt;
    if (!force &&
        checked != null &&
        _now().difference(checked) < kTracearrOwnerRenewEvery) {
      return;
    }
    if (instance.away == null && _ref.read(awayFromHomeProvider)) return;
    final client = _ref.read(tracearrOwnerClientFactoryProvider)(
      reach: _reachOf(connectionId),
      token: owner.token,
    );
    try {
      final read = await client.session();
      // What the read says is about the bearer it carried. If the owner signed
      // in again while it was in flight, the new session is not its to end or
      // to date.
      if (!read.alive) {
        await sessionEnded(connectionId, ifToken: owner.token);
        return;
      }
      await _update(
        connectionId,
        (held) => held.token == owner.token
            ? held.copyWith(expiresAt: read.expiresAt, checkedAt: _now())
            : held,
      );
    } catch (_) {
      // Not answering says nothing about the session.
    } finally {
      client.close();
    }
  }

  /// [renew] for every connection that holds a session.
  Future<void> renewAll() async {
    final due = [
      for (final instance
          in _ref
              .read(currentSettingsProvider)
              .instancesOf(ServiceKey.tracearr))
        if (instance.owner?.isSignedIn ?? false) instance.id,
    ];
    await Future.wait([for (final id in due) renew(id)]);
  }

  ConnectionReach _reachOf(String connectionId) {
    final reach = _ref.read(connectionReachProvider(connectionId));
    if (reach == null || reach.url.isEmpty) {
      throw const ServiceNotConfigured(ServiceKey.tracearr);
    }
    return reach;
  }

  Future<void> _update(
    String connectionId,
    TracearrOwnerSession Function(TracearrOwnerSession owner) change, {
    bool orStart = false,
  }) async {
    // Read when this change's turn comes, not now: two writes at once each
    // start from the other's result, and neither is lost.
    await _ref.read(settingsProvider.notifier).update((settings) {
      final instance = settings.instanceById(connectionId);
      if (instance == null || instance.service != ServiceKey.tracearr) {
        return settings;
      }
      final owner = instance.owner;
      if (owner == null && !orStart) return settings;
      final next = change(
        owner ?? const TracearrOwnerSession(kind: TracearrOwnerKind.email),
      );
      if (next == owner) return settings;
      return settings.copyWithInstance(instance.copyWith(owner: next));
    });
  }
}

/// Keeps every owner session alive: read once when the app starts and again
/// when it comes back to the foreground, each at most once a day
/// ([kTracearrOwnerRenewEvery]). Watched by the app's root.
final tracearrOwnerKeeperProvider = Provider<void>((ref) {
  final accounts = ref.read(tracearrOwnerAccountsProvider);
  void quietly(Future<void> work) => unawaited(work.catchError((Object _) {}));
  scheduleMicrotask(() => quietly(accounts.renewAll()));
  final listener = AppLifecycleListener(
    onResume: () => quietly(accounts.renewAll()),
  );
  ref.onDispose(listener.dispose);
});

/// The ways this Tracearr says an owner may sign in, read with no key from
/// `setup/status`: for the page that would offer Acknowledge and Dismiss, so
/// it never promises a sign-in that only single sign-on can give.
///
/// Dropped with the page: a Tracearr's ways change rarely and cost one cheap
/// read. A connection reached only at home while away is not asked.
final tracearrOwnerWaysProvider = FutureProvider.autoDispose
    .family<TracearrOwnerWays, String>((ref, instanceId) async {
      final transport = watchTransport(
        ref,
        ServiceKey.tracearr,
        instanceId: instanceId,
      );
      transport.ensureConfigured(ServiceKey.tracearr);
      final client = ref.read(tracearrOwnerClientFactoryProvider)(
        reach: (
          url: transport.url,
          access: transport.access,
          pin: transport.pin,
        ),
        onlyAtHome: transport.onlyAtHomeOf(ServiceKey.tracearr),
      );
      try {
        return await client.readWays();
      } finally {
        client.close();
      }
    }, retry: noProviderRetry);
