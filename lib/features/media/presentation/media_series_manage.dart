import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:cupola/core/app_spacing.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/core/utils/byte_format.dart';
import 'package:cupola/core/utils/dot_separator.dart';
import 'package:cupola/core/utils/snack_bar_helper.dart';
import 'package:cupola/core/utils/string_utils.dart';
import 'package:cupola/core/utils/episode_code.dart';
import 'package:cupola/core/widgets/widgets.dart';
import 'package:cupola/features/bazarr/domain/models/bazarr_models.dart';
import 'package:cupola/features/bazarr/presentation/widgets/bazarr_detail_sections.dart';
import 'package:cupola/features/import/presentation/manual_import_routes.dart';
import 'package:cupola/features/media/domain/media_removal.dart';
import 'package:cupola/features/media/domain/media_series_manage.dart';
import 'package:cupola/features/media/domain/media_subtitles.dart';
import 'package:cupola/features/media/presentation/media_episode_providers.dart';
import 'package:cupola/features/media/presentation/media_manage_parts.dart';
import 'package:cupola/features/media/domain/media_key.dart';
import 'package:cupola/features/media/presentation/media_parts.dart';
import 'package:cupola/features/media/presentation/media_watched_by.dart';
import 'package:cupola/features/release_search/domain/release_search_target.dart';
import 'package:cupola/features/release_search/presentation/release_search_entry.dart';
import 'package:cupola/features/series/data/sonarr_service.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode.dart';
import 'package:cupola/features/series/domain/models/sonarr_episode_file.dart';
import 'package:cupola/features/series/domain/models/sonarr_series.dart';
import 'package:cupola/features/series/domain/sonarr_series_type.dart';
import 'package:cupola/features/settings/domain/service_instance.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// A series one Sonarr holds, as its Manage acts on it.
typedef MediaSeriesHeld = ({
  ServiceInstance connection,
  String name,
  SonarrSeries series,
  List<SonarrEpisode> episodes,
});

/// An automatic search Sonarr is asked for: one copy's whole series, or one
/// of its seasons.
typedef _AutomaticSearch = ({MediaSeriesHeld copy, MediaSeasonFiles? season});

/// A series' Manage, for the operator: each Sonarr copy's files and
/// seasons with what Sonarr does about them, what it has done, a search
/// Sonarr runs on its own for the series or a season, a season's releases to
/// choose from, and its removal.
///
/// The files are read when Manage is drawn (the closed rows name their
/// qualities and the last import); the history when it opens.
class MediaSeriesManage extends ConsumerWidget {
  const MediaSeriesManage({
    super.key,
    required this.copies,
    required this.title,
    required this.onChanged,
    this.mediaKey,
    this.subtitles,
    this.now,
    this.more = const [],
  }) : assert(copies.length > 0, 'nothing to manage');

  /// The title's page, whose Watched by the removal sheet says a line of
  /// (`Watched by 3 · last 12 days ago`); null says nothing of it.
  final MediaKey? mediaKey;

  /// The page's rows after Sonarr's own: what goes through Seerr.
  final List<Widget> more;

  final List<MediaSeriesHeld> copies;

  /// The series' title, for the searches and the removal.
  final String title;

  /// Sonarr changed: the page reads it again.
  final VoidCallback onChanged;

  /// The episodes Bazarr follows, with their languages, and the Sonarr whose
  /// copy they are; null without a Bazarr that follows one.
  final ({String arr, List<BazarrEpisode> episodes})? subtitles;

