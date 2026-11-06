@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';
import 'package:cupola/features/activity/presentation/widgets/fault_card.dart';
import 'package:cupola/features/activity/presentation/widgets/needs_you_cards.dart'
    show RequestsWaitRow;
import 'package:cupola/features/activity/presentation/widgets/violation_rows.dart';
import 'package:cupola/features/home/presentation/widgets/home_module_parts.dart';
import 'package:cupola/features/services/domain/dashboard_decision.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

import 'catalog.dart';

/// The amber fill, as the cards build it.
class _Fill extends StatelessWidget {
  const _Fill(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: FilledButton(
      onPressed: () {},
      style: remedyFillStyle(context),
      child: Text(label),
    ),
  );
}

const _poster = HomeRowArt.large(posterUrl: '', icon: Icons.movie_outlined);

FaultCard _stuck({bool divided = false}) => FaultCard(
  headline: 'Big Buck Bunny is stuck at 47%',
  explanation:
      'Nothing has arrived for 3 hours, and nobody sharing it has the whole '
      'file any more.',
  art: _poster,
  release: 'Big.Buck.Bunny.2008.1080p.BluRay',
  proof: 'Radarr → qBittorrent',
  progress: 0.47,
  primary: const _Fill('Try another download'),
  primarySubtitle:
      "Radarr drops this one (1.1\u00A0GB so far), won't pick it again, and "
      'looks for another.',
  secondary: [
    (label: 'Remove', onPressed: () {}, semanticLabel: null),
    (label: 'Keep waiting', onPressed: () {}, semanticLabel: null),
  ],
  divided: divided,
);

