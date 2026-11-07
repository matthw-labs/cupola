/// Signing in as Tracearr's owner from its connection's form: the optional
/// second credential beside the public key, by name or email and by Plex, and
/// what each way says when it stops. The server is the fake Tracearr
/// (`FakeTracearr`) that answers as the 3.1.4 container measured.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/platform/browser_opener.dart';
import 'package:cupola/core/platform/local_network_access.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_address.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/service_settings_screen.dart';
import 'package:cupola/features/tracearr/data/tracearr_owner_accounts.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_owner_session.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';
import '../../../test_helpers/fake_tracearr_owner.dart';
import '../../../test_helpers/profiles/profiles.dart';

const _surface = Size(430, 3000);
const _password = 'a-pretend-password';
const _awayLabel = 'Address away\u00A0· optional';

class _Browser implements BrowserOpener {
  final opened = <Uri>[];
  var closed = 0;

  @override
  Future<bool> open(Uri url) async {
    opened.add(url);
    return true;
  }

  @override
  Future<void> close() async => closed++;
}

final _profile = Profiles.p1.withConnection(WorldConnections.tracearr);

Future<(ProfileHarness, ProviderContainer, _Browser)> _pumpForm(
  WidgetTester tester,
  FakeTracearr server, {
  TracearrOwnerSession? owner,
}) async {
  final browser = _Browser();
  final harness = await ProfileHarness.start(
    _profile,
    overrides: [
      browserOpenerProvider.overrideWithValue(browser),
      tracearrOwnerClientFactoryProvider.overrideWithValue(server.factory),
    ],
  );
  harness.network.followFakeTime(tester.binding);
  final container = harness.container();
  if (owner != null) {
    await container.read(settingsProvider.notifier).update((settings) {
      final instance = settings.instanceById(WorldIds.tracearr)!;
      return settings.copyWithInstance(instance.copyWith(owner: owner));
    });
  }
  await tester.binding.setSurfaceSize(_surface);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.darkTheme(),
        home: ServiceSettingsScreen(
          service: ServiceKey.tracearr,
          instanceId: WorldIds.tracearr,
          certificateProber: (_, {pinnedFingerprint = ''}) async => null,
          localNetworkProbe: (_, {timeout = Duration.zero}) async =>
              LocalNetworkAccess.unrestricted,
        ),
      ),
    ),
  );
  await harness.settle(tester);
  return (harness, container, browser);
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

Future<void> _tap(
  WidgetTester tester,
  ProfileHarness harness,
  Finder finder,
) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await harness.settle(tester);
}

Future<void> _type(WidgetTester tester, String label, String text) async {
  await tester.ensureVisible(_field(label));
  await tester.enterText(_field(label), text);
  await tester.pump();
}

ServiceInstance _saved(ProviderContainer container) =>
    container.read(currentSettingsProvider).instanceById(WorldIds.tracearr)!;

FakeTracearr _server() => FakeTracearr()
  ..addAccount('anna@example.test', password: _password, name: 'anna')
  ..addAccount('anna', password: _password, name: 'anna')
  ..addAccount(
    'ben',
    password: _password,
    role: FakeTracearrRole.member,
    name: 'ben',
  )
  ..addAccount('plexowner', password: 'unused', name: 'anna');

Future<void> _signInWithPassword(
  WidgetTester tester,
  ProfileHarness harness, {
  String login = 'anna@example.test',
  String password = _password,
}) async {
  await _tap(tester, harness, find.text('Sign in as the owner'));
  await _type(tester, 'Name or email', login);
  await _type(tester, 'Password', password);
  await _tap(tester, harness, find.widgetWithText(FilledButton, 'Sign in'));
}

