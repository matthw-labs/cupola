@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/widgets/app_dialog.dart';

import 'catalog.dart';

/// Opens the real dialog on a navigator of the scene's own, so the route
/// (barrier and all) paints inside the scene rather than above the sheet.
class _Opened extends StatefulWidget {
  const _Opened(this.open);

  final Future<AppConfirmResult> Function(BuildContext context) open;

  @override
  State<_Opened> createState() => _OpenedState();
}

class _OpenedState extends State<_Opened> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.open(context);
    });
  }

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: Theme.of(context).colorScheme.surface);
}

CatalogScene _scene(
  String caption,
  Future<AppConfirmResult> Function(BuildContext context) open, {
  double height = 320,
  double width = 390,
  CatalogPlatform platform = CatalogPlatform.phone,
  double textScale = 1,
  Future<void> Function(WidgetTester tester, Finder scene)? act,
}) => CatalogScene(
  caption,
  (_) => ClipRect(
    child: Navigator(
      onGenerateRoute: (_) =>
          PageRouteBuilder<void>(pageBuilder: (_, _, _) => _Opened(open)),
    ),
  ),
  width: width,
  height: height,
  platform: platform,
  textScale: textScale,
  act: act,
);

/// Enter confirms here, so the scene tabs past Cancel to the confirm: the
/// focus ring sits on the primary action, where Enter lands.
Future<AppConfirmResult> _approveByEnter(BuildContext context) =>
    showAppConfirmDialog(
      context: context,
      useRootNavigator: false,
      title: 'Approve this request?',
      message: 'Sherlock Jr. goes to Radarr · 4K and starts downloading.',
      icon: Icons.check_circle_outline_rounded,
      confirmLabel: 'Approve request',
      enterConfirms: true,
    );

/// Tracearr's Stop: a verb, the other button saying the stream goes on, and
/// an optional word for the viewer.
Future<AppConfirmResult> _stop(BuildContext context) => showAppConfirmDialog(
  context: context,
  useRootNavigator: false,
  title: 'Stop this stream?',
  message: 'Anna is watching Nosferatu. They can start it again straight away.',
  icon: Icons.stop_circle_outlined,
  confirmLabel: 'Stop stream',
  cancelLabel: 'Keep playing',
  field: const AppConfirmField(label: 'Message for Anna\u00A0· optional'),
);

/// Removing a movie from Radarr, with what Tracearr knows of who watched it:
/// a quiet line under the sentence, and nothing of it when Tracearr is silent.
Future<AppConfirmResult> _removeWatched(
  BuildContext context, {
  String? note = 'Watched by 3\u00A0· last 12 days ago',
}) => showAppConfirmDialog(
  context: context,
  useRootNavigator: false,
  title: 'Remove Big Buck Bunny from Radarr?',
  message: 'Radarr stops looking for it.',
  note: note,
  icon: Icons.delete_outline_rounded,
  cancelLabel: 'Keep it',
  confirmLabel: 'Remove from Radarr',
  confirmLabelFor: (checked) =>
      checked('files') ? 'Remove and delete 1.2 GB' : 'Remove from Radarr',
  options: const [
    AppConfirmOption(
      key: 'files',
      label: 'Also delete 1.2 GB of files',
      subtitle: 'Its folder on your server. This cannot be undone.',
    ),
    AppConfirmOption(
      key: 'exclude',
      label: "Don't add it again",
      subtitle: "Keeps Radarr's import lists from bringing it back",
    ),
  ],
);

Future<AppConfirmResult> _grab(BuildContext context) => showAppConfirmDialog(
  context: context,
  useRootNavigator: false,
  title: 'Grab release',
  message: 'Download "Nosferatu.1922.1080p.BluRay.x264"?',
  confirmLabel: 'Download release',
);

/// The Activity queue removal: two options, and a label that says both.
Future<AppConfirmResult> _remove(
  BuildContext context, {
  bool deleteChecked = true,
}) => showAppConfirmDialog(
  context: context,
  useRootNavigator: false,
  title: 'Remove from queue?',
  message: 'Metropolis.1927.1080p.BluRay.x264',
  icon: Icons.delete_outline_rounded,
  confirmLabel: deleteChecked ? 'Remove and delete files' : 'Remove from queue',
  confirmLabelFor: (checked) =>
      switch ((checked('removeFromClient'), checked('blocklist'))) {
        (true, true) => 'Remove, delete files and blocklist',
        (true, false) => 'Remove and delete files',
        (false, true) => 'Remove and blocklist',
        (false, false) => 'Remove from queue',
      },
  options: [
    AppConfirmOption(
      key: 'removeFromClient',
      label: 'Delete from download client',
      subtitle:
          'Also removes the files that have been downloaded so far. This '
          'cannot be undone.',
      initialValue: deleteChecked,
    ),
    const AppConfirmOption(
      key: 'blocklist',
      label: 'Blocklist this release',
      subtitle: 'Stops it being grabbed again, so a search finds another.',
    ),
  ],
);

