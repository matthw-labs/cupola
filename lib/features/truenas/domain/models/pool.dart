import 'package:cupola/core/utils/dynamic_map_utils.dart';

/// A member device of a vdev (leaf disk).
class TrueNasVdevMember {
  final String name;
  final String status;

  /// Read, write and checksum errors ZFS has counted on it, or null when the
  /// topology carried no counters.
  final int? errors;

  const TrueNasVdevMember({
    required this.name,
    required this.status,
    this.errors,
  });

  /// Whether ZFS reports trouble with it: a state other than `ONLINE`, or an
  /// error counted.
  bool get troubled =>
      (status.toUpperCase() != 'ONLINE' && status != 'UNKNOWN') ||
      (errors ?? 0) > 0;

  factory TrueNasVdevMember.fromJson(Map<String, dynamic> json) {
    final stats = mapOrNull(json['stats']);
    final counted = stats == null
        ? null
        : [
            intOrNull(stats['read_errors']),
            intOrNull(stats['write_errors']),
            intOrNull(stats['checksum_errors']),
          ].whereType<int>().toList();
    return TrueNasVdevMember(
      errors: counted == null || counted.isEmpty
          ? null
          : counted.fold<int>(0, (sum, n) => sum + n),
      name:
          stringOrNull(json['disk']) ??
          stringOrNull(json['device']) ??
          stringOrNull(json['name']) ??
          '—',
      status: stringOrNull(json['status']) ?? 'UNKNOWN',
    );
  }
}

/// A vdev within a pool topology category.
class TrueNasVdev {
  final String type;
  final String status;
  final List<TrueNasVdevMember> members;

  const TrueNasVdev({
    required this.type,
    required this.status,
    required this.members,
  });

  factory TrueNasVdev.fromJson(Map<String, dynamic> json) {
    final children = json['children'];
    final members = <TrueNasVdevMember>[];
    if (children is List && children.isNotEmpty) {
      for (final child in children) {
        final map = mapOrNull(child);
        if (map != null) members.add(TrueNasVdevMember.fromJson(map));
      }
    } else {
      // A bare DISK vdev is its own member.
      members.add(TrueNasVdevMember.fromJson(json));
    }
    return TrueNasVdev(
      type: stringOrNull(json['type']) ?? 'DISK',
      status: stringOrNull(json['status']) ?? 'UNKNOWN',
      members: members,
    );
  }
}

/// A storage pool from `pool.query` (optionally with topology).
class TrueNasPool {
  final int? id;
  final String name;
  final String status;
  final bool healthy;
  final int? sizeBytes;
  final int? allocatedBytes;
  final int? freeBytes;
  final String? path;
  final Map<String, List<TrueNasVdev>> topology;
  final String? scanState;
  final double? scanPercentage;

  /// What the last scan was: `SCRUB` or `RESILVER`.
  final String? scanFunction;

  /// When the last scan finished, or null while it runs or when none has.
  final DateTime? scanEndedAt;

  /// How long the running scan has left by TrueNAS's estimate
  /// (`total_secs_left`), or null when none runs or it gave none.
  final int? scanSecondsLeft;

  const TrueNasPool({
    this.id,
    required this.name,
    required this.status,
    required this.healthy,
    this.sizeBytes,
    this.allocatedBytes,
    this.freeBytes,
    this.path,
    this.topology = const {},
    this.scanState,
    this.scanPercentage,
    this.scanFunction,
    this.scanEndedAt,
    this.scanSecondsLeft,
  });

  /// Whether ZFS calls it sound: TrueNAS's health flag, and `ONLINE`.
  bool get sound => healthy && status.toUpperCase() == 'ONLINE';

  /// Its state as the app says it: `Healthy`, `Degraded`, `Has errors`.
  /// Never ZFS's own `ONLINE`, which the lexicon bans as a state.
  String get stateWord => zfsStateWord(status, errors: !healthy);

  /// Every disk of every vdev, in topology order.
  List<TrueNasVdevMember> get members => [
    for (final vdevs in topology.values)
      for (final vdev in vdevs) ...vdev.members,
  ];

