@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/service_theme.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

/// The service settings header's well, at its real values: 48×48,
/// `ServiceTheme.softContainer` (the accent at 14%), `radius-md`, the mark at
/// 24, ink walked by `onTint` against the card it sits on.
Widget _well(BuildContext context, ServiceKey service, {bool named = true}) {
  final serviceTheme = ServiceTheme.fromAccent(service.accent);
  final colorScheme = Theme.of(context).colorScheme;
  return Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: serviceTheme.softContainer,
          borderRadius: AppRadius.borderRadiusMd,
        ),
        child: Icon(
          service.icon,
          size: 24,
          color: ServiceTheme.onTint(
            service.accent,
            surface: colorScheme.surfaceContainer,
            tintAlpha: 0.14,
          ),
        ),
      ),
      if (named) ...[
        const SizedBox(height: 4),
        SizedBox(
          width: 72,
          child: Text(
            service.title,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    ],
  );
}

const _sizesInUse = <(double, String)>[
  (12.9, '12.9 · onboarding small tile'),
  (14, '14 · tab header, search'),
  (15, '15 · ⌘K row'),
  (16, '16 · deck chip, import row'),
  (17, '17 · inspector queue row'),
  (18, '18 · matrix cell, onboarding'),
  (20, '20 · import, where-to-watch'),
  (24, '24 · settings header, list row'),
];

void main() {
  catalogCard(
    'ServiceGlyphs',
    width: 1100,
    scenes: [
      CatalogScene(
        'The eighteen marks, registry order · each on the settings header\'s '
        'well (the lamp at 14%, radius-md), the mark in the primary ink: '
        'monochrome, told apart by shape',
        (context) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final service in ServiceKey.values)
                Builder(builder: (context) => _well(context, service)),
            ],
          ),
        ),
      ),
      CatalogScene(
        'Radarr\'s mark at every size in use, in on-surface, to show the '
        'shape alone',
        (context) => Wrap(
          spacing: 20,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.end,
          children: [
            for (final (size, caption) in _sizesInUse)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    ServiceKey.radarr.icon,
                    size: size,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: 84,
                    child: Text(
                      caption,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      CatalogScene(
        'Text at 200% · the eighteen wells at twice the reading size: the '
        'marks are icons, so the wells keep their 48pt',
        (context) => Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainer,
            borderRadius: AppRadius.borderRadiusMd,
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              for (final service in ServiceKey.values)
                Builder(
                  builder: (context) => _well(context, service, named: false),
                ),
            ],
          ),
        ),
        textScale: catalogTextScale,
      ),
    ],
  );
}