Future<AppConfirmResult> _deleteSnapshot(BuildContext context) =>
    showAppConfirmDialog(
      context: context,
      useRootNavigator: false,
      title: 'Delete snapshot?',
      message:
          'tank/media@auto-2026-09-22_00-00 is destroyed. This cannot be '
          'undone.',
      confirmLabel: 'Delete snapshot',
    );

Future<AppConfirmResult> _approve(BuildContext context) => showAppConfirmDialog(
  context: context,
  useRootNavigator: false,
  title: 'Approve this request?',
  message: 'Sherlock Jr. goes to Radarr · 4K and starts downloading.',
  icon: Icons.check_circle_outline_rounded,
  confirmLabel: 'Approve request',
);

Future<AppConfirmResult> _longTitle(BuildContext context) =>
    showAppConfirmDialog(
      context: context,
      useRootNavigator: false,
      title:
          'Delete The Cabinet of Dr. Caligari and every file Radarr holds '
          'for it?',
      message:
          'The Cabinet of Dr. Caligari (1920). The files go too; Radarr can '
          'download them again later.',
      confirmLabel: 'Delete movie',
    );

Future<AppConfirmResult> _shutDown(BuildContext context) async {
  await showAppTypedConfirmDialog(
    context,
    useRootNavigator: false,
    icon: Icons.power_settings_new_rounded,
    title: 'Shut down nas?',
    message:
        'Everything on this host stops: apps, instances, the SMB · NFS · '
        'iSCSI shares and this connection. Nothing in Cupola can bring it '
        'back, only the power button or IPMI can.',
    phrase: 'nas',
    confirmLabel: 'Shut down server',
  );
  return AppConfirmResult.cancelled;
}

void main() {
  catalogCard(
    'AppDialog',
    width: 880,
    scenes: [
      _scene(
        'Standard · the grab confirmation · Cancel as a TextButton, the '
        'confirm as the theme\'s FilledButton',
        _grab,
        height: 300,
      ),
      _scene(
        'With a field · Stop this stream? · an optional word for the viewer, '
        'the other button saying the stream goes on',
        _stop,
        height: 400,
      ),
      _scene(
        'With a note · the removal of a movie · Watched by 3 and when, from '
        'Tracearr, quiet under the sentence and above the options',
        _removeWatched,
        height: 520,
      ),
      _scene(
        'With a note · nobody has watched it: said only when Tracearr '
        'answered for the title',
        (context) => _removeWatched(context, note: 'Nobody has watched it'),
        height: 520,
      ),
      _scene(
        'Standard with an icon · Approve this request? · the icon in onSurface',
        _approve,
        height: 320,
      ),
      _scene(
        'Enter confirms · the focus ring is on the confirm, the one '
        'non-destructive primary action that takes Enter',
        _approveByEnter,
        height: 320,
        act: (tester, scene) async {
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pumpAndSettle();
        },
      ),
      _scene(
        'A delete, the files option ticked · the same neutral dialog; the '
        'label says the whole of it and the subtitle says it cannot be undone',
        _remove,
        height: 560,
      ),
      _scene(
        'The same, unticked · confirmLabelFor rewrites the verb as the '
        'options change',
        (context) => _remove(context, deleteChecked: false),
        height: 560,
      ),
      _scene(
        'A delete with no options · the irreversibility is one sentence in '
        'the message',
        _deleteSnapshot,
        height: 340,
      ),
      _scene(
        'Long title · the title stops at two lines',
        _longTitle,
        height: 380,
      ),
      _scene(
        'Typed confirmation · showAppTypedConfirmDialog · the button stays '
        'inert until the phrase is typed',
        _shutDown,
        height: 560,
      ),
      _scene(
        'On a desktop window · the same dialog under compact density',
        _remove,
        width: 832,
        height: 520,
        platform: CatalogPlatform.desktop,
      ),
      _scene(
        'Text at 200% · the grab confirmation: the title, the message and '
        'both buttons at twice the reading size',
        _grab,
        height: 640,
        textScale: catalogTextScale,
      ),
      _scene(
        'Text at 200% · the dialog with a field: the label, the message and '
        'both buttons',
        _stop,
        height: 1100,
        textScale: catalogTextScale,
      ),
      _scene(
        'Text at 200% · a delete with two options: the labels, the subtitles '
        'and the confirm label that rewrites itself',
        _remove,
        height: 1100,
        textScale: catalogTextScale,
      ),
      _scene(
        'Text at 200% · the typed confirmation',
        _shutDown,
        height: 1100,
        textScale: catalogTextScale,
      ),
    ],
  );
}
