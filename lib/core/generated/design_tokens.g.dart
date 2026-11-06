// GENERATED: edit design/tokens/, then run `dart run tool/design_tokens/generate.dart`.
//
// Never edit this file by hand: the test suite regenerates it from the token
// sets and fails on any difference.

import 'dart:ui' show Color, FontWeight;

import 'package:flutter/animation.dart' show Cubic;

/// The design tokens every theme shares, from `design/tokens/core.json`.
abstract final class DesignTokens {
  // color.base
  /// Pure white: reversed-out labels on deep fills (the light room's ink
  /// button, the deep status containers).
  static const Color colorBaseWhite = Color(0xFFFFFFFF);

  /// Pure black: the dark room's shadow ink and the modal barrier.
  static const Color colorBaseBlack = Color(0xFF000000);

  // color.service
  /// Seerr Indigo (indigo-500): the Seerr accent. Identity data in the
  /// registry; The interface confines accents to the service mark and its tab.
  static const Color colorServiceSeerr = Color(0xFF6366F1);

  /// Radarr Amber, the movies accent: ΔE2000 11.6 (12° of hue) from the fault
  /// amber, so never beside a fault.
  static const Color colorServiceRadarr = Color(0xFFF59E0B);

  /// Sonarr Violet, the series accent.
  static const Color colorServiceSonarr = Color(0xFF8B5CF6);

  /// Lidarr Pink, the music accent.
  static const Color colorServiceLidarr = Color(0xFFEC4899);

  /// Readarr Red, the books accent.
  static const Color colorServiceReadarr = Color(0xFFC0392B);

  /// Prowlarr Orange, the indexers accent.
  static const Color colorServiceProwlarr = Color(0xFFE66000);

  /// Bazarr Sky, the subtitles accent.
  static const Color colorServiceBazarr = Color(0xFF25A7DF);

  /// qBittorrent Blue, the torrent client accent.
  static const Color colorServiceQbittorrent = Color(0xFF2F67BA);

  /// Transmission Crimson: walked off the brand red so it clears readarr (ΔE
  /// 10.8).
  static const Color colorServiceTransmission = Color(0xFFE11D48);

  /// SABnzbd Gold, a usenet client accent.
  static const Color colorServiceSabnzbd = Color(0xFFF0A800);

  /// NZBGet Green, a usenet client accent.
  static const Color colorServiceNzbget = Color(0xFF0F9D58);

  /// Dockge Teal, the stacks accent.
  static const Color colorServiceDockge = Color(0xFF058373);

  /// TrueNAS Blue, the storage accent.
  static const Color colorServiceTruenas = Color(0xFF0095D5);

  /// Unraid Orange, the server accent.
  static const Color colorServiceUnraid = Color(0xFFFF8C2B);

  /// Nginx Proxy Manager Vermilion, the brand value unchanged.
  static const Color colorServiceNginxProxyManager = Color(0xFFF15833);

  /// Jellyfin Purple, a streaming accent.
  static const Color colorServiceJellyfin = Color(0xFFAA5CC3);

  /// Plex Bronze: deliberately not brand gold #E5A00D, which collides with
  /// sabnzbd.
  static const Color colorServicePlex = Color(0xFFC97A16);

  /// Emby Green, the brand value unchanged. Registry data only: the interface
  /// paints every service with the lamp.
  static const Color colorServiceEmby = Color(0xFF52B54B);

  // color.status
  /// GREEN, the dark room's green: available, complete, healthy. Quiet: in a
  /// status line the dot carries it and the words stay secondary ink.
  static const Color colorStatusSuccess = Color(0xFF5FE39A);

  /// The day room's green, the deep green: the dark success container under
  /// white, and text on the light one.
  static const Color colorStatusSuccessContainer = Color(0xFF0F7A45);

  /// AMBER, the dark room's amber: a fault, never the backlog. The remedy fill,
  /// under amber ink.
  static const Color colorStatusWarning = Color(0xFFF7C23A);

  /// RED, the dark room's red: unreachable, and nothing else.
  static const Color colorStatusError = Color(0xFFFF8A7A);

  /// The day room's red, the deep red: the dark error container under white,
  /// and text on the light one.
  static const Color colorStatusErrorContainer = Color(0xFFB8322A);

  /// BLUE, the dark room's blue: queued, in progress, informational, waiting on
  /// someone.
  static const Color colorStatusInfo = Color(0xFF9DB8FF);

  // color
  /// The on-ink: the label a bright fill takes (the ink button, a tone fill)
  /// where white loses the contrast measurement.
  static const Color colorInkOnBright = Color(0xFF0A0A0D);

  // color.plate
  /// Artwork stand-in (a missing poster, an album without cover): the raised
  /// step, fixed in both themes because artwork is not palette.
  static const Color colorPlateSurface = Color(0xFF17171D);

  /// The letterboxed well behind a backdrop and the terminal panel: the ground,
  /// fixed in both themes.
  static const Color colorPlateWell = Color(0xFF0A0A0D);

  /// Hairline on a plate: the edge line flattened on the ground; fixed.
  static const Color colorPlateOutline = Color(0xFF232326);

  /// Primary text on a plate: the primary ink.
  static const Color colorPlateInk = Color(0xFFF7F6F2);

  /// Secondary text on a plate: the tertiary ink flattened on the ground; 6.6:1
  /// on the plate surface, 7.3:1 on the well.
  static const Color colorPlateDimInk = Color(0xFF9D9D9E);

  // color.title-light
  /// The neutral lamp: the light of a room with no artwork (infrastructure,
  /// settings), and of a title whose artwork has too little chroma. Never a
  /// service colour.
  static const Color colorTitleLightFallback = Color(0xFF8A8A99);

  // space.scale
  /// Inside components only: glyph-to-label gap, between two lines of a row.
  static const double spaceScale2xs = 2;

  /// Tight gaps; chip vertical padding.
  static const double spaceScaleXs = 4;

  /// Inside components only: chip inner padding.
  static const double spaceScaleS = 6;

  /// Related elements; the gap between chips in a rail.
  static const double spaceScaleM = 8;

  /// A row's vertical padding.
  static const double spaceScaleRow = 10;

  /// Compact spacing: rail and grid gaps, row gaps.
  static const double spaceScaleL = 12;

  /// A slab's vertical padding and the room header's top.
  static const double spaceScaleSlabY = 14;

  /// The page gutter and a slab's padding.
  static const double spaceScaleGutter = 16;

  /// A sheet title's leading inset.
  static const double spaceScaleXl = 20;

  /// Section separation inside a page.
  static const double spaceScale2xl = 24;

  /// The space above a section heading.
  static const double spaceScaleSection = 28;

  /// Major blocks.
  static const double spaceScale3xl = 32;

  /// The largest section break.
  static const double spaceScale4xl = 40;

  /// The top margin of a screen, under the status bar.
  static const double spaceScaleTop = 56;

  // space
  /// Inside components only: glyph-to-label gap, between two lines of a row.
  static const double spaceXxs = spaceScale2xs;

  /// Minimal spacing for tight layouts; chip vertical padding.
  static const double spaceXs = spaceScaleXs;

  /// Inside components only: chip inner padding, nav bar inner padding.
  static const double spaceS = spaceScaleS;

  /// Small spacing for related elements; badge padding.
  static const double spaceSm = spaceScaleM;

  /// Inside components only: row line gaps, inner plates.
  static const double spaceM = spaceScaleRow;

  /// Compact spacing: grid and carousel gaps, button vertical padding.
  static const double spaceMd = spaceScaleL;

  /// Inside components only: nav pill horizontal padding.
  static const double spaceMl = spaceScaleSlabY;

  /// The default: page gutter, card padding, input horizontal padding.
  static const double spaceLg = spaceScaleGutter;

  /// Section separation; button horizontal padding.
  static const double spaceXl = spaceScale2xl;

  /// Major blocks.
  static const double spaceXxl = spaceScale3xl;

  /// The largest section break (the scale's largest step).
  static const double spaceXxxl = spaceScale4xl;

  /// Gap between grid items.
  static const double spaceGridGap = spaceMd;

  /// Gap between carousel items: the rail gap.
  static const double spaceCarouselGap = spaceMd;

  // radius
  /// Sharp corners (full-bleed backdrops).
  static const double radiusNone = 0;

  /// Small-object geometry: a 3dp tag.
  static const double radiusHair = 3;

  /// Subtle curves; progress tracks.
  static const double radiusXs = 4;

  /// a row thumbnail (36×54), a checkbox.
  static const double radiusThumb = 8;

  /// Small-object geometry: a poster corner in dense rails, a small badge.
  static const double radiusXs2 = radiusThumb;

