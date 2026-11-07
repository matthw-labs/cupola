import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/home/data/last_known/continue_watching_last_known.dart';
import 'package:cupola/features/home/data/last_known/resume_row_codec.dart';
import 'package:cupola/features/home/data/last_known/stream_item_codec.dart';
import 'package:cupola/features/home/data/resume.dart';
import 'package:cupola/features/home/presentation/widgets/continue_watching_module.dart';
import 'package:cupola/features/home/presentation/widgets/home_as_of_line.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/services/domain/source_coverage.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/models/stream_item.dart';
import 'package:cupola/features/home/data/home_last_known.dart';

import '../../../test_helpers/settings_scope.dart';

final _now = DateTime(2026, 10, 12, 20, 53);

const _episode = StreamItem(
  id: 'e1',
  title: 'The Second Cycle',
  subtitle: 'Cosmos Laundromat\u00A0· S2\u00A0E3',
  kind: StreamItemKind.episode,
  // No artwork: a picture would load forever in a test.
  posterPath: null,
  year: null,
  runtimeMs: 1500000,
  isPlayed: false,
  resumeOffsetMs: 1200000,
  unplayedChildCount: null,
  seasonNumber: 2,
  episodeNumber: 3,
);

const _movie = StreamItem(
  id: 'm1',
  title: 'Sintel',
  subtitle: '2010',
  kind: StreamItemKind.movie,
  posterPath: null,
  year: 2010,
  runtimeMs: 888000,
  isPlayed: false,
  resumeOffsetMs: 444000,
  unplayedChildCount: null,
  externalIds: StreamExternalIds(tmdb: '45745', imdb: 'tt1727587'),
);

ResumeRow _row(
  StreamItem item, {
  ServiceKey service = ServiceKey.jellyfin,
  String instanceId = 'jellyfin',
}) => (
  service: service,
  instanceId: instanceId,
  connectionName: null,
  item: item,
);

HomeResume _resume(
  List<ResumeRow> rows, {
  List<String> viewerMissing = const [],
  SourceCoverage? coverage,
}) => (
  rows: rows,
  coverage: coverage ?? SourceCoverage.answeredBy(ServiceKey.jellyfin),
  viewerMissing: viewerMissing,
);

