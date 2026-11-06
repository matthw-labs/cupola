/// A decoded JSON object.
typedef TracearrJson = Map<String, Object?>;

/// [value] as an object, or null when it is anything else.
///
/// A map with non-string keys is not JSON we can read, so it is null too.
TracearrJson? asTracearrJson(Object? value) {
  if (value is Map<String, Object?>) return value;
  if (value is Map) {
    if (value.keys.any((key) => key is! String)) return null;
    return Map<String, Object?>.from(value);
  }
  return null;
}

final RegExp _digits = RegExp(r'^-?\d+(\.\d+)?$');

/// Typed, forgiving reads of one JSON object.
///
/// Tracearr is a young project and its schema moves between releases, so we
/// read a field of an unexpected type as absent instead of throwing: one odd
/// value must never cost a whole page. The few fields a row cannot be used
/// without (its id) are checked by the model, which throws a [FormatException]
/// that [tracearrRows] turns into a dropped row.
extension TracearrJsonReads on TracearrJson {
  /// A non-blank string, or null.
  String? text(String key) {
    final value = this[key];
    if (value is! String) return null;
    return value.trim().isEmpty ? null : value;
  }

  /// A whole number. A JSON number with a fraction is rounded down, because
  /// some Tracearr counters are computed and arrive as `3.0`. A string of
  /// digits counts too: history sends `progress_ms` and `total_duration_ms` as
  /// strings (measured on 3.1.4), the one place a bigint column is quoted.
  int? integer(String key) {
    final value = this[key];
    if (value is int) return value;
    if (value is double && value.isFinite) return value.toInt();
    if (value is String && _digits.hasMatch(value.trim())) {
      return int.tryParse(value.trim());
    }
    return null;
  }

  double? number(String key) {
    final value = this[key];
    if (value is num && value.isFinite) return value.toDouble();
    if (value is String && _digits.hasMatch(value.trim())) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  bool? flag(String key) {
    final value = this[key];
    return value is bool ? value : null;
  }

  /// An ISO-8601 instant or date.
  DateTime? time(String key) {
    final value = this[key];
    return value is String ? DateTime.tryParse(value) : null;
  }

  TracearrJson? object(String key) => asTracearrJson(this[key]);

  /// The strings of a list, skipping anything else.
  List<String> strings(String key) {
    final value = this[key];
    if (value is! List) return const [];
    return List.unmodifiable([
      for (final item in value)
        if (item is String && item.trim().isNotEmpty) item,
    ]);
  }

  /// The objects of a list, skipping anything else.
  List<TracearrJson> objects(String key) {
    final value = this[key];
    if (value is! List) return const [];
    return List.unmodifiable([for (final item in value) ?asTracearrJson(item)]);
  }

  /// The id a row cannot exist without: a non-blank string or a
  /// [FormatException].
  String requiredText(String key) {
    return text(key) ?? (throw FormatException('missing "$key"'));
  }
}

/// The rows of a list, each built by [fromJson].
///
/// A row that is not an object, or that [fromJson] refuses, is dropped: a page
/// of fifty with one bad row is a page of forty-nine, never an error.
/// `dropped` counts what was skipped, so a caller can tell a page whose rows
/// all failed from an empty one (it must still move its cursor forward).
({List<T> rows, int dropped}) tracearrRows<T>(
  Object? raw,
  T Function(TracearrJson json) fromJson,
) {
  if (raw is! List) return (rows: const [], dropped: 0);
  final rows = <T>[];
  var dropped = 0;
  for (final item in raw) {
    final json = asTracearrJson(item);
    if (json == null) {
      dropped++;
      continue;
    }
    try {
      rows.add(fromJson(json));
    } on FormatException {
      dropped++;
    } on TypeError {
      dropped++;
    }
  }
  return (rows: List.unmodifiable(rows), dropped: dropped);
}
