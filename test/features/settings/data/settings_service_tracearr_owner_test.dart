import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/tracearr/data/tracearr_owner_accounts.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_owner_session.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';
import '../../../test_helpers/fake_tracearr_owner.dart';

/// The owner's session on a Tracearr connection: the bearer in secure
/// storage, the rest beside the address, never a password; kept across a
/// restart, emptied when it ends, renewed once a day of use, and gone with the
/// connection.
void main() {
  late SharedPreferences prefs;
  late FakeSecureSettingsStore secureStore;
  late SettingsService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    secureStore = FakeSecureSettingsStore();
    service = SettingsService(prefs, secureStore);
  });

  const token = 'sentinel-bearer.signature';
  final expiresAt = DateTime.utc(2026, 12, 6, 16, 48);
  final checkedAt = DateTime.utc(2026, 11, 6, 16, 48);
  final owner = TracearrOwnerSession(
    kind: TracearrOwnerKind.email,
    login: 'anna@home.arpa',
    displayName: 'anna',
    token: token,
    expiresAt: expiresAt,
    checkedAt: checkedAt,
  );
  final tracearr = ServiceInstance(
    id: 'tracearr',
    service: ServiceKey.tracearr,
    url: 'http://tower.home.arpa:3000',
    credential: 'trr_pub_sentinel_public_key',
    owner: owner,
  );

  Future<SettingsModel> saveAndReload(List<ServiceInstance> instances) async {
    await service.saveSettings(SettingsModel(instances: instances));
    return SettingsService(prefs, secureStore).loadSettings();
  }

  String everythingInPrefs() =>
      [for (final key in prefs.getKeys()) '$key=${prefs.get(key)}'].join('\n');

  group('kept on the device', () {
    test('survives a restart, beside the key it never replaces', () async {
      final settings = await saveAndReload([tracearr]);
      final back = settings.instanceById('tracearr')!;

      expect(back.owner, owner);
      expect(back.credential, 'trr_pub_sentinel_public_key');
      expect(back.isConfigured, isTrue);
    });

    test(
      'the bearer goes to secure storage, the rest beside the address',
      () async {
        await saveAndReload([tracearr]);

        expect(secureStore.entries['secure_tracearr_owner_session'], token);
        expect(
          secureStore.entries['secure_tracearr_api_key'],
          'trr_pub_sentinel_public_key',
        );
        expect(jsonDecode(prefs.getString('tracearr_owner')!), {
          'kind': 'email',
          'login': 'anna@home.arpa',
          'displayName': 'anna',
          'expiresAt': '2026-12-06T16:48:00.000Z',
          'checkedAt': '2026-11-06T16:48:00.000Z',
        });
        expect(everythingInPrefs(), isNot(contains('sentinel-bearer')));
      },
    );

    test('signed out, the owner stays and the bearer goes', () async {
      final settings = await saveAndReload([
        tracearr.copyWith(owner: owner.signedOut),
      ]);
      final back = settings.instanceById('tracearr')!;

      expect(back.owner?.login, 'anna@home.arpa');
      expect(back.owner?.isSignedIn, isFalse);
      expect(back.ownerSignedOut, isTrue);
      // Never a connection that is not set up: the key reads on.
      expect(back.isConfigured, isTrue);
      expect(
        secureStore.entries.containsKey('secure_tracearr_owner_session'),
        isFalse,
      );
    });

    test(
      'a removed connection takes the owner and the bearer with it',
      () async {
        await saveAndReload([tracearr]);

        await saveAndReload(const []);

        expect(prefs.getString('tracearr_owner'), isNull);
        expect(
          secureStore.entries.containsKey('secure_tracearr_owner_session'),
          isFalse,
        );
      },
    );

    test('signing the owner out of a connection forgets all of it', () async {
      await saveAndReload([tracearr]);

      final settings = await saveAndReload([
        tracearr.copyWith(clearOwner: true),
      ]);

      expect(settings.instanceById('tracearr')?.owner, isNull);
      expect(prefs.getString('tracearr_owner'), isNull);
      expect(
        secureStore.entries.containsKey('secure_tracearr_owner_session'),
        isFalse,
      );
    });

    test('clearing everything clears the owner', () async {
      await saveAndReload([tracearr]);

      await service.clearAll();

      expect(prefs.getString('tracearr_owner'), isNull);
      expect(secureStore.entries, isEmpty);
    });

    test(
      'an owner a later build wrote costs the owner, not the address',
      () async {
        await prefs.setString('tracearr_url', 'http://tower.home.arpa:3000');
        await prefs.setString('tracearr_owner', '{"kind":"passkey"}');

        final settings = await service.loadSettings();

        expect(
          settings.primaryOf(ServiceKey.tracearr)?.url,
          'http://tower.home.arpa:3000',
        );
        expect(settings.primaryOf(ServiceKey.tracearr)?.owner, isNull);
      },
    );

    test('nothing secret, and no login, in what an owner prints', () {
      for (final text in ['$owner', '$tracearr']) {
        expect(text, isNot(contains('sentinel')));
        expect(text, isNot(contains('anna@home.arpa')));
      }
    });
  });

  group('kept alive', () {
    late FakeTracearr server;

    ProviderContainer containerWith(
      SettingsModel settings, {
      List<Override> overrides = const [],
    }) {
      final container = ProviderContainer(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
          secureSettingsStoreProvider.overrideWithValue(secureStore),
          initialSettingsProvider.overrideWithValue(settings),
          tracearrOwnerClientFactoryProvider.overrideWithValue(server.factory),
          ...overrides,
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    ServiceInstance savedOf(ProviderContainer container) =>
        container.read(currentSettingsProvider).instanceById('tracearr')!;

    setUp(() {
      server = FakeTracearr()..addAccount('anna', password: 'x', name: 'anna');
    });

    ServiceInstance held(String bearer, {required Duration readAgo}) =>
        tracearr.copyWith(
          owner: owner.copyWith(
            token: bearer,
            checkedAt: DateTime.now().subtract(readAgo),
          ),
        );

    test('a session read a few hours ago is not read again', () async {
      final container = containerWith(
        SettingsModel(
          instances: [
            held(server.mint('anna'), readAgo: const Duration(hours: 3)),
          ],
        ),
      );

      await container.read(tracearrOwnerAccountsProvider).renewAll();

      expect(server.requests, isEmpty);
    });

    test(
      'a day of use reads get-session once, and keeps what Tracearr says',
      () async {
        final bearer = server.mint('anna');
        final container = containerWith(
          SettingsModel(
            instances: [held(bearer, readAgo: const Duration(hours: 21))],
          ),
        );

        await container.read(tracearrOwnerAccountsProvider).renewAll();

        final read = server.to('GET', '/auth/get-session').single;
        expect(read.headers['authorization'], 'Bearer $bearer');
        final renewed = savedOf(container).owner!;
        expect(renewed.expiresAt, DateTime.utc(2099));
        expect(
          DateTime.now().difference(renewed.checkedAt!),
          lessThan(const Duration(minutes: 1)),
        );
        expect(renewed.token, bearer);
      },
    );

    test(
      'a session Tracearr no longer knows ends, blue, keeping the login',
      () async {
        final container = containerWith(
          SettingsModel(
            instances: [
              held('unknown.sig', readAgo: const Duration(hours: 30)),
            ],
          ),
        );

        await container.read(tracearrOwnerAccountsProvider).renewAll();

        final ended = savedOf(container);
        expect(ended.owner?.isSignedIn, isFalse);
        expect(ended.owner?.login, 'anna@home.arpa');
        expect(ended.ownerSignedOut, isTrue);
        // The connection itself reads on with its key.
        expect(ended.isConfigured, isTrue);
      },
    );

    test(
      'a Tracearr that does not answer leaves the session as it was',
      () async {
        final bearer = server.mint('anna');
        final instance = held(bearer, readAgo: const Duration(hours: 30));
        final container = containerWith(SettingsModel(instances: [instance]));
        server.down = true;

        await container.read(tracearrOwnerAccountsProvider).renewAll();

        expect(savedOf(container).owner, instance.owner);
      },
    );

    test('a gateway lapsing in front of Tracearr does not end the session, '
        'which Tracearr never refused', () async {
      final bearer = server.mint('anna');
      final instance = held(bearer, readAgo: const Duration(hours: 30));
      final container = containerWith(SettingsModel(instances: [instance]));
      server.gatewayAnswers = true;

      await container.read(tracearrOwnerAccountsProvider).renewAll();

      expect(server.requests, isNotEmpty);
      expect(savedOf(container).owner, instance.owner);
      expect(savedOf(container).ownerSignedOut, isFalse);
    });

    /// The owner signing in again while a read of the old bearer is in flight:
    /// the connection now holds [next].
    Future<void> signInAgainDuring(
      ProviderContainer container,
      TracearrOwnerSession next,
    ) => container.read(settingsProvider.notifier).update((settings) {
      final instance = settings.instanceById('tracearr')!;
      return settings.copyWithInstance(instance.copyWith(owner: next));
    });

    test('a read of the old bearer never ends the session signed in since, '
        'whatever it says', () async {
      final container = containerWith(
        SettingsModel(
          instances: [held('unknown.sig', readAgo: const Duration(hours: 30))],
        ),
      );
      final fresh = owner.copyWith(
        token: server.mint('anna'),
        checkedAt: DateTime.now(),
      );
      server.holdSessionRead = Completer<void>();

      final renewing = container.read(tracearrOwnerAccountsProvider).renewAll();
      await pumpEventQueue();
      await signInAgainDuring(container, fresh);
      server.holdSessionRead!.complete();
      await renewing;

      expect(savedOf(container).owner, fresh);
    });

    test(
      'nor does it date it: the renewal is the old bearer\'s alone',
      () async {
        final container = containerWith(
          SettingsModel(
            instances: [
              held(server.mint('anna'), readAgo: const Duration(hours: 30)),
            ],
          ),
        );
        final fresh = owner.copyWith(
          token: server.mint('anna'),
          expiresAt: DateTime.utc(2030),
          checkedAt: DateTime.utc(2026, 11, 6, 17),
        );
        server.holdSessionRead = Completer<void>();

        final renewing = container
            .read(tracearrOwnerAccountsProvider)
            .renewAll();
        await pumpEventQueue();
        await signInAgainDuring(container, fresh);
        server.holdSessionRead!.complete();
        await renewing;

        expect(savedOf(container).owner, fresh);
      },
    );

    test('a refusal that met the old bearer ends only that bearer', () async {
      final container = containerWith(
        SettingsModel(instances: [held('current.sig', readAgo: Duration.zero)]),
      );
      final stale = container.read(
        Provider(
          (ref) => tracearrOwnerEvents(ref, 'tracearr', token: 'stale.sig'),
        ),
      );
      final current = container.read(
        Provider(
          (ref) => tracearrOwnerEvents(ref, 'tracearr', token: 'current.sig'),
        ),
      );

      stale.onSessionEnded!();
      await pumpEventQueue();
      expect(savedOf(container).owner?.isSignedIn, isTrue);

      current.onSessionEnded!();
      await pumpEventQueue();
      expect(savedOf(container).owner?.isSignedIn, isFalse);
      expect(savedOf(container).owner?.login, 'anna@home.arpa');
    });

    test('away from home with no address away, nothing is dialled', () async {
      final container = containerWith(
        SettingsModel(
          instances: [
            held(server.mint('anna'), readAgo: const Duration(hours: 30)),
          ],
        ),
        overrides: [awayFromHomeProvider.overrideWithValue(true)],
      );

      await container.read(tracearrOwnerAccountsProvider).renewAll();

      expect(server.requests, isEmpty);
    });
  });
}
