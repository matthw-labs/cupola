import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/lifecycle/page_activity.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/duration_format.dart';
import 'package:cupola/core/utils/percent_format.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/domain/models/jellyfin_models.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_admin_placeholder.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/stream/presentation/stream_activity_provider.dart';
import 'package:cupola/features/stream/presentation/stream_connection_provider.dart';
import 'package:cupola/features/stream/presentation/widgets/stream_now_playing_section.dart';

/// Read-only household users from Jellyfin's `/Users` endpoint.
///
/// The design also specifies enable, library-access and delete controls. Those
/// are deliberately absent here: [JellyfinClient] exposes none of those writes,
/// and a control that can only fail is a promise Cupola cannot keep.
///
/// `/Users` is elevated like `/Devices` and `/ScheduledTasks`, so a household
/// member's token gets the same calm placeholder as those two tabs rather than
/// a refusal drawn as a fault.
///
/// [instanceId] is the `?i=` of the location the tab was built for. A tab's
/// root reads the connection the visit has in view first (`streamInstanceOf`,
/// not pinned) and this where the visit has none; null reads the lens. The same
/// on every tab below.
///
/// [service] is the server of the family the tab is drawn for (Jellyfin unless
/// told otherwise): the four tabs are the same page over the same client
/// surface, so one widget serves every server and picks its providers, its
/// accent and its words by this. The same on every tab below.
class JellyfinUsersScreen extends ConsumerWidget {
  const JellyfinUsersScreen({
    super.key,
    this.topPadding = 0,
    this.instanceId,
    this.service = ServiceKey.jellyfin,
  });

  final double topPadding;
  final String? instanceId;
  final ServiceKey service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref, service)) return _notConfigured(service);
    final providers = mediaBrowserProvidersOf(service);
    final connection = streamInstanceOf(
      ref,
      service,
      instanceId,
      pinned: false,
    );
    if (ref.watch(providers.lacksAdministratorFor(connection))) {
      return _needsAdministrator(
        context,
        ref,
        service,
        'users',
        topPadding,
        connection,
      );
    }
    return ServiceListPage<JellyfinUserDto>(
      service: service,
      instanceId: connection,
      topPadding: topPadding,
      value: ref.watch(providers.usersFor(connection)),
      serviceName: '${service.title} users',
      emptyIcon: Icons.people_outline_rounded,
      emptyTitle: 'No users',
      emptyMessage: '${service.title} returned no household users.',
      onRetry: () {
        ref.invalidate(providers.usersFor(connection));
        ref.invalidate(providers.users);
      },
      summary: _usersSummary,
      rowBuilder: (user) => _UserRow(user: user),
    );
  }
}

/// Read-only device inventory from the server's `/Devices` endpoint.
class JellyfinDevicesScreen extends ConsumerWidget {
  const JellyfinDevicesScreen({
    super.key,
    this.topPadding = 0,
    this.instanceId,
    this.service = ServiceKey.jellyfin,
  });

  final double topPadding;
  final String? instanceId;
  final ServiceKey service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref, service)) return _notConfigured(service);
    final providers = mediaBrowserProvidersOf(service);
    final connection = streamInstanceOf(
      ref,
      service,
      instanceId,
      pinned: false,
    );
    if (ref.watch(providers.lacksAdministratorFor(connection))) {
      return _needsAdministrator(
        context,
        ref,
        service,
        'devices',
        topPadding,
        connection,
      );
    }
    return ServiceListPage<JellyfinDevice>(
      service: service,
      instanceId: connection,
      topPadding: topPadding,
      value: ref.watch(providers.devicesFor(connection)),
      serviceName: '${service.title} devices',
      emptyIcon: Icons.devices_other_rounded,
      emptyTitle: 'No devices',
      emptyMessage:
          'Devices appear after a client signs in to ${service.title}.',
      onRetry: () {
        ref.invalidate(providers.devicesFor(connection));
        ref.invalidate(providers.devices);
      },
      summary: (devices) => countLabel(devices.length, 'device'),
      rowBuilder: (device) => _DeviceRow(device: device),
    );
  }
}

/// Scheduled maintenance jobs from the server's `/ScheduledTasks` endpoint.
///
/// `Run now` is not drawn: the client contract is read-only, even though the
/// design board shows the write as the eventual primary action.
class JellyfinTasksScreen extends ConsumerWidget {
  const JellyfinTasksScreen({
    super.key,
    this.topPadding = 0,
    this.instanceId,
    this.service = ServiceKey.jellyfin,
  });

