import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('serviceTabs', () {
    test('every service in the registry has a bar, except TrueNAS', () {
      // Exhaustive, so a service added to the registry cannot ship without a
      // bar, and so the one exception stays a decision rather than an
      // oversight. Ten sections are too many for a bar, so TrueNAS keeps the
      // console it already has; everything else in the stack follows the tab
      // model.
      for (final service in ServiceKey.values) {
        final tabs = tabsFor(service);
        if (service == ServiceKey.truenas) {
          expect(tabs, isNull, reason: 'TrueNAS is the console exception');
        } else {
          expect(tabs, isNotNull, reason: service.name);
        }
      }
    });

    test('Overview is always first', () {
      // Opening a service always lands on Overview, and it alone carries the
      // identity block and the readouts. A bar that started anywhere else
      // would put a user somewhere they did not ask to be.
      for (final entry in serviceTabs.entries) {
        expect(entry.value.first, ServiceTab.overview, reason: entry.key.name);
      }
    });

    test('no bar exceeds six tabs', () {
      // Past six the bar stops being a bar. Three of the answered decisions
      // exist to hold this line: Lidarr merged Artists and Albums, Bazarr
      // folded Blacklist into History, Prowlarr moved Apps into its own
      // settings page, so a seventh entry here means one of them was undone.
      for (final entry in serviceTabs.entries) {
        expect(
          entry.value.length,
          lessThanOrEqualTo(6),
          reason: entry.key.name,
        );
      }
    });

    test('no service repeats a tab', () {
      for (final entry in serviceTabs.entries) {
        expect(
          entry.value.toSet().length,
          entry.value.length,
          reason: entry.key.name,
        );
      }
    });

    test('segments are unique and URL-safe', () {
      final segments = <String>{};
      for (final tab in ServiceTab.values) {
        expect(segments.add(tab.segment), isTrue, reason: tab.name);
        expect(
          RegExp(r'^[a-z0-9-]+$').hasMatch(tab.segment),
          isTrue,
          reason: '${tab.name} -> ${tab.segment}',
        );
      }
    });

    test('a segment resolves back to its tab', () {
      for (final tab in ServiceTab.values) {
        expect(ServiceTab.fromSegment(tab.segment), tab);
      }
      expect(ServiceTab.fromSegment('not-a-tab'), isNull);
    });

    test('the labels English does not title-case are spelled out', () {
      // The reason this vocabulary exists. A breadcrumb that title-cases the
      // path segment prints `Vms` and `Rss`, which is how nobody writes them
      // and how no other surface in the app said them.
      expect(ServiceTab.vms.label, 'VMs');
      expect(ServiceTab.rss.label, 'RSS');
      expect(ServiceTab.proxyHosts.label, 'Proxy hosts');
      expect(ServiceTab.accessLists.label, 'Access lists');
      expect(ServiceTab.auditLog.label, 'Audit log');
    });

    test('the four arrs share one bar, exactly', () {
      // Same record types in the same order, so a user who has learned Radarr
      // has learned Sonarr.
      final radarr = tabsFor(ServiceKey.radarr);
      for (final service in [
        ServiceKey.sonarr,
        ServiceKey.lidarr,
        ServiceKey.readarr,
      ]) {
        expect(tabsFor(service), radarr, reason: service.name);
      }
    });
  });
}
