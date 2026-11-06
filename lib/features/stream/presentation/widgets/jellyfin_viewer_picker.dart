import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/jellyfin/presentation/jellyfin_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_not_configured.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/stream/domain/stream_server_client.dart';

/// Picks whose watch state the Jellyfin library is read through.
///
/// **This is a required setting, not a preference, and the reason is structural.**
/// A Jellyfin API key authenticates as an administrator with **no user attached**:
/// the `UserId` claim is the empty GUID. It can therefore see every session and
/// every library, but it cannot answer "have I watched this": resume positions,
/// next-up and the unplayed filter are all user-scoped, and the endpoints that
/// serve them return 404 rather than a default when no `userId` is supplied.
///
/// So a household has to say which member the library speaks for. There is no
/// sensible default to fall back on: picking the first administrator would
/// silently report someone else's positions in a house of four, which is both a
/// wrong answer and a small privacy leak, and invisible in single-user testing.
///
/// **Plex has no counterpart, deliberately.** Its token *is* its user and
/// `/library/*` accepts no impersonation parameter, so a Plex library has exactly
/// one perspective. The control is absent there rather than showing a list of one.
class JellyfinViewerPicker extends ConsumerWidget {
  const JellyfinViewerPicker({
    super.key,
    this.instanceId = '',
    this.service = ServiceKey.jellyfin,
  });

  /// The server of the MediaBrowser family the viewer is chosen on: Emby's API
  /// key has no user either, so the same control serves it. It decides which
  /// providers list the users and which name the messages carry.
  final ServiceKey service;

  /// Which connection this picker fills in for.
  ///
  /// **Load-bearing, not decoration.** A Jellyfin user id exists only in one
  /// server's user table, so listing and saving have to happen against the same
  /// connection. Read and written through `settings.jellyfinUserId` /
  /// `copyWithViewer`, both of which resolve to the *first* instance, this
  /// control listed the users of the server whose form was on screen and then
  /// saved the chosen one onto a different server, leaving that one bound to an
  /// id it has never heard of, which breaks every user-scoped query on it
  /// (Continue watching, Next up, unplayed) and silently.
  ///
  /// Empty means the lens, which is what every caller meant before Jellyfin
  /// could have two.
  final String instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final selectedId = ref.watch(
      currentSettingsProvider.select(
        (s) => _instanceOf(s, service, instanceId)?.viewerId ?? '',
      ),
    );
    final viewersAsync = ref.watch(
      mediaBrowserProvidersOf(service).viewersFor(instanceId),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Watch state',
          semanticsLabel: 'Watch state',
          style: AppTheme.chrome(
            context,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Continue watching, next up and unplayed are per person. Choose whose '
          'the library should show.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        viewersAsync.when(
          loading: () => const _PickerSkeleton(),
          // Not an error state: the viewer list needs a working connection, and
          // the user may simply not have saved one yet. Saying so is more useful
          // than an exception they cannot act on from here.
          error: (error, _) => Text(
            error is ServiceNotConfigured
                ? '${Lexicon.setUp(service.title)} first, then '
                      'come back to choose a viewer.'
                : sectionFailureMessage(
                    service,
                    error,
                    consequence: 'its viewers are not shown',
                  ),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          data: (viewers) => viewers.isEmpty
              ? Text(
                  'This server reports no users.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              : _ViewerList(
                  viewers: viewers,
                  selectedId: selectedId,
                  onSelected: (viewer) => _select(ref, viewer),
                ),
        ),
      ],
    );
  }

  Future<void> _select(WidgetRef ref, StreamViewer viewer) async {
    final settings = ref.read(currentSettingsProvider);
    final instance = _instanceOf(settings, service, instanceId);
    if (instance == null) return;
    await ref
        .read(settingsProvider.notifier)
        // Onto the instance the list came from, never through `copyWithViewer`
        // (that writes the service's first connection whatever this form is
        // editing). See [instanceId].
        .updateSettings(
          settings.copyWithInstance(instance.copyWith(viewerId: viewer.id)),
        );
    // The client is rebuilt from the new id, which invalidates every per-viewer
    // lens with it; see `jellyfinClientProvider`, where the viewer is part of
    // *which client you are talking to* rather than part of a page's identity.
  }
}

/// The connection [id] names, or the one the lens is on when it names none.
ServiceInstance? _instanceOf(
  SettingsModel settings,
  ServiceKey service,
  String id,
) {
  if (id.isEmpty) return settings.primaryOf(service);
  return settings.instanceById(id);
}

class _ViewerList extends StatelessWidget {
  const _ViewerList({
    required this.viewers,
    required this.selectedId,
    required this.onSelected,
  });

  final List<StreamViewer> viewers;
  final String selectedId;
  final ValueChanged<StreamViewer> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        for (final viewer in viewers)
          Semantics(
            label: viewer.name,
            selected: viewer.id == selectedId,
            button: true,
            excludeSemantics: true,
            child: ChoiceChip(
              label: Text(viewer.name),
              selected: viewer.id == selectedId,
              onSelected: (_) => onSelected(viewer),
            ),
          ),
      ],
    );
  }
}

class _PickerSkeleton extends StatelessWidget {
  const _PickerSkeleton();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading viewers',
      child: Wrap(
        spacing: AppSpacing.sm,
        children: [
          ShimmerPlaceholder.text(width: 84),
          ShimmerPlaceholder.text(width: 68),
        ],
      ),
    );
  }
}