  final double topPadding;
  final String? instanceId;
  final ServiceKey service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref, service)) return _notConfigured(service);
    final providers = mediaBrowserProvidersOf(service);
    final connection = streamInstanceOf(
      ref,
      service,
      instanceId,
      pinned: false,
    );
    if (ref.watch(providers.lacksAdministratorFor(connection))) {
      return _needsAdministrator(
        context,
        ref,
        service,
        'scheduled tasks',
        topPadding,
        connection,
      );
    }
    return ServiceListPage<JellyfinScheduledTask>(
      service: service,
      instanceId: connection,
      topPadding: topPadding,
      value: ref.watch(providers.tasksFor(connection)),
      serviceName: '${service.title} tasks',
      emptyIcon: Icons.task_alt_rounded,
      emptyTitle: 'No scheduled tasks',
      emptyMessage: '${service.title} returned no maintenance jobs.',
      onRetry: () {
        ref.invalidate(providers.tasksFor(connection));
        ref.invalidate(providers.tasks);
      },
      summary: _tasksSummary,
      rowBuilder: (task) => _TaskRow(task: task),
    );
  }
}

/// Current playback activity of the server.
///
/// The historical `/System/ActivityLog/Entries` endpoint is not present
/// in the client contract. This tab therefore renders the real activity Cupola
/// can operate today (live sessions) through the existing Stream shell.
///
/// [instanceId] is the connection to read (`?i=`); null, or one that is not a
/// connection of [service], reads the active one.
class JellyfinActivityScreen extends ConsumerWidget {
  const JellyfinActivityScreen({
    super.key,
    this.topPadding = 0,
    this.instanceId,
    this.service = ServiceKey.jellyfin,
  });

  final double topPadding;
  final String? instanceId;
  final ServiceKey service;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!_isConfigured(ref, service)) return _notConfigured(service);
    return _JellyfinActivityBody(
      service: service,
      topPadding: topPadding,
      instanceId: streamInstanceOf(ref, service, instanceId, pinned: false),
    );
  }
}

class _JellyfinActivityBody extends ConsumerWidget {
  const _JellyfinActivityBody({
    required this.service,
    required this.topPadding,
    required this.instanceId,
  });

  final ServiceKey service;
  final double topPadding;
  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = (service: service, instanceId: instanceId);
    ref.watchWhileLive(context, streamSessionsPollProvider(connection));
    final sessions = ref.watch(streamSessionsForProvider(connection));
    // The host's two bands and the status bar the upper one consumes: this
    // page has no `SafeArea` and no app bar to take the inset off first.
    final top = topPadding + MediaQuery.paddingOf(context).top;
    // The tab is this one read: a dark server is its leaf, never "Nobody is
    // watching right now".
    if (sessions.hasError && !sessions.hasValue) {
      return AmbientScaffold(
        accent: service.accent,
        body: Padding(
          padding: EdgeInsets.only(top: top),
          child: ServiceOfflineState.failure(
            service: service,
            instanceId: instanceId,
            error: sessions.error!,
            onRetry: () => refreshStreamSessions(ref, service, instanceId),
          ),
        ),
      );
    }
    return AmbientScaffold(
      accent: service.accent,
      body: RefreshIndicator(
        onRefresh: () async => refreshStreamSessions(ref, service, instanceId),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
            0,
            top + AppSpacing.md,
            0,
            FloatingNavBarMetrics.getScrollViewBottomPadding(context),
          ),
          children: [
            StreamNowPlayingSection(
              service: service,
              instanceId: instanceId,
              sessions: sessions,
            ),
            if (ref.watch(
              mediaBrowserProvidersOf(
                service,
              ).lacksAdministratorFor(instanceId),
            ))
              const JellyfinOwnPlaybackNote(),
          ],
        ),
      ),
    );
  }
}

bool _isConfigured(WidgetRef ref, ServiceKey service) =>
    ref.watch(currentSettingsProvider).isServiceConfigured(service);

Widget _notConfigured(ServiceKey service) =>
    NotConfiguredPlaceholder.forService(service);

/// The Devices and Tasks tabs on a non-administrator token: `/Devices` and
/// `/ScheduledTasks` are elevated, so the list would only ever be a refusal.
Widget _needsAdministrator(
  BuildContext context,
  WidgetRef ref,
  ServiceKey service,
  String what,
  double topPadding,
  String instanceId,
) => AmbientScaffold(
  accent: service.accent,
  body: JellyfinAdminPlaceholder(
    service: service,
    what: what,
    // The host's two bands and the status bar the upper one consumes.
    topPadding: topPadding + MediaQuery.paddingOf(context).top,
    connectionId: streamConnectionIdOf(ref, service, instanceId),
  ),
);

class _UserRow extends StatelessWidget {
  const _UserRow({required this.user});

  final JellyfinUserDto user;