  /// The clock the dates are read against; the wall clock by default.
  final DateTime? now;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final files = <Map<int, SonarrEpisodeFile>?>[
      for (final copy in copies)
        copy.series.hasFiles
            ? ref
                  .watch(
                    mediaEpisodeFilesProvider((
                      connectionId: copy.connection.id,
                      seriesId: copy.series.id,
                    )),
                  )
                  .value
            : const <int, SonarrEpisodeFile>{},
    ];
    final single = copies.length == 1;
    final names = _names([for (final copy in copies) copy.name]);
    return MediaGroup(
      children: [
        MediaManageRow(
          title: 'Files & quality',
          summary: single
              ? mediaSeriesFilesSummary(copies.single.series, files[0]?.values)
              : names,
          body: (context) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (index, copy) in copies.indexed)
                _CopyFiles(
                  copy: copy,
                  files: files[index],
                  now: now,
                  onChanged: onChanged,
                ),
            ],
          ),
        ),
        MediaManageRow(
          title: 'History',
          summary: single
              ? mediaSeriesLastImport(
                  copies.single.episodes,
                  files[0],
                  now: now,
                )
              : '',
          body: (context) => _History(copies: copies),
        ),
        if (subtitles case (
          :final arr,
          :final episodes,
        ) when episodes.isNotEmpty)
          MediaManageRow(
            title: 'Subtitles',
            summary: mediaSeriesSubtitlesSummary(episodes),
            body: (context) => _Subtitles(
              episodes: episodes,
              sonarr: copies
                  .where((copy) => copy.connection.id == arr)
                  .firstOrNull
                  ?.episodes,
            ),
          ),
        if (_automaticSearches(single) case final searches
            when searches.isNotEmpty)
          MediaManageRow(
            title: 'Automatic search',
            summary: single
                ? '${copies.single.name} looks now for what it monitors'
                : names,
            body: (context) => MediaCopyChoices<_AutomaticSearch>(
              verb: 'Search',
              copies: searches,
              onChoose: (search) => _search(context, ref, search),
            ),
          ),
        MediaManageRow(
          title: 'Search releases',
          summary: names,
          body: (context) => MediaCopyChoices<ReleaseSearchTarget>(
            verb: 'Search releases for',
            copies: [
              for (final copy in copies)
                for (final season in mediaSeasonFilesOf(
                  copy.series,
                  copy.episodes,
                  now: now,
                ))
                  if (season.aired)
                    (
                      name: single
                          ? season.label
                          : '${season.label} on ${copy.name}',
                      target: ReleaseSearchTarget.season(
                        seriesId: copy.series.id,
                        seasonNumber: season.number,
                        label: '${truncateTitle(title)}\u00A0· ${season.label}',
                      ).stampedWith(copy.connection.id),
                    ),
            ],
            onChoose: (target) => showReleaseSearch(context, ref, target),
          ),
        ),
        if (single)
          MediaManageRow(
            title: 'Remove from ${copies.single.name}',
            summary: copies.single.series.monitored
                ? 'Stops ${copies.single.name} looking for it'
                : 'Stops ${copies.single.name} tracking it',
            onTap: () => _remove(context, ref, copies.single),
          )
        else
          MediaManageRow(
            title: 'Remove a copy',
            summary: names,
            body: (context) => MediaCopyChoices<MediaSeriesHeld>(
              verb: 'Remove from',
              copies: [
                for (final copy in copies) (name: copy.name, target: copy),
              ],
              onChoose: (copy) => _remove(context, ref, copy),
            ),
          ),
        ...more,
      ],
    );
  }

  /// `Sonarr`, `Sonarr and Sonarr 4K`, `A, B and C`.
  static String _names(List<String> names) => switch (names) {
    [] => '',
    [final one] => one,
    _ => '${names.take(names.length - 1).join(', ')} and ${names.last}',
  };

  /// What Sonarr's automatic search can be asked for, copy by copy: every
  /// season, then each season it monitors that has aired. Sonarr passes over
  /// what it does not monitor, so a series or a season it does not watch
  /// offers nothing; one season alone is not offered twice.
  List<({String name, _AutomaticSearch target})> _automaticSearches(
    bool single,
  ) => [
    for (final copy in copies)
      if (copy.series.monitored)
        if ([
              for (final season in mediaSeasonFilesOf(
                copy.series,
                copy.episodes,
                now: now,
              ))
                if (season.aired && season.monitored) season,
            ]
            case final seasons when seasons.isNotEmpty) ...[
          if (seasons.length > 1)
            (
              name: single ? 'Every season' : 'Every season on ${copy.name}',
              target: (copy: copy, season: null),
            ),
          for (final season in seasons)
            (
              name: single ? season.label : '${season.label} on ${copy.name}',
              target: (copy: copy, season: season),
            ),
        ],
  ];

  /// Asks [search]'s Sonarr to look for the series or the season now, as an
  /// episode's search asks: it says so, or why it could not.
  Future<void> _search(
    BuildContext context,
    WidgetRef ref,
    _AutomaticSearch search,
  ) async {
    final (:copy, :season) = search;
    final sonarr = ref.read(sonarrServiceForProvider(copy.connection.id));
    try {
      if (season == null) {
        await sonarr.searchSeries(copy.series.id);
      } else {
        await sonarr.searchSeason(copy.series.id, season.number);
      }
      if (!context.mounted) return;
      SnackBarHelper.success(
        context,
        '${copy.name} is searching for ${season?.label ?? 'every season'}',
      );
    } catch (error) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        'Could not ask ${copy.name} to search',
        detail: error,
      );
    }
  }

  /// Removes [copy] from its Sonarr after the question removing asks, as a
  /// movie's copy is removed; then the page reads Sonarr again.
  Future<void> _remove(
    BuildContext context,
    WidgetRef ref,
    MediaSeriesHeld copy,
  ) async {
    final removal = mediaRemoval(
      title: title,
      name: copy.name,
      sizeOnDisk: copy.series.sizeOnDisk,
      monitored: copy.series.monitored,
      keeping: [
        for (final other in copies)
          if (other != copy && other.series.hasFiles) other.name,
      ],
    );
    final result = await showAppConfirmDialog(
      context: context,
      title: removal.title,
      message: removal.message,
      note: mediaKey == null ? null : mediaWatchedByNote(ref, mediaKey!),
      icon: Icons.delete_outline_rounded,
      cancelLabel: 'Keep it',
      confirmLabel: removal.confirm(deleteFiles: false, exclude: false),
      confirmLabelFor: (checked) => removal.confirm(
        deleteFiles: checked('files'),
        exclude: checked('exclude'),
      ),
      options: [
        if (removal.filesLabel case final label?)
          AppConfirmOption(
            key: 'files',
            label: label,
            subtitle: 'Its folder on your server. This cannot be undone.',
          ),
        AppConfirmOption(
          key: 'exclude',
          label: "Don't add it again",
          subtitle: "Keeps ${copy.name}'s import lists from bringing it back",
        ),
      ],
    );
    if (!result.confirmed || !context.mounted) return;
    try {
      await ref
          .read(sonarrServiceForProvider(copy.connection.id))
          .deleteSeries(
            copy.series.id,
            deleteFiles: result.option('files'),
            addImportListExclusion: result.option('exclude'),
          );
      if (!context.mounted) return;
      SnackBarHelper.success(context, 'Removed from ${copy.name}');
      onChanged();
    } catch (error) {
      if (!context.mounted) return;
      SnackBarHelper.error(
        context,
        'Could not remove $title from ${copy.name}',
        detail: error,
      );
    }
  }
}

