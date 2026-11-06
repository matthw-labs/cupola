@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/service_record_row.dart';
import 'package:cupola/core/widgets/status_badge.dart';

import 'catalog.dart';

Widget _list(List<Widget> rows) => Column(
  mainAxisSize: MainAxisSize.min,
  children: [
    for (var i = 0; i < rows.length; i++) ...[
      if (i > 0) const SizedBox(height: 8),
      rows[i],
    ],
  ],
);

const _tasks = [
  ServiceRecordRow(
    icon: Icons.sync_rounded,
    tone: StatusTone.info,
    title: 'Scan media library',
    detail: 'Started 2 min ago',
    trailing: 'Running · 42%',
    semanticLabel: 'Scan media library, Running 42%, Started 2 min ago',
  ),
  ServiceRecordRow(
    icon: Icons.warning_amber_rounded,
    tone: StatusTone.warning,
    title: 'Extract chapter images',
    detail: 'Started 3 h ago · 4 min · The file could not be read',
    trailing: 'Failed',
    semanticLabel:
        'Extract chapter images, Failed, Started 3 h ago, 4 min, The file '
        'could not be read',
  ),
  ServiceRecordRow(
    icon: Icons.task_alt_rounded,
    tone: StatusTone.success,
    title: 'Refresh people',
    detail: 'Started yesterday · 12 min',
    trailing: 'Completed',
    semanticLabel: 'Refresh people, Completed, Started yesterday, 12 min',
  ),
  ServiceRecordRow(
    icon: Icons.schedule_rounded,
    tone: StatusTone.neutral,
    title: 'Clean transcode directory',
    detail: 'Started 2 days ago · 1 s',
    trailing: 'Idle',
    semanticLabel: 'Clean transcode directory, Idle, Started 2 days ago, 1 s',
  ),
];

void main() {
  catalogCard(
    'ServiceRecordRow',
    width: 768,
    scenes: [
      CatalogScene(
        'Jellyfin scheduled tasks · running blue, failed amber, completed '
        'green, idle neutral: the glyph and the figure share the tone',
        (_) => _list(_tasks),
        width: 390,
      ),
      CatalogScene(
        'Jellyfin users and Plex playlists · an administrator, a disabled user '
        'and a plain playlist neutral, a smart playlist blue',
        (_) => _list(const [
          ServiceRecordRow(
            icon: Icons.person_outline_rounded,
            tone: StatusTone.neutral,
            title: 'Max',
            detail: 'Last active 5 min ago',
            trailing: 'Administrator',
            semanticLabel: 'Max, Administrator, Last active 5 min ago',
          ),
          ServiceRecordRow(
            icon: Icons.person_off_outlined,
            tone: StatusTone.neutral,
            title: 'Guest',
            detail: 'Last active 3 months ago',
            trailing: 'Disabled',
            semanticLabel: 'Guest, Disabled, Last active 3 months ago',
          ),
          ServiceRecordRow(
            icon: Icons.auto_awesome_rounded,
            tone: StatusTone.info,
            title: 'Silent era',
            detail: 'video · 9 h 40 min · Updated yesterday',
            trailing: '7',
            semanticLabel:
                'Silent era, Smart playlist, 7 items, video, 9 h 40 min, '
                'Updated yesterday',
          ),
          ServiceRecordRow(
            icon: Icons.playlist_play_rounded,
            tone: StatusTone.neutral,
            title: 'Weimar cinema',
            detail: 'video · 4 h 12 min · Updated last week',
            trailing: '3',
            semanticLabel:
                'Weimar cinema, Playlist, 3 items, video, 4 h 12 min, '
                'Updated last week',
          ),
        ]),
        width: 390,
      ),
      CatalogScene(
        'Tracearr violations · unseen blue, whatever the severity, and an '
        'acknowledged one neutral; the severity in words at the end',
        (_) => _list(const [
          ServiceRecordRow(
            icon: Icons.flag_outlined,
            tone: StatusTone.info,
            title: 'Impossible travel',
            detail: 'Anna · Plex Living Room · 2 h ago',
            trailing: 'High',
            semanticLabel:
                'Impossible travel, High, Anna, Plex Living Room, 2 h ago',
          ),
          ServiceRecordRow(
            icon: Icons.flag_outlined,
            tone: StatusTone.info,
            title: 'Too many streams',
            detail: 'Luca · Emby Study · yesterday',
            trailing: 'Warning',
            semanticLabel:
                'Too many streams, Warning, Luca, Emby Study, yesterday',
          ),
          ServiceRecordRow(
            icon: Icons.flag_outlined,
            tone: StatusTone.neutral,
            title: 'Night owl',
            detail: 'Luca · Jellyfin Attic · Tue 3 Nov · Acknowledged',
            trailing: 'Low',
            semanticLabel:
                'Night owl, Low, Luca, Jellyfin Attic, Tue 3 Nov, Acknowledged',
          ),
        ]),
        width: 390,
      ),
      CatalogScene(
        'Long text · the title holds two lines, the detail three, and the '
        'trailing value yields to the title before either overflows',
        (_) => const ServiceRecordRow(
          icon: Icons.devices_other_rounded,
          tone: StatusTone.neutral,
          title:
              'Living room projector in the screening room at the back of '
              'the house',
          detail:
              'Plex for Android TV · Android · Last seen 4 h ago · streamed '
              'Nosferatu, Metropolis and The Cabinet of Dr. Caligari over the '
              'weekend without a single transcode',
          trailing: 'client · player · pubsub-player',
          semanticLabel:
              'Living room projector, Plex for Android TV, Android, client, '
              'player, pubsub-player, Last seen 4 h ago',
        ),
        width: 390,
      ),
      CatalogScene(
        'Text at 200% · the four task rows at twice the reading size, the '
        'trailing figure wrapping before it ellipsises',
        (_) => _list(_tasks),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'On the desktop · the same row across a wider list',
        (_) => _list(_tasks.take(2).toList()),
        width: 720,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
