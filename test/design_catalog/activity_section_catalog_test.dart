@Tags(['catalog'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/theme.dart';
import 'package:cupola/features/activity/presentation/widgets/activity_section.dart';

import 'catalog.dart';

/// A row of words, as the page's rows are: a title and what it says.
class _Row extends StatelessWidget {
  const _Row(this.title, this.line, {this.divided = false});

  final String title;
  final String line;
  final bool divided;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        border: divided ? Border(top: BorderSide(color: room.hair)) : null,
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppType.row.copyWith(color: room.ink)),
            Text(line, style: AppType.meta.copyWith(color: room.inkSecondary)),
          ],
        ),
      ),
    );
  }
}

void main() {
  catalogCard(
    'ActivitySection',
    scenes: [
      CatalogScene(
        'ActivitySection() · a name on the page over a slab of rows, and '
        'what it counts at the end of the name\'s line',
        (_) => ActivitySection(
          title: 'Downloads',
          meta: '4 moving · 1 stuck',
          children: const [
            _Row('Sprite Fright', '62% · 11 min'),
            _Row('Elephants Dream', '31% · 6 min', divided: true),
            _Row('Big Buck Bunny', 'Stuck at 47%', divided: true),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'ActivitySection() · no count: the name alone, as Finished today '
        'has none to say when there is only the one',
        (_) => ActivitySection(
          title: 'Finished today',
          children: const [_Row('Spring', 'Imported 18:52')],
        ),
        width: 390,
      ),
      CatalogScene(
        'ActivitySection(onOpen:) · a count too long for the name\'s line '
        '(three groups) goes under the name, left-aligned, as it does at a '
        'large reading size, instead of running past the page',
        (_) => ActivitySection(
          title: 'Needs you',
          meta: '3 faults · 2 violations · 3 requests',
          onOpen: () {},
          openHint: 'Opens Needs you',
          children: const [_Row('Big Buck Bunny', 'Stuck at 47%')],
        ),
        width: 390,
        id: 'long-count-goes-under-the-name',
      ),
      CatalogScene(
        'ActivitySection(onOpen:) · the count leads to the section\'s own '
        'view, with a chevron and a 44pt target',
        (_) => ActivitySection(
          title: 'Up next',
          meta: '1 queued',
          onOpen: () {},
          openHint: 'Opens Downloads',
          children: const [_Row('Sintel', 'Queued · starts in about 6 min')],
        ),
        width: 390,
      ),
      CatalogScene(
        'ActivitySlabLink() · the last line of a slab leads on: what it '
        'opens, what it counts, a chevron, over a hairline',
        (_) => ActivitySection(
          title: 'Everyone\'s requests',
          meta: '8 total',
          children: [
            const _Row('Coffee Run', 'Ready to watch since 17:53'),
            const _Row(
              'Sprite Fright',
              'Downloading 62% · ready around 21:04',
              divided: true,
            ),
            ActivitySlabLink(
              label: 'All 8 requests',
              meta: '2 processing',
              onTap: () {},
            ),
          ],
        ),
        width: 390,
      ),
      CatalogScene(
        'ActivitySlabLink(divided: false) · the only line of a slab, with '
        'no count, and a long label that ellipsises its count rather than '
        'itself',
        (_) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ActivitySlab(
            children: [
              ActivitySlabLink(
                label: 'All of today in History',
                meta: '3 imports and 1 failed download',
                divided: false,
                onTap: () {},
              ),
            ],
          ),
        ),
        width: 320,
      ),
      CatalogScene(
        'Text at 200% · the count goes under the name rather than beside '
        'it, the name never breaks inside a word',
        (_) => ActivitySection(
          title: 'Everyone\'s requests',
          meta: '8 total',
          onOpen: () {},
          children: [
            const _Row('Coffee Run', 'Ready to watch since 17:53'),
            ActivitySlabLink(
              label: 'All 8 requests',
              meta: '2 processing',
              onTap: () {},
            ),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'Text at 200% · a section with no count, and a link line of '
        'two words',
        (_) => ActivitySection(
          title: 'Finished today',
          children: [
            const _Row('Spring', 'Imported 18:52'),
            ActivitySlabLink(label: 'All of today in History', onTap: () {}),
          ],
        ),
        width: 390,
        textScale: catalogTextScale,
      ),
      CatalogScene(
        'On the desktop · a section in the page well',
        (_) => ActivitySection(
          title: 'Downloads',
          meta: '4 moving · 1 stuck',
          onOpen: () {},
          children: [
            const _Row('Sprite Fright', '62% · 11 min'),
            const _Row('Big Buck Bunny', 'Stuck at 47%', divided: true),
            ActivitySlabLink(label: 'All 5 downloads', onTap: () {}),
          ],
        ),
        width: 560,
        platform: CatalogPlatform.desktop,
      ),
    ],
  );
}
