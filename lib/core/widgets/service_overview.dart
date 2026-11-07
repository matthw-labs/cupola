import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart'
    show ProviderListenable, ProviderOrFamily;
import 'package:go_router/go_router.dart';

import 'package:cupola/core/api/base_arr_service.dart';
import 'package:cupola/core/status/lexicon.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/utils/arr_overview.dart';
import 'package:cupola/core/utils/image_utils.dart';
import 'package:cupola/core/widgets/async_value_widget.dart';
import 'package:cupola/core/widgets/media_poster_card.dart';
import 'package:cupola/core/widgets/pressable_scale.dart';
import 'package:cupola/core/app_animation.dart';
import 'package:cupola/core/models/service_kpi.dart';
import 'package:cupola/core/widgets/ambient_scaffold.dart';
import 'package:cupola/core/widgets/not_configured_placeholder.dart';
import 'package:cupola/core/widgets/service_kpi_peek.dart';
import 'package:cupola/core/widgets/service_tab_bar.dart';
import 'package:cupola/features/services/presentation/service_kpi_provider.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/network/connection_failure.dart';
import 'package:cupola/core/room_art.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/date_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/widgets/ambient_background.dart';
import 'package:cupola/core/widgets/content_card.dart';
import 'package:cupola/core/widgets/failure_remedy.dart';
import 'package:cupola/core/widgets/floating_bottom_nav_bar.dart';
import 'package:cupola/core/widgets/app_empty_state.dart';
import 'package:cupola/core/widgets/inline_error_retry.dart';
import 'package:cupola/core/widgets/rail_arrows.dart';
import 'package:cupola/core/widgets/section_header.dart';
import 'package:cupola/core/widgets/status_badge.dart';
import 'package:cupola/core/widgets/shimmer_placeholder.dart';
import 'package:cupola/features/media/presentation/open_media.dart';
import 'package:cupola/features/services/domain/attention_door.dart';
import 'package:cupola/features/services/domain/service_tab.dart';
import 'package:cupola/features/services/domain/service_summary.dart';
import 'package:cupola/features/services/domain/services_semantics.dart';
import 'package:cupola/features/services/presentation/dashboard_retry.dart';
import 'package:cupola/features/services/presentation/services_provider.dart';
import 'package:cupola/features/settings/data/connection_reach_provider.dart';
import 'package:cupola/features/settings/data/service_connection_provider.dart';
import 'package:cupola/features/settings/data/settings_provider.dart';
import 'package:cupola/features/settings/domain/connection_presentation.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';
import 'package:cupola/features/settings/domain/service_only_at_home.dart';

/// The furniture every service Overview is built out of: the identity line, the
/// section frame, the row, the empty note and the skeleton.
///
/// **It lives here because nineteen services get one of these pages and four
/// of them were already written.** Radarr, Seerr, Bazarr and Prowlarr each
/// carried a private `_OverviewSection` / `_OverviewRow` / `_SectionEmpty` /
/// `_RowsSkeleton` / `_IdentityBlock` that differed only in which `ServiceKey`
/// they named: the fifth copy would have been written before anyone noticed
/// the first four had drifted. Nine more Overviews are owed.
///
/// Everything here takes the [ServiceKey] and derives the rest: the ink by
/// [serviceOverviewInk], the tab link's destination and its spoken hint, the
/// branch a link switches to. Nothing takes a colour, because a caller passing
/// a colour is a caller that can pass a hue and put 2.4:1 text on paper.

/// The ink of an Overview's links and section marks: the room's secondary ink.
///
/// The room is monochrome (principle 3 of the brand book: colour is information), so a link
/// that opens another tab is the secondary ink the brand book draws section links
/// in, the same on every service: it used to be the service's accent, walked
/// until it cleared AA. Public because a page's own section marks have to be
/// inked the same way as the link and the lens chip here: four private copies
/// of this one expression is exactly what the rest of this file exists to
/// stop. [service] stays in the signature so every call site keeps naming
/// whose Overview it is.
Color serviceOverviewInk(ServiceKey service, ColorScheme colorScheme) =>
    colorScheme.onSurfaceVariant;

/// Switches to another of [service]'s tabs.
///
/// `goBranch`, not `context.go`: it restores that branch's own stack, which is
/// what makes "back returns to the tab you left" true. `maybeOf` rather than
/// `of` because an Overview is also legitimately built outside a shell, a
/// widget test, a preview, where there is no branch to switch and the link
/// simply does nothing rather than throwing.
///
/// Public because a row that leads to a sibling tab (an attention row whose
/// faults that tab lists) switches the branch the same way the section link
/// does.
void goToServiceTab(BuildContext context, ServiceKey service, ServiceTab tab) {
  final tabs = tabsFor(service);
  if (tabs == null) return;
  final index = tabs.indexOf(tab);
  if (index < 0) return;
  StatefulNavigationShell.maybeOf(context)?.goBranch(index);
}

/// What a screen reader is told about where [door] leads, read after the
/// row's own sentence: the chevron is the only visual mark of a door, and a
/// chevron has no name.
String attentionDoorHint(ServiceKey service, AttentionDoor door) =>
    switch (door) {
      AttentionTab(:final tab) => 'opens the ${service.title} ${tab.label} tab',
      AttentionDownload() => 'opens this download',
      AttentionPage(:final hint) => hint,
    };

/// Goes through [door] from a row of [service]'s Overview.
///
/// A tab by `goBranch` ([goToServiceTab]); a download or a page by the
/// router, through `open_media.dart` where a title or a download is opened
/// (a download's page goes beside its list on a tablet). Outside a router (a
/// widget test, a preview) there is nowhere to go, and nothing happens
/// rather than a throw: the same rule as the section link.
void openAttentionDoor(
  BuildContext context,
  ServiceKey service,
  AttentionDoor door,
) {
  switch (door) {
    case AttentionTab(:final tab):
      goToServiceTab(context, service, tab);
    case AttentionDownload(:final instanceId, :final key):
      if (GoRouter.maybeOf(context) == null) return;
      context.openDownloadAt(instanceId: instanceId, key: key);
    case AttentionPage(:final location):
      GoRouter.maybeOf(context)?.push(location);
  }
}

