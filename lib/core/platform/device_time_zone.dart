import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';

/// The device's time zone by its IANA name (`Europe/Rome`), or null when the
/// platform cannot give one.
///
/// Dart's own `DateTime.timeZoneName` is an abbreviation (`CET`), which a
/// server cutting a day by zone cannot rely on. A zone the platform does not
/// name, or a platform with no answer (a test, an engine without the plugin),
/// is null: the caller then asks without one, never with a guess.
Future<String?> readDeviceTimeZone() async {
  try {
    final zone = (await FlutterTimezone.getLocalTimezone()).identifier.trim();
    return zone.isEmpty ? null : zone;
  } catch (_) {
    return null;
  }
}

/// How the app reads [readDeviceTimeZone], once per read and never cached:
/// a device that travelled is in its new zone at the next refresh. Overridden
/// in tests with a fixed zone.
final deviceTimeZoneProvider = Provider<Future<String?> Function()>(
  (_) => readDeviceTimeZone,
);
