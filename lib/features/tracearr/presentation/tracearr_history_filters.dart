import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';

/// How far back History looks.
enum TracearrPeriod {
  anyTime('Any time'),
  today('Today'),
  last7('Last 7 days'),
  last30('Last 30 days');

  const TracearrPeriod(this.label);

  final String label;

  /// The start of the period, on the device's calendar, or null for any time.
  /// Today is from this day's midnight, not the last 24 hours: a person who
  /// asks for today means the day they are in.
  DateTime? since(DateTime now) {
    final local = now.toLocal();
    final midnight = DateTime(local.year, local.month, local.day);
    return switch (this) {
      anyTime => null,
      today => midnight,
      last7 => DateTime(local.year, local.month, local.day - 6),
      last30 => DateTime(local.year, local.month, local.day - 29),
    };
  }
}

/// What History is narrowed to, every part of it a question the server
/// answers: a filter applied to the pages already read would show an empty
/// list while older pages held plenty.
///
/// **There is no library filter.** Tracearr's history route has none, and a
/// filter on the pages we hold would make exactly that false emptiness; the
/// type does what a library mostly meant, and the server does it.
@immutable
final class TracearrHistoryFilters {
  const TracearrHistoryFilters({
    this.userId,
    this.userName,
    this.serverId,
    this.serverName,
    this.mediaType,
    this.onlyWatched = false,
    this.period = TracearrPeriod.anyTime,
  });

  /// A person, by Tracearr id, with the name the pill wears.
  final String? userId;
  final String? userName;

  final String? serverId;
  final String? serverName;

  final TracearrHistoryMediaType? mediaType;

  /// Only what Tracearr counts as watched.
  final bool onlyWatched;

  final TracearrPeriod period;

  /// Whether anything narrows the list.
  bool get isNarrowed =>
      userId != null ||
      serverId != null ||
      mediaType != null ||
      onlyWatched ||
      period != TracearrPeriod.anyTime;

  /// What the server is asked for, with [now] for a period's start.
  TracearrHistoryFilter toQuery(DateTime now) => TracearrHistoryFilter(
    userId: userId,
    serverId: serverId,
    mediaType: mediaType,
    watched: onlyWatched ? true : null,
    since: period.since(now),
  );

  TracearrHistoryFilters copyWith({
    ({String? id, String? name})? person,
    ({String? id, String? name})? server,
    ({TracearrHistoryMediaType? type})? type,
    bool? onlyWatched,
    TracearrPeriod? period,
  }) => TracearrHistoryFilters(
    userId: person == null ? userId : person.id,
    userName: person == null ? userName : person.name,
    serverId: server == null ? serverId : server.id,
    serverName: server == null ? serverName : server.name,
    mediaType: type == null ? mediaType : type.type,
    onlyWatched: onlyWatched ?? this.onlyWatched,
    period: period ?? this.period,
  );

  String toJson() => jsonEncode({
    'u': ?userId,
    'un': ?userName,
    's': ?serverId,
    'sn': ?serverName,
    't': ?mediaType?.name,
    if (onlyWatched) 'w': true,
    if (period != TracearrPeriod.anyTime) 'p': period.name,
  });

  /// The filters [raw] holds, or none for anything that is not what [toJson]
  /// wrote: a preference that cannot be read is a preference not set.
  static TracearrHistoryFilters fromJson(String? raw) {
    if (raw == null) return const TracearrHistoryFilters();
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return const TracearrHistoryFilters();
      String? text(String key) {
        final value = json[key];
        return value is String && value.isNotEmpty ? value : null;
      }

      return TracearrHistoryFilters(
        userId: text('u'),
        userName: text('un'),
        serverId: text('s'),
        serverName: text('sn'),
        mediaType: TracearrHistoryMediaType.values.asNameMap()[text('t')],
        onlyWatched: json['w'] == true,
        period:
            TracearrPeriod.values.asNameMap()[text('p')] ??
            TracearrPeriod.anyTime,
      );
    } catch (_) {
      return const TracearrHistoryFilters();
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TracearrHistoryFilters &&
      other.userId == userId &&
      other.userName == userName &&
      other.serverId == serverId &&
      other.serverName == serverName &&
      other.mediaType == mediaType &&
      other.onlyWatched == onlyWatched &&
      other.period == period;

  @override
  int get hashCode => Object.hash(
    userId,
    userName,
    serverId,
    serverName,
    mediaType,
    onlyWatched,
    period,
  );

  @override
  String toString() => 'TracearrHistoryFilters(narrowed: $isNarrowed)';
}

/// The key a connection's History filters are kept under in the device's
/// preferences. One per connection, so the household's second Tracearr does
/// not inherit the first one's person.
String tracearrHistoryFiltersKey(String connectionId) =>
    'tracearr.history_filters.$connectionId';

/// History's filters, remembered per connection on this device.
///
/// Read when the page first draws and written at every change, guarded like
/// the other small preferences: a screen built without them still draws, with
/// nothing narrowed, and a write that cannot land is kept for the launch.
/// Moving the lens to another Tracearr connection reads that connection's own.
final tracearrHistoryFiltersProvider =
    NotifierProvider<TracearrHistoryFiltersNotifier, TracearrHistoryFilters>(
      TracearrHistoryFiltersNotifier.new,
    );

class TracearrHistoryFiltersNotifier extends Notifier<TracearrHistoryFilters> {
  String _connection = '';

  String get _key => tracearrHistoryFiltersKey(_connection);

  @override
  TracearrHistoryFilters build() {
    _connection =
        ref.watch(activeInstanceProvider(ServiceKey.tracearr))?.id ?? '';
    try {
      return TracearrHistoryFilters.fromJson(
        ref.watch(sharedPreferencesProvider).getString(_key),
      );
    } catch (_) {
      return const TracearrHistoryFilters();
    }
  }

  void _set(TracearrHistoryFilters next) {
    if (next == state) return;
    state = next;
    try {
      final prefs = ref.read(sharedPreferencesProvider);
      if (next.isNarrowed) {
        prefs.setString(_key, next.toJson());
      } else {
        prefs.remove(_key);
      }
    } catch (_) {
      // Kept for this launch only: nothing to persist to.
    }
  }

  void person(String? id, String? name) =>
      _set(state.copyWith(person: (id: id, name: id == null ? null : name)));

  void server(String? id, String? name) =>
      _set(state.copyWith(server: (id: id, name: id == null ? null : name)));

  void type(TracearrHistoryMediaType? type) =>
      _set(state.copyWith(type: (type: type)));

  void onlyWatched(bool value) => _set(state.copyWith(onlyWatched: value));

  void period(TracearrPeriod value) => _set(state.copyWith(period: value));

  void clear() => _set(const TracearrHistoryFilters());
}