/// One region of a service Overview: a header, a body, and the air after it.
class ServiceOverviewSection extends StatelessWidget {
  /// The ordinary region, whose body is inset to the page column.
  const ServiceOverviewSection({
    super.key,
    required this.service,
    required this.title,
    required this.child,
    this.subtitle,
    this.destination,
    this.light,
  }) : padBody = true;

  /// A region whose body bleeds to the window edge: a poster rail, whose first
  /// tile aligns to the column while the row itself runs off it.
  ///
  /// A named constructor rather than a `padBody:` flag, per
  /// `lib/core/widgets/AGENTS.md`: the call site says which shape it is
  /// building instead of setting a mode on a general one.
  const ServiceOverviewSection.bleed({
    super.key,
    required this.service,
    required this.title,
    required this.child,
    this.subtitle,
    this.destination,
  }) : padBody = false,
       light = null;

  /// Whose Overview this is. It decides the link's ink and which shell the link
  /// switches a branch on.
  final ServiceKey service;

  final String title;
  final String? subtitle;

  /// The tab this region's "see the rest" link opens, or null for a region
  /// whose rows belong to several tabs at once.
  final ServiceTab? destination;

  final Widget child;

  /// False for [ServiceOverviewSection.bleed].
  final bool padBody;

  /// The picture of the light of the region's first title: its slab glows
  /// with it, as a card about a title does (brand book, *The title light*).
  /// Null for an unlit slab, and always for a rail, which has no slab.
  final RoomArt? light;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tab = destination;

    // A count of nothing under the heading says twice what the region's own
    // empty note says in words (`Nothing needs you`): only a count of
    // something, or an unknown one, is drawn.
    final subtitle = _zeroCount.hasMatch(this.subtitle ?? '')
        ? null
        : this.subtitle;
    final link = tab == null
        ? null
        : _TabLink(
            label: tab.label,
            color: serviceOverviewInk(service, colorScheme),
          );
    // The link's chevron sits inside the region the header silences, so the
    // destination comes back as a hint instead.
    final hint = tab == null
        ? null
        : 'opens the ${service.title} ${tab.label} tab';
    final open = tab == null
        ? null
        : () => goToServiceTab(context, service, tab);
    // Inside the slab the slab carries the inset.
    final header = SectionHeader.flush(
      title: title,
      subtitle: subtitle,
      showChevron: false,
      trailing: link,
      semanticHint: hint,
      onTap: open,
    );

