import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/platform/browser_opener.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/domain/connection_reach.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';
import 'package:cupola/features/tracearr/data/tracearr_owner_accounts.dart';
import 'package:cupola/features/tracearr/data/tracearr_owner_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_owner_session.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_owner_notice.dart';

/// How long the Plex page is waited on at most: Tracearr lets a PIN go after
/// 15 minutes, and this is the app's own limit beside it.
const Duration kTracearrPlexPatience = Duration(minutes: 15);

/// Tracearr is asked whether the PIN was approved once a second, through the
/// page's own gate (`VisibilityPoller`).
const Duration kTracearrPlexPollEvery = Duration(seconds: 1);

/// Where a sign-in as the owner stands.
enum TracearrOwnerSignInStage {
  /// Nothing asked yet, or back after a notice that ends the way.
  start,

  /// Reading the ways Tracearr has.
  asking,

  /// A name or email and a password.
  form,

  /// The credentials are with Tracearr.
  signingIn,

  /// Waiting on the Plex page.
  plex,
}

/// The way into Tracearr as its owner, apart from how it is drawn: read the
/// ways Tracearr offers, sign in, keep the session.
///
/// One for each connection form that draws it, owned by the widget. The
/// connection is a saved one (the owner's access is an addition to a working
/// connection), so every request goes where its route is now
/// (`connectionReachProvider`): the address, the gateway's access and the pin
/// of the connection, never the saved address.
///
/// The password lives in [password] until it is sent and is then emptied; the
/// Plex page is opened by Cupola and its approval is checked by **Tracearr**,
/// which asks plex.tv itself: plex.tv never hears from this device, and so
/// never receives a gateway's headers. The token Tracearr answers with is
/// kept by [TracearrOwnerAccounts] in secure storage and appears nowhere
/// else.
class TracearrOwnerSignInFlow extends ChangeNotifier {
  TracearrOwnerSignInFlow({
    required WidgetRef ref,
    required String connectionId,
  }) : _ref = ref,
       _connectionId = connectionId;

  final WidgetRef _ref;
  final String _connectionId;

  /// The name or email of the password form.
  final login = TextEditingController();

  /// The password of the password form, emptied the moment it is sent.
  final password = TextEditingController();

  TracearrOwnerSignInStage get stage => _stage;
  TracearrOwnerSignInStage _stage = TracearrOwnerSignInStage.start;

  /// What Tracearr said of its ways in, once read.
  TracearrOwnerWays? get ways => _ways;
  TracearrOwnerWays? _ways;

  /// What the last step ended with, when it did not end signed in.
  TracearrOwnerNotice? get notice => _notice;
  TracearrOwnerNotice? _notice;

  /// The same step again, when the notice says it can still succeed.
  VoidCallback? get retry => _retry;
  VoidCallback? _retry;

  TracearrOwnerClient? _client;
  TracearrPlexPin? _pin;
  Duration _plexWaited = Duration.zero;
  bool _checking = false;
  bool _disposed = false;

  /// Whether the Plex page is being waited on: what gates its poll.
  bool get waitingOnPlex =>
      _stage == TracearrOwnerSignInStage.plex && _pin != null;

  /// The host the sign-in goes to, as prose names it.
  String get host {
    final reach = _ref.read(connectionReachProvider(_connectionId));
    return UrlUtils.hostInProse(
      ServiceKey.tracearr.extractHost(reach?.url ?? '') ?? '',
    );
  }

  ConnectionReach get _reach {
    final reach = _ref.read(connectionReachProvider(_connectionId));
    if (reach == null || reach.url.isEmpty) {
      throw const ServiceNotConfigured(ServiceKey.tracearr);
    }
    return reach;
  }

  TracearrOwnerClient _newClient() {
    _client?.close();
    return _client = _ref.read(tracearrOwnerClientFactoryProvider)(
      reach: _reach,
    );
  }

  void _set(VoidCallback change) {
    if (_disposed) return;
    change();
    notifyListeners();
  }

  // === Reading Tracearr ====================================================

  /// Reads the ways Tracearr has, then goes to the one there is: the form, or
  /// straight to the Plex page when that is the only way. With [again], an
  /// owner signing in again goes to the way they came in.
  Future<void> begin({TracearrOwnerSession? again}) async {
    _stopWaiting();
    _set(() {
      _stage = TracearrOwnerSignInStage.asking;
      _notice = null;
      _retry = null;
    });
    final TracearrOwnerWays ways;
    try {
      ways = await _newClient().readWays();
    } catch (error) {
      if (_disposed) return;
      return _stop(
        TracearrOwnerNotice.of(error),
        retry: () => begin(again: again),
      );
    }
    if (_disposed) return;
    final closed = TracearrOwnerNotice.ofWays(ways);
    _set(() => _ways = ways);
    if (closed != null) return _stop(closed);
    if (again?.kind == TracearrOwnerKind.plex && ways.plex) {
      return startPlex();
    }
    if (!ways.local && ways.plex) return startPlex();
    _set(() {
      login.text = again?.login ?? '';
      _stage = TracearrOwnerSignInStage.form;
    });
  }

  // === Name or email, and a password =======================================

  /// Whether the password form has what it needs to be sent.
  bool get readyToSend =>
      _ways?.local == true &&
      login.text.trim().isNotEmpty &&
      password.text.isNotEmpty;