/// Files & quality, open, for one Sonarr copy: where the series lives, what
/// Sonarr does about it (profile, Monitor, how it numbers the episodes),
/// each season with what it holds and whether Sonarr looks for it, and a
/// file to import.
///
/// A change shows at once and is written to Sonarr; [onChanged] then reads
/// the copy again, and a write that failed puts the old value back.
class _CopyFiles extends ConsumerStatefulWidget {
  const _CopyFiles({
    required this.copy,
    required this.files,
    required this.onChanged,
    this.now,
  });

  final MediaSeriesHeld copy;
  final Map<int, SonarrEpisodeFile>? files;
  final VoidCallback onChanged;
  final DateTime? now;

  @override
  ConsumerState<_CopyFiles> createState() => _CopyFilesState();
}

class _CopyFilesState extends ConsumerState<_CopyFiles> {
  /// What the user chose, until the copy read again says so.
  int? _profileId;
  bool? _monitored;
  SonarrSeriesType? _type;
  final Map<int, bool> _seasons = {};

  @override
  void didUpdateWidget(_CopyFiles old) {
    super.didUpdateWidget(old);
    if (old.copy.series != widget.copy.series) {
      _profileId = null;
      _monitored = null;
      _type = null;
      _seasons.clear();
    }
  }

  SonarrService get _sonarr =>
      ref.read(sonarrServiceForProvider(widget.copy.connection.id));

  String get _name => widget.copy.name;

  Future<void> _write(
    Future<void> Function() write,
    VoidCallback undo,
    String failure,
  ) async {
    try {
      await write();
      widget.onChanged();
    } catch (error) {
      if (!mounted) return;
      setState(undo);
      SnackBarHelper.error(context, failure, detail: error);
    }
  }