    // A rail runs off the page with its heading above it; every other region
    // is a slab of the room, its heading inside.
    // Its heading carries the rail's arrows, and the rail below takes their
    // scroll (`RailArrows.controllerOf`).
    if (!padBody) {
      return RailArrows(
        builder: (context, controller, arrows) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: title,
              subtitle: subtitle,
              showChevron: false,
              trailing: link,
              semanticHint: hint,
              onTap: open,
              rail: arrows,
            ),
            const SizedBox(height: AppSpacing.sm),
            child,
            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      );
    }
    final room = CupolaRoom.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        0,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: room.slab,
          borderRadius: BorderRadius.circular(AppRadius.slab),
          border: Border.all(color: room.hair),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.slab),
          child: Stack(
            children: [
              if (light case final light?)
                Positioned.fill(child: SlabLight(art: light)),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.md,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    header,
                    const SizedBox(height: AppSpacing.sm),
                    child,
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// `0`, or `0 requests waiting`: a count of nothing.
final _zeroCount = RegExp(r'^0(\s|$)');

class _TabLink extends StatelessWidget {
  const _TabLink({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(
        text: label,
        children: [
          // The chevron belongs to the word before it: one line, always,
          // and one text, never a second copy of the tab's name.
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Icon(Icons.chevron_right_rounded, size: 18, color: color),
          ),
        ],
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: AppType.label.weight(FontWeight.w600).copyWith(color: color),
    );
  }
}

/// The widest a [ServiceOverviewRow.trailing] figure may be.
///
/// Capped rather than free: at an accessibility reading size an unconstrained
/// figure next to an `Expanded` title is a right-edge overflow, and a row that
/// throws is worse than a figure that ellipsises. The whole value is still in
/// the sentence a screen reader hears.
const double _trailingMaxWidth = 132;

/// The floor a row that opens something reaches: the whole row is the target.
const double _doorMinHeight = 44;

/// The widest a verb beside a row may be, as a share of the row: past it the
/// label ellipsises and the text keeps the larger part.
const double _actionMaxFraction = 0.45;

/// A verb beside a row: something the app already does elsewhere, one tap
/// from here.
///
/// Data rather than a widget, so a row cannot be handed a button that breaks
/// the touch target or the spoken name: [ServiceOverviewRow] draws it.
@immutable
class ServiceOverviewRowAction {
  /// A verb beside the row, a text button in the ink: what a row that is not
  /// a fault offers (a stopped stack's Start).
  const ServiceOverviewRowAction({
    required this.label,
    required this.hint,
    required this.onPressed,
  }) : remedy = false;

  /// The remedy of an amber fault (a stalled torrent's Look for peers again,
  /// a failing indexer's Test): the one amber fill, under the row's words,
  /// as the Home's Downloads draw the same remedy, so the words keep the
  /// row's width and the same cure looks the same wherever it is offered.
  const ServiceOverviewRowAction.remedy({
    required this.label,
    required this.hint,
    required this.onPressed,
  }) : remedy = true;

  /// Whether this is an amber fault's remedy ([ServiceOverviewRowAction.remedy]).
  final bool remedy;

  /// The verb, in the word the app already uses for it (`Test`, `Start`).
  final String label;

  /// What the verb acts on, said after the label: `tests Nyaa`. A button named
  /// `Test` beside a list of indexers does not say which one.
  final String hint;

  final VoidCallback onPressed;
}

/// Two lines and a leading mark: the one row shape every Overview section uses.
///
/// A row is read-only unless it is given somewhere to go. [onTap] makes it a
/// **door**: the place the row is about, one button for a screen reader that
/// speaks [spoken] and says where it leads ([doorHint]). [action] puts a verb
/// beside it, a real button of its own. A row with neither is exactly the
/// plain row it always was.
class ServiceOverviewRow extends StatelessWidget {
  const ServiceOverviewRow({
    super.key,
    required this.spoken,
    required this.leading,
    required this.title,
    required this.detail,
    this.titleColor,
    this.trailing,
    this.onTap,
    this.doorHint,
    this.action,
  }) : assert(
         (onTap == null) == (doorHint == null),
         'A door says where it leads: onTap and doorHint come together',
       );

  /// The whole row as one sentence, with the layout's `·` turned back into
  /// commas.
  final String spoken;

  /// Where the row leads, or null for a row that is only read. The whole row
  /// is the target, at least 44 tall.
  ///
  /// Drawn with a chevron, as the other rows of the app that open something
  /// are, unless the row also carries an [action]: the verb is then the mark,
  /// as it is on a Home decision row, and the body stays tappable.
  final VoidCallback? onTap;

  /// Where [onTap] goes, said after [spoken]: `opens the Prowlarr Indexers
  /// tab`. The chevron is the only visual mark of a door and has no name.
  final String? doorHint;

  /// A verb beside the row, or null. It is a button in its own right, outside
  /// the row's one sentence, so a screen reader reaches both.
  final ServiceOverviewRowAction? action;

  final Widget leading;
  final String title;
  final String detail;

  /// Ink for the title where a row states its own tone; otherwise
  /// `onSurface`. It is passed already resolved, because the tone a row is
  /// carrying is the page's fact, not this widget's.
  final Color? titleColor;

  /// The right-hand figure, e.g. `298 queries`. Already folded into [spoken],
  /// which is why the row can silence its own subtree.
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final door = onTap;
    final verb = action;

    final lines = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        leading,
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: AppTheme.data(
                  brightness,
                ).copyWith(color: titleColor ?? colorScheme.onSurface),
              ),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: AppTheme.chrome(
                    context,
                    size: 11,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: _trailingMaxWidth),
            child: Text(
              trailing!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: AppTheme.chrome(
                context,
                size: 11,
                weight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );

    // Nothing in a row that is only read is interactive, so the parts are safe
    // to silence: read separately they are three fragments of one fact.
    if (door == null) {
      final plain = Semantics(
        container: true,
        label: spoken,
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: lines,
        ),
      );
      return verb == null ? plain : _withAction(plain, verb);
    }

    // A door is one button: the sentence, where it leads, and the tap. The
    // gap under the row sits inside the target, so the rows keep the rhythm
    // of the plain ones and the target still reaches 44.
    final opens = Semantics(
      container: true,
      button: true,
      label: spoken,
      hint: doorHint,
      onTap: door,
      child: InkWell(
        onTap: door,
        borderRadius: AppRadius.borderRadiusSm,
        // The name and the tap are the node above's.
        excludeFromSemantics: true,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _doorMinHeight),
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: lines),
                  if (verb == null) ...[
                    const SizedBox(width: AppSpacing.sm),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return verb == null ? opens : _withAction(opens, verb);
  }

  /// [body] with [verb] beside it, or under it for a remedy, outside the
  /// body's own semantics: the verb is a control, and a node that silences
  /// its subtree would take it out of the tree.
  static Widget _withAction(Widget body, ServiceOverviewRowAction verb) =>
      verb.remedy ? _withRemedy(body, verb) : _beside(body, verb);

  /// Where a row's words start: the attention rows' 18pt glyph and its gap.
  static const double _wordsInset = 18 + AppSpacing.sm;

  /// [body], then [verb] in the amber fill under its words.
  static Widget _withRemedy(Widget body, ServiceOverviewRowAction verb) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          body,
          Padding(
            padding: const EdgeInsets.only(
              left: _wordsInset,
              bottom: AppSpacing.md,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: Builder(
                builder: (context) => FilledButton(
                  onPressed: verb.onPressed,
                  style: remedyFillStyle(context, compact: true),
                  // Annotated inside the button, as the text verb is.
                  child: Semantics(
                    hint: verb.hint,
                    child: Text(
                      verb.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );

  static Widget _beside(Widget body, ServiceOverviewRowAction verb) =>
      LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: body),
            // Capped, as the trailing figure is: at an accessibility reading
            // size a long verb beside an `Expanded` body is a right-edge
            // overflow, and a row that throws is worse than a verb that
            // ellipsises. The whole label is in the button's name.
            ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: constraints.maxWidth * _actionMaxFraction,
              ),
              child: _RowActionButton(action: verb),
            ),
          ],
        ),
      );
}

/// The verb beside a row: a text button in the ink, never in the fault's tone
/// (the cure is not painted as alarming as the disease), at the 44pt floor.
class _RowActionButton extends StatelessWidget {
  const _RowActionButton({required this.action});

  final ServiceOverviewRowAction action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextButton(
      onPressed: action.onPressed,
      style: TextButton.styleFrom(
        foregroundColor: theme.colorScheme.primary,
        minimumSize: const Size(56, _doorMinHeight),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        // Pinned: the desktop picks compact by itself, and compact cancels
        // `minimumSize` (44 declared, 40 measured).
        visualDensity: VisualDensity.standard,
      ),
      // The hint is annotated from INSIDE the button: a `Semantics` wrapped
      // around a button is dropped, one on its child merges into the button's
      // own node, which is where "tests Nyaa" has to be heard.
      child: Semantics(
        hint: action.hint,
        child: Text(
          action.label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelLarge?.weight(FontWeight.w600),
        ),
      ),
    );
  }
}

