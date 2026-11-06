/// The Home's last known state: what each module drew the last time it had a
/// live answer, drawn again at a cold start until the live answer comes.
///
/// The store and why it keeps drawings rather than responses are in
/// `LastKnownStore`. This is the Home's side: which modules keep one
/// ([HomeLastKnownSlot]), for which connections, and how a module reads "the
/// live answer, or else the last known one" in one call
/// ([HomeLastKnownWatch.watchOrLastKnown]).
///
/// What stays out, on purpose: Needs you and the header's health (a fault of
/// yesterday is a false alarm today) and Now playing (live by nature).
/// Activity and Discover keep nothing: they read the providers the Home
/// already made live by the time they are a tap away.
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import 'package:cupola/core/last_known/last_known_store.dart';
import 'package:cupola/core/last_known/stored_image.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/utils/url_utils.dart';
import 'package:cupola/features/discover/presentation/library_calendar_provider.dart'
    show calendarClockProvider;
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/settings_model.dart';
import 'package:cupola/features/shell/domain/shell_audience.dart';
import 'package:cupola/features/stream/presentation/stream_backend.dart';

/// One module's last drawing: its name in the store, the shape of its data,
/// the services it reads (whose connections the drawing is valid for), and
/// its codec.
///
/// [encode] turns the module's live value into JSON with no credential in it
/// (pictures through the [StoredImageKeeper] it is handed, times as
/// instants), or answers null for a value not worth keeping (every source
/// silent: the drawing before it is the better one). [decode] turns it back,
/// with pictures resolved against the connections as they are now; null for
/// anything it cannot read, which the module takes as nothing known. Bump
/// [schema] whenever the JSON changes shape: an entry of another schema is
/// dropped rather than misread.
@immutable
class HomeLastKnownSlot<T> {
  const HomeLastKnownSlot({
    required this.id,
    required this.schema,
    required this.services,
    required this.encode,
    required this.decode,
    this.silent,
  });

  final String id;
  final int schema;
  final Set<ServiceKey> services;
  final Object? Function(T value, StoredImageKeeper keep) encode;
  final T? Function(Object? data, StoredImageResolver image) decode;

  /// Whether a live value is a read that no source answered: the Home's reads
  /// do not fail, they answer with every source silent. Such a value is a
  /// failure to a module that has a last drawing, which it keeps over the
  /// failure ([HomeRead.silent]). Null for a read that fails as an error.
  final bool Function(T value)? silent;
}

/// A module's value with where it came from: live ([asOf] null), or the last
/// drawing, as of [asOf]; and the live read itself, for whether it is still
/// being asked for or failed. [silent]: the live read answered with no source
/// answering, and [value] is the drawing kept over that failure (its words
/// are the live value's coverage).
typedef HomeRead<T> = ({
  T? value,
  DateTime? asOf,
  AsyncValue<T> live,
  bool silent,
});

/// What the drawings of [services] are valid for: each of their connections
/// as it is set up (service, id, address, user, viewer, the Seerr account),
/// never a secret. A change to any of them is a different server or a
/// different person, and the drawing is dropped.
///
/// The address is the one at home, the one the connection is known by: the
/// route moving to the address away reaches the same server, so the drawing
/// stays, and its pictures draw at the address away ([resolveStoredImage]).
String homeLastKnownValidity(SettingsModel settings, Set<ServiceKey> services) {
  final parts = [
    for (final instance in settings.instances)
      if (services.contains(instance.service) && instance.url.isNotEmpty)
        [
          instance.service.name,
          instance.id,
          instance.url,
          instance.username,
          instance.viewerId,
          instance.account?.userId ?? '',
        ].join('|'),
  ]..sort();
  return parts.join(';');
}

/// The store key of [slot] for [audience]: the two Homes keep theirs apart.
String homeLastKnownKey(String audience, HomeLastKnownSlot<Object?> slot) =>
    'home.$audience.${slot.id}';

/// [slot]'s last drawing for the Home on screen, decoded, or null.
///
/// Read once per slot and connections, not on every build: it is what the
/// module draws until its live answer comes, after which nothing reads it.
final homeLastKnownProvider = Provider.autoDispose
    .family<({Object? value, DateTime asOf})?, HomeLastKnownSlot<Object?>>((
      ref,
      slot,
    ) {
      final audience = ref.watch(shellAudienceProvider).name;
      final settings = ref.watch(currentSettingsProvider);
      final entry = ref
          .read(lastKnownStoreProvider)
          .read(
            homeLastKnownKey(audience, slot),
            validity: homeLastKnownValidity(settings, slot.services),
            schema: slot.schema,
          );
      if (entry == null) return null;
      try {
        final value = slot.decode(
          entry.data,
          (image) => resolveStoredImage(ref, settings, image),
        );
        if (value == null) return null;
        return (value: value, asOf: entry.takenAt);
      } catch (_) {
        return null;
      }
    });