void main() {
  testWidgets('a working connection offers the owner\'s access, optional and '
      'after the key', (tester) async {
    final (harness, container, _) = await _pumpForm(tester, _server());

    expect(find.text('Owner access'), findsOneWidget);
    expect(find.text('Sign in as the owner'), findsOneWidget);
    // An addition to the key, never a replacement.
    expect(_saved(container).credential, isNotEmpty);
    expect(_saved(container).owner, isNull);

    await harness.unmount(tester);
  });

  group('name or email and a password', () {
    testWidgets('by email: signed in as the name Tracearr gives, the bearer '
        'in secure storage and the password nowhere', (tester) async {
      final server = _server();
      final (harness, container, _) = await _pumpForm(tester, server);

      await _signInWithPassword(tester, harness);

      expect(find.text('Signed in as anna'), findsOneWidget);
      final owner = _saved(container).owner!;
      expect(owner.isSignedIn, isTrue);
      expect(owner.kind, TracearrOwnerKind.email);
      expect(owner.expiresAt, DateTime.utc(2099));
      // The key stays: the owner is an addition to it.
      expect(_saved(container).credential, isNotEmpty);
      expect(server.to('POST', '/sign-in/email').single.body, {
        'email': 'anna@example.test',
        'password': _password,
      });
      // Kept on the device the way the Seerr session is: the token in secure
      // storage, the rest beside the address, no password anywhere.
      final secure =
          container.read(secureSettingsStoreProvider)
              as FakeSecureSettingsStore;
      expect(secure.entries['secure_tracearr_owner_session'], owner.token);
      final prefs = container.read(sharedPreferencesProvider);
      final stored = jsonDecode(prefs.getString('tracearr_owner')!) as Map;
      expect(stored['kind'], 'email');
      expect(stored['displayName'], 'anna');
      expect(stored.containsKey('token'), isFalse);
      final everything = [
        for (final key in prefs.getKeys()) '$key=${prefs.get(key)}',
      ].join('\n');
      expect(everything, isNot(contains(_password)));
      expect(everything, isNot(contains(owner.token)));
      // The form is clean again.
      expect(_field('Password'), findsNothing);

      await harness.unmount(tester);
    });

    testWidgets('by name goes to the username route', (tester) async {
      final server = _server();
      final (harness, container, _) = await _pumpForm(tester, server);

      await _signInWithPassword(tester, harness, login: 'anna');

      expect(_saved(container).owner?.kind, TracearrOwnerKind.username);
      expect(server.to('POST', '/sign-in/username'), hasLength(1));
      expect(server.to('POST', '/sign-in/email'), isEmpty);
      await harness.unmount(tester);
    });

    testWidgets('a wrong password stays on the form, says so, and saves '
        'nothing', (tester) async {
      final server = _server();
      final (harness, container, _) = await _pumpForm(tester, server);

      await _signInWithPassword(tester, harness, password: 'wrong-wrong');

      expect(
        find.text("That name or email and password didn't work"),
        findsOneWidget,
      );
      expect(_field('Name or email'), findsOneWidget);
      // The password left the field the moment it was sent.
      expect(
        tester.widget<TextField>(_field('Password')).controller!.text,
        isEmpty,
      );
      expect(_saved(container).owner, isNull);
      await harness.unmount(tester);
    });

    testWidgets('a member is refused, and the session it earned ends at '
        'Tracearr', (tester) async {
      final server = _server();
      final (harness, container, _) = await _pumpForm(tester, server);
      server.addAccount(
        'ben',
        password: _password,
        role: FakeTracearrRole.member,
      );

      await _signInWithPassword(tester, harness, login: 'ben');

      expect(find.text('Only the owner can acknowledge'), findsOneWidget);
      expect(_saved(container).owner, isNull);
      expect(server.sessions, isEmpty);
      await harness.unmount(tester);
    });

    testWidgets('single sign-on alone is said once, with its remedy, and no '
        'button promises it', (tester) async {
      final server = _server()
        ..local = false
        ..oidc = true;
      final (harness, container, _) = await _pumpForm(tester, server);

      await _tap(tester, harness, find.text('Sign in as the owner'));

      expect(
        find.text(
          "This Tracearr signs in with single sign-on, which Cupola can't use.",
        ),
        findsOneWidget,
      );
      expect(find.text('Acknowledge it in Tracearr.'), findsOneWidget);
      expect(find.text('Sign in as the owner'), findsNothing);
      expect(_saved(container).owner, isNull);
      await harness.unmount(tester);
    });
  });

  group('Plex', () {
    testWidgets('Tracearr makes the PIN, Cupola opens its page and Tracearr '
        'checks it: plex.tv is never asked from here', (tester) async {
      final server = _server()
        ..local = false
        ..plex = true;
      final (harness, container, browser) = await _pumpForm(tester, server);

      await _tap(tester, harness, find.text('Sign in as the owner'));

      expect(find.text('Finish signing in with Plex'), findsOneWidget);
      expect(browser.opened.single.host, 'app.plex.tv');
      server.approvePlex();
      await tester.pump(const Duration(seconds: 1));
      await harness.settle(tester);

      expect(find.text('Signed in as anna'), findsOneWidget);
      expect(_saved(container).owner?.kind, TracearrOwnerKind.plex);
      expect(browser.closed, 1);
      expect(
        server.to('POST', '/plex/check-pin').first.headers['cookie'],
        startsWith('better-auth.plex_pin='),
      );
      // Nothing was sent to plex.tv from this device, so no gateway's header
      // and no cookie could reach it.
      expect(harness.network.requestsToHost('plex.tv'), isEmpty);
      await harness.unmount(tester);
    });

    testWidgets('nobody approves it: timed out, and Start again', (
      tester,
    ) async {
      final server = _server()
        ..local = false
        ..plex = true;
      final (harness, container, _) = await _pumpForm(tester, server);
      await _tap(tester, harness, find.text('Sign in as the owner'));

      await tester.pump(const Duration(minutes: 16));
      await harness.settle(tester);

      expect(find.text('The Plex sign-in timed out'), findsOneWidget);
      expect(find.text('Start again'), findsOneWidget);
      expect(_saved(container).owner, isNull);
      await harness.unmount(tester);
    });

    testWidgets('beside a password form it is one more way', (tester) async {
      final server = _server()..plex = true;
      final (harness, _, browser) = await _pumpForm(tester, server);

      await _tap(tester, harness, find.text('Sign in as the owner'));
      expect(_field('Name or email'), findsOneWidget);
      await _tap(tester, harness, find.text('Continue with Plex'));

      expect(find.text('Finish signing in with Plex'), findsOneWidget);
      expect(browser.opened, hasLength(1));
      await harness.unmount(tester);
    });

    testWidgets('a Tracearr with no owner is never made one', (tester) async {
      final server = _server()
        ..local = false
        ..plex = true
        ..needsSetup = true;
      final (harness, container, _) = await _pumpForm(tester, server);

      await _tap(tester, harness, find.text('Sign in as the owner'));

      expect(find.text("This Tracearr isn't set up yet"), findsOneWidget);
      expect(server.to('POST', '/plex/initiate'), isEmpty);
      expect(_saved(container).owner, isNull);
      await harness.unmount(tester);
    });
  });

  group('the session', () {
    final session = TracearrOwnerSession(
      kind: TracearrOwnerKind.email,
      login: 'anna@example.test',
      displayName: 'anna',
      token: 'saved.sig',
      checkedAt: DateTime.utc(2026, 11, 6),
    );

    testWidgets('a saved session is restored: signed in, with Sign out', (
      tester,
    ) async {
      final (harness, _, _) = await _pumpForm(
        tester,
        _server(),
        owner: session,
      );

      expect(find.text('Signed in as anna'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
      expect(find.text('Sign in as the owner'), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('signing out asks, ends the session at Tracearr and forgets '
        'it here', (tester) async {
      final server = _server();
      final token = server.mint('anna');
      final (harness, container, _) = await _pumpForm(
        tester,
        server,
        owner: session.copyWith(token: token),
      );

      await _tap(tester, harness, find.text('Sign out'));
      expect(find.text('Sign out of Tracearr?'), findsOneWidget);
      await _tap(
        tester,
        harness,
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Sign out'),
        ),
      );

      expect(server.sessions, isEmpty);
      expect(_saved(container).owner, isNull);
      expect(find.text('Sign in as the owner'), findsOneWidget);
      expect(
        container.read(sharedPreferencesProvider).getString('tracearr_owner'),
        isNull,
      );
      expect(
        (container.read(secureSettingsStoreProvider) as FakeSecureSettingsStore)
            .entries
            .containsKey('secure_tracearr_owner_session'),
        isFalse,
      );
      await harness.unmount(tester);
    });

    testWidgets('an ended session is blue, "Signed out of Tracearr", with '
        '"Sign in again", never a fault', (tester) async {
      final ended = session.signedOut;
      final (harness, _, _) = await _pumpForm(tester, _server(), owner: ended);

      expect(find.text('Signed out of Tracearr'), findsOneWidget);
      expect(find.text('Sign in again'), findsOneWidget);
      // The info glyph is the blue notice's, not the circled `!` of a fault
      // nor the struck-through cloud of silence.
      expect(find.byIcon(Icons.info_outline_rounded), findsWidgets);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
      await harness.unmount(tester);
    });

    testWidgets('Sign in again goes back to the way the owner came in', (
      tester,
    ) async {
      final server = _server();
      final (harness, container, _) = await _pumpForm(
        tester,
        server,
        owner: session.signedOut,
      );

      await _tap(tester, harness, find.text('Sign in again'));

      expect(
        tester.widget<TextField>(_field('Name or email')).controller!.text,
        'anna@example.test',
      );
      await _type(tester, 'Password', _password);
      await _tap(tester, harness, find.widgetWithText(FilledButton, 'Sign in'));
      expect(_saved(container).owner?.isSignedIn, isTrue);
      await harness.unmount(tester);
    });

    testWidgets('moving the address to another server does not carry the '
        'bearer there', (tester) async {
      final server = _server();
      final (harness, container, _) = await _pumpForm(
        tester,
        server,
        owner: session.copyWith(token: server.mint('anna')),
      );
      await tester.ensureVisible(find.byType(TextFormField).first);
      final address = find.byWidgetPredicate(
        (widget) =>
            widget is TextFormField &&
            widget.controller?.text == _saved(container).url,
      );
      await tester.enterText(address, 'http://other.home.arpa:3001');
      await tester.pump();

      await tester.tap(find.text('Save'));
      await harness.settle(tester);

      expect(_saved(container).url, 'http://other.home.arpa:3001');
      expect(_saved(container).owner, isNull);
      await harness.unmount(tester);
    });

    /// Saves the form with the address away typed as [away] and the address at
    /// home as [home] (left as it is when null), and answers the saved
    /// connection.
    Future<ServiceInstance> saveAddresses(
      WidgetTester tester, {
      String? home,
      String? away,
      String? awayBefore,
    }) async {
      final server = _server();
      final (harness, container, _) = await _pumpForm(
        tester,
        server,
        owner: session.copyWith(token: server.mint('anna')),
      );
      if (awayBefore != null) {
        await container.read(settingsProvider.notifier).update((settings) {
          final instance = settings.instanceById(WorldIds.tracearr)!;
          return settings.copyWithInstance(
            instance.copyWith(away: ConnectionAddress(url: awayBefore)),
          );
        });
        await harness.settle(tester);
      }
      final atHome = _saved(container).url;
      if (home != null) {
        final field = find.byWidgetPredicate(
          (widget) =>
              widget is TextFormField && widget.controller?.text == atHome,
        );
        await tester.ensureVisible(field);
        await tester.enterText(field, home);
      }
      if (away != null) await _type(tester, _awayLabel, away);
      await tester.pump();
      await tester.tap(find.text('Save'));
      await harness.settle(tester);
      final saved = _saved(container);
      await harness.unmount(tester);
      return saved;
    }

    testWidgets('adding a first address away keeps the owner: it is a second '
        'route to the same Tracearr', (tester) async {
      final saved = await saveAddresses(
        tester,
        away: 'https://tracearr.example.com',
      );

      expect(saved.away?.url, 'https://tracearr.example.com');
      expect(saved.owner?.isSignedIn, isTrue);
    });

    testWidgets('changing only the address away keeps the owner', (
      tester,
    ) async {
      final saved = await saveAddresses(
        tester,
        awayBefore: 'https://old.example.com',
        away: 'https://new.example.com',
      );

      expect(saved.away?.url, 'https://new.example.com');
      expect(saved.owner?.isSignedIn, isTrue);
    });

    testWidgets('the same host over https is the same Tracearr', (
      tester,
    ) async {
      final saved = await saveAddresses(
        tester,
        home: 'https://tower.home.arpa',
      );

      expect(saved.url, 'https://tower.home.arpa');
      expect(saved.owner?.isSignedIn, isTrue);
    });
  });
}