/// The 36×54 art beside an Overview row about a title: its poster, glowing
/// with its own light once drawn, or a plate with the title's initials when
/// there is none to show.
///
/// A public picture only (TMDB's, TheTVDB's): the arrs' own copies sit behind
/// their key, and a row's poster is read for its light.
class ServiceOverviewArt extends StatelessWidget {
  const ServiceOverviewArt({
    super.key,
    required this.posterUrl,
    required this.title,
    this.httpHeaders,
  });

  final String? posterUrl;

  /// What the picture's own server wants with the request (a Tracearr poster
  /// sits behind its key, which travels here and never in the address, since
  /// the address is the cache's name for it). Null for a public picture.
  final Map<String, String>? httpHeaders;

  /// The title the row is about, for the plate's initials.
  final String title;

  static const double width = 36;
  static const double height = 54;

  @override
  Widget build(BuildContext context) {
    final url = posterUrl;
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        height: height,
        child: url == null || url.isEmpty
            ? _InitialsPlate(initials: overviewInitialsOf(title))
            : ContentCard.lit(imageUrl: url, httpHeaders: httpHeaders),
      ),
    );
  }
}

/// The first letters of the first two words of [title], `NS` for *Night
/// Shift*; the first two letters of a one-word title; empty for none.
String overviewInitialsOf(String title) {
  final words = [
    for (final word in title.trim().split(RegExp(r'\s+')))
      if (word.replaceAll(_notAWordLetter, '') case final letters
          when letters.isNotEmpty)
        letters,
  ];
  if (words.isEmpty) return '';
  final letters = words.length == 1
      ? words.first.characters.take(2).toString()
      : '${words[0].characters.first}${words[1].characters.first}';
  return letters.toUpperCase();
}

final _notAWordLetter = RegExp(r'[^\p{L}\p{N}]', unicode: true);

class _InitialsPlate extends StatelessWidget {
  const _InitialsPlate({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: room.fillStrong,
        borderRadius: AppRadius.borderRadiusSm,
        border: Border.all(color: room.edge),
      ),
      child: Center(
        // Scaled down into the plate, never out of it: the plate is 36 wide
        // at any reading size, and two letters at 200% are wider than that.
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              initials,
              maxLines: 1,
              style: AppType.label
                  .weight(FontWeight.w600)
                  .copyWith(color: room.inkSecondary),
            ),
          ),
        ),
      ),
    );
  }
}

/// The day a row of what is coming falls on, as a column: `Today` or the
/// weekday in the row's figure, the date under it, `21 Oct`.
class ServiceOverviewDay extends StatelessWidget {
  const ServiceOverviewDay({super.key, required this.day, required this.now});

  final DateTime day;
  final DateTime now;

  /// The column's width: `Tomorrow` scales down into it rather than lose a
  /// letter.
  static const double width = 58;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final words = formatDayLabel(day, now);
    // `Today`, `Tomorrow`, else the weekday alone: the date is under it.
    final lead = calendarDaysBetween(now, day) <= 1
        ? words
        : shortWeekdayName(day);
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              lead,
              maxLines: 1,
              style: AppType.figureSmall.copyWith(color: room.ink),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            formatDayMonthNoYear(day),
            maxLines: 1,
            style: AppType.caption.copyWith(color: room.inkSecondary),
          ),
        ],
      ),
    );
  }
}

/// The "nothing here" note for a region at rest.
///
/// [AppEmptyState.inline] and not the 72dp well: nothing failed and nothing is
/// missing, so the absence costs a row rather than a screenful of ceremony.
class ServiceOverviewEmpty extends StatelessWidget {
  const ServiceOverviewEmpty({
    super.key,
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return AppEmptyState.inline(icon: icon, title: label);
  }
}

/// The loading shape of a rows region: [rows] two-line ghosts.
class ServiceOverviewRowsSkeleton extends StatelessWidget {
  const ServiceOverviewRowsSkeleton({super.key, required this.rows});

  final int rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < rows; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ShimmerPlaceholder.text(width: 180, height: 14),
                const SizedBox(height: AppSpacing.xs),
                ShimmerPlaceholder.text(width: 120, height: 10),
              ],
            ),
          ),
      ],
    );
  }
}

/// The connection an Overview is about: the one [instanceId] names, else the
/// lens's.
///
/// An id that names no connection reads the lens, as every page that takes a
/// connection does.
ServiceInstance? _overviewConnection(
  WidgetRef ref,
  ServiceKey service,
  String? instanceId,
) {
  final lens = ref.watch(activeInstanceProvider(service));
  if (instanceId == null || instanceId.isEmpty) return lens;
  return ref.watch(
        currentSettingsProvider.select(
          (settings) => settings.instanceById(instanceId),
        ),
      ) ??
      lens;
}

/// The probe of the connection an Overview is about: [serviceSummaryProvider]
/// for the lens, which everything that reads the lens's health shares, and the
/// connection's own probe for another one.
ProviderListenable<AsyncValue<ServiceSummary>> _overviewSummary(
  WidgetRef ref,
  ServiceKey service,
  String? instanceId,
) {
  final lensId = ref.watch(activeInstanceProvider(service))?.id;
  if (instanceId == null || instanceId.isEmpty || instanceId == lensId) {
    return serviceSummaryProvider(service);
  }
  return instanceSummaryProvider((service: service, instanceId: instanceId));
}

/// Host, version, whether it is answering, and which connection you are
/// reading.
///
/// [instanceId] is the connection the page reads when that is not the lens's:
/// a visit to a media server opened on another connection. Null or empty is
/// the lens.
class ServiceOverviewIdentity extends ConsumerWidget {
  const ServiceOverviewIdentity({
    super.key,
    required this.service,
    this.instanceId,
  });

  final ServiceKey service;
  final String? instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final room = CupolaRoom.of(context);

    final summary = ref.watch(_overviewSummary(ref, service, instanceId));
    final instance = _overviewConnection(ref, service, instanceId);
    final hasLens = ref.watch(hasMultipleInstancesProvider(service));

