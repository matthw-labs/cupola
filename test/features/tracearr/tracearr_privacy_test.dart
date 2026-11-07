import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/data/tracearr_events.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_history.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_media_stats.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_playback.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_stream.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_user.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_violation.dart';

import '../../test_helpers/capturing_http_adapter.dart';
import '../../test_helpers/fixtures.dart';

/// What a log line, a failure message or a screenshot of a debug print must
/// never show: addresses, places and people from the fixtures, and the key.
const _secrets = [
  '192.0.2.',
  'Valmora',
  'Port Aster',
  'Nordavia',
  'Eastmark',
  'North Reach',
  'Anna',
  'anna',
  'Luca',
  'luca',
  'Lantern Keeper',
  'Harbor Lights',
  'Low Tide',
  'anna@example.test',
  'trr_pub_',
];

void _expectClean(Object? thing, {String? why}) {
  final text = '$thing';
  for (final secret in _secrets) {
    expect(
      text,
      isNot(contains(secret)),
      reason: '${why ?? thing.runtimeType} prints "$secret": $text',
    );
  }
}

void main() {
  final violations = TracearrPage.fromJson(
    jsonFixture('tracearr/violations.json'),
    TracearrViolation.fromJson,
  ).items;
  final detail = TracearrViolation.fromJson(
    jsonFixtureMap('tracearr/violation_detail.json'),
  );

  group('a violation', () {
    test('never prints the address or the place in its data', () {
      for (final violation in [...violations, detail]) {
        _expectClean(violation, why: violation.rule.name);
      }
    });

    test('prints its id and severity and no more', () {
      expect(
        violations.first.toString(),
        'TracearrViolation(11111111-aaaa-4bbb-8ccc-000000000001, high)',
      );
    });

    test('hands out places and numbers, never an address', () {
      final travel = detail.impossibleTravel!;

      _expectClean(travel);
      _expectClean(travel.from);
      _expectClean(travel.to);
      expect(travel.from!.label, isNot(contains('192.0.2')));
      expect(travel.to!.label, isNot(contains('192.0.2')));
      _expectClean(violations[1].concurrentStreams);
    });

    test('keeps its data private, so a rule we do not know shows nothing', () {
      final source = File(
        'lib/features/tracearr/domain/models/tracearr_violation.dart',
      ).readAsStringSync();

      expect(source, contains('final TracearrJson _data;'));
      expect(
        RegExp(
          r'^\s*(final\s+)?\S*\s+get\s+data\b',
          multiLine: true,
        ).hasMatch(source),
        isFalse,
        reason: 'no public reader of the free-form data',
      );
      expect(violations[2].impossibleTravel, isNull);
      expect(violations[2].concurrentStreams, isNull);
    });
  });

  group('what a person watched', () {
    test('rows print their id and nothing of the viewing', () {
      final stream = TracearrStreams.fromJson(
        jsonFixture('tracearr/streams.json'),
      );
      final history = TracearrPage.fromJson(
        jsonFixture('tracearr/history_page.json'),
        TracearrHistoryEntry.fromJson,
      );

      for (final row in [...stream.streams, ...history.items]) {
        _expectClean(row);
        _expectClean(row is TracearrStream ? row.person : null);
      }
      _expectClean(stream);
      _expectClean(stream.summary);
      _expectClean(history);
    });

    test('a person, an account and their stats print no name', () {
      final users = TracearrPage.fromJson(
        jsonFixture('tracearr/users.json'),
        TracearrUser.fromJson,
      );

      for (final user in users.items) {
        _expectClean(user);
        for (final account in user.accounts) {
          _expectClean(account);
        }
      }
      _expectClean(
        TracearrUserStats.fromJson(jsonFixture('tracearr/user_stats.json')),
      );
      _expectClean(const TracearrPerson());
      _expectClean(
        TracearrStream.fromJson({'id': 's', 'username': 'Anna'}).person,
      );
    });

    test('watchers print no one', () {
      final watchers = TracearrMediaWatchers.fromJson(
        jsonFixture('tracearr/watchers_movie.json'),
      );

      for (final watcher in watchers.watchers) {
        _expectClean(watcher);
      }
    });

    test('the live events print no one either', () {
      final text = File('test/fixtures/tracearr/events.sse').readAsStringSync();
      final frames = SseParser().add(text);

      for (final frame in frames) {
        final event = tracearrEventFrom(frame);
        if (event is TracearrStreamStarted) _expectClean(event.stream);
        if (event is TracearrViolationCreated) _expectClean(event.violation);
        if (event is TracearrStreamStopped) _expectClean(event.stream);
      }
    });
  });

  group('the key', () {
    const key = 'trr_pub_neverprintmeneverprintmeneverprintme00001';

    test('is not in the text of a failed read', () async {
      final adapter = CapturingHttpAdapter(
        statusCode: 401,
        response: const {'message': 'Missing or invalid Authorization header'},
      );
      final client = TracearrClient(baseUrl: 'https://t.test', apiKey: key)
        ..dio.httpClientAdapter = adapter;
      addTearDown(client.close);

      Object? caught;
      try {
        await client.getStreams();
      } on DioException catch (error) {
        caught = error;
      }

      expect(caught, isA<DioException>());
      expect('$caught', isNot(contains(key)));
      expect((caught! as DioException).message ?? '', isNot(contains(key)));
    });

    test('has one place in the client, the Authorization header', () {
      final source = File(
        'lib/features/tracearr/data/tracearr_client.dart',
      ).readAsLinesSync().where((line) => !line.trimLeft().startsWith('//'));
      final uses = source.where((line) => line.contains('apiKey')).toList();

      expect(
        uses.where((line) => line.contains(r'${apiKey')),
        hasLength(1),
        reason: 'one interpolation, the Bearer header',
      );
      expect(uses.where((line) => line.contains('Bearer')), hasLength(1));
    });

    test('is not logged or printed by anything under the feature', () {
      final offenders = [
        for (final file
            in Directory('lib/features/tracearr')
                .listSync(recursive: true)
                .whereType<File>()
                .where((f) => f.path.endsWith('.dart')))
          for (final (index, line) in file.readAsLinesSync().indexed)
            if (!line.trimLeft().startsWith('//') &&
                RegExp(
                  r'\b(print|debugPrint|log|developer\.log)\(',
                ).hasMatch(line))
              '${file.path}:${index + 1}',
      ];

      expect(offenders, isEmpty);
    });
  });
}