  /// Small-object geometry: an inner plate, a row's leading tile.
  static const double radiusSm2 = 10;

  /// chips' inner plates, tiles, fault chips, stale bands.
  static const double radiusChip = 12;

  /// Chips, badges and small objects.
  static const double radiusSm = radiusChip;

  /// a poster.
  static const double radiusPoster = 14;

  /// a medium button, a segmented track, a stepper, an icon button.
  static const double radiusControl = 14;

  /// The default: cards, controls, posters, list tiles.
  static const double radiusMd = radiusControl;

  /// a large button, a banner, a toast.
  static const double radiusButton = 16;

  /// a text field and the search field.
  static const double radiusField = 16;

  /// Buttons, fields, banners, grouped settings.
  static const double radiusLg = radiusButton;

  /// a door (Discover's entrances, tiles).
  static const double radiusDoor = 20;

  /// grouped rows (settings, record lists).
  static const double radiusGroup = 22;

  /// a slab (a section) and a dialog.
  static const double radiusSlab = 26;

  /// a bottom sheet's top corners.
  static const double radiusSheet = 30;

  /// The floating navigation bar and sheet tops.
  static const double radiusXl = radiusSheet;

  /// Fully rounded: chips, the selected tab, segment pills, metadata pills.
  /// Every pill is drawn at half its height.
  static const double radiusPill = 999;

  /// Metadata pills (tags, genres, ratings). The same corner as a selected
  /// pill.
  static const double radiusFull = radiusPill;

  // size
  /// The minimum touch target.
  static const double sizeTouch = 44;

  /// A primary button.
  static const double sizeButtonL = 52;

  /// A secondary button.
  static const double sizeButtonM = 44;

  /// A text field.
  static const double sizeField = 52;

  /// The search field.
  static const double sizeSearch = 48;

  /// A chip (inside a 44 target).
  static const double sizeChip = 36;

  /// The floating tab bar.
  static const double sizeTabbar = 62;

  /// An icon in a row or a button.
  static const double sizeIcon = 20;

  /// A large icon.
  static const double sizeIconL = 24;

  /// A row thumbnail's width.
  static const double sizeThumbW = 36;

  /// A row thumbnail's height.
  static const double sizeThumbH = 54;

  // breakpoint
  /// Below this width the floating bar switches to compact item targets.
  static const double breakpointNavCompact = 360;

  /// Below this width a desktop window paints the touch shell under a bare drag
  /// strip.
  static const double breakpointDesktopMobile = 720;

  /// At or above this width a touch build moves from the bottom bar to a side
  /// rail.
  static const double breakpointTouchRail = 840;

  /// At or above this width a touch build opens a title beside the page it was
  /// opened from: the phone's column on the left, the title on the right.
  static const double breakpointTouchSplit = 1024;

  /// The column a page keeps beside an open title on a tablet: the widest
  /// phone.
  static const double breakpointSplitList = 440;

  /// Below this width the desktop shell uses its compact variants.
  static const double breakpointDesktopCompact = 1100;

  /// The widest the main content well may grow, on any shell.
  static const double breakpointContentWell = 1140;

  /// The widest a page of one column grows: an artist's or an author's page,
  /// rows read top to bottom, centred rather than stretched to the window.
  static const double breakpointReadingWell = 720;

  /// Narrowest a desktop window may be dragged: a small phone's width.
  static const double breakpointDesktopMinWidth = 360;

  /// Shortest a desktop window may be dragged: the compact artboard's height.
  static const double breakpointDesktopMinHeight = 450;

  /// Aspect ratio at or above which a frame puts two things side by side
  /// instead of stacking. A shape, not a width.
  static const double breakpointLandscapeAspect = 1.2;

  // motion.curve
  /// The one ease: a fast start and a long settle. Press, state changes, the
  /// pager, entrances, flights, progress.
  static const Cubic motionCurveStandard = Cubic(0.2, 0.8, 0.2, 1);

  /// Sheets and dialogs arriving.
  static const Cubic motionCurveSheetIn = Cubic(0.05, 0.7, 0.1, 1);

  /// Sheets and dialogs leaving.
  static const Cubic motionCurveSheetOut = Cubic(0.3, 0, 0.8, 0.15);

  /// A figure rolling into place (easeOutCubic).
  static const Cubic motionCurveRoll = Cubic(0.33, 1, 0.68, 1);

  /// CSS `ease`: cross-fades of artwork and of the room light.
  static const Cubic motionCurveEase = Cubic(0.25, 0.1, 0.25, 1);

  /// Loops: the skeleton, a dwell.
  static const Cubic motionCurveLinear = Cubic(0, 0, 1, 1);

  /// CSS `ease-in-out`: the ambient loops (breathe, Ken Burns).
  static const Cubic motionCurveEaseInOut = Cubic(0.42, 0, 0.58, 1);

  // motion.press
  /// The press dip. Unchanged under Reduce Motion.
  static const Duration motionPressDuration = Duration(milliseconds: 180);

  static const Cubic motionPressCurve = motionCurveStandard;

  /// The scale a pressed target dips to.
  static const double motionPressScale = 0.96;

  // motion.hover
  /// A poster rising under the pointer, and settling back. Instant under Reduce
  /// Motion.
  static const Duration motionHoverDuration = Duration(milliseconds: 180);

  /// How far a poster rises under the pointer: a mouse or a trackpad, never a
  /// finger.
  static const double motionHoverLift = 2;

  // motion.standard
  /// State changes, expand, select. Reduce Motion: a 150 ms fade.
  static const Duration motionStandardDuration = Duration(milliseconds: 320);

  static const Cubic motionStandardCurve = motionCurveStandard;

  // motion.emphasized
  /// The pager, the segmented thumb, the chip rail. Reduce Motion: a 150 ms
  /// fade.
  static const Duration motionEmphasizedDuration = Duration(milliseconds: 420);

  static const Cubic motionEmphasizedCurve = motionCurveStandard;

  // motion.enter
  /// An entrance: rise and fade. Reduce Motion: no rise.
  static const Duration motionEnterDuration = Duration(milliseconds: 520);

  static const Cubic motionEnterCurve = motionCurveStandard;

  /// How far an entering element rises.
  static const double motionEnterRise = 12;

  /// The delay between siblings entering.
  static const Duration motionEnterStagger = Duration(milliseconds: 40);

  /// Siblings past this many enter together.
  static const double motionEnterStaggerMax = 6;

  // motion.sheet-in
  /// Sheets and dialogs in. Reduce Motion: a fade.
  static const Duration motionSheetInDuration = Duration(milliseconds: 380);

  static const Cubic motionSheetInCurve = motionCurveSheetIn;

  // motion.sheet-out
  /// Sheets and dialogs out. Reduce Motion: a fade.
  static const Duration motionSheetOutDuration = Duration(milliseconds: 240);

  static const Cubic motionSheetOutCurve = motionCurveSheetOut;

  // motion.shared
  /// The poster → Media flight. Reduce Motion: a cross-fade.
  static const Duration motionSharedDuration = Duration(milliseconds: 450);

  static const Cubic motionSharedCurve = motionCurveStandard;

  // motion.progress
  /// A bar moving to a new value. Reduce Motion: a jump.
  static const Duration motionProgressDuration = Duration(milliseconds: 600);

  static const Cubic motionProgressCurve = motionCurveStandard;

  // motion.text-xfade
  /// Carousel copy changing, rising 10.
  static const Duration motionTextXfadeDuration = Duration(milliseconds: 700);

  static const Cubic motionTextXfadeCurve = motionCurveStandard;

  /// How far the copy rises as it comes in. Reduce Motion: none.
  static const double motionTextXfadeRise = 10;

  // motion.image-xfade
  /// Carousel art changing.
  static const Duration motionImageXfadeDuration = Duration(milliseconds: 900);

  static const Cubic motionImageXfadeCurve = motionCurveEase;

  // motion.roll
  /// A figure rolls once from "—" to its value; never counts up from 0. Reduce
  /// Motion: the final figure.
  static const Duration motionRollDuration = Duration(milliseconds: 900);

  static const Cubic motionRollCurve = motionCurveRoll;

  // motion.light
  /// The room light moving to a new title. Reduce Motion: a jump.
  static const Duration motionLightDuration = Duration(milliseconds: 1500);

  static const Cubic motionLightCurve = motionCurveEase;

  // motion.shimmer
  /// One skeleton sweep, looping.
  static const Duration motionShimmerDuration = Duration(milliseconds: 1600);

  static const Cubic motionShimmerCurve = motionCurveLinear;

  // motion.dwell
  /// A carousel slide; the pager fills. Reduce Motion: no auto-advance.
  static const Duration motionDwellDuration = Duration(milliseconds: 6000);