/// A kept picture with the headers its connection sends today; nothing, for
/// a connection that is gone.
///
/// An arr's picture is drawn at the address its connection is reached at now
/// (`connectionReachProvider`), whichever address it was kept at, with that
/// address's access: a drawing kept at home draws away from home as the live
/// one would. Its credential goes to that address and nowhere else.
ImageSource resolveStoredImage(
  Ref ref,
  SettingsModel settings,
  StoredImage image,
) {
  switch (image) {
    case StoredUrl(:final url):
      return (url: url, headers: null);
    case StoredArrImage(:final connectionId, :final path):
      final instance = settings.instanceById(connectionId);
      if (instance == null || instance.credential.isEmpty) return noImage;
      final reach = ref.watch(connectionReachProvider(connectionId));
      final url = reach == null ? '' : UrlUtils.buildUrl(reach.url, path);
      if (url.isEmpty) return noImage;
      return (
        url: url,
        headers: {...reach!.access.headers(), 'X-Api-Key': instance.credential},
      );
    case StoredStreamImage(:final service, :final connectionId, :final path):
      if (settings.instanceById(connectionId) == null) return noImage;
      // A picture kept against anything but a media server has no client to
      // resolve it through, and is drawn as none.
      final source = service.isMediaServer
          ? ref
                .read(streamBackendOf(service).clientFor(connectionId))
                .imageFor(path, width: image.width)
          : null;
      return source ?? noImage;
  }
}

/// Keeps a picture against the connections of [settings]: an arr's by its
/// connection and its path under whichever of that connection's addresses it
/// was drawn from, at home or away ([StoredImage.ofSource]).
StoredImageKeeper storedImageKeeper(SettingsModel settings) =>
    (source, {service, connectionId}) => StoredImage.ofSource(
      source,
      service: service,
      connectionId: connectionId,
      addresses: switch (connectionId) {
        final id? => settings.instanceById(id)?.addresses ?? const [],
        null => const [],
      },
    );

extension HomeLastKnownWatch on WidgetRef {
  /// [live]'s value when it has one, kept as [slot]'s last drawing; until it
  /// has one, the last drawing, with the time it is as of.
  ///
  /// Kept from the module's build because a module is built only while it is
  /// on (or near) the screen: what is kept is what the person saw, and a
  /// module scrolled far away neither loads nor writes. The write is cheap
  /// (an identical value is not encoded again) and lands on disk once the
  /// burst of answers has passed.
  HomeRead<T> watchOrLastKnown<T>(
    ProviderListenable<AsyncValue<T>> live,
    HomeLastKnownSlot<T> slot,
  ) {
    final read = watch(live);
    if (read.value case final T value?) {
      final silent = slot.silent?.call(value) ?? false;
      if (silent) {
        // No source answered: the last drawing, if there is one, stands
        // over the failure rather than giving way to nothing.
        final known = watch(homeLastKnownProvider(slot));
        if (known != null) {
          return (
            value: known.value as T,
            asOf: known.asOf,
            live: read,
            silent: true,
          );
        }
      } else {
        _keep(this, slot, value);
      }
      return (value: value, asOf: null, live: read, silent: false);
    }
    final known = watch(homeLastKnownProvider(slot));
    if (known == null) {
      return (value: null, asOf: null, live: read, silent: false);
    }
    return (
      value: known.value as T,
      asOf: known.asOf,
      live: read,
      silent: false,
    );
  }
}

void _keep<T>(WidgetRef ref, HomeLastKnownSlot<T> slot, T value) {
  final store = ref.read(lastKnownStoreProvider);
  final key = homeLastKnownKey(ref.read(shellAudienceProvider).name, slot);
  final settings = ref.read(currentSettingsProvider);
  final validity = homeLastKnownValidity(settings, slot.services);
  // The same answer, rebuilt: already kept.
  if (value is Object && store.holds(key, validity: validity, source: value)) {
    return;
  }
  final data = slot.encode(value, storedImageKeeper(settings));
  if (data == null) return;
  store.write(
    key,
    validity: validity,
    schema: slot.schema,
    data: data,
    takenAt: ref.read(calendarClockProvider)(),
    source: value,
  );
}

