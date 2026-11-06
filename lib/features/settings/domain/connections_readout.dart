import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/status/media_status.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// "SABnzbd and Unraid": a list of service names a sentence can hold.
///
/// One rule in one place: the summary card joins service names in three
/// different contexts (a fault, the ones still to set up, the ones a search
/// cannot reach past the app) and they must read identically. The final "and"
/// rather than a trailing comma, because two service names separated by a
/// comma read as one name with a suffix.
String joinServiceNames(List<ServiceKey> services) => switch (services.length) {
  0 => '',
  1 => services.single.title,
  2 => '${services[0].title} and ${services[1].title}',
  _ =>
    '${services.take(services.length - 1).map((s) => s.title).join(', ')} '
        'and ${services.last.title}',
};

/// Every service that shares one connection state, and the state itself.
///
/// The grouping is the point. Eighteen services with one cause (the VPN is
/// down, the host is asleep) is one fact, and eighteen rows saying
/// "Unreachable" is that fact repeated until it stops being read. Grouped by
/// the vocabulary's own label, the same screen says "SABnzbd and Unraid ·
/// Unreachable" and "Bazarr · API key rejected", which is two facts and two
/// different things to go and do.
class ConnectionGroup {
  const ConnectionGroup({required this.presentation, required this.services});

  /// The state all of [services] are in. Its `label`, `icon` and `tone` are the
  /// only words and colours this group is ever described with.
  final ConnectionPresentation presentation;

  /// In registry order, so the same fault always reads in the same order.
  final List<ServiceKey> services;

  String get names => joinServiceNames(services);
}

/// What the whole stack looks like right now, folded out of
/// [describeConnection] and nothing else.
///
/// Pure, and takes the already-described states rather than the providers that
/// produce them, so the rule (which counts are printed, which tone the summary
/// takes, how failures group) can be tested without a widget or a container.
class ConnectionsReadout {
  ConnectionsReadout._({
    required this.registrySize,
    required this.setUp,
    required this.answering,
    required this.checking,
    this.onlyAtHome = 0,
    required this.faults,
    required this.notSetUp,
  });

  /// Folds [states]: one entry per **configured** service, in registry order,
  /// into the readout.
  ///
  /// [notSetUp] is passed rather than derived because "not set up" is not a
  /// connection state the prober can return: nothing was dialled.
  ///
  /// [answeringServices], when given, is the count the summary prints, made by
  /// the Stack's rule: a service that answered and refused the key answered.
  /// The Stack counts it and names the refusal; this card used to leave it out
  /// of the count and name it, which made `12 of 13` there and `11 answering`
  /// here out of one stack. The fault groups still come from [states].
  factory ConnectionsReadout.from({
    required Map<ServiceKey, ConnectionPresentation> states,
    required List<ServiceKey> notSetUp,
    int registrySize = -1,
    int? answeringServices,
  }) {
    var answering = 0;
    var checking = 0;
    var onlyAtHome = 0;
    // Insertion-ordered, so the groups come out in the order the registry lists
    // the first service of each.
    final grouped = <String, List<ServiceKey>>{};
    final presentations = <String, ConnectionPresentation>{};

    for (final entry in states.entries) {
      final presentation = entry.value;
      // Away from home, not asked: counted apart, never a group to fix.
      if (presentation.label == StateWord.onlyAtHome.label) {
        onlyAtHome++;
        continue;
      }
      if (presentation.needsAttention) {
        grouped.putIfAbsent(presentation.label, () => []).add(entry.key);
        presentations[presentation.label] = presentation;
        continue;
      }
      // Answering and checking are told apart by the tone's own vocabulary
      // rather than by re-reading the status: `checking` is the one healthy
      // state that is not an answer yet, and counting it as one would make a
      // stack that has not finished probing look whole.
      if (presentation.tone == StatusTone.success) {
        answering++;
      } else {
        checking++;
      }
    }

    return ConnectionsReadout._(
      registrySize: registrySize < 0 ? ServiceKey.values.length : registrySize,
      setUp: states.length,
      answering: answeringServices ?? answering,
      checking: checking,
      onlyAtHome: onlyAtHome,
      faults: [
        for (final entry in grouped.entries)
          ConnectionGroup(
            presentation: presentations[entry.key]!,
            services: entry.value,
          ),
      ],
      notSetUp: notSetUp,
    );
  }

  /// Every service Cupola knows how to talk to: the denominator the count chip
  /// and this summary both print, so "16 of 17" means the same thing on both.
  final int registrySize;

  final int setUp;
  final int answering;
  final int checking;

  /// Services not asked because the app is away from home and they have no
  /// address away: `· 11 only at home`, neutral, never a fault group.
  final int onlyAtHome;

  /// One group per distinct failing state, worst first is **not** imposed here:
  /// registry order is, because a stable order is what lets the eye skip a card
  /// it has already read.
  final List<ConnectionGroup> faults;

  final List<ServiceKey> notSetUp;

  bool get isEmpty => setUp == 0;

  /// The one line the card leads with: "16 of 17 set up · 14 answering".
  ///
  /// "answering" is the vocabulary's own word for a healthy connection (it is
  /// what `describeConnection` returns), not a synonym invented for a summary.
  String get summary {
    final line = StringBuffer('$setUp of $registrySize set up');
    if (setUp > 0) line.write('\u00A0· $answering answering');
    if (checking > 0) line.write('\u00A0· checking $checking');
    if (onlyAtHome > 0) {
      line.write('\u00A0· $onlyAtHome ${StateWord.onlyAtHome.inline}');
    }
    return line.toString();
  }

  /// The tone of the whole card.
  ///
  /// **The worst tone among the failures, never a boolean.** It used to be
  /// "any failure at all ⇒ red", which painted a stack whose only complaint is
  /// a rejected API key in the colour this system reserves for *nothing
  /// answered*, sending the user to check cables over a wrong key that the
  /// form two taps away would have fixed.
  StatusTone get tone {
    if (faults.any((group) => group.presentation.tone == StatusTone.error)) {
      return StatusTone.error;
    }
    if (faults.isNotEmpty) return StatusTone.warning;
    if (isEmpty) return StatusTone.neutral;
    return StatusTone.success;
  }
}
