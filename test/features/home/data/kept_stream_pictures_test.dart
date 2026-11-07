/// A picture kept from a media server is drawn back through that server's own
/// client, for every media server: the switch this reads used to end in a
/// catch-all, so one it did not name drew no picture at all after a cold start.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/core/last_known/stored_image.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/features/home/data/home_last_known.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';

import '../../../test_helpers/fake_secure_settings_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<ImageSource> drawn(
    ServiceKey service, {
    required String path,
    String? connectionId,
  }) async {
    final settings = SettingsModel(
      instances: [
        ServiceInstance(
          id: 'media',
          service: service,
          url: 'http://media.lan:8096',
          credential: 'server-key',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [
        sharedPreferencesProvider.overrideWithValue(
          await SharedPreferences.getInstance(),
        ),
        secureSettingsStoreProvider.overrideWithValue(
          FakeSecureSettingsStore(),
        ),
        currentSettingsProvider.overrideWith((ref) => settings),
        initialActiveInstancesProvider.overrideWithValue(const {}),
      ],
    );
    addTearDown(container.dispose);
    return container.read(
      Provider(
        (ref) => resolveStoredImage(
          ref,
          settings,
          StoredStreamImage(
            service: service,
            connectionId: connectionId ?? 'media',
            path: path,
            width: 360,
          ),
        ),
      ),
    );
  }

  for (final service in mediaServers) {
    test(
      '${service.name}: the picture is drawn through its connection',
      () async {
        final image = await drawn(service, path: '/library/metadata/4/thumb/9');
        expect(image.url, isNotEmpty);
        expect(image.url, contains('media.lan'));
      },
    );

    test('${service.name}: a connection that is gone draws none', () async {
      final image = await drawn(
        service,
        path: '/library/metadata/4/thumb/9',
        connectionId: 'removed',
      );
      expect(image, noImage);
    });
  }

  test('a picture kept against a service that is no media server draws '
      'none', () async {
    for (final service in ServiceKey.values.where((s) => !s.isMediaServer)) {
      expect(await drawn(service, path: '/x'), noImage, reason: service.name);
    }
  });
}
