import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cupola/core/providers/async_value_kept.dart';

import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/utils/arr_activity_display.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/dockge/presentation/dockge_actions.dart';
import 'package:cupola/features/dockge/presentation/dockge_overview_provider.dart';
import 'package:cupola/features/dockge/presentation/dockge_provider.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The first tab of Dockge's service home.
///
/// Overview alone carries the identity block and the readouts: Stacks is a
/// view of one kind of record and Terminal is a console, and then two
/// regions: the stacks, running ones by name and the rest summed by state, and
/// which instances this login can reach. The stacks region ends in a link
/// named exactly like the tab it jumps to.
///
/// There is no Needs attention region. That region holds faults, and Dockge
/// reports none: a stopped stack may have been brought down on purpose, and
/// the push says nothing more. A Dockge that does not answer is the stacks
/// region's own error.
///
/// What is not running still leads to where it is looked after: every row is
/// a door. A stack opens its own page (its log and its controls); a row that
/// sums several opens the Stacks tab; and one stopped stack can be started
/// from its row, through the action the Stacks tab runs.
///
/// **It draws neither the app bar nor the tab bar.** `ServiceHomeScreen` owns
/// the first, including the agent lens, which is an app-bar control and not a
/// tab (decision 41), and which this page must therefore never grow a second
/// copy of, and `ServiceTabScaffold` owns the second. Both float above this
/// page as glass bands so the ambient gradient reads continuously behind them;
/// this screen reserves the room with [topPadding] instead.
///
/// ## Where this departs from the board, and why
///
/// Dockge speaks Socket.IO and not REST, and its `stackList` push is a name, an
/// integer status, tags, a compose filename and an endpoint. Four things the
/// board draws have no source in that protocol, and each is **absent rather
/// than stubbed**: a section given a fake zero is worse than a section that
/// was never promised:
///
///  * **`Updates 3 · images newer` and the `Update all 3` button.** Dockge has
///    an `updateStack` command and no read that answers whether an update
///    exists; there is no event for "newer image available". A readout that
///    cannot be computed and a button that cannot know what it would pull are
///    both promises this app cannot keep.
///  * **`34 containers` beside the running count.** Container counts come from
///    `serviceStatusList`, which is **per stack**: one socket round trip each.
///    Fanning twelve of them out to fill one readout would be expensive, and
///    fanning out only the five the preview draws and printing the sum as a
///    total would be a figure counted inside a capped sample and then stated as
///    a census. Neither is worth a number.
///  * **`stopped · 3 h ago` and `exit code 137 · out of memory`.** Nothing in
///    this protocol is dated, and nothing carries a container exit code. See
///    `dockge_overview_provider.dart` for the long form.
///  * **The terminal card.** `DockgeClient` streams `terminalWrite` only after
///    joining a *named* stack's combined terminal, so the Overview offers a
///    way in through each stack row while the dedicated Terminal tab owns the
///    live session for the selected stack.
///
/// Sections load and fail independently. A Dockge that pushes a stack list but
/// no agent list still draws two regions, and the third simply is not there.
class DockgeOverviewScreen extends StatelessWidget {
  const DockgeOverviewScreen({
    super.key,
    this.topPadding = ServiceOverviewPage.hostedTopPadding,
  });

  /// Height of the chrome the host draws above this page.
  final double topPadding;

  @override
  Widget build(BuildContext context) {
    return ServiceOverviewPage(
      service: ServiceKey.dockge,
      topPadding: topPadding,
      kpis: (ref) => ref
          .watch(dockgeOverviewCensusProvider)
          .whenDataKept(
            (census) => dockgeKpisFromCounts(
              total: census.total,
              running: census.running,
              stopped: census.stopped,
            ),
          ),
      refresh: _refresh,
      sections: (ref) => [const _StacksSection(), const _AgentsSection()],
    );
  }
}

/// What a pull re-reads besides the readout (`ServiceOverviewPage`).
void _refresh(WidgetRef ref) {
  // The probe as well as the wrapper over it: the probe is not
  // `autoDispose`, so a pull that left it alone redrew the band from the
  // answer it already had.
  // The two pushes every region is folded from, and the three folds
  // derived from them.
  ref.invalidate(dockgeStackListProvider);
  ref.invalidate(dockgeAgentsProvider);
  ref.invalidate(dockgeOverviewCensusProvider);
  ref.invalidate(dockgeOverviewStacksProvider);
  ref.invalidate(dockgeOverviewAgentsProvider);
}

// ─── 1. Stacks ──────────────────────────────────────────────────────────────

/// What is up, by name, and the rest by state under it.
class _StacksSection extends ConsumerWidget {
  const _StacksSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(dockgeOverviewStacksProvider);
    final census = ref.watch(dockgeOverviewCensusProvider).asData?.value;

