import 'package:cupola/features/tracearr/domain/models/tracearr_json.dart';

/// One page of a cursor-paged v2 read (`data` plus `meta`).
final class TracearrPage<T> {
  const TracearrPage({
    required this.items,
    this.nextCursor,
    this.pageSize,
    this.dropped = 0,
  });

  /// Reads a page whose rows are built by [fromJson].
  ///
  /// A body that is not an object at all is a [FormatException]: that is a
  /// wrong answer (a web page, another product), not a short page. A row that
  /// cannot be read is dropped and counted in [dropped].
  factory TracearrPage.fromJson(
    Object? body,
    T Function(TracearrJson json) fromJson,
  ) {
    final json = asTracearrJson(body);
    if (json == null) {
      throw const FormatException('Tracearr page is not an object');
    }
    final read = tracearrRows(json['data'], fromJson);
    final meta = json.object('meta');
    return TracearrPage(
      items: read.rows,
      nextCursor: meta?.text('nextCursor'),
      pageSize: meta?.integer('pageSize'),
      dropped: read.dropped,
    );
  }

  final List<T> items;

  /// The cursor of the next page, null on the last one.
  final String? nextCursor;

  final int? pageSize;

  /// Rows the server sent that we could not read.
  final int dropped;

  bool get hasMore => nextCursor != null;

  @override
  String toString() =>
      'TracearrPage(${items.length} rows, hasMore: $hasMore, dropped: $dropped)';
}