  @override
  Widget build(BuildContext context) {
    final role = user.isAdministrator ? 'Administrator' : 'User';
    final state = user.isDisabled ? 'Disabled' : role;
    final lastActivity = user.lastActivityAt == null
        ? 'Last activity unavailable'
        : 'Last active ${formatDayWords(user.lastActivityAt!, now: DateTime.now())}';
    // A role is not a state, and colour is information: an administrator's
    // row says so in its words, as every other row does, and carries no tone.
    const tone = StatusTone.neutral;
    return ServiceRecordRow(
      icon: user.isDisabled
          ? Icons.person_off_outlined
          : Icons.person_outline_rounded,
      tone: tone,
      title: user.name.trim().isEmpty ? 'Unnamed user' : user.name.trim(),
      detail: lastActivity,
      trailing: state,
      semanticLabel:
          '${user.name.trim().isEmpty ? 'Unnamed user' : user.name.trim()}, '
          '$state, $lastActivity',
    );
  }
}

class _DeviceRow extends StatelessWidget {
  const _DeviceRow({required this.device});

  final JellyfinDevice device;

  @override
  Widget build(BuildContext context) {
    final name = device.name.trim().isEmpty ? 'Unnamed device' : device.name;
    final client = [
      device.appName.trim(),
      device.appVersion.trim(),
    ].where((part) => part.isNotEmpty).join(' ');
    final owner = device.lastUserName.trim().isEmpty
        ? 'User unavailable'
        : device.lastUserName.trim();
    final lastSeen = device.lastActivityAt == null
        ? 'Last seen unavailable'
        : 'Last seen ${formatRelativeDateTime(device.lastActivityAt!)}';
    final detail = [
      owner,
      if (client.isNotEmpty) client,
      lastSeen,
    ].join(dotSeparator);
    return ServiceRecordRow(
      icon: Icons.devices_other_rounded,
      tone: StatusTone.neutral,
      title: name,
      detail: detail,
      trailing: client.isEmpty ? '—' : device.appName,
      semanticLabel:
          '$name, $owner, ${client.isEmpty ? 'client unavailable' : client}, $lastSeen',
    );
  }
}

class _TaskRow extends StatelessWidget {
  const _TaskRow({required this.task});

  final JellyfinScheduledTask task;

  @override
  Widget build(BuildContext context) {
    final presentation = _taskPresentation(task);
    final started = task.lastStartedAt == null
        ? 'Last run unavailable'
        : 'Started ${formatRelativeDateTime(task.lastStartedAt!)}';
    final duration = _taskDuration(task);
    final detail = [
      started,
      ?duration,
      if (task.errorMessage.trim().isNotEmpty) task.errorMessage.trim(),
    ].join(dotSeparator);
    final name = task.name.trim().isEmpty ? 'Unnamed task' : task.name.trim();
    return ServiceRecordRow(
      icon: presentation.icon,
      tone: presentation.tone,
      title: name,
      detail: detail,
      trailing: presentation.label,
      semanticLabel:
          '$name, ${presentation.label}, ${spokenFromDotted(detail)}',
    );
  }
}

String _usersSummary(List<JellyfinUserDto> users) {
  final disabled = users.where((user) => user.isDisabled).length;
  final suffix = disabled == 0 ? '' : '\u00A0· $disabled disabled';
  return '${countLabel(users.length, 'user')}$suffix';
}

String _tasksSummary(List<JellyfinScheduledTask> tasks) {
  final running = tasks.where((task) => task.isRunning).length;
  final suffix = running == 0 ? '' : '\u00A0· $running running';
  return '${tasks.length} scheduled$suffix';
}

({String label, StatusTone tone, IconData icon}) _taskPresentation(
  JellyfinScheduledTask task,
) {
  if (task.isRunning) {
    final progress = task.progress;
    final suffix = progress == null
        ? ''
        : '\u00A0· ${formatPercent(progress.clamp(0, 100))}';
    return (
      label: 'Running$suffix',
      tone: StatusTone.info,
      icon: Icons.sync_rounded,
    );
  }
  if (task.failed) {
    return (
      label: 'Failed',
      tone: StatusTone.warning,
      icon: Icons.warning_amber_rounded,
    );
  }
  if (task.lastStatus.toLowerCase() == 'completed') {
    return (
      label: 'Completed',
      tone: StatusTone.success,
      icon: Icons.task_alt_rounded,
    );
  }
  final label = task.state.trim().isEmpty ? 'Idle' : task.state.trim();
  return (label: label, tone: StatusTone.neutral, icon: Icons.schedule_rounded);
}

String? _taskDuration(JellyfinScheduledTask task) {
  final start = task.lastStartedAt;
  final end = task.lastEndedAt;
  if (start == null || end == null || end.isBefore(start)) return null;
  final duration = end.difference(start);
  return formatTimeSpan(duration);
}