  /// Used fraction 0..1 when capacity is known, else null.
  double? get usedFraction {
    final size = sizeBytes;
    final allocated = allocatedBytes;
    if (size == null || allocated == null || size <= 0) return null;
    return (allocated / size).clamp(0, 1).toDouble();
  }

  bool get hasTopology => topology.values.any((v) => v.isNotEmpty);

  /// Whether a scrub or a resilver is running now.
  bool get isScanning => scanState?.toUpperCase() == 'SCANNING';

  /// The disk named [disk] (`sdd`) among its vdevs, or null when the
  /// topology holds none by that name.
  TrueNasVdevMember? memberNamed(String disk) =>
      members.where((member) => member.name == disk).firstOrNull;

  factory TrueNasPool.fromJson(Map<String, dynamic> json) {
    // pool.query returns size/allocated either at the top level or nested in
    // the root dataset stats depending on release; handle both.
    int? size = intOrNull(json['size']);
    int? allocated = intOrNull(json['allocated']);
    int? free = intOrNull(json['free']);
    final rootDataset = mapOrNull(json['root_dataset']);
    if (rootDataset != null) {
      // `root_dataset.available` is ZFS FREE space, not capacity: reading it as
      // the total made [usedFraction] compute used/free, which clamps every
      // pool at or past half full to a flat 100%. Capacity is used + available.
      final rootUsed = intOrNull(mapOrNull(rootDataset['used'])?['parsed']);
      final rootAvailable = intOrNull(
        mapOrNull(rootDataset['available'])?['parsed'],
      );
      allocated ??= rootUsed;
      free ??= rootAvailable;
      if (size == null && rootUsed != null && rootAvailable != null) {
        size = rootUsed + rootAvailable;
      }
    }

    final topology = <String, List<TrueNasVdev>>{};
    final topoJson = mapOrNull(json['topology']);
    if (topoJson != null) {
      for (final entry in topoJson.entries) {
        final list = entry.value;
        if (list is List && list.isNotEmpty) {
          final vdevs = list
              .map(mapOrNull)
              .whereType<Map<String, dynamic>>()
              .map(TrueNasVdev.fromJson)
              .toList(growable: false);
          if (vdevs.isNotEmpty) topology[entry.key] = vdevs;
        }
      }
    }

    final scan = mapOrNull(json['scan']);
    final endTime = scan?['end_time'];
    final endMs = endTime is Map ? intOrNull(endTime['\$date']) : null;

    return TrueNasPool(
      id: intOrNull(json['id']),
      name: stringOrNull(json['name']) ?? 'Pool',
      status: stringOrNull(json['status']) ?? 'UNKNOWN',
      healthy: json['healthy'] == true,
      sizeBytes: size,
      allocatedBytes: allocated,
      freeBytes: free,
      path: stringOrNull(json['path']),
      topology: topology,
      scanState: stringOrNull(scan?['state']),
      scanPercentage: doubleOrNull(scan?['percentage']),
      scanFunction: stringOrNull(scan?['function']),
      // A pool never scanned can carry the epoch: no finish to tell.
      scanEndedAt: endMs == null || endMs <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(endMs, isUtc: true),
      scanSecondsLeft: intOrNull(scan?['total_secs_left']),
    );
  }
}

/// ZFS's [status] of a pool, a vdev or a disk, as a word: `Healthy`,
/// `Degraded`, `Faulted`. [errors] is whether ZFS still counts errors on
/// something `ONLINE`, which then reads `Has errors`.
String zfsStateWord(String status, {bool errors = false}) =>
    switch (status.trim().toUpperCase()) {
      'ONLINE' => errors ? 'Has errors' : 'Healthy',
      'DEGRADED' => 'Degraded',
      'FAULTED' => 'Faulted',
      // Taken out of use on purpose.
      'OFFLINE' => 'Not in service',
      'UNAVAIL' => 'Unavailable',
      'REMOVED' => 'Removed',
      'SUSPENDED' => 'Suspended',
      '' || 'UNKNOWN' => 'State unknown',
      final other => other[0] + other.substring(1).toLowerCase(),
    };