  static const Cubic motionDwellCurve = motionCurveLinear;

  /// After a touch anywhere in the carousel, the slide stays at least this
  /// long.
  static const Duration motionDwellHold = Duration(milliseconds: 1200);

  // motion.breathe
  /// One slab's light per screen, alternating on the 12 Hz ambient clock.
  /// Reduce Motion: still.
  static const Duration motionBreatheDuration = Duration(milliseconds: 8000);

  static const Cubic motionBreatheCurve = motionCurveEaseInOut;

  /// The breathing light's low opacity.
  static const double motionBreatheLow = 0.42;

  /// The breathing light's high opacity.
  static const double motionBreatheHigh = 0.55;

  // motion.kenburns
  /// Carousel art drifting 1.02 → 1.12, alternating. Reduce Motion: still.
  static const Duration motionKenburnsDuration = Duration(milliseconds: 14000);

  static const Cubic motionKenburnsCurve = motionCurveEaseInOut;

  /// The art's scale at the start of its drift.
  static const double motionKenburnsFrom = 1.02;

  /// The art's scale at the far end of its drift.
  static const double motionKenburnsTo = 1.12;

  // duration
  /// Micro-interactions: the press dip, a highlight.
  static const Duration durationXs = motionPressDuration;

  /// Simple state changes.
  static const Duration durationSm = motionStandardDuration;

  /// Standard transitions.
  static const Duration durationMd = motionStandardDuration;

  /// Complex transitions.
  static const Duration durationLg = motionEmphasizedDuration;

  /// Entrances.
  static const Duration durationXl = motionEnterDuration;

  /// One skeleton shimmer cycle.
  static const Duration durationShimmer = motionShimmerDuration;

  /// How long a transient success check replaces a button's icon before
  /// reverting.
  static const Duration durationConfirmationHold = Duration(milliseconds: 1600);

  // opacity
  /// A service accent's soft container: icon backgrounds and chips.
  static const double opacityServiceSoftContainer = 0.14;

  /// Centre of a signature card's accent glow. A grid repeating the treatment
  /// takes a fraction of it.
  static const double opacityServiceGlow = 0.22;

  /// Mid stop of the hero scrim at rest; it deepens to opaque as the hero
  /// collapses.
  static const double opacityHeroScrimRest = 0.85;

  /// Top stop of the hero scrim once collapsed, so the art recedes behind
  /// chrome.
  static const double opacityHeroScrimDeep = 0.35;

  /// The surface behind a status badge laid over artwork.
  static const double opacityStatusBadge = 0.8;

  /// A control whose target is not set up: dimmed but tappable.
  static const double opacityDimmed = 0.5;

  // shadow.level-1.contact
  static const double shadowLevel1ContactOffsetX = 0;

  static const double shadowLevel1ContactOffsetY = 2;

  static const double shadowLevel1ContactBlur = 6;

  static const double shadowLevel1ContactSpread = 0;

  // shadow.level-1.ambient
  static const double shadowLevel1AmbientOffsetX = 0;

  static const double shadowLevel1AmbientOffsetY = 4;

  static const double shadowLevel1AmbientBlur = 12;

  static const double shadowLevel1AmbientSpread = 0;

  // shadow.level-2.contact
  static const double shadowLevel2ContactOffsetX = 0;

  static const double shadowLevel2ContactOffsetY = 2;

  static const double shadowLevel2ContactBlur = 6;

  static const double shadowLevel2ContactSpread = 0;

  // shadow.level-2.ambient
  static const double shadowLevel2AmbientOffsetX = 0;

  static const double shadowLevel2AmbientOffsetY = 16;

  static const double shadowLevel2AmbientBlur = 30;

  static const double shadowLevel2AmbientSpread = -12;

  // shadow.level-3.contact
  static const double shadowLevel3ContactOffsetX = 0;

  static const double shadowLevel3ContactOffsetY = 2;

  static const double shadowLevel3ContactBlur = 6;

  static const double shadowLevel3ContactSpread = 0;

  // shadow.level-3.ambient
  static const double shadowLevel3AmbientOffsetX = 0;

  static const double shadowLevel3AmbientOffsetY = 10;

  static const double shadowLevel3AmbientBlur = 30;

  static const double shadowLevel3AmbientSpread = 0;

  // shadow.glass.ambient
  static const Color shadowGlassAmbientColor = colorBaseBlack;

  static const double shadowGlassAmbientOffsetX = 0;

  static const double shadowGlassAmbientOffsetY = 10;

  static const double shadowGlassAmbientBlur = 30;

  static const double shadowGlassAmbientSpread = 0;

  // shadow.glass.highlight
  static const Color shadowGlassHighlightColor = colorBaseWhite;

  static const double shadowGlassHighlightOffsetX = 0;

  static const double shadowGlassHighlightOffsetY = 1;

  static const double shadowGlassHighlightBlur = 0;

  static const double shadowGlassHighlightSpread = 0;

  // shadow.poster.glow
  static const Color shadowPosterGlowColor = colorTitleLightFallback;

  static const double shadowPosterGlowOffsetX = 0;

  static const double shadowPosterGlowOffsetY = 16;

  static const double shadowPosterGlowBlur = 30;

  static const double shadowPosterGlowSpread = -12;

  // shadow.hero.glow
  static const Color shadowHeroGlowColor = colorTitleLightFallback;

  static const double shadowHeroGlowOffsetX = 0;

  static const double shadowHeroGlowOffsetY = 30;

  static const double shadowHeroGlowBlur = 70;

  static const double shadowHeroGlowSpread = -16;

  // shadow.hero.contact
  static const Color shadowHeroContactColor = colorBaseBlack;

  static const double shadowHeroContactOffsetX = 0;

  static const double shadowHeroContactOffsetY = 2;

  static const double shadowHeroContactBlur = 6;

  static const double shadowHeroContactSpread = 0;

  // shadow.float.drop
  static const Color shadowFloatDropColor = colorBaseBlack;

  static const double shadowFloatDropOffsetX = 0;

  static const double shadowFloatDropOffsetY = 10;

  static const double shadowFloatDropBlur = 30;

  static const double shadowFloatDropSpread = 0;

  // shadow.sheet.drop
  static const Color shadowSheetDropColor = colorBaseBlack;

  static const double shadowSheetDropOffsetX = 0;

  static const double shadowSheetDropOffsetY = -12;

  static const double shadowSheetDropBlur = 40;

  static const double shadowSheetDropSpread = 0;

  // type.family
  /// Bricolage Grotesque, bundled (opsz 12–96, wdth 75–100, wght 200–800):
  /// display type, figures. Its default instance is 96pt ExtraBold, so every
  /// role sets all three axes. Geist Mono after it carries the symbols it lacks
  /// (⇧ ⏎), Apple Symbols the Apple modifier glyphs (⌘ ⌥).
  static const String typeFamilyDisplay = 'Bricolage Grotesque';
  static const List<String> typeFamilyDisplayFallback = <String>[
    'Geist Mono',
    'Apple Symbols',
  ];

  /// Onest, bundled (wght 100–900): every text role. Has tabular figures. Geist
  /// Mono after it carries the symbols it lacks (∞ ⇧ ⏎), Apple Symbols the
  /// Apple modifier glyphs (⌘ ⌥), which only Apple platforms print.
  static const String typeFamilyText = 'Onest';
  static const List<String> typeFamilyTextFallback = <String>[
    'Geist Mono',
    'Apple Symbols',
  ];

  /// Geist Mono, bundled (wght 100–900): release names, paths, logs, keys, the
  /// terminal. Apple Symbols after it carries the Apple modifier glyphs it
  /// lacks (⌘ ⌥); the platform mono faces follow.
  static const String typeFamilyMono = 'Geist Mono';
  static const List<String> typeFamilyMonoFallback = <String>[
    'Apple Symbols',
    'Menlo',
    'SF Mono',
    'Roboto Mono',
    'Droid Sans Mono',
    'Consolas',
    'monospace',
  ];

  /// The app's default family: the text face.
  static const String typeFamilySans = typeFamilyText;
  static const List<String> typeFamilySansFallback = typeFamilyTextFallback;

  // type.role
  /// Tab-root titles.
  static const String typeRoleScreenFontFamily = typeFamilyDisplay;
  static const List<String> typeRoleScreenFontFamilyFallback =
      typeFamilyDisplayFallback;
  static const double typeRoleScreenFontSize = 36;
  static const double typeRoleScreenLineHeight = 1;
  static const FontWeight typeRoleScreenFontWeight = FontWeight.w600;
  static const double typeRoleScreenWght = 600;
  static const double typeRoleScreenFontWidth = 92;
  static const double typeRoleScreenLetterSpacing = -0.72;