    return ServiceOverviewSection(
      service: ServiceKey.dockge,
      title: 'Stacks',
      subtitle: _subtitle(
        ref,
        census: census,
        shown: preview.asData?.value.running.length,
      ),
      destination: ServiceTab.stacks,
      child: AsyncValueWidget<DockgeStacksPreview>.section(
        value: preview,
        service: ServiceKey.dockge,
        consequence: 'its stacks are not shown',
        loadingLabel: 'Loading the stacks',
        // The **source**, not the fold. Invalidating this fold alone would
        // rebuild it against the `AsyncError` the stream is still holding and
        // hand back the same failure without a round trip, and the stream,
        // watched by the census as well, is never disposed and so never
        // re-subscribes on its own. Invalidating it is what reconnects; the
        // folds follow it down.
        onRetry: () {
          ref.invalidate(dockgeStackListProvider);
          ref.invalidate(dockgeOverviewStacksProvider);
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 3),
        // Empty only on a server with no stacks at all: one whose stacks are
        // all down still draws their rows.
        isEmpty: (data) => data.running.isEmpty && data.idle.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.layers_clear_rounded,
          label: 'No stacks here yet',
        ),
        data: (data) => Column(
          children: [
            for (final row in data.running) _StackRow(row: row),
            for (final group in data.idle) _IdleRow(group: group),
          ],
        ),
      ),
    );
  }

  /// What the readout rail cannot say, and nothing it already has.
  ///
  /// `_dockgeKpis` fills the `ServiceKpiPeek` two regions above this one with
  /// Stacks / Running / Stopped / Inactive, off this same push. A subtitle
  /// reading `12 stacks · 9 running · 2 stopped · 1 inactive` would be those
  /// four figures again, one region below the rail that already spells them, at
  /// bodySmall and wrapping to three lines beside the `Stacks →` link at 375pt.
  ///
  /// Two things are left that the rail genuinely cannot say, and they are the
  /// whole of this line:
  ///
  ///  * **which Dockge these figures came off**, when there is more than one to
  ///    have come off. The client holds exactly one agent's stacks at a time,
  ///    so the rail's own `12` is per agent too. This is the clause that keeps
  ///    it from reading as the deployment's total.
  ///  * **how much of the running list the five rows below leave out**, which
  ///    is a fact about this preview and exists nowhere else on the page.
  ///
  /// Null when neither applies: a single-instance Dockge with nothing
  /// truncated, because a header with nothing to add says nothing. There is no
  /// em dash either: an em dash stands in for a figure whose source did not
  /// answer, and this line no longer states a figure to stand in for.
  static String? _subtitle(
    WidgetRef ref, {
    required DockgeStackCensus? census,
    required int? shown,
  }) {
    final parts = joinDisplayParts([
      _agentQualifier(ref),
      if (census != null && shown != null && shown < census.running)
        '$shown of ${census.running} running',
    ]);
    return parts.isEmpty ? null : parts;
  }

  /// `on nas`, or nothing on a Dockge with one instance.
  ///
  /// Read off the agent list rather than the lens alone, because the lens holds
  /// an endpoint (`truenas.lan:5001`) and the header wants the name.
  static String? _agentQualifier(WidgetRef ref) {
    final agents = ref.watch(dockgeAgentsProvider).asData?.value ?? const [];
    if (agents.length < 2) return null;
    final selected = ref.watch(dockgeSelectedAgentProvider);
    for (final agent in agents) {
      if (agent.endpoint == selected) return 'on ${agent.name}';
    }
    return null;
  }
}

class _StackRow extends StatelessWidget {
  const _StackRow({required this.row});

  final DockgeStackRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(
      colorScheme,
      row.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    // Every stack is a door: its own page carries the log and the controls,
    // and the hint says so, because "opens the stack" does not explain why
    // somebody looking at it would want to.
    return ServiceOverviewRow(
      spoken: row.spoken,
      // A dot rather than a glyph: every row in this section is one state of
      // one healthy thing, and an icon per row would read as a kind of event.
      leading: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 5),
        decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
      ),
      // The name stays in ink: the tone belongs to the dot, and a page where
      // every title is coloured has no way left to say one of them differs.
      title: row.name,
      detail: row.detail,
      onTap: () => openAttentionDoor(context, ServiceKey.dockge, row.door),
      doorHint: attentionDoorHint(ServiceKey.dockge, row.door),
    );
  }
}

/// The stacks in one state that is not running, summed: neutral, because
/// Dockge does not say whether a stop was meant.
///
/// A row about one stack opens that stack's page, and a stopped one can be
/// started from here, through the action the Stacks tab and the stack's page
/// already run (Start is additive, so it stays one tap, as it is there). A row
/// that sums several has no single stack to open or start: its door is the
/// Stacks tab, which lists them all.
class _IdleRow extends ConsumerWidget {
  const _IdleRow({required this.group});

