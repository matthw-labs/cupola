/// Posts what the run says: one notification per new thing, grouped by kind.
///
/// It speaks only from the run with the app away (`runOutsideInBackground`),
/// so it initialises the plugin in that isolate, with no tap handler: a tap
/// opens the app, whose own start reads the tap (`ReleaseSearchNotifications`
/// owns the plugin there) and lands on [outsideNoticeRouteOf]'s route.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:cupola/features/outside/data/outside_run.dart';
import 'package:cupola/features/outside/data/outside_shelf.dart';
import 'package:cupola/features/outside/domain/outside_notices.dart';

/// What a notification's payload starts with when its tap opens a place in
/// the app. A release search's payload is its job id, which never does.
const outsideNoticePayloadPrefix = 'route:';

/// The route a tapped notification's [payload] names, or null when it names
/// none (a release search's, or one with no route).
String? outsideNoticeRouteOf(String? payload) {
  if (payload == null || !payload.startsWith(outsideNoticePayloadPrefix)) {
    return null;
  }
  final route = payload.substring(outsideNoticePayloadPrefix.length);
  return route.startsWith('/') ? route : null;
}

/// Each kind's Android channel: its own, so a person can quiet one in the
/// system's settings and keep the other. Default importance: a fault on a
/// home server is news, not an alarm.
({String id, String description}) _channelOf(OutsideNoticeKind kind) =>
    switch (kind) {
      OutsideNoticeKind.needsYou => (
        id: 'needs_you',
        description:
            'A download that is stuck, an import that waits, a disk or a key '
            'that fails.',
      ),
      OutsideNoticeKind.readyToWatch => (
        id: 'ready_to_watch',
        description: 'Something asked for that arrived.',
      ),
      OutsideNoticeKind.flagged => (
        id: 'flagged',
        description: 'A rule that Tracearr flagged.',
      ),
    };

class LocalOutsideSpeaker implements OutsideSpeaker {
  LocalOutsideSpeaker([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// The status-bar icon, the release searches' own.
  static const _androidSmallIcon = 'ic_stat_cupola';

  @override
  Future<void> say(List<OutsideNotice> notices, OutsideShelf shelf) async {
    if (notices.isEmpty) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings(_androidSmallIcon),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
    } catch (_) {
      return;
    }
    for (final kind in OutsideNoticeKind.values) {
      final mine = [
        for (final notice in notices)
          if (notice.kind == kind) notice,
      ];
      for (final notice in mine) {
        await _show(notice, shelf);
      }
      // Android folds a kind's notifications under one summary once there
      // are two; iOS folds them by thread on its own.
      if (mine.length > 1 && Platform.isAndroid) await _summary(kind, mine);
    }
  }

  Future<void> _show(OutsideNotice notice, OutsideShelf shelf) async {
    final channel = _channelOf(notice.kind);
    final picture = notice.picture == null
        ? null
        : File('${shelf.pictures.path}/${notice.picture}');
    final hasPicture = picture != null && await picture.exists();
    try {
      await _plugin.show(
        id: outsideNoticeId(notice),
        title: notice.title,
        body: notice.body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            notice.kind.label,
            channelDescription: channel.description,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            groupKey: 'cupola.${notice.kind.name}',
            largeIcon: hasPicture ? FilePathAndroidBitmap(picture.path) : null,
          ),
          iOS: DarwinNotificationDetails(
            threadIdentifier: notice.kind.name,
            // iOS moves an attachment into its own store: it gets a copy, so
            // the widget keeps the picture.
            attachments: hasPicture
                ? [
                    DarwinNotificationAttachment(
                      await _copyForAttachment(picture),
                    ),
                  ]
                : null,
          ),
        ),
        payload: notice.route == null
            ? null
            : '$outsideNoticePayloadPrefix${notice.route}',
      );
    } catch (_) {
      // A notification that cannot post is a notification lost, nothing more.
    }
  }

  Future<void> _summary(
    OutsideNoticeKind kind,
    List<OutsideNotice> notices,
  ) async {
    final channel = _channelOf(kind);
    final more = notices.length - 1;
    try {
      await _plugin.show(
        id: kind.name.hashCode,
        title: kind.label,
        // The Needs you banner's own shape: the first, and how many more.
        body: '${notices.first.body}\u00A0· +$more',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            kind.label,
            channelDescription: channel.description,
            groupKey: 'cupola.${kind.name}',
            setAsGroupSummary: true,
            styleInformation: InboxStyleInformation([
              for (final notice in notices) notice.body,
            ]),
          ),
        ),
      );
    } catch (_) {
      // The children stand without it.
    }
  }

  Future<String> _copyForAttachment(File picture) async {
    final copy = File(
      '${Directory.systemTemp.path}/cupola-notice-'
      '${DateTime.now().microsecondsSinceEpoch}.jpg',
    );
    await picture.copy(copy.path);
    return copy.path;
  }
}

/// A notification's id: the same thing keeps the same id, so saying it again
/// (it never is, but a second run racing the first could) replaces it.
@visibleForTesting
int outsideNoticeId(OutsideNotice notice) => notice.key.hashCode & 0x7fffffff;