  /// A title on its Media page.
  static const String typeRoleMediaFontFamily = typeFamilyDisplay;
  static const List<String> typeRoleMediaFontFamilyFallback =
      typeFamilyDisplayFallback;
  static const double typeRoleMediaFontSize = 42;
  static const double typeRoleMediaLineHeight = 0.9762;
  static const FontWeight typeRoleMediaFontWeight = FontWeight.w600;
  static const double typeRoleMediaWght = 600;
  static const double typeRoleMediaFontWidth = 90;
  static const double typeRoleMediaLetterSpacing = -0.924;

  /// Pushed screen and service room titles.
  static const String typeRoleRoomFontFamily = typeFamilyDisplay;
  static const List<String> typeRoleRoomFontFamilyFallback =
      typeFamilyDisplayFallback;
  static const double typeRoleRoomFontSize = 30;
  static const double typeRoleRoomLineHeight = 1.0333;
  static const FontWeight typeRoleRoomFontWeight = FontWeight.w600;
  static const double typeRoleRoomWght = 600;
  static const double typeRoleRoomFontWidth = 92;
  static const double typeRoleRoomLetterSpacing = -0.54;

  /// A featured title, a sheet title.
  static const String typeRoleFeatureFontFamily = typeFamilyDisplay;
  static const List<String> typeRoleFeatureFontFamilyFallback =
      typeFamilyDisplayFallback;
  static const double typeRoleFeatureFontSize = 26;
  static const double typeRoleFeatureLineHeight = 1.0385;
  static const FontWeight typeRoleFeatureFontWeight = FontWeight.w600;
  static const double typeRoleFeatureWght = 600;
  static const double typeRoleFeatureFontWidth = 92;
  static const double typeRoleFeatureLetterSpacing = -0.39;

  /// Section headings.
  static const String typeRoleSectionFontFamily = typeFamilyDisplay;
  static const List<String> typeRoleSectionFontFamilyFallback =
      typeFamilyDisplayFallback;
  static const double typeRoleSectionFontSize = 21;
  static const double typeRoleSectionLineHeight = 1.1429;
  static const FontWeight typeRoleSectionFontWeight = FontWeight.w600;
  static const double typeRoleSectionWght = 600;
  static const double typeRoleSectionFontWidth = 96;
  static const double typeRoleSectionLetterSpacing = -0.21;

  /// One hero readout per room.
  static const String typeRoleFigureHeroFontFamily = typeFamilyDisplay;
  static const List<String> typeRoleFigureHeroFontFamilyFallback =
      typeFamilyDisplayFallback;
  static const double typeRoleFigureHeroFontSize = 44;
  static const double typeRoleFigureHeroLineHeight = 1;
  static const FontWeight typeRoleFigureHeroFontWeight = FontWeight.w600;
  static const double typeRoleFigureHeroWght = 600;
  static const double typeRoleFigureHeroFontWidth = 90;
  static const double typeRoleFigureHeroLetterSpacing = -0.88;

  /// KPI figures, big numbers.
  static const String typeRoleFigureFontFamily = typeFamilyDisplay;
  static const List<String> typeRoleFigureFontFamilyFallback =
      typeFamilyDisplayFallback;
  static const double typeRoleFigureFontSize = 24;
  static const double typeRoleFigureLineHeight = 1;
  static const FontWeight typeRoleFigureFontWeight = FontWeight.w600;
  static const double typeRoleFigureWght = 600;
  static const double typeRoleFigureFontWidth = 92;
  static const double typeRoleFigureLetterSpacing = -0.24;

  /// Times and figures in rows.
  static const String typeRoleFigureSFontFamily = typeFamilyDisplay;
  static const List<String> typeRoleFigureSFontFamilyFallback =
      typeFamilyDisplayFallback;
  static const double typeRoleFigureSFontSize = 20;
  static const double typeRoleFigureSLineHeight = 1;
  static const FontWeight typeRoleFigureSFontWeight = FontWeight.w600;
  static const double typeRoleFigureSWght = 600;
  static const double typeRoleFigureSFontWidth = 92;
  static const double typeRoleFigureSLetterSpacing = -0.2;

  /// Paragraphs.
  static const String typeRoleBodyFontFamily = typeFamilyText;
  static const List<String> typeRoleBodyFontFamilyFallback =
      typeFamilyTextFallback;
  static const double typeRoleBodyFontSize = 15;
  static const double typeRoleBodyLineHeight = 1.4667;
  static const FontWeight typeRoleBodyFontWeight = FontWeight.w400;
  static const double typeRoleBodyWght = 400;
  static const double typeRoleBodyFontWidth = 100;
  static const double typeRoleBodyLetterSpacing = 0;

  /// Row titles.
  static const String typeRoleRowFontFamily = typeFamilyText;
  static const List<String> typeRoleRowFontFamilyFallback =
      typeFamilyTextFallback;
  static const double typeRoleRowFontSize = 15;
  static const double typeRoleRowLineHeight = 1.3333;
  static const FontWeight typeRoleRowFontWeight = FontWeight.w600;
  static const double typeRoleRowWght = 600;
  static const double typeRoleRowFontWidth = 100;
  static const double typeRoleRowLetterSpacing = 0;

  /// Primary buttons.
  static const String typeRoleButtonFontFamily = typeFamilyText;
  static const List<String> typeRoleButtonFontFamilyFallback =
      typeFamilyTextFallback;
  static const double typeRoleButtonFontSize = 16;
  static const double typeRoleButtonLineHeight = 1.25;
  static const FontWeight typeRoleButtonFontWeight = FontWeight.w600;
  static const double typeRoleButtonWght = 600;
  static const double typeRoleButtonFontWidth = 100;
  static const double typeRoleButtonLetterSpacing = 0;

  /// Small buttons, links, chips.
  static const String typeRoleLabelFontFamily = typeFamilyText;
  static const List<String> typeRoleLabelFontFamilyFallback =
      typeFamilyTextFallback;
  static const double typeRoleLabelFontSize = 14;
  static const double typeRoleLabelLineHeight = 1.2857;
  static const FontWeight typeRoleLabelFontWeight = FontWeight.w600;
  static const double typeRoleLabelWght = 600;
  static const double typeRoleLabelFontWidth = 100;
  static const double typeRoleLabelLetterSpacing = 0;

  /// Secondary lines.
  static const String typeRoleMetaFontFamily = typeFamilyText;
  static const List<String> typeRoleMetaFontFamilyFallback =
      typeFamilyTextFallback;
  static const double typeRoleMetaFontSize = 13;
  static const double typeRoleMetaLineHeight = 1.3846;
  static const FontWeight typeRoleMetaFontWeight = FontWeight.w500;
  static const double typeRoleMetaWght = 500;
  static const double typeRoleMetaFontWidth = 100;
  static const double typeRoleMetaLetterSpacing = 0;

  /// Captions, badges.
  static const String typeRoleCaptionFontFamily = typeFamilyText;
  static const List<String> typeRoleCaptionFontFamilyFallback =
      typeFamilyTextFallback;
  static const double typeRoleCaptionFontSize = 12;
  static const double typeRoleCaptionLineHeight = 1.3333;
  static const FontWeight typeRoleCaptionFontWeight = FontWeight.w500;
  static const double typeRoleCaptionWght = 500;
  static const double typeRoleCaptionFontWidth = 100;
  static const double typeRoleCaptionLetterSpacing = 0;

  /// Tab labels, poster marks. The floor: nothing renders smaller.
  static const String typeRoleMicroFontFamily = typeFamilyText;
  static const List<String> typeRoleMicroFontFamilyFallback =
      typeFamilyTextFallback;
  static const double typeRoleMicroFontSize = 11;
  static const double typeRoleMicroLineHeight = 1.2727;
  static const FontWeight typeRoleMicroFontWeight = FontWeight.w600;
  static const double typeRoleMicroWght = 600;
  static const double typeRoleMicroFontWidth = 100;
  static const double typeRoleMicroLetterSpacing = 0.11;

  /// Release names, paths, logs, the terminal.
  static const String typeRoleMonoFontFamily = typeFamilyMono;
  static const List<String> typeRoleMonoFontFamilyFallback =
      typeFamilyMonoFallback;
  static const double typeRoleMonoFontSize = 13;
  static const double typeRoleMonoLineHeight = 1.3846;
  static const FontWeight typeRoleMonoFontWeight = FontWeight.w400;
  static const double typeRoleMonoWght = 450;
  static const double typeRoleMonoFontWidth = 100;
  static const double typeRoleMonoLetterSpacing = -0.13;

