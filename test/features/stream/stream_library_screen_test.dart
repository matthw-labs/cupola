import 'dart:async';

import 'package:dio/dio.dart' show CancelToken;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/stream/domain/models/stream_library.dart';
import 'package:cupola/features/stream/domain/models/stream_library_page.dart';
import 'package:cupola/features/stream/domain/models/stream_search_group.dart';
import 'package:cupola/features/stream/domain/models/stream_session.dart';
import 'package:cupola/features/stream/domain/stream_external_match.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';
import 'package:cupola/features/stream/presentation/stream_library_screen.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_poster_tile.dart';

import '../../test_helpers/fake_secure_settings_store.dart';

import '../../test_helpers/settings_scope.dart';

/// What one request asks for: the order and whether only unplayed titles.
typedef _Shelf = ({StreamLibrarySort sort, bool unplayedOnly});

const _wholeByName = (sort: StreamLibrarySort.name, unplayedOnly: false);
const _unplayedByName = (sort: StreamLibrarySort.name, unplayedOnly: true);
const _wholeByYear = (sort: StreamLibrarySort.year, unplayedOnly: false);

/// A media server that answers whatever the test scripted, page by page.
///
/// Scripted by *start index* rather than by call order, because the thing under
/// test is precisely that the screen asks for the offset the server told it to.
class _ScriptedServer implements StreamServerClient {
  _ScriptedServer(
    this.pages, {
    this.shelfPages = const {},
    this.gates = const {},
  });

  final Map<int, StreamLibraryPage> pages;

  /// Per-shelf overrides, for the cases where two shelves must answer
  /// differently at the same offset.
  final Map<_Shelf, Map<int, StreamLibraryPage>> shelfPages;

  /// Shelves whose requests hang until the test says otherwise.
  ///
  /// The only way to have a request still in flight while the screen does
  /// something else, which is what a stale fetch outliving its controller needs.
  final Map<_Shelf, Completer<void>> gates;

  final List<int> requested = [];
  final List<_Shelf> requestedShelves = [];

  @override
  Future<StreamLibraryPage> getLibraryPage({
    required String libraryId,
    StreamLibrarySort sort = StreamLibrarySort.name,
    bool unplayedOnly = false,
    String? viewerId,
    int startIndex = 0,
    int limit = 50,
    CancelToken? cancelToken,
  }) async {
    requested.add(startIndex);
    final shelf = (sort: sort, unplayedOnly: unplayedOnly);
    requestedShelves.add(shelf);
    final gate = gates[shelf];
    if (gate != null) await gate.future;
    return shelfPages[shelf]?[startIndex] ??
        pages[startIndex] ??
        StreamLibraryPage.empty(startIndex: startIndex);
  }

  @override
  StreamImageSource? imageFor(String posterPath, {int? width}) => null;

