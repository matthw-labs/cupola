@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/core/widgets/app_card.dart';
import 'package:cupola/core/widgets/settings_switch_row.dart';

import 'catalog.dart';

Widget _group(List<Widget> rows) => Padding(
  padding: const EdgeInsets.symmetric(horizontal: 16),
  child: SettingsGroupCard(children: rows),
);

const _needsYou =
    'When a download is stuck, an import waits, or a disk or a '
    'key fails.';

Widget _states(BuildContext context) => _group([
  SettingsSwitchRow(
    icon: Icons.priority_high_rounded,
    title: 'Needs you',
    description: _needsYou,
    value: true,
    onChanged: (_) {},
  ),
  SettingsSwitchRow(
    icon: Icons.play_circle_outline_rounded,
    title: 'Ready to watch',
    description: 'When something someone asked for arrives.',
    value: false,
    onChanged: (_) {},
  ),
  SettingsSwitchRow(
    icon: Icons.flag_outlined,
    title: 'Flagged by Tracearr',
    description: 'When someone breaks a rule Tracearr watches.',
    value: false,
    onChanged: (_) {},
  ),
]);

Widget _withNote(BuildContext context) => _group([
  SettingsSwitchRow(
    icon: Icons.notifications_active_outlined,
    title: 'Tell me when one finishes',
    description: 'Only when Cupola is not in front of you',
    note: (
      text: 'Blocked in Settings › Notifications › Cupola',
      tone: StatusTone.warning,
    ),
    value: true,
    onChanged: (_) {},
  ),
  SettingsSwitchRow(
    icon: Icons.notifications_active_outlined,
    title: 'Tell me when one finishes',
    description: 'Only when Cupola is not in front of you',
    note: (text: 'System permission: granted', tone: null),
    value: true,
    onChanged: (_) {},
  ),
]);

Widget _held(BuildContext context) => _group([
  const SettingsSwitchRow(
    icon: Icons.notifications_active_outlined,
    title: 'Tell me when one finishes',
    description:
        'Needs Background search, a search that ends with the app has '
        'nothing to announce',
    value: false,
    onChanged: null,
  ),
  SettingsSwitchRow(
    icon: Icons.priority_high_rounded,
    title: 'Needs you',
    description: _needsYou,
    value: false,
    onChanged: (_) {},
    busy: true,
  ),
]);

void main() {
  catalogCard(
    'SettingsSwitchRow',
    scenes: [
      CatalogScene(
        'SettingsSwitchRow · on and off, in a group (Notifications: Needs you, '
        'Ready to watch, Flagged by Tracearr)',
        _states,
        width: 390,
      ),
      CatalogScene(
        'SettingsSwitchRow · with a note: a permission blocked, in amber, and '
        'granted, quiet',
        _withNote,
        width: 390,
      ),
      CatalogScene(
        'SettingsSwitchRow · held by another setting, and busy while the OS '
        'asks',
        _held,
        width: 390,
      ),
      CatalogScene(
        'SettingsSwitchRow · at 200%',
        _states,
        width: 390,
        textScale: catalogTextScale,
      ),
    ],
  );
}
