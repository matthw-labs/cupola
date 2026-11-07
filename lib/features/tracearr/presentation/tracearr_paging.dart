import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_page.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';

/// The rows read so far from a list Tracearr answers a page at a time, and
/// what is left to ask.
///
/// History, Users and Violations all page by cursor and give no total, so
/// every one of them is this: the rows, the cursor of the next page (null on
/// the last), and whether a later page is out or failed. A later page that
/// fails keeps the rows already on the screen and says so where the next page
/// would have been, never turning the whole list into an error.
@immutable
final class TracearrRows<T> {
  const TracearrRows({
    required this.items,
    this.nextCursor,
    this.loadingMore = false,
    this.moreFailed = false,
  });

  final List<T> items;

  /// The cursor of the next page, null when this is the end.
  final String? nextCursor;

  final bool loadingMore;

  /// The last attempt at a next page failed: the rows stand, and a Retry asks
  /// the same page again.
  final bool moreFailed;

  bool get hasMore => nextCursor != null;

  TracearrRows<T> copyWith({
    List<T>? items,
    String? Function()? nextCursor,
    bool? loadingMore,
    bool? moreFailed,
  }) => TracearrRows(
    items: items ?? this.items,
    nextCursor: nextCursor == null ? this.nextCursor : nextCursor(),
    loadingMore: loadingMore ?? this.loadingMore,
    moreFailed: moreFailed ?? this.moreFailed,
  );
}

/// A list read by cursor, for a screen's own provider file to subclass: it
/// says how one page is asked ([fetch]) and the rest (the first read, `Load
/// more`, what a failed second page does) is here once.
///
/// A subclass is the screen's state: it may watch what narrows the list (a
/// filter) in [fetch]'s reads, and the list is read again from the first page
/// when that changes, because [build] re-runs.
abstract class TracearrPagedList<T> extends AsyncNotifier<TracearrRows<T>> {
  /// One page, from [cursor] (null for the first).
  Future<TracearrPage<T>> fetch(TracearrClient client, String? cursor);

  /// Whether a row is worth listing. A row the server sent that the screen
  /// should not draw is dropped here, never after the count was made.
  bool keep(T row) => true;

  /// Counts the reads from the first page. A next page that answers after the
  /// filter changed belongs to a list that is gone, so [loadMore] drops it
  /// when this moved on while it waited.
  int _generation = 0;

  @override
  Future<TracearrRows<T>> build() async {
    _generation++;
    final page = await fetch(ref.watch(tracearrClientProvider), null);
    return TracearrRows(
      items: page.items.where(keep).toList(growable: false),
      nextCursor: page.nextCursor,
    );
  }

  /// Asks the next page and appends it. Nothing when there is none, or one is
  /// already out.
  Future<void> loadMore() async {
    final current = state.asData?.value;
    if (current == null || !current.hasMore || current.loadingMore) return;
    final started = _generation;
    state = AsyncData(current.copyWith(loadingMore: true, moreFailed: false));
    try {
      final page = await fetch(
        ref.read(tracearrClientProvider),
        current.nextCursor,
      );
      if (started != _generation) return;
      state = AsyncData(
        current.copyWith(
          items: [...current.items, ...page.items.where(keep)],
          nextCursor: () => page.nextCursor,
          loadingMore: false,
        ),
      );
    } catch (_) {
      if (started != _generation) return;
      state = AsyncData(current.copyWith(loadingMore: false, moreFailed: true));
    }
  }
}

/// What ends a paged list: `Load more` while a page follows, the spinner while
/// it is out, and the sentence with `Retry` when it failed.
class TracearrLoadMore extends StatelessWidget {
  const TracearrLoadMore({
    super.key,
    required this.rows,
    required this.onLoadMore,
    required this.noun,
  });

  final TracearrRows<Object?> rows;
  final VoidCallback onLoadMore;

  /// What the list holds, plural (`entries`), for the failure line.
  final String noun;

  @override
  Widget build(BuildContext context) {
    if (!rows.hasMore) return const SizedBox.shrink();
    if (rows.loadingMore) {
      return const Padding(
        padding: EdgeInsets.all(AppSpacing.md),
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final failed = rows.moreFailed;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (failed)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              'Could not ask for more $noun',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: CupolaThemeColors.of(context).dimText,
              ),
            ),
          ),
        OutlinedButton.icon(
          onPressed: onLoadMore,
          icon: Icon(
            failed ? Icons.refresh_rounded : Icons.expand_more_rounded,
          ),
          label: Text(failed ? Lexicon.retry : 'Load more'),
        ),
      ],
    );
  }
}
