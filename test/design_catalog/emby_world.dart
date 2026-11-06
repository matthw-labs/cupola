import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../test_helpers/profiles/profiles.dart';

/// The demo world's Emby (`lib/demo/world/`), as a card's scenes read it: the
/// fake server answers at its own address, nothing leaves the process, and
/// the app's own clients, providers and parsers draw what comes back.
///
/// A card starts the world in its `overrides` callback, which runs inside the
/// card's test body, so the network is installed for the test and taken down
/// with it. Each scene then reads it through an [EmbyWorldScope], a container
/// of its own over the world's settings, so a card's other scenes never see
/// the profile.
ProfileHarness? _world;

/// Installs [profile]'s fake network for the test the caller runs in.
///
/// Dated from the real clock, not from [catalogNow]: the app judges whether a
/// session is playing by its own `DateTime.now()` (the dialect takes no
/// clock), so a world dated to the hour would read every session as idle.
/// Scenes therefore draw nothing the world words by the hour.
///
/// Returns no overrides: the card has none to share, and the world is read
/// through [EmbyWorldScope].
Future<List<Override>> startEmbyWorld(ConfigProfile profile) async {
  _world = await ProfileHarness.start(profile);
  return const [];
}

/// A scene's own provider container over the started world's settings and
/// network, with [overrides] on top. Retries are off, since a sheet is drawn
/// once and a retry timer would outlive the test.
class EmbyWorldScope extends StatefulWidget {
  const EmbyWorldScope({
    super.key,
    this.overrides = const [],
    required this.child,
  });

  final List<Override> overrides;
  final Widget child;

  @override
  State<EmbyWorldScope> createState() => _EmbyWorldScopeState();
}

class _EmbyWorldScopeState extends State<EmbyWorldScope> {
  late final ProviderContainer _container = ProviderContainer(
    overrides: [..._world!.overrides, ...widget.overrides],
    retry: (retryCount, error) => null,
  );

  @override
  void dispose() {
    _container.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      UncontrolledProviderScope(container: _container, child: widget.child);
}