/// The modules drawing their last known state right now, and as of when;
/// what the Home's one line reads (`HomeAsOfLine`).
///
/// Not provider state: a module says it from its widget's own life
/// ([LastKnownMark]), and a module scrolled out of the tree takes its mark
/// with it. Listeners hear after the frame, never during a build.
class HomeLastKnownMarks extends ChangeNotifier {
  final Map<Object, ({DateTime asOf, bool checking})> _marks = {};
  bool _scheduled = false;
  bool _disposed = false;

  @override
  void dispose() {
    // A mark leaving the tree with the scope that held this hears nothing.
    _disposed = true;
    super.dispose();
  }

  /// The marks now: what the line reads.
  Iterable<({DateTime asOf, bool checking})> get marks => _marks.values;

  void _set(Object key, ({DateTime asOf, bool checking})? mark) {
    if (_disposed) return;
    final before = _marks[key];
    if (mark == null) {
      if (_marks.remove(key) == null) return;
    } else {
      if (before == mark) return;
      _marks[key] = mark;
    }
    if (_scheduled) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (!_disposed) notifyListeners();
    });
    SchedulerBinding.instance.ensureVisualUpdate();
  }
}

final homeLastKnownMarksProvider = Provider<HomeLastKnownMarks>((ref) {
  final marks = HomeLastKnownMarks();
  ref.onDispose(marks.dispose);
  return marks;
});

/// Says, for as long as it is in the tree, that [child] is a last drawing as
/// of [asOf] (nothing when [asOf] is null), and whether the live answer is
/// still being asked for ([checking]).
class LastKnownMark extends ConsumerStatefulWidget {
  const LastKnownMark({
    super.key,
    required this.asOf,
    required this.checking,
    required this.child,
  });

  final DateTime? asOf;
  final bool checking;
  final Widget child;

  @override
  ConsumerState<LastKnownMark> createState() => _LastKnownMarkState();
}

class _LastKnownMarkState extends ConsumerState<LastKnownMark> {
  late final HomeLastKnownMarks _marks = ref.read(homeLastKnownMarksProvider);

  @override
  void initState() {
    super.initState();
    _say();
  }

  @override
  void didUpdateWidget(LastKnownMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    _say();
  }

  void _say() => _marks._set(this, switch (widget.asOf) {
    final asOf? => (asOf: asOf, checking: widget.checking),
    null => null,
  });

  @override
  void dispose() {
    _marks._set(this, null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final asOf = widget.asOf;
    if (asOf == null) return widget.child;
    final now = ref.watch(calendarClockProvider)();
    return LastKnownWords(
      words: 'As of ${formatAsOf(asOf, now: now)}',
      child: widget.child,
    );
  }
}

/// The words of the drawing a module stands on (`As of 20:41`), for a line
/// under it that says why it is one: away from home, `Lidarr only works at
/// home. As of 20:41.` Put there by [LastKnownMark].
class LastKnownWords extends InheritedWidget {
  const LastKnownWords({super.key, required this.words, required super.child});

  final String words;

  /// The words of the drawing [context] stands on, or null over a live read.
  static String? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<LastKnownWords>()?.words;

  @override
  bool updateShouldNotify(LastKnownWords oldWidget) => oldWidget.words != words;
}

/// The Home's one line about its last known state: `As of 20:53 · checking
/// now` while a module draws one and its answer is being asked for, `As of
/// 20:53` once only failures are left; the oldest of them, since the line
/// speaks for all.
///
/// The day as the rows of people say it (`As of yesterday 20:53`, `As of
/// Wednesday 20:53`, then `As of Tue 29 Sep`): the brand book's `As of
/// 20:53`, a snapshot's own words.
String? homeAsOfWords(
  Iterable<({DateTime asOf, bool checking})> marks, {
  required DateTime now,
}) {
  if (marks.isEmpty) return null;
  final oldest = marks
      .map((mark) => mark.asOf)
      .reduce((a, b) => a.isBefore(b) ? a : b);
  final checking = marks.any((mark) => mark.checking);
  return [
    'As of ${formatAsOf(oldest, now: now)}',
    if (checking) 'checking now',
  ].join(dotSeparator);
}

/// When a snapshot was taken, as `As of …` finishes it: `20:53` today,
/// `yesterday 20:53`, `Wednesday 20:53` within the week, then the date alone
/// (`Tue 29 Sep`).
String formatAsOf(DateTime at, {required DateTime now}) {
  final local = at.toLocal();
  final day = formatPastDay(local, now: now);
  if (day == null) return formatClockTime(local);
  if (calendarDaysBetween(local, now.toLocal()) < 7) {
    return '$day ${formatClockTime(local)}';
  }
  return day;
}
