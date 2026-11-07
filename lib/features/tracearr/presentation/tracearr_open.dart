import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/platform/browser_opener.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// Where Tracearr's own page for a violation is on its web app. Read from its
/// web source (`/violations/:id`), not from any API: the one place Cupola
/// sends a person to read what it does not draw.
String tracearrViolationWebPath(String violationId) =>
    'violations/${Uri.encodeComponent(violationId)}';

/// Where Tracearr's server settings are on its web app.
const String tracearrServersWebPath = 'settings/servers/connections';

/// Opens [webPath] of Tracearr's web app in the browser, at the address the
/// connection is reached on now (home or away), under whatever path prefix a
/// reverse proxy gives it.
///
/// [instanceId] names the connection; empty is the lens. Nothing opens when
/// the connection has no address yet. The address comes from the reach and
/// never from the saved one, and carries no key: Tracearr's web app asks for
/// its own sign-in.
Future<void> openInTracearr(
  WidgetRef ref,
  String webPath, {
  String instanceId = '',
}) async {
  final id = instanceId.isNotEmpty
      ? instanceId
      : ref.read(activeInstanceProvider(ServiceKey.tracearr))?.id ?? '';
  final reach = ref.read(connectionReachProvider(id));
  if (reach == null) return;
  final base = Uri.tryParse(reach.url);
  if (base == null || base.host.isEmpty) return;
  final prefix = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  await ref
      .read(browserOpenerProvider)
      .open(base.replace(path: '$prefix/$webPath'));
}