/// Continue watching at a cold start: the titles somebody left half way, as
/// they were last drawn, until the live answer comes.
void main() {
  group('a cold start', () {
    late LastKnownStore store;
    setUp(() => store = LastKnownStore.memory());

    /// One run of the app: a fresh scope over the same [store], as a start
    /// over the same file would be.
    Future<void> run(
      WidgetTester tester,
      Future<HomeResume> Function() resume, {
      SettingsModel Function(SettingsModel)? customize,
      DateTime? now,
    }) async {
      tester.view.physicalSize = const Size(1170, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final clock = now ?? _now;
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            ...await settingsScopeOverrides(
              configured: const [ServiceKey.jellyfin],
              customize: customize,
            ),
            lastKnownStoreProvider.overrideWithValue(store),
            calendarClockProvider.overrideWithValue(() => clock),
            homeResumeProvider.overrideWith((ref) => resume()),
          ],
          child: MaterialApp(
            theme: AppTheme.darkTheme(),
            home: const Scaffold(
              body: Column(
                children: [HomeAsOfLine(), HomeContinueWatchingModule()],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    Future<void> firstRun(
      WidgetTester tester, {
      SettingsModel Function(SettingsModel)? customize,
    }) async {
      await run(
        tester,
        () async => _resume([_row(_episode), _row(_movie)]),
        customize: customize,
      );
      await tester.pumpAndSettle();
      expect(find.text('Cosmos Laundromat'), findsOne);
      expect(find.textContaining('As of'), findsNothing);
    }

    testWidgets('draws the titles as they were at once, says so, then the '
        'live ones', (tester) async {
      await firstRun(tester);

      final answer = Completer<HomeResume>();
      await run(tester, () => answer.future);
      // No skeleton: the rows the person last saw, and the one line.
      expect(find.text('Cosmos Laundromat'), findsOne);
      expect(find.text('S2\u00A0E3\u00A0· The Second Cycle'), findsOne);
      expect(find.text('Sintel'), findsOne);
      expect(find.text('As of 20:53\u00A0· checking now'), findsOne);
      // Where each stopped is a fact of then, drawn as it was: the time left
      // and the bar.
      expect(find.text('5\u00A0min left'), findsOne);
      expect(find.byType(LinearProgressIndicator), findsNWidgets(2));

      answer.complete(
        _resume([
          _row(
            const StreamItem(
              id: 'm2',
              title: 'Spring',
              subtitle: '2019',
              kind: StreamItemKind.movie,
              posterPath: null,
              year: 2019,
              runtimeMs: 450000,
              isPlayed: false,
              resumeOffsetMs: 90000,
              unplayedChildCount: null,
            ),
          ),
          _row(_movie),
        ]),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cosmos Laundromat'), findsNothing);
      expect(find.text('Spring'), findsOne);
      expect(find.text('Sintel'), findsOne);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('a row from the drawing opens the page the live row does', (
      tester,
    ) async {
      await firstRun(tester);
      await run(tester, () => Completer<HomeResume>().future);

      final rows = tester
          .widgetList<ContinueWatchingRow>(find.byType(ContinueWatchingRow))
          .toList();
      expect(rows.map((row) => row.key), [
        const ValueKey('jellyfin/e1'),
        const ValueKey('jellyfin/m1'),
      ]);
      // A movie opens on its Media page by the ids the server gave.
      expect(MediaKey.ofStreamItem(rows.last.row.item), MediaKey.movie(45745));
      expect(rows.first.row.item.kind, StreamItemKind.episode);
    });

    testWidgets('a live read that fails keeps the drawing at full ink, over '
        'the failure, and stops checking', (tester) async {
      await firstRun(tester);

      await run(
        tester,
        () async =>
            throw const ClassifiedFailure(ServiceFailureReason.unreachable),
      );
      await tester.pumpAndSettle();
      expect(find.text('Cosmos Laundromat'), findsOne);
      expect(find.text('Sintel'), findsOne);
      expect(find.textContaining('did not answer'), findsOne);
      expect(find.text('As of 20:53'), findsOne);
      expect(find.byType(Opacity), findsNothing);
    });

    testWidgets('another server draws nothing of it', (tester) async {
      await firstRun(tester);
      // The same server draws it: the drawing is there to be refused.
      await run(tester, () => Completer<HomeResume>().future);
      expect(find.text('Cosmos Laundromat'), findsOne);

      await run(
        tester,
        () => Completer<HomeResume>().future,
        customize: (settings) => settings.copyWithService(
          ServiceKey.jellyfin,
          url: 'https://other.test',
          apiKey: 'jellyfin-key',
        ),
      );
      expect(find.text('Cosmos Laundromat'), findsNothing);
      expect(find.text('Sintel'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('another household member draws nothing of it', (tester) async {
      await firstRun(
        tester,
        customize: (settings) =>
            settings.copyWithViewer(ServiceKey.jellyfin, 'anna'),
      );

      // The same member draws it: the drawing is there to be refused.
      await run(
        tester,
        () => Completer<HomeResume>().future,
        customize: (settings) =>
            settings.copyWithViewer(ServiceKey.jellyfin, 'anna'),
      );
      expect(find.text('Cosmos Laundromat'), findsOne);

      await run(
        tester,
        () => Completer<HomeResume>().future,
        customize: (settings) =>
            settings.copyWithViewer(ServiceKey.jellyfin, 'ben'),
      );
      expect(find.text('Cosmos Laundromat'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('a live answer with nothing in progress replaces the '
        'drawing: what was finished is not drawn again', (tester) async {
      await firstRun(tester);
      await run(tester, () async => _resume(const []));
      await tester.pumpAndSettle();
      expect(find.text('Continue watching'), findsNothing);

      await run(tester, () => Completer<HomeResume>().future);
      // The loading frame, never the rows that were finished since, and
      // nothing dated: there is nothing drawn from the past.
      expect(find.text('Cosmos Laundromat'), findsNothing);
      expect(find.text('Sintel'), findsNothing);
      expect(find.textContaining('As of'), findsNothing);
    });

    testWidgets('a read with every server silent is not kept', (tester) async {
      await firstRun(tester);
      await run(
        tester,
        () async => _resume(
          const [],
          coverage: SourceCoverage.failure(
            ServiceKey.jellyfin,
            const ClassifiedFailure(ServiceFailureReason.unreachable),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await run(tester, () => Completer<HomeResume>().future);
      expect(find.text('Cosmos Laundromat'), findsOne);
      expect(find.text('As of 20:53\u00A0· checking now'), findsOne);
    });

    testWidgets('the question of who you are is kept with the titles, and '
        'dates nothing by itself', (tester) async {
      // A Jellyfin with no member chosen, and one title in progress.
      await run(
        tester,
        () async => _resume([_row(_movie)], viewerMissing: const ['jellyfin']),
      );
      await tester.pumpAndSettle();
      expect(find.text('Which Jellyfin user are you?'), findsOne);

      await run(tester, () => Completer<HomeResume>().future);
      expect(find.text('Sintel'), findsOne);
      expect(find.text('Which Jellyfin user are you?'), findsOne);
      expect(find.text('As of 20:53\u00A0· checking now'), findsOne);

      // Only the question: nothing drawn from the past to date.
      await run(
        tester,
        () async => _resume(const [], viewerMissing: const ['jellyfin']),
      );
      await tester.pumpAndSettle();
      await run(tester, () => Completer<HomeResume>().future);
      expect(find.text('Which Jellyfin user are you?'), findsOne);
      expect(find.textContaining('As of'), findsNothing);
    });
  });

  group('the codecs', () {
    const episode = StreamItem(
      id: 'e1',
      title: 'The Second Cycle',
      subtitle: 'Cosmos Laundromat\u00A0· S2\u00A0E3',
      kind: StreamItemKind.episode,
      posterPath: '/Items/e1/Images/Primary?tag=abc',
      backdropPath: '/Items/s1/Images/Backdrop?tag=def',
      year: 2015,
      runtimeMs: 1500000,
      isPlayed: false,
      resumeOffsetMs: 1200000,
      unplayedChildCount: 4,
      externalIds: StreamExternalIds(tmdb: '1', tvdb: '2', imdb: 'tt3'),
      seasonNumber: 2,
      episodeNumber: 3,
      seriesId: 'jf-cosmos',
    );

    Object? onDisk(Object? json) => jsonDecode(jsonEncode(json));

    test('an item survives its codec whole', () {
      final back = streamItemFromJson(onDisk(streamItemToJson(episode)))!;
      expect(back.id, episode.id);
      expect(back.title, episode.title);
      expect(back.subtitle, episode.subtitle);
      expect(back.kind, episode.kind);
      expect(back.posterPath, episode.posterPath);
      expect(back.backdropPath, episode.backdropPath);
      expect(back.year, episode.year);
      expect(back.runtimeMs, episode.runtimeMs);
      expect(back.isPlayed, episode.isPlayed);
      expect(back.resumeOffsetMs, episode.resumeOffsetMs);
      expect(back.unplayedChildCount, episode.unplayedChildCount);
      expect(back.externalIds, episode.externalIds);
      expect(back.seasonNumber, episode.seasonNumber);
      expect(back.episodeNumber, episode.episodeNumber);
      expect(back.seriesId, episode.seriesId);
      expect(back.resumeProgress, episode.resumeProgress);
      // What an item does not carry stays what it was.
      final bare = streamItemFromJson(onDisk(streamItemToJson(_movie)))!;
      expect(bare.posterPath, isNull);
      expect(bare.backdropPath, isNull);
      expect(bare.seasonNumber, isNull);
      expect(bare.seriesId, isNull);
      expect(bare.externalIds, _movie.externalIds);
      expect(
        streamItemFromJson(
          onDisk(
            streamItemToJson(
              const StreamItem(
                id: 'x',
                title: 'No ids',
                subtitle: null,
                kind: StreamItemKind.movie,
                posterPath: null,
                year: null,
                runtimeMs: null,
                isPlayed: true,
                resumeOffsetMs: null,
                unplayedChildCount: null,
              ),
            ),
          ),
        )!.externalIds,
        StreamExternalIds.none,
      );
    });

    test('a row survives its codec whole', () {
      final row = (
        service: ServiceKey.plex,
        instanceId: 'plex-2',
        connectionName: 'Upstairs',
        item: episode,
      );
      final back = resumeRowFromJson(onDisk(resumeRowToJson(row)))!;
      expect(back.service, ServiceKey.plex);
      expect(back.instanceId, 'plex-2');
      expect(back.connectionName, 'Upstairs');
      expect(
        streamItemToJson(back.item),
        streamItemToJson(episode),
        reason: 'the item is kept whole',
      );
    });

    test('a broken record is refused, never half read', () {
      final good = streamItemToJson(episode);
      expect(streamItemFromJson(null), isNull);
      expect(streamItemFromJson('nope'), isNull);
      expect(streamItemFromJson({...good}..remove('id')), isNull);
      expect(streamItemFromJson({...good}..remove('title')), isNull);
      expect(streamItemFromJson({...good, 'kind': 'cartoon'}), isNull);
      expect(streamItemFromJson({...good, 'year': '2015'}), isNull);
      expect(streamItemFromJson({...good, 'isPlayed': 'yes'}), isNull);
      expect(streamItemFromJson({...good, 'externalIds': 7}), isNull);

      final row = resumeRowToJson(_row(episode));
      expect(resumeRowFromJson({...row}..remove('instanceId')), isNull);
      expect(resumeRowFromJson({...row, 'item': 'nope'}), isNull);
      expect(resumeRowFromJson({...row, 'service': 'sonarr'}), isNull);
      expect(resumeRowFromJson({...row, 'service': 'nowhere'}), isNull);
      expect(
        resumeRowFromJson({
          ...row,
          'item': {...good, 'kind': 'cartoon'},
        }),
        isNull,
      );

      // A drawing with one row it cannot read is not drawn at all.
      final slot = continueWatchingLastKnown;
      final data =
          onDisk(slot.encode(_resume([_row(_episode)]), _keep))! as Map;
      expect(
        slot.decode(data, (_) => throw StateError('no pictures')),
        isNotNull,
      );
      expect(
        slot.decode({
          ...data,
          'rows': [
            ...data['rows'] as List,
            {'service': 'sonarr'},
          ],
        }, (_) => throw StateError('no pictures')),
        isNull,
      );
      expect(slot.decode('nope', (_) => throw StateError('')), isNull);
      expect(slot.decode({'rows': []}, (_) => throw StateError('')), isNull);
    });

    test(
      'no credential is kept: the paths, never an address a server built',
      () {
        final json = jsonEncode(
          continueWatchingLastKnown.encode(
            _resume([
              _row(episode),
              _row(
                const StreamItem(
                  id: 'm9',
                  title: 'Leaky',
                  subtitle: null,
                  kind: StreamItemKind.movie,
                  // A path that carries a key in its query is not kept.
                  posterPath: '/Items/m9/Images/Primary?api_key=SECRET-KEY',
                  backdropPath:
                      '/library/metadata/9/art?X-Plex-Token=SECRET-TOKEN',
                  year: null,
                  runtimeMs: 100,
                  isPlayed: false,
                  resumeOffsetMs: 50,
                  unplayedChildCount: null,
                ),
              ),
            ]),
            _keep,
          ),
        );
        expect(json, contains('/Items/e1/Images/Primary?tag=abc'));
        expect(json, isNot(contains('SECRET')));
        expect(json, isNot(contains('jellyfin-key')));
        expect(json, isNot(contains('.test')));
        expect(json, isNot(contains('Authorization')));
        expect(json, isNot(contains('X-Emby')));
      },
    );

    test('what is kept is bounded, and a read of nothing is not kept', () {
      final many = [
        for (var i = 0; i < 20; i++)
          _row(
            StreamItem(
              id: 'i$i',
              title: 'Title $i',
              subtitle: null,
              kind: StreamItemKind.movie,
              posterPath: null,
              year: null,
              runtimeMs: 100,
              isPlayed: false,
              resumeOffsetMs: 50,
              unplayedChildCount: null,
            ),
          ),
      ];
      final kept =
          continueWatchingLastKnown.encode(_resume(many), _keep)! as Map;
      expect(kept['rows'], hasLength(continueWatchingRowLimit * 2));
      expect(
        continueWatchingLastKnown.encode(
          _resume(
            const [],
            coverage: SourceCoverage.failure(
              ServiceKey.jellyfin,
              const ClassifiedFailure(ServiceFailureReason.unreachable),
            ),
          ),
          _keep,
        ),
        isNull,
      );
    });
  });
}

/// Keeps the pictures as the Home does, against no connection: a picture
/// with headers has nothing to be kept by, and only public ones are.
final _keep = storedImageKeeper(const SettingsModel());