  // type.display
  /// Rare editorial and onboarding moments.
  static const String typeDisplayLargeFontFamily = typeRoleFigureHeroFontFamily;
  static const List<String> typeDisplayLargeFontFamilyFallback =
      typeRoleFigureHeroFontFamilyFallback;
  static const double typeDisplayLargeFontSize = typeRoleFigureHeroFontSize;
  static const double typeDisplayLargeLineHeight = typeRoleFigureHeroLineHeight;
  static const FontWeight typeDisplayLargeFontWeight =
      typeRoleFigureHeroFontWeight;
  static const double typeDisplayLargeWght = typeRoleFigureHeroWght;
  static const double typeDisplayLargeFontWidth = typeRoleFigureHeroFontWidth;
  static const double typeDisplayLargeLetterSpacing =
      typeRoleFigureHeroLetterSpacing;

  /// Editorial display, one step down: the onboarding door.
  static const String typeDisplayMediumFontFamily = typeRoleMediaFontFamily;
  static const List<String> typeDisplayMediumFontFamilyFallback =
      typeRoleMediaFontFamilyFallback;
  static const double typeDisplayMediumFontSize = typeRoleMediaFontSize;
  static const double typeDisplayMediumLineHeight = typeRoleMediaLineHeight;
  static const FontWeight typeDisplayMediumFontWeight = typeRoleMediaFontWeight;
  static const double typeDisplayMediumWght = typeRoleMediaWght;
  static const double typeDisplayMediumFontWidth = typeRoleMediaFontWidth;
  static const double typeDisplayMediumLetterSpacing =
      typeRoleMediaLetterSpacing;

  /// The smallest display.
  static const String typeDisplaySmallFontFamily = typeRoleScreenFontFamily;
  static const List<String> typeDisplaySmallFontFamilyFallback =
      typeRoleScreenFontFamilyFallback;
  static const double typeDisplaySmallFontSize = typeRoleScreenFontSize;
  static const double typeDisplaySmallLineHeight = typeRoleScreenLineHeight;
  static const FontWeight typeDisplaySmallFontWeight = typeRoleScreenFontWeight;
  static const double typeDisplaySmallWght = typeRoleScreenWght;
  static const double typeDisplaySmallFontWidth = typeRoleScreenFontWidth;
  static const double typeDisplaySmallLetterSpacing =
      typeRoleScreenLetterSpacing;

  // type.headline
  /// Screen-level headings.
  static const String typeHeadlineLargeFontFamily = typeRoleScreenFontFamily;
  static const List<String> typeHeadlineLargeFontFamilyFallback =
      typeRoleScreenFontFamilyFallback;
  static const double typeHeadlineLargeFontSize = typeRoleScreenFontSize;
  static const double typeHeadlineLargeLineHeight = typeRoleScreenLineHeight;
  static const FontWeight typeHeadlineLargeFontWeight =
      typeRoleScreenFontWeight;
  static const double typeHeadlineLargeWght = typeRoleScreenWght;
  static const double typeHeadlineLargeFontWidth = typeRoleScreenFontWidth;
  static const double typeHeadlineLargeLetterSpacing =
      typeRoleScreenLetterSpacing;

  /// Screen headings on compact widths; pushed screens.
  static const String typeHeadlineMediumFontFamily = typeRoleRoomFontFamily;
  static const List<String> typeHeadlineMediumFontFamilyFallback =
      typeRoleRoomFontFamilyFallback;
  static const double typeHeadlineMediumFontSize = typeRoleRoomFontSize;
  static const double typeHeadlineMediumLineHeight = typeRoleRoomLineHeight;
  static const FontWeight typeHeadlineMediumFontWeight = typeRoleRoomFontWeight;
  static const double typeHeadlineMediumWght = typeRoleRoomWght;
  static const double typeHeadlineMediumFontWidth = typeRoleRoomFontWidth;
  static const double typeHeadlineMediumLetterSpacing =
      typeRoleRoomLetterSpacing;

  /// Detail hero titles, collapsed; sheet titles.
  static const String typeHeadlineSmallFontFamily = typeRoleFeatureFontFamily;
  static const List<String> typeHeadlineSmallFontFamilyFallback =
      typeRoleFeatureFontFamilyFallback;
  static const double typeHeadlineSmallFontSize = typeRoleFeatureFontSize;
  static const double typeHeadlineSmallLineHeight = typeRoleFeatureLineHeight;
  static const FontWeight typeHeadlineSmallFontWeight =
      typeRoleFeatureFontWeight;
  static const double typeHeadlineSmallWght = typeRoleFeatureWght;
  static const double typeHeadlineSmallFontWidth = typeRoleFeatureFontWidth;
  static const double typeHeadlineSmallLetterSpacing =
      typeRoleFeatureLetterSpacing;

  // type.title
  /// Section headers and the app-bar title.
  static const String typeTitleLargeFontFamily = typeRoleSectionFontFamily;
  static const List<String> typeTitleLargeFontFamilyFallback =
      typeRoleSectionFontFamilyFallback;
  static const double typeTitleLargeFontSize = typeRoleSectionFontSize;
  static const double typeTitleLargeLineHeight = typeRoleSectionLineHeight;
  static const FontWeight typeTitleLargeFontWeight = typeRoleSectionFontWeight;
  static const double typeTitleLargeWght = typeRoleSectionWght;
  static const double typeTitleLargeFontWidth = typeRoleSectionFontWidth;
  static const double typeTitleLargeLetterSpacing =
      typeRoleSectionLetterSpacing;

  /// A service's own name in its app bar.
  static const String typeTitleSubtitleFontFamily = typeRoleSectionFontFamily;
  static const List<String> typeTitleSubtitleFontFamilyFallback =
      typeRoleSectionFontFamilyFallback;
  static const double typeTitleSubtitleFontSize = typeRoleSectionFontSize;
  static const double typeTitleSubtitleLineHeight = typeRoleSectionLineHeight;
  static const FontWeight typeTitleSubtitleFontWeight =
      typeRoleSectionFontWeight;
  static const double typeTitleSubtitleWght = typeRoleSectionWght;
  static const double typeTitleSubtitleFontWidth = typeRoleSectionFontWidth;
  static const double typeTitleSubtitleLetterSpacing =
      typeRoleSectionLetterSpacing;

  /// An h2 inside a page: a Dockge stack, an NPM host, a TrueNAS console
  /// section.
  static const String typeTitlePanelHeaderFontFamily =
      typeRoleSectionFontFamily;
  static const List<String> typeTitlePanelHeaderFontFamilyFallback =
      typeRoleSectionFontFamilyFallback;
  static const double typeTitlePanelHeaderFontSize = typeRoleSectionFontSize;
  static const double typeTitlePanelHeaderLineHeight =
      typeRoleSectionLineHeight;
  static const FontWeight typeTitlePanelHeaderFontWeight =
      typeRoleSectionFontWeight;
  static const double typeTitlePanelHeaderWght = typeRoleSectionWght;
  static const double typeTitlePanelHeaderFontWidth = typeRoleSectionFontWidth;
  static const double typeTitlePanelHeaderLetterSpacing =
      typeRoleSectionLetterSpacing;

  /// Card titles. The system has no 16pt title: the slot takes the button
  /// role's values until each site moves to row, section or feature.
  static const String typeTitleMediumFontFamily = typeRoleButtonFontFamily;
  static const List<String> typeTitleMediumFontFamilyFallback =
      typeRoleButtonFontFamilyFallback;
  static const double typeTitleMediumFontSize = typeRoleButtonFontSize;
  static const double typeTitleMediumLineHeight = typeRoleButtonLineHeight;
  static const FontWeight typeTitleMediumFontWeight = typeRoleButtonFontWeight;
  static const double typeTitleMediumWght = typeRoleButtonWght;
  static const double typeTitleMediumFontWidth = typeRoleButtonFontWidth;
  static const double typeTitleMediumLetterSpacing =
      typeRoleButtonLetterSpacing;

  /// The primary line of a row that is a name, not a sentence.
  static const String typeTitleRowTitleFontFamily = typeRoleRowFontFamily;
  static const List<String> typeTitleRowTitleFontFamilyFallback =
      typeRoleRowFontFamilyFallback;
  static const double typeTitleRowTitleFontSize = typeRoleRowFontSize;
  static const double typeTitleRowTitleLineHeight = typeRoleRowLineHeight;
  static const FontWeight typeTitleRowTitleFontWeight = typeRoleRowFontWeight;
  static const double typeTitleRowTitleWght = typeRoleRowWght;
  static const double typeTitleRowTitleFontWidth = typeRoleRowFontWidth;
  static const double typeTitleRowTitleLetterSpacing = typeRoleRowLetterSpacing;

