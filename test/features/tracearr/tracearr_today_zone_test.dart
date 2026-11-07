import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/platform/device_time_zone.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

import '../../test_helpers/capturing_http_adapter.dart';
import '../../test_helpers/fixtures.dart';

/// Today is the device's day: the zone it names goes with the read, and a
/// device that names none asks for Tracearr's own.
void main() {
  Future<Map<String, String>> todayAsked({required String? zone}) async {
    final adapter = CapturingHttpAdapter(
      response: jsonFixture('tracearr/today.json'),
    );
    final client = TracearrClient(
      baseUrl: 'http://tracearr.test',
      apiKey: 'trr_pub_t',
    );
    client.dio.httpClientAdapter = adapter;
    addTearDown(client.close);
    final container = ProviderContainer(
      overrides: [
        tracearrClientProvider.overrideWithValue(client),
        deviceTimeZoneProvider.overrideWithValue(() async => zone),
      ],
    );
    addTearDown(container.dispose);

    final today = await container.read(tracearrTodayProvider.future);

    expect(today.todayPlays, 14);
    return adapter.lastUri!.queryParameters;
  }

  test('the device zone goes with the read', () async {
    expect(await todayAsked(zone: 'Asia/Kolkata'), {
      'timezone': 'Asia/Kolkata',
    });
  });

  test('a device with no zone asks for Tracearr\'s own day', () async {
    expect(await todayAsked(zone: null), isEmpty);
  });

  test('a platform with no answer reads as no zone', () async {
    // Under `flutter test` the plugin's channel has no host: the read must
    // not throw, so the caller simply asks without a zone.
    TestWidgetsFlutterBinding.ensureInitialized();
    expect(await readDeviceTimeZone(), isNull);
  });
}
