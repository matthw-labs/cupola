@Tags(['catalog'])
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/features/truenas/presentation/storage/truenas_storage_screen.dart';

import 'catalog.dart';
import 'truenas_world.dart';

void main() {
  catalogCard(
    'TrueNasStorage',
    width: 480,
    overrides: trueNasCatalogOverrides,
    scenes: [
      CatalogScene(
        'Storage · a sound pool and a degraded one: each reads its state in '
        "the lexicon's word, never ZFS's uppercase one",
        (_) => trueNasPhone(trueNasShell(const TrueNasStorageScreen())),
        width: 390,
        height: 844,
      ),
    ],
  );
}
