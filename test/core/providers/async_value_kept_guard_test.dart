import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/providers/async_value_kept.dart';

final _source = FutureProvider.autoDispose<int>((ref) async => 1);
final _derived = FutureProvider.autoDispose<int>(
  (ref) async => ref.watch(_source.future),
);

void main() {
  test('a reload keeps the mapped answer, where whenData drops it', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    container.listen(_derived, (_, _) {});
    await container.read(_derived.future);

    // A poll's tick: the source is asked again and the derived read reloads.
    container.invalidate(_source);
    container.read(_source);
    final reloading = container.read(_derived);

    expect(reloading.isLoading, isTrue);
    expect(reloading.hasValue, isTrue);
    expect(
      reloading.whenData((v) => '$v').hasValue,
      isFalse,
      reason: 'Riverpod drops the answer: the page drew its skeleton',
    );
    expect(reloading.whenDataKept((v) => '$v').value, '1');
  });

  test('a first load, a failure and an answer are whenData\'s', () {
    expect(const AsyncLoading<int>().whenDataKept((v) => v).isLoading, isTrue);
    expect(const AsyncData(2).whenDataKept((v) => v * 2).value, 4);
    final failed = AsyncError<int>('no', StackTrace.empty);
    expect(failed.whenDataKept((v) => v).hasError, isTrue);
  });

  test('lib maps a drawn answer through whenDataKept, never whenData', () {
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        if (line.startsWith('//')) continue;
        if (line.contains('.whenData(')) offenders.add('${file.path}:${i + 1}');
      }
    }
    expect(offenders, isEmpty);
  });
}