    // The probe reduced to the connection vocabulary, **with its reason**. A
    // summary still in flight is `checking` rather than a guess. A failed one
    // says why: without the reason every failure read red "did not answer",
    // so a Radarr that refused the key sat under the same word as one that
    // was switched off.
    final status = summary.when(
      loading: () => ServiceConnectionStatus.checking,
      error: (_, _) => ServiceConnectionStatus.disconnected,
      data: (value) => value.isOnline
          ? ServiceConnectionStatus.connected
          // Saved without its key: not asked, and said as not set up.
          : value.isNotSetUp
          ? ServiceConnectionStatus.notConfigured
          : ServiceConnectionStatus.disconnected,
    );
    final reason = summary.when(
      loading: () => null,
      error: (error, _) => classifyConnectionFailure(error),
      data: (value) => value.failureReason,
    );
    final presentation = describeConnection(
      service,
      status: status,
      reason: reason,
      gateway: summary.when(
        loading: () => null,
        error: (error, _) => accessGatewayOf(error),
        data: (value) => value.failure?.gateway,
      ),
    );
    final toneColor = statusToneColor(colorScheme, presentation.tone);

    final host = service.extractHost(instance?.url);
    // A figure whose source did not answer reads "—", never a fallback dressed
    // up as an answer: `ServiceSummary.versionLabel` degrades to "v3 API" when
    // the service named no version, which is honest for a server that replied
    // and a fabrication for one that never did.
    final summaryData = summary.asData?.value;
    final version = summaryData != null && summaryData.isOnline
        ? summaryData.versionLabel
        : null;
    // The app's one rule for naming a connection: with two, a connection the
    // user never named still reads `Radarr 2` rather than nothing at all.
    final lens = hasLens && instance != null
        ? ref.watch(connectionNameProvider(instance.id))
        : null;

    final facts = <String>[
      host == null || host.isEmpty ? '—' : host,
      version == null || version.isEmpty ? '—' : version,
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Semantics(
        container: true,
        // One sentence rather than four stops: the host alone, read out on its
        // own, does not say what it is the host of.
        label: joinSpokenParts([
          service.title,
          ...facts,
          presentation.label,
          if (lens != null && lens.isNotEmpty) lens,
        ]),
        excludeSemantics: true,
        // The room's status line: its state as a dot and a word, then
        // where it is and what it runs. Tone and word both, because colour is
        // not information: the word is the channel that always works.
        child: Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.xs,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: toneColor,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    [presentation.label, ...facts].join(dotSeparator),
                    style: AppType.meta.copyWith(color: room.inkSecondary),
                  ),
                ),
              ],
            ),
            if (lens != null && lens.isNotEmpty)
              _LensChip(service: service, label: lens),
          ],
        ),
      ),
    );
  }
}

class _LensChip extends StatelessWidget {
  const _LensChip({required this.service, required this.label});

  final ServiceKey service;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusSm,
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Text(
        label,
        style: AppTheme.chrome(
          context,
          size: 11,
          weight: FontWeight.w600,
          color: serviceOverviewInk(service, colorScheme),
        ),
      ),
    );
  }
}

/// An Overview's [sections], or the one line that stands for all of them,
/// when every section is bound to fail for one reason the page can name
/// before asking:
///
///  * away from home, for a lens connection with no address away: every
///    request is refused before it is sent ([ServiceOnlyAtHome]), and each
///    section said so in the same sentence with the same remedy, three times
///    in Seerr's first screen under a figure peek of dashes. Said once
///    instead, under the identity line that already reads `Only at home`,
///    with `Add an address away` as its one action;
///  * for a lens connection neither of whose addresses answered the route
///    probe ([ServiceFailureReason.unreachableAtBoth]): the red names both
///    addresses once, and its Retry knocks at both;
///  * for a lens connection that did not answer at the one address it has
///    ([ServiceFailureReason.unreachable]): the red names it once. Not for a
///    page that already says it once on its own ([ownSilence]: Stream's
///    offline state, drawn when its own reads failed).
///
/// "Lens" above is the connection the page reads: [instanceId] when the page
/// reads another (a visit to a media server opened on one), else the lens.
///
/// A spread rather than a wrapper, so the sections stay direct children of
/// [ServiceOverviewScroll]; called from the page's build with its [ref].
List<Widget> sectionsOrOneLine(
  WidgetRef ref,
  ServiceKey service,
  List<Widget> sections, {
  bool ownSilence = false,
  String? instanceId,
}) {
  final reason = ref.watch(
    _overviewSummary(
      ref,
      service,
      instanceId,
    ).select((summary) => summary.asData?.value.failureReason),
  );
  return switch (reason) {
    ServiceFailureReason.onlyAtHome => [
      ServiceOverviewOnlyAtHome(service: service, instanceId: instanceId),
    ],
    ServiceFailureReason.unreachableAtBoth => [
      ServiceOverviewUnanswered(service: service, instanceId: instanceId),
    ],
    ServiceFailureReason.unreachable when !ownSilence => [
      ServiceOverviewUnanswered.atItsAddress(
        service: service,
        instanceId: instanceId,
      ),
    ],
    _ => sections,
  };
}

/// The Overview tab of a service, minus what is the service's own: the shell
/// the fourteen screens that are not Stream's used to write out each.
///
/// Two widgets, and they stay two: [ServiceOverviewPage] settles whether the
/// service is configured and draws [NotConfiguredPlaceholder.forService]
/// otherwise; the body below it is the only thing that reaches a provider.
/// **Checked before anything reaches a provider.** A service's client provider
/// throws "not configured", and letting an `AsyncValueWidget` catch that throw
/// would paint the same pixels while leaving failed providers behind it, each
/// scheduling a retry with backoff for a condition no amount of waiting
/// changes: a pending timer in tests and a wake-up every few seconds on device
/// for a server nobody has entered yet. `.forService`, never the generic form:
/// this is a service dashboard, so the door goes to the service's own
/// connection form rather than to the settings index.
///
/// What the body does is the same for every service: the room's scroll view
/// ([ServiceOverviewScroll], with [topPadding] reserved for the two glass bands
/// above), the identity line, the readouts ([ServiceKpiPeek.room]) and the
/// [sections], held together by [sectionsOrOneLine]; and a pull that re-reads
/// the service's readout (`invalidateServiceReadout`: the probe as well as the
/// wrapper over it, and the figures' sources) before [refresh] re-reads what
/// the sections are folded from.
///
/// The page sits in an [AmbientScaffold] under a [SafeArea] that takes the
/// status bar's inset, so [topPadding] (the band and the tab bar, without that
/// inset) starts below it: `service_tab_inset_test.dart` measures it once, for
/// every Overview.
class ServiceOverviewPage extends ConsumerWidget {
  const ServiceOverviewPage({
    super.key,
    required this.service,
    required this.topPadding,
    required this.sections,
    required this.refresh,
    this.kpis,
    this.configured,
    this.beforeRefresh,
  });