  Future<void> _pickProfile(Map<int, String> profiles, int current) async {
    final picked = await showMediaValueSheet<int>(
      context,
      title: 'Quality profile',
      value: current,
      currentLabel: profiles[current] ?? '',
      options: [
        for (final MapEntry(:key, :value) in profiles.entries)
          MediaDetailValueOption(value: key, label: value),
      ],
    );
    if (picked == null || picked.value == current || !mounted) return;
    setState(() => _profileId = picked.value);
    await _write(
      () => _sonarr.updateSeriesProfile(widget.copy.series.id, picked.value),
      () => _profileId = null,
      'Could not change the profile in $_name',
    );
  }

  Future<void> _pickType(SonarrSeriesType? current) async {
    final picked = await showMediaValueSheet<SonarrSeriesType>(
      context,
      title: 'Series type',
      value: current ?? SonarrSeriesType.standard,
      currentLabel: current?.label ?? '',
      options: [
        for (final type in SonarrSeriesType.values)
          MediaDetailValueOption(value: type, label: type.label),
      ],
    );
    if (picked == null || picked.value == current || !mounted) return;
    setState(() => _type = picked.value);
    await _write(
      () => _sonarr.updateSeriesType(
        widget.copy.series.id,
        picked.value.wireValue,
      ),
      () => _type = null,
      'Could not change the series type in $_name',
    );
  }

  Future<void> _setMonitored(bool value) async {
    setState(() => _monitored = value);
    await _write(
      () => _sonarr.updateSeriesMonitored(widget.copy.series.id, value),
      () => _monitored = null,
      value
          ? 'Could not monitor it in $_name'
          : 'Could not stop monitoring it in $_name',
    );
  }

  Future<void> _setSeason(int season, bool value) async {
    setState(() => _seasons[season] = value);
    await _write(
      () => _sonarr.setSeasonMonitored(
        widget.copy.series.id,
        season,
        monitored: value,
      ),
      () => _seasons.remove(season),
      'Could not change it in $_name',
    );
  }

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final series = widget.copy.series;
    final profiles =
        ref
            .watch(mediaSonarrProfilesProvider(widget.copy.connection.id))
            .value ??
        const <int, String>{};
    final profileId = _profileId ?? series.qualityProfileId;
    final profile = profiles[profileId];
    final monitored = _monitored ?? series.monitored;
    final type = _type ?? SonarrSeriesType.fromWire(series.seriesType);
    final seasons = mediaSeasonFilesOf(
      series,
      widget.copy.episodes,
      files: widget.files,
      now: widget.now,
    );
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.xs),
      child: Text(
        text,
        style: AppType.label.copyWith(color: room.inkSecondary),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        label(
          [
            _name,
            if (series.sizeOnDisk > 0) formatBytes(series.sizeOnDisk),
          ].join(dotSeparator),
        ),
        if ((series.path ?? '').isNotEmpty) FileInfoSection(path: series.path),
        // Unnamed until Sonarr has said what its profiles are called.
        if (profile != null)
          MediaValueRow(
            label: 'Quality profile',
            value: Text(
              profile,
              textAlign: TextAlign.end,
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
            onTap: profiles.length > 1 && profileId != null
                ? () => _pickProfile(profiles, profileId)
                : null,
          ),
        MediaSwitchRow(
          label: 'Monitor',
          detail: monitored
              ? 'Grabs new episodes and upgrades them to '
                    '${profile ?? 'its profile'}'
              : '$_name lists it and never looks for it',
          value: monitored,
          onChanged: _setMonitored,
        ),
        MediaValueRow(
          label: 'Series type',
          value: Text(
            type?.label ?? capitalizeFirst(series.seriesType ?? ''),
            textAlign: TextAlign.end,
            style: AppType.meta.copyWith(color: room.inkSecondary),
          ),
          onTap: () => _pickType(type),
        ),
        if (seasons.isNotEmpty) ...[
          label('Seasons'),
          for (final season in seasons)
            MediaSwitchRow(
              label: season.label,
              detail: season.detail,
              value: _seasons[season.number] ?? season.monitored,
              onChanged: (value) => _setSeason(season.number, value),
            ),
        ],
        // A file the user already has, on this copy's server: the wizard is
        // bound to this connection, so it lands in this copy's library.
        MediaLinkRow(
          label: 'Import a file',
          detail: 'From a folder on the server',
          onTap: () async {
            await context.push(
              manualImportLocation(
                manualImportBrowsePath,
                ServiceKey.sonarr,
                targetId: series.id,
                instanceId: widget.copy.connection.id,
              ),
            );
            widget.onChanged();
          },
        ),
      ],
    );
  }
}

