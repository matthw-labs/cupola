import 'package:cupola/features/tracearr/domain/models/tracearr_enums.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_json.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_playback.dart';
import 'package:cupola/features/tracearr/domain/models/tracearr_server.dart';

/// The rule a violation broke.
final class TracearrRuleRef {
  const TracearrRuleRef({this.id, this.name = ''});

  factory TracearrRuleRef.fromJson(TracearrJson json) =>
      TracearrRuleRef(id: json.text('id'), name: json.text('name') ?? '');

  final String? id;

  /// The name the owner gave the rule in Tracearr. The public API does not
  /// send the rule's type, only this.
  final String name;
}

/// What Tracearr did, or tried to do, about a violation (notify, kill the
/// stream, ...).
final class TracearrViolationAction {
  const TracearrViolationAction({
    this.type = '',
    this.success = false,
    this.skipped = false,
    this.skipReason,
    this.errorMessage,
    this.executedAt,
  });

  factory TracearrViolationAction.fromJson(TracearrJson json) =>
      TracearrViolationAction(
        type: json.text('type') ?? '',
        success: json.flag('success') ?? false,
        skipped: json.flag('skipped') ?? false,
        skipReason: json.text('skip_reason'),
        errorMessage: json.text('error_message'),
        executedAt: json.time('executed_at'),
      );

  /// The action's own word (`notify`, `terminate_stream`): the set is the
  /// owner's to extend, so it stays a string.
  final String type;

  final bool success;

  /// Tracearr chose not to run it (a cooldown, a missing target).
  final bool skipped;

  final String? skipReason;
  final String? errorMessage;
  final DateTime? executedAt;

  /// It ran and did not work: a fault, unlike a skip.
  bool get failed => !success && !skipped;
}

/// A place a violation names: Tracearr gives a city and a country, from its
/// own geolocation of an address. Where someone is, is theirs: [toString]
/// prints none of it.
final class TracearrPlace {
  const TracearrPlace({this.city, this.country});

  final String? city;
  final String? country;

  /// `City, Country` over whatever parts are there; null when none.
  String? get label {
    final parts = [
      for (final part in [city, country])
        if (part != null && part.isNotEmpty) part,
    ];
    return parts.isEmpty ? null : parts.join(', ');
  }

  @override
  String toString() => 'TracearrPlace()';
}

/// The "impossible travel" rule: one person streamed from two places too far
/// apart for the time between them.
final class TracearrImpossibleTravel {
  const TracearrImpossibleTravel({
    this.from,
    this.to,
    this.distanceKm,
    this.elapsed,
  });

  final TracearrPlace? from;
  final TracearrPlace? to;

  /// Kilometres, as Tracearr measured it.
  final double? distanceKm;

  /// The time between the two streams.
  final Duration? elapsed;

  @override
  String toString() => 'TracearrImpossibleTravel()';
}

/// The "concurrent streams" rule: more streams at once than the limit.
final class TracearrConcurrentStreams {
  const TracearrConcurrentStreams({required this.count, required this.limit});

  final int count;
  final int limit;

  @override
  String toString() => 'TracearrConcurrentStreams($count of $limit)';
}

/// One rule violation.
///
/// Its free-form `data` holds IP addresses and places, so it stays private:
/// the only ways out are [impossibleTravel] and [concurrentStreams], which read
/// the two rules we know and hand back places and numbers, never an address.
/// A rule we do not know shows its name and nothing else. [toString] prints
/// the id and the severity only.
final class TracearrViolation {
  const TracearrViolation({
    required this.id,
    this.severity = TracearrSeverity.unknown,
    this.createdAt,
    this.acknowledgedAt,
    this.sessionId,
    this.rule = const TracearrRuleRef(),
    this.server = const TracearrServerRef(id: ''),
    this.person = const TracearrPerson(),
    this.actions = const [],
    TracearrJson data = const {},
  }) : _data = data;

  factory TracearrViolation.fromJson(TracearrJson json) {
    final rule = json.object('rule');
    final server = json.object('server');
    final user = json.object('user');
    return TracearrViolation(
      id: json.requiredText('id'),
      severity: TracearrSeverity.fromWire(json['severity']),
      createdAt: json.time('created_at'),
      acknowledgedAt: json.time('acknowledged_at'),
      sessionId: json.text('session_id'),
      rule: rule == null
          ? const TracearrRuleRef()
          : TracearrRuleRef.fromJson(rule),
      server: server == null
          ? const TracearrServerRef(id: '')
          : TracearrServerRef.fromJson(server),
      person: user == null
          ? const TracearrPerson()
          : TracearrPerson.fromJson(user),
      actions: tracearrRows(
        json['actions'],
        TracearrViolationAction.fromJson,
      ).rows,
      data: json.object('data') ?? const {},
    );
  }

  final String id;
  final TracearrSeverity severity;
  final DateTime? createdAt;

  /// Null while nobody has looked at it.
  final DateTime? acknowledgedAt;

  /// The session that triggered it, when there is one.
  final String? sessionId;

  final TracearrRuleRef rule;
  final TracearrServerRef server;
  final TracearrPerson person;

  /// What Tracearr did about it. Only the single-violation read carries them;
  /// on a list row this is empty, which is not "nothing was done".
  final List<TracearrViolationAction> actions;

