# Components

One card per widget. Each card is a `README.md`: what the widget is for, its variants, the tokens it
uses, what the caller provides, how it reads to a screen reader, and what not to do with it, and a
catalog of pictures the real widget renders:

```sh
flutter test --tags catalog --run-skipped test/design_catalog
```

writes `build/design_catalog/<Card>/<phone|desktop>.<dark|light>.png` from
`test/design_catalog/<card>_catalog_test.dart`. The pictures are built, not committed. The animated
cards live in [`../motion/`](../motion/).

| Group | Card | Widget |
| --- | --- | --- |
| Actions | [Button](Button/README.md) | `lib/core/theme.dart`, `lib/core/widgets/cross_service_action.dart` |
| Actions | [CrossServiceAction](CrossServiceAction/README.md) | `lib/core/widgets/cross_service_action.dart` |
| Actions | [HeaderActionRow](HeaderActionRow/README.md) | `lib/core/widgets/header_action_row.dart`, `lib/core/status/media_action.dart` |
| Actions | [ReelCommandButton](ReelCommandButton/README.md) | `lib/core/widgets/reel_command_button.dart`, `lib/core/reel_motion.dart` |
| Actions | [RequestAnswerControls](RequestAnswerControls/README.md) | `lib/features/requests/presentation/widgets/request_answer_controls.dart`, `lib/features/activity/presentation/widgets/activity_actions.dart`, `lib/features/home/data/answered_requests.dart` |
| Navigation | [FloatingBottomNavBar](FloatingBottomNavBar/README.md) | `lib/core/widgets/floating_bottom_nav_bar.dart`, `lib/features/settings/domain/nav_tab.dart`, `lib/features/shell/presentation/shell_screen.dart` |
| Navigation | [FloatingNavRail](FloatingNavRail/README.md) | `lib/core/widgets/floating_nav_rail.dart`, `lib/features/shell/presentation/shell_screen.dart` |
| Navigation | [PageTabs](PageTabs/README.md) | `lib/core/widgets/page_tabs.dart`, `lib/features/activity/domain/activity_tab.dart` |
| Navigation | [SearchBarHeader](SearchBarHeader/README.md) | `lib/core/widgets/search_bar_header.dart` |
| Navigation | [SelectionPills](SelectionPills/README.md) | `lib/core/widgets/selection_pills.dart` |
| Navigation | [RailArrows](RailArrows/README.md) | `lib/core/widgets/rail_arrows.dart`, `lib/core/widgets/section_header.dart` |
| Navigation | [SettingsMasterDetail](SettingsMasterDetail/README.md) | `lib/features/settings/presentation/widgets/settings_master_detail.dart`, `lib/core/router.dart` |
| Navigation | [ServiceTabBar](ServiceTabBar/README.md) | `lib/core/widgets/service_tab_bar.dart`, `lib/features/services/domain/service_tab.dart` |
| Structure | [SectionHeader](SectionHeader/README.md) | `lib/core/widgets/section_header.dart` |
| Structure | [ActivitySection](ActivitySection/README.md) | `lib/features/activity/presentation/widgets/activity_section.dart` |
| Containers | [AppCard](AppCard/README.md) | `lib/core/widgets/app_card.dart` |
| Lists | [ServiceRecordRow](ServiceRecordRow/README.md) | `lib/core/widgets/service_record_row.dart` |
| Lists | [ActivityRows](ActivityRows/README.md) | `lib/features/activity/presentation/widgets/activity_download_row.dart`, `lib/features/activity/presentation/widgets/activity_history_row.dart`, `lib/features/activity/presentation/widgets/everyone_request_row.dart` |
| Lists | [DownloadTable](DownloadTable/README.md) | `lib/features/activity/presentation/widgets/download_table.dart`, `lib/features/activity/domain/download_table.dart` |
| Metadata | [TagChip](TagChip/README.md) | `lib/core/widgets/tag_chip.dart` |
| Metadata | [MachineName](MachineName/README.md) | `lib/core/widgets/machine_name.dart` |
| Status | [DownloadDetail](DownloadDetail/README.md) | `lib/features/activity/presentation/download_page.dart`, `lib/features/activity/presentation/widgets/download_parts.dart` |
| Status | [NoticeLine](NoticeLine/README.md) | `lib/core/widgets/notice_line.dart` |
| Status | [FaultCard](FaultCard/README.md) | `lib/features/activity/presentation/widgets/fault_card.dart`, `lib/features/activity/presentation/widgets/needs_you_cards.dart` |
| Status | [ImportReview](ImportReview/README.md) | `lib/features/import/presentation/blocked_import_review_page.dart`, `lib/features/import/presentation/blocked_import_parts.dart`, `lib/features/activity/presentation/widgets/import_done_card.dart` |
| Status | [AppErrorState](AppErrorState/README.md) | `lib/core/widgets/app_error_state.dart`, `lib/core/widgets/inline_error_retry.dart`, `lib/core/widgets/brief_failure_line.dart` |
| Status | [CapabilityBanner](CapabilityBanner/README.md) | `lib/core/widgets/capability_banner.dart`, `lib/core/capability/capability_copy.dart` |
| Status | [ConnectionBadge](ConnectionBadge/README.md) | `lib/core/widgets/connection_badge.dart` |
| Status | [NotConfiguredPlaceholder](NotConfiguredPlaceholder/README.md) | `lib/core/widgets/not_configured_placeholder.dart` |
| Status | [StartupFailurePage](StartupFailurePage/README.md) | `lib/features/shell/presentation/startup_failure_page.dart`, `lib/features/shell/domain/startup_failure.dart` |
| Status | [ServiceOfflineState](ServiceOfflineState/README.md) | `lib/core/widgets/service_offline_state.dart` |
| Status | [StatusBadge](StatusBadge/README.md) | `lib/core/widgets/status_badge.dart` |
| Readouts | [ServiceKpiPeek](ServiceKpiPeek/README.md) | `lib/core/widgets/service_kpi_peek.dart`, `lib/features/services/presentation/service_kpi_provider.dart` |
| Feedback | [AppEmptyState](AppEmptyState/README.md) | `lib/core/widgets/app_empty_state.dart` |
| Feedback | [FaultBand](FaultBand/README.md) | `lib/core/widgets/fault_band.dart` |
| Feedback | [FaultNote](FaultNote/README.md) | `lib/core/widgets/fault_note.dart` |
| Loading | [Skeleton](Skeleton/README.md) | `lib/core/widgets/shimmer_placeholder.dart`, `lib/core/widgets/app_skeleton.dart`, `lib/core/widgets/list_rows_shimmer.dart` |
| Overlays | [AppBottomSheet](AppBottomSheet/README.md) | `lib/core/widgets/app_bottom_sheet.dart`, `lib/core/utils/sheet_utils.dart` |
| Overlays | [AppDialog](AppDialog/README.md) | `lib/core/widgets/app_dialog.dart` |
| Overlays | [InviteSheet](InviteSheet/README.md) | `lib/features/settings/presentation/widgets/invite_sheet.dart`, `lib/features/discover/domain/seerr_invite.dart` |
| Forms | [TracearrOwnerFields](TracearrOwnerFields/README.md) | `lib/features/tracearr/presentation/tracearr_owner_fields.dart`, `lib/features/tracearr/presentation/tracearr_owner_sign_in_flow.dart`, `lib/features/tracearr/presentation/tracearr_owner_notice.dart` |
| Forms | [TextField](TextField/README.md) | `lib/core/theme.dart` |
| Forms | [QrCodeView](QrCodeView/README.md) | `lib/core/widgets/qr_code_view.dart` |
| Iconography | [ServiceGlyphs](ServiceGlyphs/README.md) | `lib/core/service_glyphs.dart`, `lib/features/settings/domain/service_key.dart` |
| Home | [HomeModule](HomeModule/README.md) | `lib/features/home/presentation/widgets/home_module_frame.dart`, `lib/features/home/presentation/widgets/needs_you_banner.dart`, `lib/features/home/presentation/widgets/set_up_next_module.dart`, `lib/features/home/presentation/widgets/downloads_module.dart`, `lib/features/home/presentation/widgets/requests_module.dart`, `lib/features/home/presentation/widgets/now_playing_module.dart`, `lib/features/home/presentation/widgets/continue_watching_module.dart`, `lib/features/home/presentation/widgets/coming_up_module.dart`, `lib/features/home/presentation/widgets/arrived_module.dart` |
| Home | [FeaturedPager](FeaturedPager/README.md) | `lib/features/home/presentation/widgets/featured_pager.dart`, `lib/features/home/presentation/widgets/featured_module.dart` |
| Home | [RequesterRequestRow](RequesterRequestRow/README.md) | `lib/features/requests/presentation/widgets/requester_request_row.dart`, `lib/features/requests/presentation/requests_screen.dart`, `lib/features/home/presentation/widgets/ready_to_watch_module.dart`, `lib/features/home/presentation/widgets/your_requests_module.dart` |
| Home | [EditHome](EditHome/README.md) | `lib/features/home/presentation/edit_home_page.dart`, `lib/features/home/domain/home_layout.dart` |
| Media | [CalendarAgenda](CalendarAgenda/README.md) | `lib/features/discover/presentation/widgets/calendar_agenda.dart` |
| Media | [CalendarBand](CalendarBand/README.md) | `lib/features/discover/presentation/widgets/calendar_band.dart` |
| Media | [CalendarMonthGrid](CalendarMonthGrid/README.md) | `lib/features/discover/presentation/widgets/calendar_month_grid.dart` |
| Media | [CalendarWeekStrip](CalendarWeekStrip/README.md) | `lib/features/discover/presentation/widgets/calendar_week_strip.dart` |
| Media | [CatalogPoster](CatalogPoster/README.md) | `lib/features/discover/presentation/widgets/catalog_poster.dart` |
| Media | [CollectionTally](CollectionTally/README.md) | `lib/features/discover/presentation/widgets/collection_tally.dart` |
| Media | [DiscoverDoor](DiscoverDoor/README.md) | `lib/features/discover/presentation/widgets/discover_door.dart` |
| Media | [SearchRow](SearchRow/README.md) | `lib/features/discover/presentation/widgets/search_row.dart` |
| Media | [ContentCard](ContentCard/README.md) | `lib/core/widgets/content_card.dart` |
| Media | [MediaBrowseScaffold](MediaBrowseScaffold/README.md) | `lib/core/widgets/media_browse_scaffold.dart`, `lib/core/widgets/search_bar_header.dart` |
| Media | [MediaPosterCard](MediaPosterCard/README.md) | `lib/core/widgets/media_poster_card.dart`, `lib/core/widgets/media_grid.dart` |
| Media | [StreamLibrary](StreamLibrary/README.md) | `lib/features/stream/presentation/stream_library_screen.dart`, `lib/features/stream/presentation/widgets/stream_poster_tile.dart` |
| Media | [StreamWatching](StreamWatching/README.md) | `lib/features/stream/presentation/stream_watching.dart` |
| Media detail | [MediaDetailActions](MediaDetailActions/README.md) | `lib/core/widgets/media_detail_actions.dart`, `lib/core/status/media_action.dart` |
| Media detail | [MediaChildList](MediaChildList/README.md) | `lib/core/widgets/media_child_list.dart` |
| Media detail | [MediaChipSection](MediaChipSection/README.md) | `lib/core/widgets/media_chip_section.dart`, `lib/core/widgets/tag_chip.dart` |
| Media detail | [MediaDetailHero](MediaDetailHero/README.md) | `lib/core/widgets/media_detail_view.dart` |
| Media detail | [MediaDetailSection](MediaDetailSection/README.md) | `lib/core/widgets/media_detail_slot.dart` |
| Media detail | [MediaPage](MediaPage/README.md) | `lib/features/media/presentation/media_page.dart`, `lib/features/media/domain/media_row_view.dart`, `lib/core/title_light.dart` |
| Media detail | [ShelfPage](ShelfPage/README.md) | `lib/features/media/presentation/shelf_page.dart`, `lib/features/music/presentation/artist_page.dart`, `lib/features/readarr/presentation/author_page.dart` |
| Media detail | [MediaInfoCard](MediaInfoCard/README.md) | `lib/core/widgets/media_info_card.dart`, `lib/core/widgets/file_info_section.dart` |
| Media detail | [MediaProseSection](MediaProseSection/README.md) | `lib/core/widgets/media_prose_section.dart` |
| Media detail | [MediaMetadataLine](MediaMetadataLine/README.md) | `lib/core/widgets/media_metadata_line.dart` |
| Downloads | [DownloadQueueTile](DownloadQueueTile/README.md) | `lib/core/widgets/download_queue_tile.dart`, `lib/features/qbittorrent/presentation/widgets/torrent_tile.dart` |
| Downloads | [ReleaseRow](ReleaseRow/README.md) | `lib/core/widgets/release_list_widgets.dart`, `lib/core/widgets/interactive_search_sheet.dart` |
| Service surfaces | [AmbientScaffold](AmbientScaffold/README.md) | `lib/core/widgets/ambient_scaffold.dart`, `lib/features/services/presentation/service_home_screen.dart` |
| Service surfaces | [DomainSectionHeader](DomainSectionHeader/README.md) | `lib/core/widgets/domain_section.dart`, `lib/features/settings/domain/service_key.dart` |
| Service surfaces | [ServiceOverview](ServiceOverview/README.md) | `lib/core/widgets/service_overview.dart`, `lib/features/movies/presentation/radarr_overview_screen.dart` |
| Service surfaces | [NowPlaying](NowPlaying/README.md) | `lib/features/stream/presentation/widgets/stream_session_slab.dart`, `lib/features/stream/presentation/widgets/stream_now_playing_section.dart` |
| Service surfaces | [ServiceRing](ServiceRing/README.md) | `lib/core/widgets/service_ring.dart` |
| Service surfaces | [TrueNasShares](TrueNasShares/README.md) | `lib/features/truenas/presentation/shares/truenas_shares_screen.dart`, `lib/core/widgets/floating_bottom_nav_bar.dart` |
| Service surfaces | [TrueNasCredentials](TrueNasCredentials/README.md) | `lib/features/truenas/presentation/system/truenas_credentials_screen.dart`, `lib/core/widgets/floating_bottom_nav_bar.dart` |
| Service surfaces | [TrueNasStorage](TrueNasStorage/README.md) | `lib/features/truenas/presentation/storage/truenas_storage_screen.dart`, `lib/core/widgets/floating_bottom_nav_bar.dart` |
| Onboarding | [SetupDoors](SetupDoors/README.md) | `lib/core/widgets/setup_doors.dart` |
| Onboarding | [DemoMark](DemoMark/README.md) | `lib/demo/presentation/demo_mark.dart` |
| Onboarding | [PairReceive](PairReceive/README.md) | `lib/features/pairing/presentation/pair_receive_screen.dart`, `lib/features/pairing/presentation/pair_words.dart` |
| Settings | [PairOffer](PairOffer/README.md) | `lib/features/pairing/presentation/pair_offer_screen.dart`, `lib/features/pairing/presentation/pair_words.dart` |
| Settings | [SettingsSignature](SettingsSignature/README.md) | `lib/features/settings/presentation/widgets/settings_signature.dart` |
| Settings | [SettingsSwitchRow](SettingsSwitchRow/README.md) | `lib/core/widgets/settings_switch_row.dart` |
| Desktop shell | [CommandDeck](CommandDeck/README.md) | `lib/features/shell/presentation/desktop/command_deck.dart`, `lib/features/shell/domain/command_deck_entry.dart` |
| Desktop shell | [DesktopNavRail](DesktopNavRail/README.md) | `lib/features/shell/presentation/desktop/desktop_nav_rail.dart`, `lib/features/shell/presentation/desktop/desktop_rail_services.dart`, `lib/features/settings/domain/nav_tab.dart` |
| Desktop shell | [DesktopShell](DesktopShell/README.md) | `lib/features/shell/presentation/desktop/desktop_shell.dart` |
| Desktop shell | [InspectorPane](InspectorPane/README.md) | `lib/features/shell/presentation/desktop/inspector_pane.dart`, `lib/features/shell/domain/inspector_state.dart` |
| Desktop shell | [ServicePortal](ServicePortal/README.md) | `lib/features/shell/presentation/service_portal.dart` |
| Desktop shell | [WindowChrome](WindowChrome/README.md) | `lib/features/shell/presentation/desktop/window_chrome.dart`, `lib/features/shell/presentation/desktop/service_deck.dart`, `lib/core/platform/desktop_window.dart` |