  /// Small titles and dense card headers.
  static const String typeTitleSmallFontFamily = typeRoleLabelFontFamily;
  static const List<String> typeTitleSmallFontFamilyFallback =
      typeRoleLabelFontFamilyFallback;
  static const double typeTitleSmallFontSize = typeRoleLabelFontSize;
  static const double typeTitleSmallLineHeight = typeRoleLabelLineHeight;
  static const FontWeight typeTitleSmallFontWeight = typeRoleLabelFontWeight;
  static const double typeTitleSmallWght = typeRoleLabelWght;
  static const double typeTitleSmallFontWidth = typeRoleLabelFontWidth;
  static const double typeTitleSmallLetterSpacing = typeRoleLabelLetterSpacing;

  // type.body
  /// The widest prose measure: overviews and descriptions.
  static const String typeBodyLargeFontFamily = typeRoleBodyFontFamily;
  static const List<String> typeBodyLargeFontFamilyFallback =
      typeRoleBodyFontFamilyFallback;
  static const double typeBodyLargeFontSize = typeRoleBodyFontSize;
  static const double typeBodyLargeLineHeight = typeRoleBodyLineHeight;
  static const FontWeight typeBodyLargeFontWeight = typeRoleBodyFontWeight;
  static const double typeBodyLargeWght = typeRoleBodyWght;
  static const double typeBodyLargeFontWidth = typeRoleBodyFontWidth;
  static const double typeBodyLargeLetterSpacing = typeRoleBodyLetterSpacing;

  /// Running text, empty-state copy, input text.
  static const String typeBodyMediumFontFamily = typeRoleBodyFontFamily;
  static const List<String> typeBodyMediumFontFamilyFallback =
      typeRoleBodyFontFamilyFallback;
  static const double typeBodyMediumFontSize = typeRoleBodyFontSize;
  static const double typeBodyMediumLineHeight = typeRoleBodyLineHeight;
  static const FontWeight typeBodyMediumFontWeight = typeRoleBodyFontWeight;
  static const double typeBodyMediumWght = typeRoleBodyWght;
  static const double typeBodyMediumFontWidth = typeRoleBodyFontWidth;
  static const double typeBodyMediumLetterSpacing = typeRoleBodyLetterSpacing;

  /// Fine print and secondary lines.
  static const String typeBodySmallFontFamily = typeRoleMetaFontFamily;
  static const List<String> typeBodySmallFontFamilyFallback =
      typeRoleMetaFontFamilyFallback;
  static const double typeBodySmallFontSize = typeRoleMetaFontSize;
  static const double typeBodySmallLineHeight = typeRoleMetaLineHeight;
  static const FontWeight typeBodySmallFontWeight = typeRoleMetaFontWeight;
  static const double typeBodySmallWght = typeRoleMetaWght;
  static const double typeBodySmallFontWidth = typeRoleMetaFontWidth;
  static const double typeBodySmallLetterSpacing = typeRoleMetaLetterSpacing;

  // type.label
  /// The answer in a row: an attention item, a queue entry, a table cell. Never
  /// smaller than the label describing it.
  static const String typeLabelDataFontFamily = typeRoleMetaFontFamily;
  static const List<String> typeLabelDataFontFamilyFallback =
      typeRoleMetaFontFamilyFallback;
  static const double typeLabelDataFontSize = typeRoleMetaFontSize;
  static const double typeLabelDataLineHeight = typeRoleMetaLineHeight;
  static const FontWeight typeLabelDataFontWeight = typeRoleMetaFontWeight;
  static const double typeLabelDataWght = typeRoleMetaWght;
  static const double typeLabelDataFontWidth = typeRoleMetaFontWidth;
  static const double typeLabelDataLetterSpacing = typeRoleMetaLetterSpacing;

  /// Button labels, tab labels, links.
  static const String typeLabelLargeFontFamily = typeRoleLabelFontFamily;
  static const List<String> typeLabelLargeFontFamilyFallback =
      typeRoleLabelFontFamilyFallback;
  static const double typeLabelLargeFontSize = typeRoleLabelFontSize;
  static const double typeLabelLargeLineHeight = typeRoleLabelLineHeight;
  static const FontWeight typeLabelLargeFontWeight = typeRoleLabelFontWeight;
  static const double typeLabelLargeWght = typeRoleLabelWght;
  static const double typeLabelLargeFontWidth = typeRoleLabelFontWidth;
  static const double typeLabelLargeLetterSpacing = typeRoleLabelLetterSpacing;

  /// Captions, badges.
  static const String typeLabelMediumFontFamily = typeRoleCaptionFontFamily;
  static const List<String> typeLabelMediumFontFamilyFallback =
      typeRoleCaptionFontFamilyFallback;
  static const double typeLabelMediumFontSize = typeRoleCaptionFontSize;
  static const double typeLabelMediumLineHeight = typeRoleCaptionLineHeight;
  static const FontWeight typeLabelMediumFontWeight = typeRoleCaptionFontWeight;
  static const double typeLabelMediumWght = typeRoleCaptionWght;
  static const double typeLabelMediumFontWidth = typeRoleCaptionFontWidth;
  static const double typeLabelMediumLetterSpacing =
      typeRoleCaptionLetterSpacing;

  /// The 11px floor. Nothing in the app renders smaller.
  static const String typeLabelSmallFontFamily = typeRoleMicroFontFamily;
  static const List<String> typeLabelSmallFontFamilyFallback =
      typeRoleMicroFontFamilyFallback;
  static const double typeLabelSmallFontSize = typeRoleMicroFontSize;
  static const double typeLabelSmallLineHeight = typeRoleMicroLineHeight;
  static const FontWeight typeLabelSmallFontWeight = typeRoleMicroFontWeight;
  static const double typeLabelSmallWght = typeRoleMicroWght;
  static const double typeLabelSmallFontWidth = typeRoleMicroFontWidth;
  static const double typeLabelSmallLetterSpacing = typeRoleMicroLetterSpacing;

  /// Dense desktop-shell chrome. Its size is both the default and the enforced
  /// floor.
  static const String typeLabelChromeFontFamily = typeRoleMicroFontFamily;
  static const List<String> typeLabelChromeFontFamilyFallback =
      typeRoleMicroFontFamilyFallback;
  static const double typeLabelChromeFontSize = typeRoleMicroFontSize;
  static const double typeLabelChromeLineHeight = typeRoleMicroLineHeight;
  static const FontWeight typeLabelChromeFontWeight = typeRoleMicroFontWeight;
  static const double typeLabelChromeWght = typeRoleMicroWght;
  static const double typeLabelChromeFontWidth = typeRoleMicroFontWidth;
  static const double typeLabelChromeLetterSpacing = typeRoleMicroLetterSpacing;
}

/// The Dark theme's semantic tokens, from `design/tokens/theme/dark.json`.
abstract final class DesignTokensDark {
  // color.room
  /// The floor.
  static const Color colorRoomGround = Color(0xFF0A0A0D);

  /// A section (with a line.hair edge), a card, grouped rows.
  static const Color colorRoomSlab = Color(0xFF121218);

  /// Sheets and dialogs.
  static const Color colorRoomRaised = Color(0xFF17171D);

  /// Discover's doors, tiles.
  static const Color colorRoomDoor = Color(0xFF16161C);

  /// Floating bars (tab, rail, compact bar, selection), at the glass opacity:
  /// lit enamel, never a live blur.
  static const Color colorRoomEnamel = Color(0xFF1A1A1F);

  /// Popover menus.
  static const Color colorRoomMenu = Color(0xFF1D1D24);

  /// A toast.
  static const Color colorRoomToast = Color(0xFF202028);

  /// Behind sheets and dialogs: the ground at 70%.
  static const Color colorRoomScrim = Color(0xB30A0A0D);

  // color.line
  /// A slab's edge, a divider.
  static const Color colorLineHair = Color(0x12FFFFFF);

  /// A control's edge, a field at rest.
  static const Color colorLineEdge = Color(0x1AFFFFFF);

  /// The focus ring and a focused field.
  static const Color colorLineFocus = Color(0xB8FFFFFF);

  // color.fill
  /// Chips at rest, fields, the segmented track.
  static const Color colorFillQuiet = Color(0x0FFFFFFF);

  /// Ghost buttons, icon buttons, steppers.
  static const Color colorFillControl = Color(0x14FFFFFF);

  /// The selected tab pill, a switch track at rest.
  static const Color colorFillStrong = Color(0x1FFFFFFF);

  /// A progress track.
  static const Color colorFillTrack = Color(0x1FFFFFFF);

  /// A skeleton block at rest: 8% white, so it reads on the ground, a slab and
  /// a lit header alike.
  static const Color colorFillSkeleton = Color(0x14FFFFFF);

  /// The band that sweeps a skeleton: brighter than the block, like light
  /// passing over it.
  static const Color colorFillSkeletonGlint = Color(0x24FFFFFF);