  /// Sends the name or email and the password; the password leaves the form
  /// first.
  Future<void> signInWithPassword() async {
    if (!readyToSend) return;
    final typed = login.text.trim();
    final secret = password.text;
    // Out of the form the moment it is sent: whatever comes back, it is not
    // kept on this screen.
    password.clear();
    _set(() {
      _stage = TracearrOwnerSignInStage.signingIn;
      _notice = null;
      _retry = null;
    });
    try {
      final token = await (_client ?? _newClient()).signIn(
        login: typed,
        password: secret,
      );
      await _finish(
        kind: typed.contains('@')
            ? TracearrOwnerKind.email
            : TracearrOwnerKind.username,
        login: typed,
        token: token,
      );
    } catch (error) {
      if (_disposed) return;
      _signInStopped(error, back: TracearrOwnerSignInStage.form);
    }
  }

  // === Plex ================================================================

  /// Asks Tracearr for a Plex PIN and opens its page.
  Future<void> startPlex() async {
    _stopWaiting();
    _set(() {
      _stage = TracearrOwnerSignInStage.plex;
      _notice = null;
      _retry = null;
    });
    final TracearrPlexPin pin;
    try {
      pin = await _newClient().startPlex();
    } catch (error) {
      if (_disposed) return;
      return _stop(
        TracearrOwnerNotice.of(error),
        back: _backStage,
        retry: startPlex,
      );
    }
    if (_disposed) return;
    _set(() {
      _pin = pin;
      _plexWaited = Duration.zero;
    });
    await openPlexPage();
  }

  /// One second of waiting on the Plex page, while the sign-in is on screen:
  /// ask Tracearr, until the app's own patience runs out.
  void onPlexTick() {
    _plexWaited += kTracearrPlexPollEvery;
    if (_plexWaited >= kTracearrPlexPatience) return _plexTimedOut();
    unawaited(_checkNow());
  }

  /// Opens the Plex page of the PIN again.
  Future<void> openPlexPage() async {
    final pin = _pin;
    if (pin == null) return;
    await _ref.read(browserOpenerProvider).open(pin.authUrl);
  }

  Future<void> _checkNow() async {
    if (_checking) return;
    _checking = true;
    try {
      await _checkPlex();
    } finally {
      _checking = false;
    }
  }

  Future<void> _checkPlex() async {
    final client = _client;
    final pin = _pin;
    if (client == null || pin == null) return;
    final TracearrPlexCheck check;
    try {
      check = await client.checkPlex(pin);
    } on TracearrSignInRefused catch (error) {
      if (_disposed) return;
      _stopWaiting();
      unawaited(_ref.read(browserOpenerProvider).close());
      return _stop(TracearrOwnerNotice.of(error), back: _backStage);
    } catch (_) {
      // One missed answer is not the end: the next second asks again.
      return;
    }
    if (_disposed || _stage != TracearrOwnerSignInStage.plex) return;
    switch (check) {
      case TracearrPlexWaiting():
        return;
      case TracearrPlexExpired():
        return _plexTimedOut();
      case TracearrPlexSignedIn(:final token):
        _stopWaiting();
        _set(() => _stage = TracearrOwnerSignInStage.signingIn);
        unawaited(_ref.read(browserOpenerProvider).close());
        try {
          await _finish(kind: TracearrOwnerKind.plex, login: '', token: token);
        } catch (error) {
          if (_disposed) return;
          _signInStopped(error, back: _backStage);
        }
    }
  }

  void _plexTimedOut() {
    _stopWaiting();
    if (_disposed) return;
    unawaited(_ref.read(browserOpenerProvider).close());
    _stop(TracearrOwnerNotice.plexTimedOut, back: _backStage, retry: startPlex);
  }

  /// Where a stopped Plex wait goes back to: the form when there is one.
  TracearrOwnerSignInStage get _backStage => _ways?.local == true
      ? TracearrOwnerSignInStage.form
      : TracearrOwnerSignInStage.start;

  void _stopWaiting() {
    _pin = null;
    _plexWaited = Duration.zero;
  }

  /// Stops waiting on Plex, back to the form or the start.
  void cancel() {
    final wasPlex = _stage == TracearrOwnerSignInStage.plex;
    _stopWaiting();
    if (wasPlex) unawaited(_ref.read(browserOpenerProvider).close());
    _set(() {
      _notice = null;
      _retry = null;
      _stage = _backStage;
    });
  }

  // === The outcome =========================================================

  Future<void> _finish({
    required TracearrOwnerKind kind,
    required String login,
    required String token,
  }) async {
    await _ref
        .read(tracearrOwnerAccountsProvider)
        .signedIn(_connectionId, kind: kind, login: login, token: token);
    if (_disposed) return;
    _client?.close();
    _client = null;
    this.login.clear();
    _set(() {
      _stage = TracearrOwnerSignInStage.start;
      _notice = null;
      _retry = null;
    });
  }

  void _signInStopped(Object error, {required TracearrOwnerSignInStage back}) {
    final notice = TracearrOwnerNotice.of(error);
    _stop(
      notice,
      back: back,
      retry: notice.retryHelps ? () => unawaited(begin()) : null,
    );
  }

  void _stop(
    TracearrOwnerNotice notice, {
    TracearrOwnerSignInStage back = TracearrOwnerSignInStage.start,
    VoidCallback? retry,
  }) {
    _set(() {
      _notice = notice;
      _retry = retry;
      _stage = back;
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _stopWaiting();
    _client?.close();
    login.dispose();
    password.dispose();
    super.dispose();
  }
}