  final TracearrJson _data;

  bool get isAcknowledged => acknowledgedAt != null;

  /// An action that ran and failed: a fault the owner should hear about.
  bool get hasFailedAction => actions.any((action) => action.failed);

  /// The "impossible travel" reading of the data, or null for any other rule.
  ///
  /// The public contract types `data` as free-form and does not send the
  /// rule's type, so the rule is recognised by what Tracearr wrote, which we
  /// read off its server source (v3.1.4, `automations/runRecorder.ts` and
  /// `evaluators/index.ts`) and not off a guess. A live 3.1.4 has since
  /// answered for the concurrent-streams rule exactly as the source said; this
  /// rule's own shape has not been seen live yet:
  ///
  ///  * a run of Tracearr 3.x keeps what it weighed in `data.evidence`, a list
  ///    of groups of conditions; impossible travel is the condition whose
  ///    `field` is `travel_speed_kmh`, which carries in `details` the
  ///    `distance` (km), the `timeDeltaHours` between the two streams and the
  ///    `previousLocation` and `currentLocation`, each with a `city` and a
  ///    `country`;
  ///  * a violation recorded before Tracearr 3 kept a flat `data` of its own:
  ///    the speed in `calculatedSpeedKmh`, the distance in `distanceKm` or
  ///    `distance`, the places as `fromCity` and `toCity` or as objects
  ///    (`previousLocation`, `currentLocation`, `fromLocation`,
  ///    `toLocation`), and the time in `timeDiffHours` or `timeWindowMinutes`.
  ///
  /// A violation with neither marker is another rule, whatever else it holds,
  /// and the screen shows its name alone. Needs both the distance and at least
  /// a place or a time, so a half-written record never reads as a journey.
  TracearrImpossibleTravel? get impossibleTravel {
    final condition = _matchedCondition(_data, 'travel_speed_kmh');
    if (condition != null) {
      final details = condition.object('details');
      if (details == null) return null;
      return _travel(
        distance: details.number('distance'),
        from: _place(details.object('previousLocation')),
        to: _place(details.object('currentLocation')),
        elapsed: _hours(details.number('timeDeltaHours')),
      );
    }
    if (_data.number('calculatedSpeedKmh') == null) return null;
    return _travel(
      distance: _data.number('distanceKm') ?? _data.number('distance'),
      from:
          _place(_data.object('fromLocation')) ??
          _place(_data.object('previousLocation')) ??
          _place({'city': _data.text('fromCity')}),
      to:
          _place(_data.object('toLocation')) ??
          _place(_data.object('currentLocation')) ??
          _place({'city': _data.text('toCity')}),
      elapsed:
          _hours(_data.number('timeDiffHours')) ??
          _minutes(_data.number('timeWindowMinutes')),
    );
  }

  /// The "concurrent streams" reading of the data, or null for any other rule.
  ///
  /// Recognised by what Tracearr wrote (see [impossibleTravel]): the condition
  /// whose `field` is `concurrent_streams` and whose operator is `gt`, so its
  /// `threshold` is the limit and its `actual` the number of streams; or, on a
  /// violation recorded before Tracearr 3, the flat `streamCount` with
  /// `maxStreams`. Any other rule that happens to hold a count and a limit is
  /// not this one.
  TracearrConcurrentStreams? get concurrentStreams {
    final condition = _matchedCondition(_data, 'concurrent_streams');
    final double? count;
    final double? limit;
    if (condition != null) {
      if (condition['operator'] != 'gt') return null;
      count = condition.number('actual');
      limit = condition.number('threshold');
    } else {
      count = _data.number('streamCount');
      limit = _data.number('maxStreams');
    }
    if (count == null || limit == null) return null;
    return TracearrConcurrentStreams(
      count: count.round(),
      limit: limit.round(),
    );
  }

  @override
  String toString() => 'TracearrViolation($id, ${severity.name})';
}

/// The condition of [field] that matched, among the groups of
/// `data.evidence` Tracearr's engine kept, or null: no evidence is not a rule
/// we know.
TracearrJson? _matchedCondition(TracearrJson data, String field) {
  for (final group in data.objects('evidence')) {
    for (final condition in group.objects('conditions')) {
      if (condition['field'] == field && condition.flag('matched') == true) {
        return condition;
      }
    }
  }
  return null;
}

TracearrImpossibleTravel? _travel({
  required double? distance,
  required TracearrPlace? from,
  required TracearrPlace? to,
  required Duration? elapsed,
}) {
  if (distance == null) return null;
  if (from == null && to == null && elapsed == null) return null;
  return TracearrImpossibleTravel(
    from: from,
    to: to,
    distanceKm: distance,
    elapsed: elapsed,
  );
}

/// The place an object of `city` and `country` names, or null when it names
/// none. Never a bare string, which could as well be an address.
TracearrPlace? _place(TracearrJson? object) {
  if (object == null) return null;
  final place = TracearrPlace(
    city: object.text('city'),
    country: object.text('country'),
  );
  return place.label == null ? null : place;
}

Duration? _hours(double? hours) =>
    hours == null ? null : Duration(milliseconds: (hours * 3600000).round());

Duration? _minutes(double? minutes) =>
    minutes == null ? null : Duration(milliseconds: (minutes * 60000).round());
