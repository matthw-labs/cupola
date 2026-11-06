/// An Emby connection keeps the household member it reads as across a
/// restart, as a Jellyfin one does: an API key has no user, so without the
/// stored viewer every launch would ask who is watching again.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/settings/data/settings_service.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import '../../test_helpers/fake_secure_settings_store.dart';

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

  test('the first Emby\'s viewer is saved and read back, beside its own '
      'storage keys', () async {
    var settings = await service.loadSettings();
    settings = settings.copyWithService(
      ServiceKey.emby,
      url: 'https://emby.lan:8096',
      apiKey: 'emby-key',
    );
    settings = settings.copyWithViewer(ServiceKey.emby, 'user-anna');
    await service.saveSettings(settings);

    expect(prefs.getString('emby_url'), 'https://emby.lan:8096');
    expect(prefs.getString('emby_user_id'), 'user-anna');
    expect(await secureStore.read(key: 'secure_emby_api_key'), 'emby-key');

    final reloaded = await service.loadSettings();
    final emby = reloaded.primaryOf(ServiceKey.emby)!;
    expect(emby.viewerId, 'user-anna');
    expect(emby.url, 'https://emby.lan:8096');
    // Nothing of Jellyfin's moved.
    expect(reloaded.primaryOf(ServiceKey.jellyfin), isNull);
  });

  test('one household\'s Jellyfin and Emby keep a viewer each', () async {
    var settings = await service.loadSettings();
    settings = settings
        .copyWithService(
          ServiceKey.jellyfin,
          url: 'https://jf.lan:8096',
          apiKey: 'jf-key',
        )
        .copyWithService(
          ServiceKey.emby,
          url: 'https://emby.lan:8096',
          apiKey: 'emby-key',
        );
    settings = settings
        .copyWithViewer(ServiceKey.jellyfin, 'jf-user')
        .copyWithViewer(ServiceKey.emby, 'emby-user');
    await service.saveSettings(settings);

    final reloaded = await service.loadSettings();
    expect(reloaded.primaryOf(ServiceKey.jellyfin)!.viewerId, 'jf-user');
    expect(reloaded.primaryOf(ServiceKey.emby)!.viewerId, 'emby-user');
  });
}