/// History, open: each Sonarr copy's own events, newest first, each naming
/// its episode, read when the section opens.
class _History extends ConsumerWidget {
  const _History({required this.copies});

  final List<MediaSeriesHeld> copies;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final room = CupolaRoom.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final copy in copies) ...[
          if (copies.length > 1)
            Padding(
              padding: const EdgeInsets.only(
                top: AppSpacing.sm,
                bottom: AppSpacing.xs,
              ),
              child: Text(
                copy.name,
                style: AppType.label.copyWith(color: room.inkSecondary),
              ),
            ),
          switch (ref.watch(
            mediaSonarrHistoryProvider((
              connectionId: copy.connection.id,
              seriesId: copy.series.id,
            )),
          )) {
            AsyncValue(:final value?) when value.isEmpty => Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                'Nothing in its history yet',
                style: AppType.meta.copyWith(color: room.inkTertiary),
              ),
            ),
            AsyncValue(:final value?) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final record in value.take(8))
                  MediaHistoryLine(record: record, scheme: scheme),
              ],
            ),
            AsyncValue(:final error?) => InlineErrorRetry(
              message: 'Could not read the history',
              error: error,
              service: copy.connection.service,
              instanceId: copy.connection.id,
              onRetry: () => ref.invalidate(
                mediaSonarrHistoryProvider((
                  connectionId: copy.connection.id,
                  seriesId: copy.series.id,
                )),
              ),
            ),
            _ => const ShimmerPlaceholder(height: 36),
          },
        ],
      ],
    );
  }
}

/// Subtitles, open: the languages on disk across the series, then each
/// episode still wanting one, with what it wants.
class _Subtitles extends StatelessWidget {
  const _Subtitles({required this.episodes, this.sonarr});

  final List<BazarrEpisode> episodes;

  /// Sonarr's episodes of the copy Bazarr follows, for their titles.
  final List<SonarrEpisode>? sonarr;

  /// How many wanting episodes are listed before the rest are counted.
  static const _shown = 12;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    final present = {
      for (final language in mediaSeriesLanguagesOnDisk(episodes))
        (language.code2 ?? language.name ?? '').toLowerCase(): language,
    }..remove('');
    final wanting =
        [
          for (final episode in episodes)
            if (episode.missingLanguages.isNotEmpty) episode,
        ]..sort(
          (a, b) => a.season != b.season
              ? a.season.compareTo(b.season)
              : a.episode.compareTo(b.episode),
        );
    final titles = {
      for (final episode in sonarr ?? const <SonarrEpisode>[])
        episode.id: episode.title,
    };
    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.s),
      child: Text(
        text,
        style: AppType.label.copyWith(color: room.inkSecondary),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (present.isNotEmpty) ...[
          label('On disk'),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: BazarrSubtitleLanguageWrap(
              languages: present.values.toList(),
            ),
          ),
        ],
        if (wanting.isNotEmpty) ...[
          label('Wanted'),
          for (final episode in wanting.take(_shown))
            _Wanting(
              code: formatArrEpisodeCode(episode.season, episode.episode) ?? '',
              title: titles[episode.sonarrEpisodeId] ?? episode.title ?? '',
              wanted: mediaLanguageWords(episode.missingLanguages),
            ),
          if (wanting.length > _shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                '${wanting.length - _shown} more',
                style: AppType.meta.copyWith(color: room.inkTertiary),
              ),
            ),
        ],
      ],
    );
  }
}

/// One episode that wants a subtitle: its code, its title, the languages it
/// wants. Read as one sentence.
class _Wanting extends StatelessWidget {
  const _Wanting({
    required this.code,
    required this.title,
    required this.wanted,
  });

  final String code;
  final String title;
  final String wanted;

  @override
  Widget build(BuildContext context) {
    final room = CupolaRoom.of(context);
    return Semantics(
      container: true,
      excludeSemantics: true,
      label:
          '${[code, if (title.isNotEmpty) title].join(', ')}: $wanted wanted',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          children: [
            SizedBox(
              width: 52,
              child: Text(
                code,
                style: AppType.meta.copyWith(color: room.inkTertiary),
              ),
            ),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppType.meta
                    .weight(FontWeight.w400)
                    .copyWith(color: room.ink),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Text(
              wanted,
              style: AppType.meta.copyWith(color: room.inkSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
