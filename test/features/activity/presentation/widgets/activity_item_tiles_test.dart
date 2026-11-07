import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/media_search_popup_menu.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/widgets/tag_chip.dart';
import 'package:cupola/features/activity/domain/service_type.dart';
import 'package:cupola/features/activity/presentation/activity_provider.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_item_tiles.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

void main() {
  group('QueueItemTile', () {
    testWidgets('renders media-first title, release details, and warning', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueueItemTile(
              item: {
                'title': 'Movie.2024.2160p.WEB-DL-GROUP',
                'movie': {'title': 'Movie', 'year': 2024},
                'status': 'downloading',
                'trackedDownloadStatus': 'warning',
                'protocol': 'torrent',
                'timeleft': '00:12:00',
                'size': 100,
                'sizeleft': 17,
                'statusMessages': [
                  {
                    'title': 'Import Warning',
                    'messages': ['Needs manual import'],
                  },
                ],
              },
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.text('Movie (2024)'), findsOneWidget);
      expect(
        find.textContaining('Movie.2024.2160p.WEB-DL-GROUP'),
        findsOneWidget,
      );
      // The chip row still flags the warning, and the message the service
      // supplied is now spelled out instead of being fetched and discarded.
      expect(find.text('Warning'), findsOneWidget);
      expect(find.textContaining('Needs manual import'), findsOneWidget);
      expect(find.text('torrent'), findsOneWidget);
      // The label and the percentage come from StatusBadge now, so the
      // percentage is tabular and no longer concatenated into a subtitle string
      // that re-flowed on every tick.
      expect(find.text('Downloading'), findsOneWidget);
      expect(find.text('83%'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(InkWell), findsOneWidget);
    });

    testWidgets('renders fallback title for missing fields', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueueItemTile(item: {}, serviceType: ServiceType.movies),
          ),
        ),
      );

      expect(find.text('Unknown release'), findsOneWidget);
    });

    testWidgets('does not invent episode zero when episode number is missing', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueueItemTile(
              item: {
                'title': 'Frieren.S02.Pack.1080p.WEB-DL-GROUP',
                'series': {'title': 'Frieren: Beyond Journey\'s End'},
                'seasonNumber': 2,
              },
              serviceType: ServiceType.series,
            ),
          ),
        ),
      );

      expect(find.text('Frieren: Beyond Journey\'s End'), findsOneWidget);
      expect(
        find.textContaining('Frieren.S02.Pack.1080p.WEB-DL-GROUP'),
        findsOneWidget,
      );
      expect(find.textContaining('S2\u00A0E0'), findsNothing);
    });
  });

  group('HistoryItemTile', () {
    testWidgets('renders media-first title and release name as secondary', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HistoryItemTile(
              item: {
                'sourceTitle': 'Release.Name',
                'eventType': 'grabbed',
                'protocol': 'torrent',
                'movie': {'title': 'Movie Title', 'year': 2024},
              },
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.text('Movie Title (2024)'), findsOneWidget);
      expect(find.text('Release.Name'), findsOneWidget);
      expect(find.text('Grabbed'), findsOneWidget);
      expect(find.text('torrent'), findsNothing);
    });

    testWidgets('renders episode code for series history', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HistoryItemTile(
              item: {
                'sourceTitle': 'Release.Name',
                'eventType': 'downloadImported',
                'episode': {'seasonNumber': 1, 'episodeNumber': 2},
              },
              serviceType: ServiceType.series,
            ),
          ),
        ),
      );

      expect(find.text('S1\u00A0E2'), findsWidgets);
      expect(find.text('Imported'), findsOneWidget);
    });

    testWidgets('renders date-only history metadata', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HistoryItemTile(
              item: {
                'sourceTitle': 'Release.Name',
                'eventType': 'grabbed',
                'date': '2026-04-03T12:34:56Z',
              },
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.textContaining('2026-04-03'), findsOneWidget);
      expect(find.textContaining('12:34'), findsNothing);
    });
  });

  group('WantedItemTile', () {
    testWidgets('renders movie title without subtitle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: {'title': 'Cool Movie'},
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.text('Cool Movie'), findsOneWidget);
    });

    // Dates read `Wed 1 May 2024` (a year only when it is another year), never
    // the sortable `2024-05-01`: the chip and the line above it.
    testWidgets('a movie\'s release date is in the brand book\'s voice', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: {
                'title': 'Cool Movie',
                'inCinemas': '2024-05-01T00:00:00Z',
              },
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.text('Release Wed 1 May 2024'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(TagChip),
          matching: find.text('Wed 1 May 2024'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('2024-05-01'), findsNothing);
    });

    testWidgets('an episode\'s air date chip is in the brand book\'s voice', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: {
                'title': 'Pilot',
                'seasonNumber': 1,
                'episodeNumber': 1,
                'airDateUtc': '2024-05-01T00:00:00Z',
                'series': {'title': 'Breaking Bad'},
              },
              serviceType: ServiceType.series,
            ),
          ),
        ),
      );

      expect(
        find.descendant(
          of: find.byType(TagChip),
          matching: find.text('Wed 1 May 2024'),
        ),
        findsOneWidget,
      );
      expect(find.textContaining('2024-05-01'), findsNothing);
    });

    testWidgets('renders search popup when callbacks provided', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: const {'title': 'Cool Movie'},
              serviceType: ServiceType.movies,
              onAutoSearch: () {},
              onInteractiveSearch: () {},
            ),
          ),
        ),
      );

      expect(find.byType(MediaSearchPopupMenu), findsOneWidget);
    });

    testWidgets('hides search popup when callbacks missing', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: {'title': 'Cool Movie'},
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.byType(MediaSearchPopupMenu), findsNothing);
    });

    testWidgets('renders series format with subtitle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: {
                'title': 'Pilot',
                'seasonNumber': 1,
                'episodeNumber': 1,
                'series': {'title': 'Breaking Bad'},
              },
              serviceType: ServiceType.series,
            ),
          ),
        ),
      );

      expect(find.text('S1\u00A0E1\u00A0· Pilot'), findsOneWidget);
      expect(find.text('Breaking Bad'), findsOneWidget);
    });

    testWidgets('renders music with artist subtitle', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: {
                'title': 'Album Name',
                'artist': {'artistName': 'Artist Name'},
              },
              serviceType: ServiceType.music,
            ),
          ),
        ),
      );

      expect(find.text('Album Name'), findsOneWidget);
      expect(find.text('Artist Name'), findsOneWidget);
    });

    testWidgets('cutoff movie shows quality chip and size highlight', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(
              item: {
                'title': 'Long Movie Title',
                'status': 'released',
                'qualityProfileId': 7,
                'sizeOnDisk': 8003897815,
                'airDateUtc': '2026-04-03T12:34:56Z',
              },
              serviceType: ServiceType.movies,
              isCutoff: true,
              qualityProfileName: 'HD-1080p',
            ),
          ),
        ),
      );

      expect(find.text('HD-1080p'), findsOneWidget);
      expect(find.text('7.5\u00A0GB'), findsOneWidget);
      expect(find.textContaining('Release 2026-04-03'), findsNothing);
      expect(find.text('Released'), findsNothing);
    });

    testWidgets('handles missing series data gracefully', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: WantedItemTile(item: {}, serviceType: ServiceType.series),
          ),
        ),
      );

      expect(find.text('Unknown episode'), findsOneWidget);
      expect(find.text('Unknown series'), findsOneWidget);
    });
  });

  // The tone rule, on the two chips that broke it: a flagged queue record is a
  // fault (amber), an unmonitored wanted row is backlog (neutral). Both used to
  // be red, which says the service did not answer.
  group('GlobalActivityItemTile, the blocklist row', () {
    const blocked = GlobalActivityItem(
      kind: GlobalActivityKind.blocklist,
      service: ServiceKey.radarr,
      serviceType: ServiceType.movies,
      instanceId: 'radarr',
      title: 'Blade Runner 2049',
      subtitle: 'Blade.Runner.2049.2017.2160p.UHD.BluRay-GROUP',
      status: MediaStatusInfo(
        availability: MediaAvailability.available,
        labelOverride: 'Blocked',
        hasWarning: true,
        detail: 'Release was rejected: a manual import',
      ),
      raw: {
        'sourceTitle': 'Blade.Runner.2049.2017.2160p.UHD.BluRay-GROUP',
        'id': 7,
        'movie': {'title': 'Blade Runner 2049', 'year': 2017},
        'date': '2026-10-01T10:00:00Z',
      },
    );

    Future<void> pumpRow(WidgetTester tester) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(body: GlobalActivityItemTile(item: blocked)),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says what was blocked, why, and its status', (tester) async {
      await pumpRow(tester);

      expect(find.text('Blade Runner 2049'), findsOneWidget);
      expect(
        find.textContaining('Blade.Runner.2049.2017.2160p.UHD.BluRay-GROUP'),
        findsOneWidget,
      );
      expect(find.text('Blocked'), findsOneWidget);
      expect(
        find.textContaining('Release was rejected: a manual import'),
        findsOneWidget,
      );
    });

    testWidgets('its overflow menu offers removing it from the blocklist', (
      tester,
    ) async {
      await pumpRow(tester);

      await tester.tap(find.byTooltip('Actions for Blade Runner 2049'));
      await tester.pumpAndSettle();

      expect(find.text('Remove from blocklist'), findsOneWidget);
    });
  });

  group('tone rule', () {
    Color chipInk(WidgetTester tester, String label) => tester
        .widget<Text>(
          find.descendant(of: find.byType(TagChip), matching: find.text(label)),
        )
        .style!
        .color!;

    for (final theme in [AppTheme.darkTheme(), AppTheme.lightTheme()]) {
      final scheme = theme.colorScheme;
      final name = theme.brightness.name;

      testWidgets('a queue warning is amber, not red ($name)', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: QueueItemTile(
                item: {
                  'title': 'Movie.2024.WEB-DL',
                  'status': 'downloading',
                  'trackedDownloadStatus': 'warning',
                },
                serviceType: ServiceType.movies,
              ),
            ),
          ),
        );

        // The room's own amber (the day room's is deeper than the dark
        // room's) walked over its wash on the tile.
        expect(
          chipInk(tester, 'Warning'),
          ServiceTheme.onTint(
            statusToneFill(scheme, StatusTone.warning),
            surface: scheme.surfaceContainer,
            tintAlpha: 0.12,
          ),
        );
      });

      testWidgets('an unmonitored wanted row is neutral ($name)', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: WantedItemTile(
                item: {
                  'title': 'Cool Movie',
                  'status': 'released',
                  'hasFile': false,
                  'monitored': false,
                },
                serviceType: ServiceType.movies,
              ),
            ),
          ),
        );

        expect(
          chipInk(tester, 'Unmonitored'),
          ServiceTheme.onTint(
            scheme.onSurfaceVariant,
            surface: scheme.surfaceContainer,
            tintAlpha: 0.12,
          ),
        );
        // "Missing from disk" is the list of things to fetch, not damage.
        expect(
          tester
              .widget<Text>(find.text('Movie missing from disk'))
              .style!
              .color,
          scheme.onSurfaceVariant,
        );
      });

      // A release's protocol and a wanted row's date state no status, so their
      // chips wear no tone: the plain chip, like the quality beside them. They
      // used to wear the info blue.
      Future<void> pumpRow(WidgetTester tester, Widget row) =>
          tester.pumpWidget(
            MaterialApp(
              theme: theme,
              home: Scaffold(body: row),
            ),
          );

      Iterable<Color?> chipTones(WidgetTester tester) =>
          tester.widgetList<TagChip>(find.byType(TagChip)).map((c) => c.color);

      testWidgets('a queue row\'s protocol is a plain chip ($name)', (
        tester,
      ) async {
        await pumpRow(
          tester,
          const QueueItemTile(
            item: {'title': 'Movie.2024.WEB-DL', 'protocol': 'torrent'},
            serviceType: ServiceType.movies,
          ),
        );

        expect(chipTones(tester), [null]);
      });

      // The green scheme role (`tertiary`) is a tone too: a download client and
      // an indexer are names, not a status, and wore it.
      testWidgets('a queue row\'s download client is a plain chip ($name)', (
        tester,
      ) async {
        await pumpRow(
          tester,
          const QueueItemTile(
            item: {
              'title': 'Movie.2024.WEB-DL',
              'downloadClient': 'qBittorrent',
            },
            serviceType: ServiceType.movies,
          ),
        );

        expect(find.text('qBittorrent'), findsOneWidget);
        expect(chipTones(tester), [null]);
      });

      testWidgets('a history row\'s indexer is a plain chip ($name)', (
        tester,
      ) async {
        await pumpRow(
          tester,
          const HistoryItemTile(
            item: {
              'sourceTitle': 'Release.Name',
              'eventType': 'grabbed',
              'data': {'indexer': 'NZBgeek'},
            },
            serviceType: ServiceType.movies,
          ),
        );

        expect(find.text('NZBgeek'), findsOneWidget);
        expect(chipTones(tester), [null]);
      });

      testWidgets('a wanted row\'s date is a plain chip ($name)', (
        tester,
      ) async {
        await pumpRow(
          tester,
          const WantedItemTile(
            item: {
              'title': 'Pilot',
              'seasonNumber': 1,
              'episodeNumber': 1,
              'airDateUtc': '2024-05-01T00:00:00Z',
              'series': {'title': 'Breaking Bad'},
            },
            serviceType: ServiceType.series,
          ),
        );

        expect(chipTones(tester), [null]);
      });
    }
  });

  group('Queue status normalization', () {
    testWidgets('prefers trackedDownloadState over completed status', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueueItemTile(
              item: {
                'title': 'Queued Import',
                'trackedDownloadState': 'importPending',
                'status': 'completed',
              },
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.text('Waiting to import'), findsOneWidget);
      expect(find.text('Available'), findsNothing);
    });

    testWidgets('shows no inline progress when not downloading', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QueueItemTile(
              item: {
                'title': 'Completed Item',
                'status': 'completed',
                'size': 100,
                'sizeleft': 0,
              },
              serviceType: ServiceType.movies,
            ),
          ),
        ),
      );

      expect(find.byType(LinearProgressIndicator), findsNothing);
      expect(find.textContaining('%'), findsNothing);
    });
  });
}
