/// Storage on the Home: how full each pool is, and whether a disk needs the
/// person.
///
/// A TrueNAS pool and an Unraid array read the same way: a name, a share used
/// in ink, `31.2 of 43.6 TB`, its state, and under it, in amber, each disk in
/// trouble with its way in. Only state takes colour: a pool at 90% is full,
/// not faulty, and the bar says so in ink.
library;

import 'package:flutter/foundation.dart';

import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/unit_space.dart';
import 'package:cupola/features/services/presentation/dashboard_sections.dart'
    show askedAgo;
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/truenas/domain/models/pool.dart';
import 'package:cupola/features/unraid/domain/models/unraid_models.dart';

/// How many pools the slab draws.
const storagePoolLimit = 4;

/// One pool, as the slab draws it.
@immutable
class StoragePool {
  const StoragePool({
    required this.service,
    required this.instanceId,
    required this.name,
    required this.healthy,
    required this.state,
    this.usedFraction,
    this.usedBytes,
    this.totalBytes,
    this.scan,
    this.disks = const [],
  });

  /// TrueNAS or Unraid.
  final ServiceKey service;

  /// The connection it was read from.
  final String instanceId;

  /// `tank`, or `Array` for Unraid's.
  final String name;

  /// Whether its state is the one nothing needs doing about.
  final bool healthy;

  /// `Healthy`, `Degraded`, `Started`.
  final String state;

  final double? usedFraction;
  final int? usedBytes;
  final int? totalBytes;

  /// `scrubbed Sunday`, `scrubbing 41%`, or null.
  final String? scan;

  /// Each disk in trouble, in one sentence: `Disk sdd reports 8 errors`.
  final List<String> disks;

  /// `72%`, or null when the pool reported no capacity.
  String? get percent {
    final fraction = usedFraction;
    return fraction == null ? null : formatPercent(fraction * 100);
  }

  /// `31.2 of 43.6 TB`, or null without both figures.
  String? get capacity {
    final used = usedBytes;
    final total = totalBytes;
    if (used == null || total == null || total <= 0) return null;
    return formatBytesOfTotal(used, total);
  }

  /// `Healthy · scrubbed Sunday`.
  String get stateLine => [state, ?scan].join(dotSeparator);
}

/// [pool] of TrueNAS connection [instanceId], with its disks when its
/// topology was read. [now] dates its last scrub.
StoragePool storagePoolOfTrueNas(
  TrueNasPool pool, {
  required String instanceId,
  required DateTime now,
}) {
  final healthy = pool.sound;
  return StoragePool(
    service: ServiceKey.truenas,
    instanceId: instanceId,
    name: pool.name,
    healthy: healthy,
    state: pool.stateWord,
    usedFraction: pool.usedFraction,
    usedBytes: pool.allocatedBytes,
    totalBytes: pool.sizeBytes,
    scan: _scanLine(pool, now: now),
    disks: [
      for (final disk in pool.members)
        if (disk.troubled) _zfsDisk(disk),
    ],
  );
}

/// The Unraid array of connection [instanceId].
StoragePool storagePoolOfUnraid(
  UnraidArray array, {
  required String instanceId,
}) {
  final state = array.state.trim().toUpperCase();
  final troubled = [
    for (final disk in array.drives)
      if (disk.flagged || disk.warm) disk,
  ];
  return StoragePool(
    service: ServiceKey.unraid,
    instanceId: instanceId,
    name: 'Array',
    healthy: state == 'STARTED' && troubled.isEmpty,
    state: switch (state) {
      'STARTED' => troubled.isEmpty ? 'Healthy' : 'Started',
      'STOPPED' => 'Stopped',
      '' || 'UNKNOWN' => 'State unknown',
      _ => _sentenceCase(state),
    },
    usedFraction: array.usedFraction,
    usedBytes: array.usedBytes,
    totalBytes: array.totalBytes,
    disks: [for (final disk in troubled) _unraidDisk(disk)],
  );
}

String _zfsDisk(TrueNasVdevMember disk) {
  final name = 'Disk ${disk.name}';
  final errors = disk.errors ?? 0;
  return switch (disk.status.toUpperCase()) {
    'FAULTED' => '$name has failed',
    'DEGRADED' => '$name is degraded',
    'OFFLINE' => '$name was taken out of the pool',
    'UNAVAIL' => '$name is unavailable',
    'REMOVED' => '$name was removed',
    _ when errors > 0 =>
      '$name reports $errors ${errors == 1 ? 'error' : 'errors'}',
    _ => '$name needs a look',
  };
}

String _unraidDisk(UnraidDisk disk) {
  final status = disk.status.trim().toUpperCase();
  final name = _slotName(disk.name);
  if (!disk.flagged) return '$name is at ${withUnit(disk.temp ?? 0, '°C')}';
  return switch (status) {
    'DISK_DSBL' || 'DISK_DSBL_NEW' => '$name is disabled',
    'DISK_NP_MISSING' || 'DISK_NP_DSBL' => '$name is missing',
    'DISK_INVALID' => '$name is not valid',
    'DISK_WRONG' => '$name is not the disk the array expects',
    _ => '$name needs a look',
  };
}

/// `scrubbed Sunday`, `scrubbing 41%`, `resilvering 12%`.
String? _scanLine(TrueNasPool pool, {required DateTime now}) {
  final scrub = pool.scanFunction?.toUpperCase() == 'SCRUB';
  final state = pool.scanState?.toUpperCase();
  if (state == 'SCANNING') {
    final percent = pool.scanPercentage;
    final verb = scrub ? 'scrubbing' : 'resilvering';
    return percent == null ? verb : '$verb ${formatPercent(percent)}';
  }
  final ended = pool.scanEndedAt;
  if (scrub && state == 'FINISHED' && ended != null) {
    return 'scrubbed ${askedAgo(ended, now: now)}';
  }
  return null;
}

/// `Disk 3`, `Parity 2`, `Cache`: Unraid's slot names (`disk3`), as words.
String _slotName(String slot) {
  final match = RegExp(r'^([a-zA-Z]+)(\d+)$').firstMatch(slot.trim());
  if (match == null) return _sentenceCase(slot.trim());
  return '${_sentenceCase(match.group(1)!)} ${match.group(2)}';
}

String _sentenceCase(String word) {
  final lower = word.toLowerCase();
  return lower.isEmpty ? lower : lower[0].toUpperCase() + lower.substring(1);
}