  /// The room the two glass bands above an Overview occupy: composed from the
  /// same two constants the router composes its own from, so a screen built
  /// outside the router (a test, a preview) reserves the right space instead
  /// of tucking its first region under the tab bar.
  static const double hostedTopPadding = kToolbarHeight + ServiceTabBar.height;

  final ServiceKey service;

  /// Height of the chrome the host draws above the page.
  final double topPadding;

  /// The sections under the readouts, built inside the body: the page's own
  /// `ref` is the one they watch with, and none of it runs for a service that
  /// is not configured.
  final List<Widget> Function(WidgetRef ref) sections;

  /// What a pull re-reads besides the readout: the sources the sections are
  /// folded from, then the folds. Invalidating only the folds would recompute
  /// them over the cached payloads and leave the page showing the same
  /// figures after a deliberate pull.
  final void Function(WidgetRef ref) refresh;

  /// The readouts, where they are not the service's own
  /// (`serviceKpiProvider`): folded from a source the page already watches, so
  /// the figures and the rows under them are one poll.
  final AsyncValue<List<ServiceKpi>> Function(WidgetRef ref)? kpis;

  /// Whether the page has a connection to read, where that is not the
  /// settings' answer for [service]: Seerr's is the lens's account.
  final bool Function(WidgetRef ref)? configured;

  /// What a pull does before anything is invalidated (qBittorrent forgets a
  /// refused login, so the re-read asks again).
  final void Function(WidgetRef ref)? beforeRefresh;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final own = configured;
    final bool ready = own != null
        ? own(ref)
        : ref.watch(
            currentSettingsProvider.select(
              (settings) => settings.isServiceConfigured(service),
            ),
          );

    return AmbientScaffold(
      accent: service.accent,
      body: SafeArea(
        bottom: false,
        child: ready
            ? _ServiceOverviewBody(page: this)
            : NotConfiguredPlaceholder.forService(service),
      ),
    );
  }
}

class _ServiceOverviewBody extends ConsumerWidget {
  const _ServiceOverviewBody({required this.page});

  final ServiceOverviewPage page;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final service = page.service;
    return RefreshIndicator(
      onRefresh: () async {
        page.beforeRefresh?.call(ref);
        invalidateServiceReadout(ref, service);
        page.refresh(ref);
        await Future<void>.delayed(AppAnimation.durationMd);
      },
      // One scroll view for the whole page: the regions are one column of
      // reading, not independently scrolling panes.
      child: ServiceOverviewScroll(
        topPadding: page.topPadding,
        children: [
          ServiceOverviewIdentity(service: service),
          ...sectionsOrOneLine(ref, service, [
            ServiceKpiPeek.room(
              kpis:
                  page.kpis?.call(ref) ??
                  ref.watch(serviceKpiProvider(service)),
              service: service,
            ),
            ...page.sections(ref),
          ]),
        ],
      ),
    );
  }
}

/// The one scroll view of an Overview: the band's room at its top, the
/// sections in one column, and the bar's clearance at its foot.
///
/// **Every section stays built, never a lazy list.** A section's figures come
/// from `autoDispose` providers derived from the page's sources. In a
/// `ListView` a section scrolled past its cache extent was unmounted, its
/// provider collected, and scrolling back rebuilt it from a skeleton a third of
/// its height before the figures arrived a frame later: the list corrected its
/// offset above the viewport twice, and the page jumped under the thumb
/// (qBittorrent's Queue, 21/10). An Overview is half a dozen sections, so
/// building them all costs nothing a lazy list would save.
class ServiceOverviewScroll extends StatelessWidget {
  const ServiceOverviewScroll({
    super.key,
    required this.topPadding,
    required this.children,
  });