void main() {
  catalogCard(
    'FaultCard',
    scenes: [
      CatalogScene(
        'FaultCard() · a stuck download: its proof, the amber fill with '
        'what it does, and the quieter two',
        (_) => ActivitySlab(children: [_stuck()]),
        width: 390,
      ),
      CatalogScene(
        'FaultCard() · a group of blocked imports, its cause behind Why?, '
        'one way out',
        (_) => const ActivitySlab(
          children: [
            FaultCard(
              headline: '18 downloads need a manual import',
              explanation:
                  "Sonarr finished them and won't import them on its own.",
              source: 'Sonarr',
              why:
                  'Found matching series via grab history, but release was '
                  'matched to series by ID. Automatic import is not possible.',
              art: HomeRowArt.large(posterUrl: '', icon: Icons.tv_outlined),
              primary: _Fill('Review 18'),
            ),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'FaultCard(note:) · once a way out was taken: what happened in '
        'place of the controls, with Undo where it can be taken back',
        (_) => ActivitySlab(
          children: [
            const FaultCard(
              headline: 'Elephants Dream is stuck at 31%',
              art: _poster,
              note: (
                text: 'Dropped · Radarr 4K is looking for another download',
                onUndo: null,
              ),
            ),
            FaultCard(
              headline: 'Big Buck Bunny is stuck at 47%',
              art: _poster,
              note: (
                text:
                    'Hidden until tomorrow 20:53 · it comes back if nothing '
                    'moves',
                onUndo: () {},
              ),
              divided: true,
            ),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'FaultCard.whole() · the Needs you page: a slab of its own, the '
        'headline larger, the evidence whole, Why? open',
        (_) => const ActivitySlab(
          children: [
            FaultCard.whole(
              headline: 'Disk sdd reports 8 uncorrectable errors',
              explanation:
                  'sdd could not read some data by itself. The pool is still '
                  'healthy: a scrub reads every block and repairs it from the '
                  'other disks.',
              source: 'TrueNAS · pool tank',
              why: '8 uncorrectable errors reported for sdd (ZL2PQR7T).',
              art: HomeRowArt.large(posterUrl: '', icon: Icons.storage_rounded),
              evidence: ['Pool tank · Healthy · 72%', 'Disk sdd · 8 errors'],
              primary: _Fill('Scrub tank'),
            ),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'FaultCard(running:) · work the remedy started, in blue in place of '
        'the fill, with the way out beside it',
        (_) => ActivitySlab(
          children: [
            FaultCard(
              headline: 'Disk sdd reports 8 uncorrectable errors',
              explanation:
                  'sdd could not read some data by itself. The pool is still '
                  'healthy: a scrub reads every block and repairs it from the '
                  'other disks.',
              source: 'TrueNAS · pool tank',
              art: const HomeRowArt.large(
                posterUrl: '',
                icon: Icons.storage_rounded,
              ),
              running: (
                text: 'Scrubbing tank · 2% · about 9\u00A0h left',
                progress: 0.02,
              ),
              secondary: [
                (label: 'Open alert', onPressed: () {}, semanticLabel: null),
              ],
            ),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'A health check failing on four arrs · one card in the app\'s words, '
        'the arrs named, the first on the fill and the other three two a row',
        (_) => ActivitySlab(children: [_health()]),
        width: 390,
      ),
      CatalogScene(
        'Text at 200% · every line wraps, the buttons keep their target',
        (_) => ActivitySlab(children: [_stuck()]),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'On the desktop · a stuck download in the page well',
        (_) => ActivitySlab(children: [_stuck()]),
        width: 560,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'FaultCard.row() · All on a desktop: a line a fault, its remedy '
        'beside it at the size of its words, the quieter ways behind ⋯; the '
        'requests that wait a line of their own, with Review',
        (_) => _rows(),
        width: 784,
        platform: CatalogPlatform.desktop,
      ),
      CatalogScene(
        'FaultCard.row() · the list beside an open download on a tablet '
        '(440): the remedy under the words',
        (_) => _rows(),
        width: 440,
      ),
      CatalogScene(
        'ViolationDecisionRow · Tracearr\'s unseen violations of severity '
        'high under the faults: a blue count, then a row each (the rule, '
        'the person, when) that opens the violation; no fill, no remedy',
        (_) => _violations(),
        width: 390,
        id: 'violation-rows',
      ),
      CatalogScene(
        'ViolationDecisionRow · a longer list than the page reads: the '
        'count is a floor, `5+`, never the total',
        (_) => _violations(floor: true),
        width: 390,
        id: 'violation-rows-floor',
      ),
      CatalogScene(
        'Text at 200% · ViolationDecisionRow, the words wrap and the row '
        'keeps its 44pt target',
        (_) => _violations(),
        width: 390,
        textScale: catalogTextScale,
        id: 'violation-rows-text-200',
      ),
      CatalogScene(
        'Text at 200% · FaultCard.row(), the remedy under the words',
        (_) => _rows(),
        width: 784,
        platform: CatalogPlatform.desktop,
        textScale: catalogTextScale,
      ),
    ],
  );
}

/// The same health check on four \*arrs, as `DecisionFaultCard` builds it.
FaultCard _health() {
  return FaultCard(
    headline: 'No indexer is watching for new releases',
    explanation:
        "New releases aren't grabbed on their own until an indexer has RSS "
        'sync on.',
    source: 'Radarr, Radarr 4K, Sonarr and Lidarr',
    why:
        'No indexers available with RSS sync enabled, Radarr will not grab '
        'new releases automatically',
    art: HomeRowArt.large(posterUrl: '', icon: ServiceKey.radarr.icon),
    primary: const _Fill('Open in Radarr'),
    secondary: [
      for (final arr in ['Radarr 4K', 'Sonarr', 'Lidarr'])
        (label: 'Open in $arr', onPressed: () {}, semanticLabel: null),
    ],
  );
}

/// Tracearr's violations as Needs you draws them, under the faults: one blue
/// line that counts, a row each. Invented: the rule, the person and when.
Widget _violations({bool floor = false}) {
  final decisions = [
    for (final (index, rule, who, ago) in [
      (1, 'Impossible travel', 'Anna', const Duration(hours: 2)),
      (2, 'Too many streams', 'Luca', const Duration(hours: 5)),
      (3, 'Night owl', 'Anna', const Duration(days: 1)),
    ])
      DashboardDecision(
        kind: DecisionKind.violation,
        id: 'tracearr-violation-$index',
        service: ServiceKey.tracearr,
        title: rule,
        detail: who,
        occurredAt: catalogNow.subtract(ago),
      ),
  ];
  return Builder(
    builder: (context) {
      final room = CupolaRoom.of(context);
      final blue = statusToneColor(
        Theme.of(context).colorScheme,
        StatusTone.info,
        surface: room.slab,
      );
      return ActivitySlab(
        children: violationRowsOf((
          shown: decisions,
          count: floor ? kNeedsYouViolationCap : decisions.length,
          floor: floor,
        ), blue),
      );
    },
  );
}

/// Needs you on All, a line a fault and one for the requests.
Widget _rows() => ActivitySlab(
  children: [
    FaultCard.row(
      headline: 'Big Buck Bunny is stuck at 47%',
      art: _poster,
      proof: 'Nothing for 3\u00A0h · Radarr → qBittorrent',
      primary: const _Fill('Try another download'),
      secondary: [
        (label: 'Remove', onPressed: () {}, semanticLabel: null),
        (label: 'Keep waiting', onPressed: () {}, semanticLabel: null),
      ],
    ),
    const FaultCard.row(
      headline: '18 downloads need a manual import',
      source: 'Sonarr · Cosmos Laundromat',
      art: HomeRowArt.large(posterUrl: '', icon: Icons.tv_outlined),
      primary: _Fill('Review 18'),
      divided: true,
    ),
    FaultCard.row(
      headline: 'Disk sdd reports 8 uncorrectable errors',
      source: 'TrueNAS · pool tank',
      art: const HomeRowArt.large(posterUrl: '', icon: Icons.storage_rounded),
      primary: const _Fill('Scrub tank'),
      secondary: [(label: 'Open alert', onPressed: () {}, semanticLabel: null)],
      divided: true,
    ),
    RequestsWaitRow(
      requests: [
        for (final (id, title, who) in const [
          (1, 'Charge', 'Anna'),
          (2, 'Metropolis', 'Luca'),
        ])
          DashboardDecision(
            kind: DecisionKind.pendingRequest,
            id: 'seerr-$id',
            service: ServiceKey.seerr,
            title: title,
            detail: who,
            occurredAt: null,
          ),
      ],
      onReview: () {},
      divided: true,
    ),
  ],
);