  // color.ink
  /// Primary text and the ink button.
  static const Color colorInkPrimary = Color(0xFFF7F6F2);

  /// Secondary text.
  static const Color colorInkSecondary = Color(0xB8FFFFFF);

  /// Tertiary text: still at least 4.5:1 on a slab.
  static const Color colorInkTertiary = Color(0x99FFFFFF);

  /// Disabled text.
  static const Color colorInkDisabled = Color(0x61FFFFFF);

  /// Text on the ink button and on a bright fill.
  static const Color colorInkOnInk = DesignTokens.colorInkOnBright;

  // color.tone
  /// GREEN: available, complete, healthy.
  static const Color colorToneGreen = DesignTokens.colorStatusSuccess;

  /// The green dot.
  static const Color colorToneGreenDot = Color(0xFF34D17F);

  /// AMBER: a fault.
  static const Color colorToneAmber = DesignTokens.colorStatusWarning;

  /// Text on the amber remedy fill.
  static const Color colorToneAmberInk = Color(0xFF2A1E00);

  /// The remedy button's fill.
  static const Color colorToneAmberFill = DesignTokens.colorStatusWarning;

  /// A fault chip's wash.
  static const Color colorToneAmberWash = Color(0x1FF7C23A);

  /// RED: unreachable, and nothing else.
  static const Color colorToneRed = DesignTokens.colorStatusError;

  /// The red dot.
  static const Color colorToneRedDot = Color(0xFFFF6B5B);

  /// BLUE: queued, in progress, informational.
  static const Color colorToneBlue = DesignTokens.colorStatusInfo;

  /// NEUTRAL: the backlog, drawn with a hollow dot.
  static const Color colorToneNeutral = Color(0xB8FFFFFF);

  // color
  /// The interactive ink: the ink button, text-button labels, the selected
  /// control, focus, progress. The chrome is monochrome.
  static const Color colorPrimary = colorInkPrimary;

  /// Label on the ink button.
  static const Color colorOnPrimary = colorInkOnInk;

  /// The fill.strong, flattened on the ground so contrast is measurable. The
  /// nav indicator.
  static const Color colorPrimaryContainer = Color(0xFF28282A);

  /// Text on the primary container.
  static const Color colorOnPrimaryContainer = colorInkPrimary;

  /// The ink.secondary, flattened on the ground so contrast is measurable.
  static const Color colorSecondary = Color(0xFFBBBBBC);

  /// Label on a secondary fill.
  static const Color colorOnSecondary = colorInkOnInk;

  /// The fill.strong, flattened on the ground so contrast is measurable. A
  /// tonal (ghost) button, a selected segment in Material widgets.
  static const Color colorSecondaryContainer = Color(0xFF28282A);

  /// Label on the secondary container.
  static const Color colorOnSecondaryContainer = colorInkPrimary;

  /// The green tone as a scheme role.
  static const Color colorTertiary = colorToneGreen;

  /// Label on a green fill.
  static const Color colorOnTertiary = colorInkOnInk;

  /// Filled status surface for green: the deep green.
  static const Color colorTertiaryContainer =
      DesignTokens.colorStatusSuccessContainer;

  /// Text on the green container: 5.4:1.
  static const Color colorOnTertiaryContainer = DesignTokens.colorBaseWhite;

  /// The unreachable tone as a scheme role.
  static const Color colorError = colorToneRed;

  /// Label on a red fill: dark ink measures 8.6:1, white 2.3:1.
  static const Color colorOnError = colorInkOnInk;

  /// Filled status surface for red: the deep red.
  static const Color colorErrorContainer =
      DesignTokens.colorStatusErrorContainer;

  /// Text on the red container: 5.95:1.
  static const Color colorOnErrorContainer = DesignTokens.colorBaseWhite;

  /// The floor: the scaffold behind every screen.
  static const Color colorSurface = colorRoomGround;

  /// Primary text and icons on every surface.
  static const Color colorOnSurface = colorInkPrimary;

  /// Recessed wells such as log panels: nothing sits below the floor.
  static const Color colorSurfaceContainerLowest = colorRoomGround;

  /// Grouped-list backgrounds: a slab.
  static const Color colorSurfaceContainerLow = colorRoomSlab;

  /// Cards, KPI tiles, panels: a slab.
  static const Color colorSurfaceContainer = colorRoomSlab;

  /// Sheets, dialogs, secondary panels: raised.
  static const Color colorSurfaceContainerHigh = colorRoomRaised;

  /// Input and chip fill, popovers: the menu step.
  static const Color colorSurfaceContainerHighest = colorRoomMenu;

  /// The ink.secondary, flattened on the ground so contrast is measurable.
  /// Metadata, chip labels, hints.
  static const Color colorOnSurfaceVariant = Color(0xFFBBBBBC);

  /// The ink.tertiary, flattened on the ground so contrast is measurable.
  /// Captions and tertiary metadata; 6.2:1 on the menu step.
  static const Color colorDimText = Color(0xFF9D9D9E);

  /// The line.edge, flattened on the ground so contrast is measurable. Outlined
  /// controls.
  static const Color colorOutline = Color(0xFF232326);

  /// The line.hair, flattened on the ground so contrast is measurable.
  /// Dividers, a slab's edge.
  static const Color colorOutlineVariant = Color(0xFF1B1B1E);

  /// The ink every elevation level paints its shadow in.
  static const Color colorShadow = DesignTokens.colorBaseBlack;

  /// Modal barrier base and hero scrims.
  static const Color colorScrim = DesignTokens.colorBaseBlack;

  /// The toast (snackbar) fill: the toast stays in the room.
  static const Color colorInverseSurface = colorRoomToast;

  /// Toast text.
  static const Color colorOnInverseSurface = colorInkPrimary;

  /// The ink on the toast.
  static const Color colorInversePrimary = colorInkPrimary;

  // opacity
  /// Opacity of the enamel in the floating bars: lit enamel, a tint and never a
  /// backdrop blur.
  static const double opacityGlassSurface = 0.95;

  /// Centre of the lamp: the light hung at the top of a room no title leads,
  /// and of a lit room until its picture comes up.
  static const double opacityAmbientGlow = 0.42;

  // elevation.level-1
  /// Level-1 contact: flat in the dark room.
  static const double elevationLevel1Contact = 0;

  /// Level-1 ambient: flat in the dark room.
  static const double elevationLevel1Ambient = 0;

  // elevation.level-2
  /// Level-2 contact.
  static const double elevationLevel2Contact = 0.6;

  /// Level-2 ambient (the poster geometry, in the shadow ink).
  static const double elevationLevel2Ambient = 0.8;

  // elevation.level-3
  /// Level-3 contact.
  static const double elevationLevel3Contact = 0.6;

  /// Level-3 ambient (the float).
  static const double elevationLevel3Ambient = 0.6;

  // elevation.glass
  /// The bar's float shadow.
  static const double elevationGlassAmbient = 0.6;

  /// The bar's 1px edge light (#FFFFFF14).
  static const double elevationGlassHighlight = 0.08;

  // elevation.poster
  /// A poster's glow: its light at 80%.
  static const double elevationPosterGlow = 0.8;

  /// A poster under the pointer: its light at full strength.
  static const double elevationPosterLifted = 1;

  // elevation.hero
  /// The hero's glow: its light at 48%.
  static const double elevationHeroGlow = 0.48;

  /// The hero's contact shadow.
  static const double elevationHeroContact = 0.6;

  // elevation.float
  /// The float shadow.
  static const double elevationFloatDrop = 0.6;

  // elevation.sheet
  /// The sheet shadow.
  static const double elevationSheetDrop = 0.5;
}

/// The Light theme's semantic tokens, from `design/tokens/theme/light.json`.
abstract final class DesignTokensLight {
  // color.room
  /// Paper: the floor of the day room.
  static const Color colorRoomGround = Color(0xFFF6F4EF);

  /// A section (with a line.hair edge and a soft shadow), a card.
  static const Color colorRoomSlab = Color(0xFFFFFFFF);

  /// Sheets and dialogs.
  static const Color colorRoomRaised = Color(0xFFFFFFFF);

  /// Doors and tiles (the day room has no separate door).
  static const Color colorRoomDoor = Color(0xFFFFFFFF);

  /// Floating bars, at the glass opacity.
  static const Color colorRoomEnamel = Color(0xFFFFFFFF);

  /// Popover menus (derived: the day room lifts menus by shadow, not by tone).
  static const Color colorRoomMenu = Color(0xFFFFFFFF);

  /// A toast: the ink, reversed (derived).
  static const Color colorRoomToast = Color(0xFF16151A);

  /// Behind sheets and dialogs: the ink at 40%.
  static const Color colorRoomScrim = Color(0x6616151A);

