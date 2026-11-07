import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/utils/service_routes.dart';

/// Opens a person's page, under the tab the page it is called from is in, so
/// Back returns to the row (`ServiceRoutes.tracearrPerson`). Outside a router
/// (a widget test, a preview) there is nowhere to go and nothing happens.
void openTracearrPerson(BuildContext context, String id) {
  final router = GoRouter.maybeOf(context);
  if (router == null) return;
  router.push(ServiceRoutes.tracearrPerson(id, from: router.state.uri.path));
}

/// Opens Tracearr's Violations tab narrowed to one person (`?user=`), which the
/// tab reads (`TracearrViolationsScreen`): [userId] is `TracearrUser.id`, the
/// id the tab's `user_id` filter takes.
void openTracearrViolationsOf(BuildContext context, String userId) =>
    GoRouter.maybeOf(context)?.go(ServiceRoutes.tracearrViolationsOf(userId));
