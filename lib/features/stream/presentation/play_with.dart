import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/widgets/app_bottom_sheet.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/settings/data/stream_player_provider.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/presentation/widgets/settings_choice_row.dart';
import 'package:cupola/features/stream/data/stream_app_launcher.dart';
import 'package:cupola/features/stream/domain/stream_players.dart';

/// Whether this device plays a title in an app of the viewer's choosing: a
/// phone, where those apps exist. Elsewhere the browser, as before.
bool playsOnPhone() =>
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.android;

/// Plays [itemId] on [server], in the app the viewer chooses.
///
/// Only Jellyfin and Emby on a phone have a choice, each among its own
/// players ([StreamPlayer.of]). Anything else opens [webUrl] in the browser
/// with no sheet, as it always did. On those two the order is:
///
///  1. the app the viewer remembered, while it is still installed, straight
///     away; one uninstalled since is forgotten, and the sheet shows;
///  2. the browser alone, when no app is installed: opened, no sheet;
///  3. otherwise the sheet, one row per installed player with the browser last,
///     and a box to remember the choice.
///
/// Nothing is preferred by default. [title] is what the sheet names the item.
Future<void> playWith(
  BuildContext context,
  WidgetRef ref, {
  required ServiceInstance server,
  required String itemId,
  required String title,
  Uri? webUrl,
}) async {
  final players = StreamPlayer.of(server.service);
  if (players.isEmpty || !playsOnPhone()) {
    await _open(context, ref, _browserOf(server.service), webUrl);
    return;
  }

  final serverId = await _serverId(ref, server);
  final userId = server.viewerId.trim();
  final links = <StreamPlayer, Uri>{};
  for (final player in players) {
    if (!player.platforms.contains(defaultTargetPlatform)) continue;
    final link = player.link(
      itemId: itemId,
      serverId: serverId,
      userId: userId,
      webUrl: webUrl,
    );
    if (link != null) links[player] = link;
  }
  final installed = await _installed(ref, players, links);
  if (!context.mounted || installed.isEmpty) return;

  final choice = streamPlayerChoiceOf(server.service);
  final remembered = ref.read(choice);
  if (remembered != null) {
    if (installed.contains(remembered)) {
      await _open(context, ref, remembered, links[remembered]);
      return;
    }
    // Uninstalled since it was chosen: forgotten, and the viewer is asked.
    ref.read(choice.notifier).set(null);
  }

  if (installed.length == 1 && installed.single.isBrowser) {
    final browser = installed.single;
    await _open(context, ref, browser, links[browser]);
    return;
  }

  if (!context.mounted) return;
  final picked = await AppBottomSheet.show<(StreamPlayer, bool)>(
    context: context,
    title: 'Play with',
    subtitle: title,
    showClose: true,
    builder: (_) =>
        PlayWithSheet(players: installed, serviceTitle: server.service.title),
  );
  if (picked == null || !context.mounted) return;
  final (player, remember) = picked;
  if (remember) ref.read(choice.notifier).set(player);
  await _open(context, ref, player, links[player]);
}

/// The browser player of [service]: the one a server with no apps opens.
StreamPlayer _browserOf(ServiceKey service) =>
    service == ServiceKey.emby ? StreamPlayer.embyWeb : StreamPlayer.web;

/// Opens [link] in [player]'s app. A failure says so once.
Future<void> _open(
  BuildContext context,
  WidgetRef ref,
  StreamPlayer player,
  Uri? link,
) async {
  final opened =
      link != null && await ref.read(streamAppLauncherProvider).open(link);
  if (!opened && context.mounted) {
    SnackBarHelper.error(context, 'Could not open ${player.label}');
  }
}

/// The players among [links] that can be opened: the browser always, an app
/// when the platform says one claims its scheme. In the order of [players],
/// the browser last.
Future<List<StreamPlayer>> _installed(
  WidgetRef ref,
  List<StreamPlayer> players,
  Map<StreamPlayer, Uri> links,
) async {
  final launcher = ref.read(streamAppLauncherProvider);
  final installed = <StreamPlayer>[];
  for (final player in players) {
    final link = links[player];
    if (link == null) continue;
    if (player.isBrowser || await launcher.canOpen(link)) {
      installed.add(player);
    }
  }
  return [
    ...installed.where((player) => !player.isBrowser),
    ...installed.where((player) => player.isBrowser),
  ];
}

/// The server's own id, or null when it is not known: Swiftfin and Emby's app
/// are then not offered.
Future<String?> _serverId(WidgetRef ref, ServiceInstance server) async {
  try {
    return await ref.read(
      mediaBrowserProvidersOf(server.service).serverId(server.id).future,
    );
  } catch (_) {
    return null;
  }
}

/// The choice of the player, one row each, the browser last. Tapping one
/// chooses it; the box says whether to remember it.
///
/// Public so the design catalog draws the body of the sheet `playWith` opens
/// on the root navigator, which a sheet of scenes cannot show.
class PlayWithSheet extends StatefulWidget {
  const PlayWithSheet({
    super.key,
    required this.players,
    required this.serviceTitle,
  });

  final List<StreamPlayer> players;

  /// The server the title is on, which the setting is found under.
  final String serviceTitle;

  @override
  State<PlayWithSheet> createState() => _PlayWithSheetState();
}

class _PlayWithSheetState extends State<PlayWithSheet> {
  bool _remember = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Nothing is chosen until the viewer taps: no row carries a check.
        for (final player in widget.players)
          SettingsChoiceRow(
            label: player.label,
            description: player.line,
            selected: false,
            onSelected: () => Navigator.of(context).pop((player, _remember)),
          ),
        const SizedBox(height: AppSpacing.sm),
        CheckboxListTile(
          value: _remember,
          onChanged: (value) => setState(() => _remember = value ?? false),
          controlAffinity: ListTileControlAffinity.leading,
          contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          title: const Text('Remember my choice'),
          // The secondary ink, as every subtitle.
          subtitle: Text(
            'Change it in Settings, on your ${widget.serviceTitle} connection.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// The Settings choice of the app a [service] title plays in: `Ask every
/// time`, or one of the players installed here, the browser last. Chosen in a
/// sheet, saved at once.
Future<void> chooseStreamPlayer(
  BuildContext context,
  WidgetRef ref, {
  ServiceKey service = ServiceKey.jellyfin,
}) async {
  final launcher = ref.read(streamAppLauncherProvider);
  final installed = <StreamPlayer>[];
  for (final player in StreamPlayer.of(service)) {
    final probe = player.probe;
    if (probe != null && await launcher.canOpen(probe)) installed.add(player);
  }
  // The browser last, as in the sheet that plays a title.
  installed.add(_browserOf(service));
  final choice = streamPlayerChoiceOf(service);
  if (!context.mounted) return;
  await AppBottomSheet.show<void>(
    context: context,
    title: 'Play with',
    subtitle: '${service.title} titles',
    showClose: true,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final current = ref.watch(choice);
        void choose(StreamPlayer? player) {
          ref.read(choice.notifier).set(player);
          Navigator.of(sheetContext).pop();
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SettingsChoiceRow(
              label: 'Ask every time',
              selected: current == null,
              onSelected: () => choose(null),
            ),
            for (final player in installed)
              SettingsChoiceRow(
                label: player.label,
                description: player.line,
                selected: current == player,
                onSelected: () => choose(player),
              ),
          ],
        );
      },
    ),
  );
}
