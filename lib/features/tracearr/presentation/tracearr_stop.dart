import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_dialog.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/tracearr/data/tracearr_client.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_live_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_present.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_provider.dart';
import 'package:cupola/features/tracearr/presentation/tracearr_session.dart';

/// Asks whether to end [session], with a word for the person watching, and
/// ends it through Tracearr.
///
/// A write, so nothing happens before the person says so: a neutral
/// confirmation whose button names what will happen, and whose other button
/// says the stream goes on. The word for the viewer is optional and is handed
/// to Tracearr as it is typed; the sheet never claims it arrived, because
/// Tracearr relays it and the player decides whether it can show one.
///
/// What comes back decides what is said:
///
///  * **ended**: the row leaves the list at once (Tracearr's stop event would
///    say the same) and a line says so;
///  * **no such route** (an older Tracearr): Stop is hidden for this
///    connection from then on ([tracearrStopAbsentProvider]) and one line says
///    this Tracearr cannot stop a stream, which is a fact about it and not a
///    fault;
///  * **already ended**: the list is read again and the line says it had
///    stopped by itself;
///  * **refused**: Tracearr reached the media server and the stream was not
///    ended. Only the status is said: the server's own sentence may name a
///    host.
///  * **a transport failure** is the usual one, in the classification's words.
Future<void> stopTracearrStream(
  BuildContext context,
  WidgetRef ref,
  TracearrSession session,
) async {
  final who = tracearrPersonOf(session.person);
  final result = await showAppConfirmDialog(
    context: context,
    title: 'Stop this stream?',
    message:
        '$who is watching ${tracearrMediaTitleOf(session.media)}. They can '
        'start it again straight away.',
    icon: Icons.stop_circle_outlined,
    confirmLabel: 'Stop stream',
    cancelLabel: 'Keep playing',
    field: AppConfirmField(label: 'Message for $who\u00A0· optional'),
  );
  if (!result.confirmed || !context.mounted) return;

  final live = ref.read(tracearrLiveProvider.notifier);
  final connection =
      ref.read(activeInstanceProvider(ServiceKey.tracearr))?.id ?? '';
  try {
    final outcome = await ref
        .read(tracearrClientProvider)
        .terminate(session.id, reason: result.text);
    if (!context.mounted) return;
    switch (outcome) {
      case TracearrTerminated():
        live.drop(session.id);
        SnackBarHelper.success(context, 'Stream stopped');
      case TracearrTerminateRouteAbsent():
        ref.read(tracearrStopAbsentProvider.notifier).mark(connection);
        SnackBarHelper.info(context, 'This Tracearr cannot stop streams.');
      case TracearrTerminateStreamGone():
        live.refresh();
        SnackBarHelper.info(context, 'That stream had already ended.');
      case TracearrTerminateFailed(:final statusCode):
        SnackBarHelper.error(
          context,
          'Could not stop the stream. Tracearr refused'
          '${statusCode == null ? '' : ' ($statusCode)'}.',
        );
    }
  } catch (error) {
    if (!context.mounted) return;
    SnackBarHelper.error(
      context,
      'Could not stop the stream. '
      '${writeFailureReason(ServiceKey.tracearr, error)}',
      cause: error,
    );
  }
}