  /// Height of the chrome the host draws above the page.
  final double topPadding;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.only(
        top: topPadding,
        bottom: FloatingNavBarMetrics.getScrollViewBottomPadding(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

/// The one line of an Overview whose lens connection did not answer. Red,
/// and its Retry (a ghost in ink) asks again (`retryDashboardServices`). See
/// [sectionsOrOneLine].
class ServiceOverviewUnanswered extends ConsumerWidget {
  /// Neither address answered: `Radarr did not answer at home or away`, then
  /// where, one address a line; its Retry asks both.
  const ServiceOverviewUnanswered({
    super.key,
    required this.service,
    this.instanceId,
  }) : _atBoth = true;

  /// The one address the connection has did not answer:
  /// `Radarr did not answer at nas.home.arpa:7878.`
  const ServiceOverviewUnanswered.atItsAddress({
    super.key,
    required this.service,
    this.instanceId,
  }) : _atBoth = false;

  final ServiceKey service;

  /// The connection that did not answer when it is not the lens's; null or
  /// empty is the lens.
  final String? instanceId;
  final bool _atBoth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = _overviewConnection(ref, service, instanceId);
    final name =
        (ref.watch(hasMultipleInstancesProvider(service)) && instance != null
            ? ref.watch(connectionNameProvider(instance.id))
            : null) ??
        service.title;
    final unanswered = instance == null || !_atBoth
        ? null
        : ref.watch(unansweredConnectionProvider(instance.id));
    final reason = _atBoth
        ? ServiceFailureReason.unreachableAtBoth
        : ServiceFailureReason.unreachable;
    // Nothing answered, so nothing in front of it did either: no gateway.
    final headline = _atBoth
        ? failureHeadline(ServiceFailureReason.unreachableAtBoth, subject: name)
        : failureHeadline(ServiceFailureReason.unreachable, subject: name);
    // The address it asked: on a connection with an address away, the one
    // its route is on.
    final host = _atBoth || instance == null
        ? null
        : service.extractHost(
            ref.watch(connectionReachProvider(instance.id))?.url,
          );
    final message = switch ((unanswered, host)) {
      (final unanswered?, _) => '$headline.\n${unanswered.failureDetail}',
      (_, final host?) when !_atBoth && host.isNotEmpty =>
        '$headline at $host.',
      _ => '$headline.',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: InlineErrorRetry.flush(
        message: message,
        error: unanswered ?? ClassifiedFailure(reason),
        service: service,
        instanceId: instance?.id,
        onRetry: () => retryDashboardServices(ref, [service]),
      ),
    );
  }
}

/// The one line of an Overview whose connection is reached only at home,
/// read away from home: see [sectionsOrOneLine].
class ServiceOverviewOnlyAtHome extends ConsumerWidget {
  const ServiceOverviewOnlyAtHome({
    super.key,
    required this.service,
    this.instanceId,
  });

  final ServiceKey service;

  /// The connection with no address away when it is not the lens's; null or
  /// empty is the lens.
  final String? instanceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = _overviewConnection(ref, service, instanceId);
    // The connection by its name when there are two: the other Radarr may
    // well have an address away.
    final name =
        (ref.watch(hasMultipleInstancesProvider(service)) && instance != null
            ? ref.watch(connectionNameProvider(instance.id))
            : null) ??
        service.title;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      // On the page column, its glyph under the identity line's first fact.
      child: InlineErrorRetry.flush(
        message:
            '$name has no address away, so Cupola reaches it only on your '
            'home Wi-Fi.',
        error: ServiceOnlyAtHome(service),
        service: service,
        instanceId: instance?.id,
        // Never offered: the same request is refused again until the app is
        // home, or the connection has an address away.
        onRetry: () {},
      ),
    );
  }
}

/// One row of Needs attention: the fault's glyph and words in its tone, the
/// evidence under them, and where it leads.
///
/// **The tone is the fault's own**, through the tone rule and never a raw
/// colour: amber is a fault, and a backlog row (movies below the cutoff,
/// missing episodes) is neutral by construction. It is walked against the
/// surface the row actually lands on, which on the light theme is a different
/// hue from the one the dark artboards draw.
class ServiceAttentionRow extends StatelessWidget {
  const ServiceAttentionRow({
    super.key,
    required this.service,
    required this.item,
  });

  final ServiceKey service;
  final ArrAttentionItem<ArrAttentionKind> item;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(
      colorScheme,
      item.tone,
      surface: colorScheme.surfaceContainerLow,
    );
    final door = item.door;

    return ServiceOverviewRow(
      spoken: item.spoken,
      leading: Icon(item.icon, size: 18, color: tone),
      title: item.headline,
      titleColor: tone,
      detail: item.detail,
      onTap: door == null
          ? null
          : () => openAttentionDoor(context, service, door),
      doorHint: door == null ? null : attentionDoorHint(service, door),
    );
  }
}

/// One row of History: an 8px dot in the event's tone, the subject and what
/// happened to it, and the quality, size and age under them.
class ServiceHistoryRow extends StatelessWidget {
  const ServiceHistoryRow({super.key, required this.entry});

  final OverviewHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tone = statusToneColor(
      colorScheme,
      entry.tone,
      surface: colorScheme.surfaceContainerLow,
    );

    return ServiceOverviewRow(
      spoken: entry.spoken,
      leading: Container(
        width: 8,
        height: 8,
        margin: const EdgeInsets.only(top: 5),
        decoration: BoxDecoration(color: tone, shape: BoxShape.circle),
      ),
      title: '${entry.subject}\u00A0· ${entry.event.toLowerCase()}',
      detail: entry.detail,
    );
  }
}

/// The Needs attention section of an \*arr's Overview: faults first, the
/// backlog last, each row its own door.
///
/// **No link in the header**: every row here belongs to a different tab (a
/// stalled download to Queue, a backlog to Wanted), and a single destination
/// would have to lie about some of them.
///
/// **The count is read through `hasValue`, never `asData`.** `asData` is null
/// on an `AsyncError` even when Riverpod retained the value it had, while
/// [AsyncValueWidget] under this header draws exactly that retained list at
/// full ink beneath the unreachable band: read through `asData`, the header
/// printed `—` over rows it was still showing. A source that never answered has
/// no retained value and still reads `—`, never a `0`: a count printed over an
/// unanswered question is a claim nobody made, and it is the reassuring
/// direction of wrong.
///
/// The count is the faults the rows stand for, not the rows (a folded row of
/// three downloads is three), and a floor (`3+`) when [queueRecords] says the
/// queue walk stopped on a full page.
///
/// [retry] is every source the section is folded from: the fold, the raw queue
/// walk and whatever the backlog row is read off.
class ArrNeedsAttentionSection<K extends ArrAttentionKind>
    extends ConsumerWidget {
  const ArrNeedsAttentionSection({
    super.key,
    required this.service,
    required this.items,
    required this.queueRecords,
    required this.retry,
  });

  final ServiceKey service;

  final ProviderListenable<AsyncValue<List<ArrAttentionItem<K>>>> items;

  /// The raw queue walk the faults were read from, for its `cutShort`.
  final ProviderListenable<AsyncValue<ArrRecordPage>> queueRecords;

  final List<ProviderOrFamily> retry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(items);
    final count = value.hasValue
        ? value.requireValue.fold(0, (sum, item) => sum + item.count)
        : null;
    final floor = ref.watch(queueRecords).value?.cutShort ?? false;

    return ServiceOverviewSection(
      service: service,
      title: 'Needs attention',
      subtitle: count == null ? '—' : (floor ? Lexicon.floor(count) : '$count'),
      child: AsyncValueWidget<List<ArrAttentionItem<K>>>.section(
        value: value,
        service: service,
        consequence: 'what needs attention is not shown',
        loadingLabel: 'Loading what needs attention',
        onRetry: () {
          for (final source in retry) {
            ref.invalidate(source);
          }
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (data) => data.isEmpty,
        // A resting state wears no alarm chrome: nothing is wrong, and saying
        // so is not an error state.
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.check_circle_outline_rounded,
          label: 'Nothing needs you',
        ),
        data: (data) => Column(
          children: [
            for (final item in data)
              ServiceAttentionRow(service: service, item: item),
          ],
        ),
      ),
    );
  }
}

