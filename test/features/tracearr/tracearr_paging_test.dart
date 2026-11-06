import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_paging.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

class _Scope extends Notifier<String> {
  @override
  String build() => 'A';

  void pick(String value) => state = value;
}

final _scope = NotifierProvider<_Scope, String>(_Scope.new);

/// Hands out each page through a completer the test holds, so the order in
/// which a read answers is the test's, not the clock's.
final _pending = <String, Completer<TracearrPage<String>>>{};

class _List extends TracearrPagedList<String> {
  @override
  Future<TracearrPage<String>> fetch(TracearrClient client, String? cursor) {
    final scope = ref.watch(_scope);
    if (cursor == null) {
      return Future.value(
        TracearrPage(items: ['$scope-1'], nextCursor: 'next'),
      );
    }
    return (_pending['$scope-$cursor'] = Completer()).future;
  }
}

final _provider = AsyncNotifierProvider<_List, TracearrRows<String>>(_List.new);

void main() {
  test('a page that answers after the scope changed is dropped', () async {
    final container = ProviderContainer(
      overrides: [
        tracearrClientProvider.overrideWithValue(
          TracearrClient(baseUrl: 'http://tracearr.test', apiKey: 'trr_pub_t'),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(_provider, (_, _) {});

    await container.read(_provider.future);
    final late = container.read(_provider.notifier).loadMore();
    await Future<void>.delayed(Duration.zero);

    container.read(_scope.notifier).pick('B');
    final b = await container.read(_provider.future);
    expect(b.items, ['B-1']);

    _pending['A-next']!.complete(
      TracearrPage(items: ['A-2'], nextCursor: null),
    );
    await late;

    final after = container.read(_provider).requireValue;
    expect(after.items, ['B-1']);
    expect(after.nextCursor, 'next');
    expect(after.loadingMore, isFalse);
  });

  test('a page that fails after the scope changed is dropped too', () async {
    final container = ProviderContainer(
      overrides: [
        tracearrClientProvider.overrideWithValue(
          TracearrClient(baseUrl: 'http://tracearr.test', apiKey: 'trr_pub_t'),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.listen(_provider, (_, _) {});

    await container.read(_provider.future);
    final late = container.read(_provider.notifier).loadMore();
    await Future<void>.delayed(Duration.zero);
    container.read(_scope.notifier).pick('B');
    await container.read(_provider.future);

    _pending['A-next']!.completeError(StateError('late'));
    await late;

    expect(container.read(_provider).requireValue.moreFailed, isFalse);
  });
}