  final DockgeIdleGroup group;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    // Through the tone rule, never a colour constant. Every group is neutral:
    // a stack somebody brought down is backlog, and painting it the amber of
    // one that died is the failure the five-arm rule exists to prevent.
    final tone = statusToneColor(
      colorScheme,
      group.tone,
      surface: colorScheme.surfaceContainerLow,
    );
    final door = group.door;
    final stack = group.stack;

    return ServiceOverviewRow(
      spoken: group.spoken,
      leading: Icon(group.icon, size: 18, color: tone),
      title: group.headline,
      titleColor: tone,
      detail: group.detail,
      onTap: door == null
          ? null
          : () => openAttentionDoor(context, ServiceKey.dockge, door),
      doorHint: door == null
          ? null
          : attentionDoorHint(ServiceKey.dockge, door),
      action: group.startable && stack != null
          ? ServiceOverviewRowAction(
              label: 'Start',
              hint: 'starts $stack',
              onPressed: () => runDockgeStackAction(
                context,
                ref,
                (client) => client.startStack(stack),
                'Started $stack',
                'Could not start $stack',
                invalidate: [
                  dockgeStackListProvider,
                  serviceKpiProvider(ServiceKey.dockge),
                ],
              ),
            )
          : null,
    );
  }
}

// ─── 2. Agents ──────────────────────────────────────────────────────────────

/// Which instances this login can reach.
///
/// Drawn **only when there are two or more**, which is the same guard
/// `DockgeAgentLensButton` keeps and deliberately the same rule: most Dockge
/// installs are a single instance, and a section listing "local" teaches the
/// user there is a decision to make when there is not. It is also why the
/// section has no link: the picker is the app-bar lens, and a second one here
/// would be two controls fighting over one piece of state.
///
/// That missing link is why [dockgeAgentRows] is **uncapped**, and the two facts
/// are one decision. Every other region on this page ends in a tab that holds
/// the rest of its list; this one ends nowhere, so a row this section does not
/// draw is a row the app never mentions. With no cap, the header's figures are
/// counted over exactly what is on screen, which is the whole list, instead of
/// stating a sample's own length as the deployment's total.
class _AgentsSection extends ConsumerWidget {
  const _AgentsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rows = ref.watch(dockgeOverviewAgentsProvider).asData?.value;
    // Nothing at all while the list is in flight, and nothing on a
    // single-instance Dockge: a skeleton here would promise a region that on
    // most servers correctly does not exist, and an error state would report
    // the failure of a feature the user may not have.
    if (rows == null || rows.length < 2) return const SizedBox.shrink();

    // Counted over `rows`, which is every agent the push carried. See the
    // class doc. Red is the one tone that means "did not answer", so this is
    // the offline count and not a roll-up of everything that is not green:
    // `connecting` has not failed yet.
    final offline = rows.where((row) => row.tone == StatusTone.error).length;

    return ServiceOverviewSection(
      service: ServiceKey.dockge,
      title: 'Agents',
      subtitle: joinDisplayParts([
        '${rows.length} instances',
        if (offline > 0) '$offline ${StateWord.didNotAnswer.inline}',
      ]),
      child: Column(children: [for (final row in rows) _AgentRow(row: row)]),
    );
  }
}

class _AgentRow extends StatelessWidget {
  const _AgentRow({required this.row});

  final DockgeAgentRow row;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(
      colorScheme,
      row.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: row.spoken,
      // The lens's position, drawn. `DockgeAgentRow.detail` already ends in
      // "showing its stacks", which is what a screen reader hears; the ring is
      // the same fact for an eye scanning four rows, and it is the only thing
      // that makes this a list of instances rather than a readout of them. It
      // borrows the row's own tone rather than an accent, so a selected agent
      // that is offline does not quietly lose its red.
      leading: _AgentDot(tone: tone, selected: row.isSelected),
      title: row.name,
      detail: row.detail,
    );
  }
}

/// The state dot, ringed on the agent the lens is on.
class _AgentDot extends StatelessWidget {
  const _AgentDot({required this.tone, required this.selected});

  final Color tone;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
    );

    // The same 16pt box and the same optical centre either way: the ring eats
    // the inset it needs out of the padding rather than growing the box, so the
    // row's text does not step sideways when the lens moves.
    return Container(
      margin: const EdgeInsets.only(top: 1),
      padding: EdgeInsets.all(selected ? 3 : 4),
      decoration: selected
          ? BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: tone.withValues(alpha: 0.45)),
            )
          : null,
      child: dot,
    );
  }
}