/// The History section of an \*arr's Overview: what happened today, with a
/// link to the History tab. Headed `History` with the word `today` beside it,
/// and "today" is the local calendar day: a heading is a promise.
class ArrHistoryTodaySection<E extends OverviewHistoryEntry>
    extends ConsumerWidget {
  const ArrHistoryTodaySection({
    super.key,
    required this.service,
    required this.entries,
    required this.retry,
  });

  final ServiceKey service;
  final ProviderListenable<AsyncValue<List<E>>> entries;
  final List<ProviderOrFamily> retry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ServiceOverviewSection(
      service: service,
      title: 'History',
      subtitle: 'today',
      destination: ServiceTab.history,
      child: AsyncValueWidget<List<E>>.section(
        value: ref.watch(entries),
        service: service,
        consequence: "today's history is not shown",
        loadingLabel: "Loading today's history",
        onRetry: () {
          for (final source in retry) {
            ref.invalidate(source);
          }
        },
        skeleton: const ServiceOverviewRowsSkeleton(rows: 2),
        isEmpty: (items) => items.isEmpty,
        emptyBuilder: const ServiceOverviewEmpty(
          icon: Icons.history_rounded,
          label: 'Nothing yet today',
        ),
        data: (items) => Column(
          children: [
            for (final entry in items) ServiceHistoryRow(entry: entry),
          ],
        ),
      ),
    );
  }
}

/// The poster rail of an \*arr's Overview (Radarr's Recently added, Sonarr's
/// Recently downloaded, Lidarr's Recently added): tiles 96 wide, each one
/// button that speaks the title with its caption as the value.
///
/// What the services differ in is data and one closure: [titleOf], [imagesOf]
/// and [captionOf] (a year, an episode and its age, a count of albums; null or
/// empty draws none, and says none), and [onTap], which opens the title's own
/// page under this tab. **Never a flag.** The hero tag is its own namespace
/// (`radarr_overview_recent_<id>`): the Library tab's grid is alive in a
/// sibling branch and tags a poster of the same title, and two live Heroes
/// sharing a tag is an assertion, not a flight.
///
/// The posters are read at the address the lens's connection is reached at
/// now, and the box grows with the reading size by the *clamped* scale so the
/// captions are not clipped at an accessibility text size; the text is laid out
/// at the same clamp, or the rail is sized for 1.6x and painted at 3.0x, which
/// is an overflow stripe.
class ServicePosterRail<T> extends ConsumerWidget {
  const ServicePosterRail({
    super.key,
    required this.service,
    required this.items,
    required this.idOf,
    required this.titleOf,
    required this.imagesOf,
    required this.captionOf,
    required this.onTap,
  });

  final ServiceKey service;
  final List<T> items;
  final int Function(T item) idOf;
  final String Function(T item) titleOf;
  final List<dynamic> Function(T item) imagesOf;
  final String? Function(T item) captionOf;

  /// Opens the title, handed the hero tag its poster carries.
  final void Function(BuildContext context, T item, String heroTag) onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final instance = ref.watch(activeInstanceProvider(service));
    final reachedAt = instance == null
        ? ''
        : ref.watch(connectionReachProvider(instance.id))?.url ?? '';

    return SizedBox(
      // 138pt poster, the gap, and two label lines.
      height: TextScaleMetrics.boxHeight(context, base: 176, textHeight: 34),
      child: MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaleMetrics.clampedScalerOf(context)),
        child: ListView.separated(
          controller: RailArrows.controllerOf(context),
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          itemCount: items.length,
          separatorBuilder: (_, _) =>
              const SizedBox(width: AppSpacing.carouselGap),
          itemBuilder: (context, index) {
            final item = items[index];
            final heroTag = '${service.name}_overview_recent_${idOf(item)}';
            final caption = captionOf(item);
            return _PosterTile(
              title: titleOf(item),
              caption: caption == null || caption.isEmpty ? null : caption,
              heroTag: heroTag,
              poster: ImageUtils.extractPosterUrl(
                imagesOf(item),
                baseUrl: reachedAt,
                apiKey: instance?.credential ?? '',
              ),
              onTap: () => onTap(context, item, heroTag),
            );
          },
        ),
      ),
    );
  }
}

class _PosterTile extends StatelessWidget {
  const _PosterTile({
    required this.title,
    required this.caption,
    required this.heroTag,
    required this.poster,
    required this.onTap,
  });

  final String title;
  final String? caption;
  final String heroTag;
  final ImageSource poster;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final caption = this.caption;

    return SizedBox(
      width: 96,
      child: PressableScale(
        onTap: onTap,
        // A poster is an image with no name of its own; the tile announces the
        // title and its caption as one button.
        semanticLabel: title,
        semanticValue: caption == null ? null : spokenFromDotted(caption),
        excludeChildSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 96,
              height: 138,
              child: MediaPosterCard(
                heroTag: heroTag,
                imageUrl: poster.url,
                imageHeaders: poster.headers,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall
                  ?.weight(FontWeight.w600)
                  .copyWith(color: colorScheme.onSurface),
            ),
            if (caption != null)
              Text(
                caption,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
