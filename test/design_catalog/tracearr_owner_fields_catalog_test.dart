@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/platform/browser_opener.dart';
import 'package:cupola/features/onboarding/data/onboarding_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/tracearr/data/tracearr_owner_accounts.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_owner_session.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_owner_fields.dart';

import '../test_helpers/fake_secure_settings_store.dart';
import '../test_helpers/fake_tracearr_owner.dart';
import 'catalog.dart';

late SharedPreferences _prefs;

const _signedIn = TracearrOwnerSession(
  kind: TracearrOwnerKind.email,
  login: 'anna@example.test',
  displayName: 'Anna',
  token: 'catalog.token',
);

/// A Tracearr, saved, with the owner's session [owner] or none.
SettingsModel _tracearr({TracearrOwnerSession? owner}) => SettingsModel(
  instances: [
    ServiceInstance(
      id: 'tracearr',
      service: ServiceKey.tracearr,
      url: 'https://tracearr.lan:3000',
      credential: 'trr_pub_k',
      owner: owner,
    ),
  ],
);

class _NoBrowser implements BrowserOpener {
  @override
  Future<bool> open(Uri url) async => true;

  @override
  Future<void> close() async {}
}

/// One scene's providers: the connection saved, and the Tracearr that answers.
/// A scene that overrides gets a container of its own, so these are the
/// whole set.
List<Override> _world({TracearrOwnerSession? owner, FakeTracearr? server}) => [
  sharedPreferencesProvider.overrideWithValue(_prefs),
  secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
  initialSettingsProvider.overrideWithValue(_tracearr(owner: owner)),
  initialOnboardingCompletedProvider.overrideWithValue(true),
  initialActiveInstancesProvider.overrideWithValue(const {}),
  browserOpenerProvider.overrideWithValue(_NoBrowser()),
  tracearrOwnerClientFactoryProvider.overrideWithValue(
    (server ?? FakeTracearr()).factory,
  ),
];

FakeTracearr _server({
  bool local = true,
  bool plex = false,
  bool oidc = false,
  FakeTracearrRole role = FakeTracearrRole.owner,
}) => FakeTracearr(local: local, plex: plex, oidc: oidc)
  ..addAccount('anna', password: 'right-password', role: role, name: 'Anna');

/// The section in its own root container: what is derived from the settings
/// resolves there, and a failed read stays failed.
Widget _fields(List<Override> overrides) => _Isolated(
  overrides,
  const Padding(
    padding: EdgeInsets.all(24),
    child: Material(
      type: MaterialType.transparency,
      child: TracearrOwnerFields(connectionId: 'tracearr'),
    ),
  ),
);

class _Isolated extends StatefulWidget {
  const _Isolated(this.overrides, this.child);

  final List<Override> overrides;
  final Widget child;

  @override
  State<_Isolated> createState() => _IsolatedState();
}

class _IsolatedState extends State<_Isolated> {
  late final _container = ProviderContainer(
    overrides: widget.overrides,
    retry: (_, _) => null,
  );

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      UncontrolledProviderScope(container: _container, child: widget.child);
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tapText(WidgetTester tester, Finder scene, String text) async {
  final target = find.descendant(of: scene, matching: find.text(text));
  await tester.tap(target.first);
  await _settle(tester);
}

Future<void> _openForm(WidgetTester tester, Finder scene) =>
    _tapText(tester, scene, 'Sign in as the owner');

Future<void> _refusedPassword(WidgetTester tester, Finder scene) async {
  await _openForm(tester, scene);
  final fields = find.descendant(of: scene, matching: find.byType(TextField));
  await tester.enterText(fields.at(0), 'anna@example.test');
  await tester.enterText(fields.at(1), 'wrong-password');
  await tester.pump();
  await _tapText(tester, scene, 'Sign in');
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    _prefs = await SharedPreferences.getInstance();
  });

  catalogCard(
    'TracearrOwnerFields',
    scenes: [
      CatalogScene(
        'TracearrOwnerFields · nobody signed in: what the owner adds, and the '
        'one way in',
        (_) => _fields(_world()),
        width: 390,
        height: 260,
        id: 'owner-signed-out',
      ),
      CatalogScene(
        'TracearrOwnerFields · name or email and password: the form, the '
        'promise about the password, Continue with Plex only where Tracearr '
        'offers it',
        (_) => _fields(_world(server: _server(plex: true))),
        width: 390,
        height: 560,
        id: 'owner-form',
        act: _openForm,
      ),
      CatalogScene(
        'TracearrOwnerFields · a refused password: the amber notice above the '
        'form, the password field emptied',
        (_) => _fields(_world(server: _server())),
        width: 390,
        height: 640,
        id: 'owner-wrong-password',
        act: _refusedPassword,
      ),
      CatalogScene(
        'TracearrOwnerFields · Plex only: the page is open, waiting for the '
        'approval Tracearr checks',
        (_) => _fields(_world(server: _server(local: false, plex: true))),
        width: 390,
        height: 360,
        id: 'owner-plex-waiting',
        act: _openForm,
      ),
      CatalogScene(
        'TracearrOwnerFields · single sign-on only: said once, in blue, with '
        'its remedy, and no button that cannot be kept',
        (_) => _fields(_world(server: _server(local: false, oidc: true))),
        width: 390,
        height: 300,
        id: 'owner-single-sign-on',
        act: _openForm,
      ),
      CatalogScene(
        'TracearrOwnerFields · a member\'s account: refused in blue, Only the '
        'owner can acknowledge',
        (_) => _fields(
          _world(
            server: _server(role: FakeTracearrRole.member)
              ..addAccount(
                'anna@example.test',
                password: 'right-password',
                role: FakeTracearrRole.member,
                name: 'Anna',
              ),
          ),
        ),
        width: 390,
        height: 640,
        id: 'owner-member-refused',
        act: (tester, scene) async {
          await _openForm(tester, scene);
          final fields = find.descendant(
            of: scene,
            matching: find.byType(TextField),
          );
          await tester.enterText(fields.at(0), 'anna@example.test');
          await tester.enterText(fields.at(1), 'right-password');
          await tester.pump();
          await _tapText(tester, scene, 'Sign in');
        },
      ),
      CatalogScene(
        'TracearrOwnerFields · signed in: the name, the host, Sign out',
        (_) => _fields(_world(owner: _signedIn)),
        width: 390,
        height: 260,
        id: 'owner-signed-in',
      ),
      CatalogScene(
        'TracearrOwnerFields · the session ended: blue, Signed out of '
        'Tracearr, Sign in again, never a fault',
        (_) => _fields(_world(owner: _signedIn.signedOut)),
        width: 390,
        height: 260,
        id: 'owner-session-ended',
      ),
      CatalogScene(
        'TracearrOwnerFields · on a desktop window: the buttons keep their '
        '44pt floor',
        (_) => _fields(_world(owner: _signedIn)),
        width: 560,
        height: 260,
        platform: CatalogPlatform.desktop,
        id: 'owner-signed-in-desktop',
      ),
      CatalogScene(
        'Text at 200% · a refused password: the notice and the form wrap',
        (_) => _fields(_world(server: _server())),
        width: 390,
        height: 1400,
        textScale: catalogTextScale,
        id: 'owner-text-200',
        act: _refusedPassword,
      ),
    ],
  );
}