  @override
  Future<List<StreamItem>> getChildren(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async => const [];

  @override
  Future<List<StreamItem>> getEpisodes(
    String seriesId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async => const [];

  @override
  Future<StreamItem?> getItem(
    String itemId, {
    String? viewerId,
    CancelToken? cancelToken,
  }) async => null;

  @override
  Future<MediaKey?> getSeriesKey(
    String seriesId, {
    CancelToken? cancelToken,
  }) async => null;

  @override
  Future<MediaKey?> getTitleKey(
    String titleId, {
    CancelToken? cancelToken,
  }) async => null;

  @override
  Future<StreamExternalLookup> lookupByExternalId({
    String? tmdbId,
    String? tvdbId,
    String? imdbId,
    StreamItemKind? kind,
    String? title,
    int? year,
    CancelToken? cancelToken,
  }) async => const StreamExternalLookup.notInLibrary();

  @override
  Future<List<StreamLibrary>> getLibraries() async => const [];

  @override
  Future<int?> getLibraryItemCount(
    String libraryId, {
    CancelToken? cancelToken,
  }) async => null;

  @override
  Future<List<StreamSearchGroup>> search(
    String query, {
    int? limit,
    CancelToken? cancelToken,
  }) async => const [];

  @override
  Future<List<StreamSession>> getSessions() async => const [];

  @override
  Future<List<StreamViewer>> getViewers() async => const [];

  @override
  Future<List<StreamItem>> getContinueWatching({
    required int count,
    CancelToken? cancelToken,
  }) async => const [];

  @override
  Future<List<StreamItem>> getNextUp({
    required int count,
    CancelToken? cancelToken,
  }) async => const [];

  @override
  Future<List<StreamItem>> getRecentlyAdded({
    required int count,
    CancelToken? cancelToken,
  }) async => const [];

  @override
  Future<List<StreamWatched>> getRecentlyWatched({
    String? viewerId,
    int limit = 5,
    CancelToken? cancelToken,
  }) async => const [];

  @override
  Future<String?> probeVersion() async => '10.11.0';

  @override
  Future<bool> verifyCredential() async => true;

  @override
  Future<void> stopSession(String sessionId) async {}

  @override
  void close() {}
}

StreamItem _item(String id, String title) => StreamItem(
  id: id,
  title: title,
  subtitle: null,
  kind: StreamItemKind.movie,
  posterPath: null,
  year: 2016,
  runtimeMs: 7200000,
  isPlayed: false,
  resumeOffsetMs: null,
  unplayedChildCount: null,
);

StreamLibraryPage _page(
  List<StreamItem> items, {
  required int nextStartIndex,
  required bool hasMore,
}) => StreamLibraryPage(
  items: items,
  nextStartIndex: nextStartIndex,
  hasMore: hasMore,
);

Future<void> _pumpLibrary(
  WidgetTester tester,
  _ScriptedServer server, {
  ServiceKey service = ServiceKey.jellyfin,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        // Both servers configured, because the browse checks that before it
        // asks the paging controller for a page: a deep link can land here on a
        // server that was never set up, and what that must show is the
        // not-configured leaf rather than a Retry that can never succeed. These
        // cases are about the pager, so they answer the question and move on.
        currentSettingsProvider.overrideWith(
          (ref) => settingsWithServices(const [
            ServiceKey.jellyfin,
            ServiceKey.plex,
          ]),
        ),
        jellyfinServerProvider.overrideWithValue(server),
      ],
      child: MaterialApp(
        home: StreamLibraryScreen(
          service: service,
          libraryId: 'lib-1',
          libraryTitle: 'Films',
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    // A gated request leaves a spinner on screen, and a spinner never settles.
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }
}

/// The library screen over a real `settingsProvider`, so a case can change a
/// setting the way the settings screen does and watch what the screen makes of
/// it. Returns the container so the test can drive that change.
Future<ProviderContainer> _pumpLibraryWithSettings(
  WidgetTester tester,
  _ScriptedServer server, {
  required SettingsModel settings,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final container = ProviderContainer(
    overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
      secureSettingsStoreProvider.overrideWithValue(FakeSecureSettingsStore()),
      initialSettingsProvider.overrideWith((ref) => settings),
      jellyfinServerProvider.overrideWithValue(server),
    ],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: StreamLibraryScreen(
          service: ServiceKey.jellyfin,
          libraryId: 'lib-1',
          libraryTitle: 'Films',
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  group('the Stream library browse', () {
    testWidgets('starts at offset zero, not one page in', (tester) async {
      // `nextIntPageKey` starts at 1, so multiplying it by the page size made
      // the very first request skip the first fifty rows of every shelf.
      final server = _ScriptedServer({
        0: _page([_item('a', 'Arrival')], nextStartIndex: 1, hasMore: false),
      });

      await _pumpLibrary(tester, server);

      expect(server.requested.first, 0);
      expect(find.byType(StreamPosterTile), findsOneWidget);
    });

    testWidgets('walks past a page that came back with no rows', (
      tester,
    ) async {
      // A page can come back with no rows while the next one is full (a server
      // that filters after counting). Stopping there rendered an empty state
      // over a library that had plenty, and `PagedLayoutBuilder` never asks
      // again once the accumulated count is zero.
      final server = _ScriptedServer({
        0: _page(const [], nextStartIndex: 50, hasMore: true),
        50: _page([_item('b', 'Solaris')], nextStartIndex: 100, hasMore: false),
      });

      await _pumpLibrary(tester, server);

      expect(server.requested, [0, 50]);
      expect(find.byType(StreamPosterTile), findsOneWidget);
      expect(find.text('Nothing in progress'), findsNothing);
    });

    testWidgets('advances by the offset the server reported', (tester) async {
      // Not `pageIndex * pageSize`: both servers are explicit that a response
      // may hold a different number of rows than was asked for.
      final server = _ScriptedServer({
        0: _page([_item('a', 'Arrival')], nextStartIndex: 37, hasMore: true),
        37: _page([_item('b', 'Solaris')], nextStartIndex: 74, hasMore: false),
      });

      await _pumpLibrary(tester, server);
      await tester.pumpAndSettle();

      expect(server.requested, [0, 37]);
    });

    testWidgets('stops when the server says "more" without moving on', (
      tester,
    ) async {
      // Jellyfin computes `nextStartIndex` from the rows it sent while
      // `hasMore` compares it against `TotalRecordCount`, so an endpoint that
      // filters rows away server-side answers zero rows, an unmoved offset and
      // `hasMore: true`. Taking that at its word re-requested the same offset
      // forever: the fetch burnt its attempts, the controller appended an empty
      // page, and `PagedLayoutBuilder` fired the next fetch straight back while
      // the user sat at the bottom of the grid.
      final server = _ScriptedServer({
        0: _page([_item('a', 'Arrival')], nextStartIndex: 50, hasMore: true),
        50: _page(const [], nextStartIndex: 50, hasMore: true),
      });

      await _pumpLibrary(tester, server);
      await tester.pumpAndSettle();

      expect(server.requested, [0, 50]);
      expect(find.byType(StreamPosterTile), findsOneWidget);
    });

    testWidgets('a fetch left behind by a sort change is abandoned', (
      tester,
    ) async {
      // The offset lives on the State, which means it is shared across a
      // controller rebuild in a way `PagingState` never was, and
      // `PagingController.dispose` only detaches the result, it does not stop
      // the fetch. So the fetch has to be fenced: a stale one must not issue a
      // second request (under the *new* sort, since it read the field fresh)
      // and must not write the new sort's offset.
      final gate = Completer<void>();
      final server = _ScriptedServer(
        const {},
        shelfPages: {
          // Empty but "there is more", so an unfenced fetch walks on to a
          // second request: the observable symptom.
          _wholeByName: {0: _page(const [], nextStartIndex: 50, hasMore: true)},
          _wholeByYear: {
            0: _page(
              [_item('a', 'Arrival')],
              nextStartIndex: 50,
              hasMore: false,
            ),
          },
        },
        gates: {_wholeByName: gate},
      );

      await _pumpLibrary(tester, server, settle: false);
      expect(server.requestedShelves, [_wholeByName]);

      // Switch to Year while Name's first page is still in flight. Year is not
      // gated, so it answers straight away.
      // A spinner is on screen until the gate opens, so the menu is pumped by
      // time rather than settled.
      await tester.tap(find.byTooltip('Change sort order'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Year').last);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));

      gate.complete();
      await tester.pumpAndSettle();

      expect(server.requested, [0, 0]);
      expect(server.requestedShelves, [_wholeByName, _wholeByYear]);
      expect(find.byType(StreamPosterTile), findsOneWidget);
    });

    testWidgets('a failed first page offers a retry, never "empty"', (
      tester,
    ) async {
      // Both clients degrade a remote failure to an empty list, so a browse that
      // only saw rows told the user "This library is empty · The server reports
      // no items here" about a server that had not answered at all.
      final server = _ScriptedServer({
        0: const StreamLibraryPage.failed(startIndex: 0),
      });

      await _pumpLibrary(tester, server);

      expect(find.text('This library is empty'), findsNothing);
      expect(find.text('The server reports no items here'), findsNothing);
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('a mid-list failure keeps the rows and offers a retry', (
      tester,
    ) async {
      // The old behaviour was a silent truncation: no spinner, no message, no
      // way to ask for the rest.
      final server = _ScriptedServer({
        0: _page([_item('a', 'Arrival')], nextStartIndex: 50, hasMore: true),
        50: const StreamLibraryPage.failed(startIndex: 50),
      });

      await _pumpLibrary(tester, server);
      await tester.pumpAndSettle();

      expect(find.byType(StreamPosterTile), findsOneWidget);
      expect(
        find.textContaining('the rest of this library did not load'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
    });

    testWidgets('no viewer names the setting instead of claiming empty', (
      tester,
    ) async {
      // A Jellyfin API key is an administrator with no user attached, so
      // "unplayed" has no subject until one is chosen, and the picker lives in
      // settings, which this screen offers no path to on its own.
      final server = _ScriptedServer(
        {
          0: _page([_item('a', 'Arrival')], nextStartIndex: 1, hasMore: false),
        },
        shelfPages: {
          _unplayedByName: {0: const StreamLibraryPage.viewerRequired()},
        },
      );

      await _pumpLibrary(tester, server);
      // The whole shelf needs nobody.
      expect(find.byType(StreamPosterTile), findsOneWidget);
      expect(find.text('Choose whose watch state to show'), findsNothing);

      await tester.tap(find.text('Unplayed'));
      await tester.pumpAndSettle();

      expect(server.requestedShelves.last, _unplayedByName);
      expect(find.text('This library is empty'), findsNothing);
      expect(find.text('Choose whose watch state to show'), findsOneWidget);
      expect(find.text('Pick a viewer'), findsOneWidget);
    });

    testWidgets('choosing a viewer resolves the panel that asked for one', (
      tester,
    ) async {
      // The panel's whole point is that the user has something to act on. The
      // action lives on another route, nothing else here reads settings, and
      // `PagedLayoutBuilder` never retries a first-page error, so coming back
      // used to find the same "Choose whose watch state to show", with the
      // viewer already chosen.
      final server = _ScriptedServer(
        const {},
        shelfPages: {
          _unplayedByName: {0: const StreamLibraryPage.viewerRequired()},
        },
      );

      final container = await _pumpLibraryWithSettings(
        tester,
        server,
        settings: settingsWith(
          jellyfinUrl: 'https://jellyfin.lan:8096',
          jellyfinApiKey: 'abcdef1234567890',
        ),
      );
      await tester.tap(find.text('Unplayed'));
      await tester.pumpAndSettle();
      expect(find.text('Choose whose watch state to show'), findsOneWidget);

      // What the settings screen does when a household member is picked.
      server.shelfPages[_unplayedByName]![0] = _page(
        [_item('a', 'Arrival')],
        nextStartIndex: 1,
        hasMore: false,
      );
      await container
          .read(settingsProvider.notifier)
          .updateSettings(
            container
                .read(settingsProvider)
                .copyWithViewer(ServiceKey.jellyfin, 'u-1'),
          );
      await tester.pumpAndSettle();

      expect(find.text('Choose whose watch state to show'), findsNothing);
      expect(find.byType(StreamPosterTile), findsOneWidget);
    });

    testWidgets('a genuinely empty library still reads as empty', (
      tester,
    ) async {
      // The distinction has to cut both ways: an answered request with nothing
      // in it is an empty state, and offering a retry there would be noise.
      final server = _ScriptedServer({0: const StreamLibraryPage.empty()});

      await _pumpLibrary(tester, server);

      expect(find.text('This library is empty'), findsOneWidget);
      expect(find.text('The server reports no items here.'), findsOneWidget);
      expect(find.text('Retry'), findsNothing);
      expect(find.text('Show all'), findsNothing);
    });

    testWidgets('an unplayed shelf with nothing on it offers the whole one', (
      tester,
    ) async {
      final server = _ScriptedServer(
        {
          0: _page([_item('a', 'Arrival')], nextStartIndex: 1, hasMore: false),
        },
        shelfPages: {
          _unplayedByName: {0: const StreamLibraryPage.empty()},
        },
      );

      await _pumpLibrary(tester, server);
      await tester.tap(find.text('Unplayed'));
      await tester.pumpAndSettle();

      expect(find.text('Everything has been played'), findsOneWidget);
      expect(find.byType(StreamPosterTile), findsNothing);

      await tester.tap(find.text('Show all'));
      await tester.pumpAndSettle();

      expect(server.requestedShelves.last, _wholeByName);
      expect(find.text('Everything has been played'), findsNothing);
      expect(find.byType(StreamPosterTile), findsOneWidget);
    });

    testWidgets('opens on the whole library in Name order', (tester) async {
      final server = _ScriptedServer({
        0: _page([_item('a', 'Arrival')], nextStartIndex: 1, hasMore: false),
      });

      await _pumpLibrary(tester, server);

      expect(server.requestedShelves, [_wholeByName]);
      // The bar: two chips and the sort, which says what it is sorted by.
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Unplayed'), findsOneWidget);
      expect(find.byTooltip('Change sort order'), findsOneWidget);
      expect(find.text('Name'), findsOneWidget);
      // The lenses of the old page are gone.
      for (final gone in ['Continue', 'Next up', 'Recent', 'A–Z']) {
        expect(find.text(gone), findsNothing);
      }
    });

    testWidgets('choosing Year asks again in that order', (tester) async {
      final server = _ScriptedServer(
        {
          0: _page([_item('a', 'Arrival')], nextStartIndex: 1, hasMore: false),
        },
        shelfPages: {
          _wholeByYear: {
            0: _page(
              [_item('b', 'Solaris')],
              nextStartIndex: 1,
              hasMore: false,
            ),
          },
        },
      );

      await _pumpLibrary(tester, server);
      await tester.tap(find.byTooltip('Change sort order'));
      await tester.pumpAndSettle();
      // The menu lists every order the server was measured to take.
      expect(find.text('Date added'), findsOneWidget);
      await tester.tap(find.text('Year').last);
      await tester.pumpAndSettle();

      expect(server.requestedShelves, [_wholeByName, _wholeByYear]);
      expect(server.requested, [0, 0]);
      // The sort control now reads the new order.
      expect(
        find.descendant(
          of: find.byTooltip('Change sort order'),
          matching: find.text('Year'),
        ),
        findsOneWidget,
      );
    });

    testWidgets('Unplayed asks for the unplayed shelf and All goes back', (
      tester,
    ) async {
      final server = _ScriptedServer({
        0: _page([_item('a', 'Arrival')], nextStartIndex: 1, hasMore: false),
      });

      await _pumpLibrary(tester, server);
      await tester.tap(find.text('Unplayed'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();

      expect(server.requestedShelves, [
        _wholeByName,
        _unplayedByName,
        _wholeByName,
      ]);
    });

    testWidgets('a tile names its title and year under the poster, and '
        'speaks them once', (tester) async {
      final handle = tester.ensureSemantics();
      final server = _ScriptedServer({
        0: _page([_item('a', 'Arrival')], nextStartIndex: 1, hasMore: false),
      });

      await _pumpLibrary(tester, server);

      expect(find.text('Arrival'), findsOneWidget);
      expect(find.text('2016'), findsOneWidget);
      // One button, named by the full title: the caption is not a second
      // reading of it.
      expect(find.bySemanticsLabel('Arrival'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('at twice the reading size every cell holds its caption', (
      tester,
    ) async {
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final server = _ScriptedServer({
        0: _page(
          [
            for (var i = 0; i < 6; i++)
              _item('$i', 'A title long enough to be cut $i'),
          ],
          nextStartIndex: 6,
          hasMore: false,
        ),
      });

      await _pumpLibrary(tester, server);

      expect(tester.takeException(), isNull);
      expect(find.text('2016'), findsWidgets);
    });
  });
}
