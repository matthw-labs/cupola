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

/// A place a violation names. Where someone is, is theirs: [toString] prints
/// none of it.
final class TracearrPlace {
  const TracearrPlace({this.city, this.region, this.country});

  final String? city;
  final String? region;
  final String? country;

  /// `City, Region, Country` over whatever parts are there; null when none.
  String? get label {
    final parts = [
      for (final part in [city, region, country])
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
  /// rule's type, so we recognise the rule by what the data holds: a distance
  /// plus at least a place or a time. The key spellings below (snake case and
  /// camel case) are the ones we expect, not ones the contract promises: it
  /// does not describe `data`. A spelling we have not met reads as null, which
  /// the screen shows as the rule's name alone, so a wrong guess costs detail,
  /// never a crash. Confirm them against a real violation on the lab.
  TracearrImpossibleTravel? get impossibleTravel {
    final distance = _number(_data, const [
      'distance_km',
      'distanceKm',
      'distance',
    ]);
    if (distance == null) return null;
    final from = _place(_data, const ['from', 'previous'], 'from');
    final to = _place(_data, const ['to', 'current'], 'to');
    final elapsed = _elapsed(_data);
    if (from == null && to == null && elapsed == null) return null;
    return TracearrImpossibleTravel(
      from: from,
      to: to,
      distanceKm: distance,
      elapsed: elapsed,
    );
  }

  /// The "concurrent streams" reading of the data, or null for any other rule.
  ///
  /// Needs both the number of streams and the limit, so a rule that merely has
  /// a `count` is not mistaken for it.
  TracearrConcurrentStreams? get concurrentStreams {
    final count = _number(_data, const [
      'stream_count',
      'streamCount',
      'active_streams',
      'activeStreams',
      'concurrent_streams',
      'concurrentStreams',
      'count',
    ]);
    final limit = _number(_data, const [
      'max_streams',
      'maxStreams',
      'max_concurrent',
      'maxConcurrent',
      'limit',
    ]);
    if (count == null || limit == null) return null;
    return TracearrConcurrentStreams(
      count: count.round(),
      limit: limit.round(),
    );
  }

  @override
  String toString() => 'TracearrViolation($id, ${severity.name})';
}

double? _number(TracearrJson data, List<String> keys) {
  for (final key in keys) {
    final value = data.number(key);
    if (value != null) return value;
  }
  return null;
}

/// The place of one side: an object of `city`, `region` and `country`, or flat
/// `<side>City` keys. Never a bare string, which could as well be an address.
TracearrPlace? _place(TracearrJson data, List<String> names, String side) {
  for (final name in names) {
    for (final key in [name, '${name}Location', '${name}_location']) {
      final object = data.object(key);
      if (object != null) {
        final place = TracearrPlace(
          city: object.text('city'),
          region: object.text('region'),
          country: object.text('country'),
        );
        if (place.label != null) return place;
      }
    }
    final flat = TracearrPlace(
      city: data.text('${name}City') ?? data.text('${name}_city'),
      region: data.text('${name}Region') ?? data.text('${name}_region'),
      country: data.text('${name}Country') ?? data.text('${name}_country'),
    );
    if (flat.label != null) return flat;
  }
  return null;
}

Duration? _elapsed(TracearrJson data) {
  final minutes = _number(data, const [
    'time_diff_minutes',
    'timeDiffMinutes',
    'minutes',
  ]);
  if (minutes != null) return Duration(milliseconds: (minutes * 60000).round());
  final hours = _number(data, const [
    'time_diff_hours',
    'timeDiffHours',
    'time_hours',
    'timeHours',
    'hours',
  ]);
  if (hours != null) return Duration(milliseconds: (hours * 3600000).round());
  final seconds = _number(data, const [
    'time_diff_seconds',
    'timeDiffSeconds',
    'seconds',
  ]);
  if (seconds != null) return Duration(milliseconds: (seconds * 1000).round());
  return null;
}