  // color.line
  /// A slab's edge, a divider.
  static const Color colorLineHair = Color(0x0F000000);

  /// A control's edge, a field at rest.
  static const Color colorLineEdge = Color(0x1A16151A);

  /// The focus ring and a focused field (derived: secondary ink).
  static const Color colorLineFocus = Color(0xB316151A);

  // color.fill
  /// Chips at rest, fields, the segmented track.
  static const Color colorFillQuiet = Color(0x0D16151A);

  /// Ghost buttons, icon buttons, steppers (derived: 8% ink).
  static const Color colorFillControl = Color(0x1416151A);

  /// The selected tab pill (derived: 12% ink).
  static const Color colorFillStrong = Color(0x1F16151A);

  /// A progress track (derived: 12% ink).
  static const Color colorFillTrack = Color(0x1F16151A);

  /// A skeleton block at rest: 8% ink, so it reads on the ground, a slab and a
  /// lit header alike.
  static const Color colorFillSkeleton = Color(0x1416151A);

  /// The band that sweeps a skeleton: brighter than the block, like light
  /// passing over it.
  static const Color colorFillSkeletonGlint = Color(0x8CFFFFFF);

  // color.ink
  /// Primary text and the ink button.
  static const Color colorInkPrimary = Color(0xFF16151A);

  /// Secondary text.
  static const Color colorInkSecondary = Color(0xB316151A);

  /// Tertiary text: 5.4:1 on paper.
  static const Color colorInkTertiary = Color(0xA616151A);

  /// Disabled text (derived: 38% ink).
  static const Color colorInkDisabled = Color(0x6116151A);

  /// Text on the ink button: white.
  static const Color colorInkOnInk = DesignTokens.colorBaseWhite;

  // color.tone
  /// GREEN: available, complete, healthy.
  static const Color colorToneGreen = Color(0xFF0F7A45);

  /// The green dot (derived: the tone itself).
  static const Color colorToneGreenDot = Color(0xFF0F7A45);

  /// AMBER: a fault.
  static const Color colorToneAmber = Color(0xFF8F5E00);

  /// Text on the amber remedy fill.
  static const Color colorToneAmberInk = Color(0xFF2A1E00);

  /// The remedy button's fill.
  static const Color colorToneAmberFill = Color(0xFFF2B531);

  /// A fault chip's wash (derived: the remedy fill at 18%).
  static const Color colorToneAmberWash = Color(0x2EF2B531);

  /// RED: unreachable, and nothing else.
  static const Color colorToneRed = Color(0xFFB8322A);

  /// The red dot (derived: the tone itself).
  static const Color colorToneRedDot = Color(0xFFB8322A);

  /// BLUE: queued, in progress, informational.
  static const Color colorToneBlue = Color(0xFF2F5BD3);

  /// NEUTRAL: the backlog, drawn with a hollow dot.
  static const Color colorToneNeutral = Color(0xA616151A);

  // color
  /// The interactive ink: the ink button, text-button labels, the selected
  /// control, focus, progress.
  static const Color colorPrimary = colorInkPrimary;

  /// Label on the ink button: white.
  static const Color colorOnPrimary = colorInkOnInk;

  /// The fill, flattened on the ground so contrast is measurable. The nav
  /// indicator.
  static const Color colorPrimaryContainer = Color(0xFFEBE9E4);

  /// Text on the primary container.
  static const Color colorOnPrimaryContainer = colorInkPrimary;

  /// The ink-2, flattened on the ground so contrast is measurable.
  static const Color colorSecondary = Color(0xFF595759);

  /// Label on a secondary fill.
  static const Color colorOnSecondary = DesignTokens.colorBaseWhite;

  /// The line.edge, flattened on the ground so contrast is measurable. A tonal
  /// (ghost) button, a selected segment in Material widgets.
  static const Color colorSecondaryContainer = Color(0xFFDFDDD9);

  /// Label on the secondary container.
  static const Color colorOnSecondaryContainer = colorInkPrimary;

  /// The green tone as a scheme role.
  static const Color colorTertiary = colorToneGreen;

  /// Label on a green fill: 5.4:1.
  static const Color colorOnTertiary = DesignTokens.colorBaseWhite;

  /// Filled status surface for green: the tone at 10% on white.
  static const Color colorTertiaryContainer = Color(0xFFE7F2EC);

  /// Text on the green container: 4.7:1.
  static const Color colorOnTertiaryContainer = colorToneGreen;

  /// The unreachable tone as a scheme role.
  static const Color colorError = colorToneRed;

  /// Label on a red fill: 5.95:1.
  static const Color colorOnError = DesignTokens.colorBaseWhite;

  /// Filled status surface for red: the tone at 10% on white.
  static const Color colorErrorContainer = Color(0xFFF8EAEA);

  /// Text on the red container: 5.1:1.
  static const Color colorOnErrorContainer = colorToneRed;

  /// Paper: the scaffold behind every screen.
  static const Color colorSurface = colorRoomGround;

  /// Primary text and icons on every surface.
  static const Color colorOnSurface = colorInkPrimary;

  /// White.
  static const Color colorSurfaceContainerLowest = colorRoomSlab;

  /// Grouped-list backgrounds: paper.
  static const Color colorSurfaceContainerLow = colorRoomGround;

  /// Cards and KPI tiles: a white slab.
  static const Color colorSurfaceContainer = colorRoomSlab;

  /// The fill, flattened on the ground so contrast is measurable. (on a slab)
  /// Secondary panels.
  static const Color colorSurfaceContainerHigh = Color(0xFFF3F3F3);

  /// The fill, flattened on the ground so contrast is measurable. Input and
  /// chip fill.
  static const Color colorSurfaceContainerHighest = Color(0xFFEBE9E4);

  /// The ink-2, flattened on the ground so contrast is measurable. 5.9:1 on the
  /// chip fill.
  static const Color colorOnSurfaceVariant = Color(0xFF595759);

  /// The ink-3, flattened on the ground so contrast is measurable. 4.9:1 on the
  /// chip fill.
  static const Color colorDimText = Color(0xFF646364);

  /// The line.edge, flattened on the ground so contrast is measurable.
  static const Color colorOutline = Color(0xFFDFDDD9);

  /// The line.hair, flattened on the ground so contrast is measurable.
  static const Color colorOutlineVariant = Color(0xFFE8E6E1);

  /// The ink every elevation level paints its shadow in: ink, not black, so a
  /// shadow reads as depth on paper.
  static const Color colorShadow = colorInkPrimary;

  /// Modal barrier base and hero scrims.
  static const Color colorScrim = DesignTokens.colorBaseBlack;

  /// The toast (snackbar) fill.
  static const Color colorInverseSurface = colorRoomToast;

  /// Toast text.
  static const Color colorOnInverseSurface = colorRoomGround;

  /// The ink on the toast.
  static const Color colorInversePrimary = colorRoomGround;

  // opacity
  /// Opacity of the enamel in the floating bars: lit enamel, a tint and never a
  /// backdrop blur.
  static const double opacityGlassSurface = 0.95;

  /// Centre of the lamp: the light hung at the top of a room no title leads,
  /// and of a lit room until its picture comes up.
  static const double opacityAmbientGlow = 0.14;

  // elevation.level-1
  /// Level-1 contact: the soft lift of a slab on paper.
  static const double elevationLevel1Contact = 0.06;

  /// Level-1 ambient.
  static const double elevationLevel1Ambient = 0.04;

  // elevation.level-2
  /// Level-2 contact.
  static const double elevationLevel2Contact = 0.08;

  /// Level-2 ambient.
  static const double elevationLevel2Ambient = 0.05;

  // elevation.level-3
  /// Level-3 contact.
  static const double elevationLevel3Contact = 0.1;

  /// Level-3 ambient.
  static const double elevationLevel3Ambient = 0.07;

  // elevation.glass
  /// The bar's float shadow.
  static const double elevationGlassAmbient = 0.18;

  /// The bar's 1px edge light.
  static const double elevationGlassHighlight = 0.55;

  // elevation.poster
  /// A poster's glow (derived: the day room's light opacity).
  static const double elevationPosterGlow = 0.35;

  /// A poster under the pointer (derived: the poster's glow, half again).
  static const double elevationPosterLifted = 0.5;

  // elevation.hero
  /// The hero's glow (derived).
  static const double elevationHeroGlow = 0.35;

  /// The hero's contact shadow (derived).
  static const double elevationHeroContact = 0.1;

  // elevation.float
  /// The float shadow (derived).
  static const double elevationFloatDrop = 0.18;

  // elevation.sheet
  /// The sheet shadow (derived).
  static const double elevationSheetDrop = 0.12;
}
