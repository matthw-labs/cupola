import 'package:flutter/material.dart';
import 'package:cupola/core/app_radius.dart';
import 'package:cupola/core/focus_ring.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/text_scale.dart';
import 'package:cupola/core/widgets/themed_system_bars.dart';

/// Builds a [TextStyle] for one role of the type system.
///
/// Every style goes through here so that the variable axes are impossible to
/// forget. The three bundled families are each one variable file registered
/// once, and Flutter resolves `fontWeight` against that single face without
/// touching an axis, so a bare [TextStyle] renders the file's default instance
/// whatever it asks for; for Bricolage Grotesque that instance is 96pt
/// ExtraBold at full width. See [AppTheme.variations].
TextStyle _role({
  Color? color,
  required String family,
  required List<String> fallback,
  required double fontSize,
  required FontWeight fontWeight,
  required double wght,
  required double height,
  required double letterSpacing,
  double width = 100,
  List<FontFeature>? fontFeatures,
}) {
  return TextStyle(
    fontFamily: family,
    fontFamilyFallback: fallback.isEmpty ? null : fallback,
    color: color,
    fontSize: fontSize,
    fontWeight: fontWeight,
    fontVariations: AppTheme.variations(
      family,
      wght: wght,
      width: width,
      fontSize: fontSize,
    ),
    height: height,
    letterSpacing: letterSpacing,
    fontFeatures: fontFeatures,
  );
}

/// Type-level helpers that have to reach the variable axes.
///
/// These exist because [TextStyle.copyWith] is a trap on a variable font: it
/// will happily change [TextStyle.fontWeight] and leave `fontVariations`
/// pointing at the old weight, so the text keeps rendering at the weight it
/// had. Re-weight through [weight] instead.
extension CupolaTextStyle on TextStyle {
  /// Re-weights this style so the change actually reaches the `wght` axis.
  ///
  /// Each bundled family is a single variable face. Flutter resolves
  /// `fontWeight: FontWeight.w600` against that one face, finds it, and never
  /// touches the axis, so the glyphs stay at the default instance and the only
  /// difference is whatever synthetic emboldening Skia decides to add.
  ///
  /// Only `wght` moves: the width and the optical size a display role set are
  /// carried over, so re-weighting a Bricolage title does not hand it back the
  /// file's full-width, 96pt drawing.
  TextStyle weight(FontWeight weight) {
    final kept = [
      for (final variation in fontVariations ?? const <FontVariation>[])
        if (variation.axis != 'wght') variation,
    ];
    return copyWith(
      fontWeight: weight,
      fontVariations: [FontVariation('wght', weight.value.toDouble()), ...kept],
    );
  }

  /// Locks digits to a single advance width.
  ///
  /// The Tabular Rule: anything that updates in place (a transfer rate, a
  /// percentage, a queue count) jitters as it counts with proportional digits.
  /// All three families carry `tnum`.
  TextStyle get tabular =>
      copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// Switches a style onto the mono family, for machine strings only: release
  /// names, paths, hashes, keys, logs, exactly as returned, and the legend of a
  /// physical key. **Never for a figure**: a size, a rate, a percentage, a
  /// clock or a count stays in the text face and takes [tabular] there.
  /// `test/core/theme/mono_face_guard_test.dart` lists every use and why.
  ///
  /// Keeps the size, colour and line height it already had: a fingerprint or a
  /// log line still belongs to the role it was set in, it just needs columns
  /// that line up. It takes the mono role's own drawing: `wght` 450 (or the
  /// style's weight, if that was heavier) and the mono role's tracking in em,
  /// so the grid stays the one the face was spaced on. See
  /// [AppTheme.monoFontFamily] for the fallbacks after Geist Mono.
  TextStyle get mono {
    final size = fontSize ?? DesignTokens.typeRoleMonoFontSize;
    final own = fontWeight?.value.toDouble() ?? 400;
    final wght = own > DesignTokens.typeRoleMonoWght
        ? own
        : DesignTokens.typeRoleMonoWght;
    return copyWith(
      fontFamily: AppTheme.monoFontFamily,
      fontFamilyFallback: AppTheme.monoFontFamilyFallback,
      fontVariations: [FontVariation('wght', wght)],
      letterSpacing:
          DesignTokens.typeRoleMonoLetterSpacing /
          DesignTokens.typeRoleMonoFontSize *
          size,
      fontFeatures: const [FontFeature.slashedZero()],
    );
  }
}

/// The fixed palette: service accents, the tones as fill bytes, the plate and
/// the per-theme scheme bytes, all read from the generated tokens.
///
/// The room is monochrome. Colour reaches the interface from two sources only,
/// the content (a title's light) and the state (the five tones), so nothing in
/// the chrome carries a hue of its own: the interactive ink is the primary ink,
/// a room with no artwork is lit by the [lamp], and a service's accent is
/// registry data that no pixel is painted with.
class AppColors {
  AppColors._();

  // === SERVICE ACCENTS ===
  //
  // Registry data (`ServiceKey.brandAccent`), never paint: the interface paints
  // every service with the [lamp] (`ServiceKey.accent`), and a service's mark,
  // tab, room and buttons are monochrome. Outside this class and the registry
  // they may be read only where a colour is the information itself: see
  // `test/core/theme/monochrome_accent_test.dart`.
  static const Color seerr = DesignTokens.colorServiceSeerr;
  static const Color radarr = DesignTokens.colorServiceRadarr;
  static const Color sonarr = DesignTokens.colorServiceSonarr;
  static const Color lidarr = DesignTokens.colorServiceLidarr;
  static const Color qbittorrent = DesignTokens.colorServiceQbittorrent;
  static const Color bazarr = DesignTokens.colorServiceBazarr;
  static const Color truenas = DesignTokens.colorServiceTruenas; // TrueNAS blue
  static const Color dockge = DesignTokens.colorServiceDockge; // Dockge teal
  static const Color prowlarr =
      DesignTokens.colorServiceProwlarr; // Prowlarr orange
  static const Color readarr = DesignTokens.colorServiceReadarr; // Readarr red
  static const Color sabnzbd =
      DesignTokens.colorServiceSabnzbd; // SABnzbd amber/gold
  static const Color nzbget = DesignTokens.colorServiceNzbget; // NZBGet green
  static const Color unraid = DesignTokens.colorServiceUnraid; // Unraid orange
  static const Color jellyfin =
      DesignTokens.colorServiceJellyfin; // Jellyfin purple

  /// Transmission crimson: the brand's red family, walked off its own hex for
  /// the same reason [plex] is walked off Plex gold.
  ///
  /// Transmission's mark is a plain red that lands ΔE 5.3 from [readarr]: two
  /// near-identical reds, and at the 8pt source dot on the merged Recently
  /// Added rail, and at the 18pt glyph on a folded matrix cell, that is not a
  /// distinguishable colour. Rotating toward crimson keeps it unmistakably
  /// Transmission red while clearing ΔE 10.8 from Readarr.
  static const Color transmission = DesignTokens.colorServiceTransmission;

  /// Nginx Proxy Manager vermilion: the brand value, used unchanged.
  ///
  /// Unlike [transmission] and [plex] this one needed no adjustment: it sits
  /// ΔE 9.2 from [prowlarr]'s orange, because it is a *red*-orange and the
  /// crowded band above it ([unraid], [plex], [radarr], [sabnzbd]) is amber.
  static const Color nginxProxyManager =
      DesignTokens.colorServiceNginxProxyManager;

  /// Plex bronze: deliberately **not** Plex's brand gold `#E5A00D`.
  ///
  /// In CIE Lab brand gold sits ΔE 5 from [sabnzbd], so the 8pt source dot on
  /// the merged Recently Added rail could not tell a Plex item from a SABnzbd
  /// one. This value keeps the brand's hue family (34° against the brand's 41°,
  /// so it still reads as Plex gold) while clearing ΔE 18 from every other
  /// amber. As a label it still goes through `ServiceTheme.onTint`.
  static const Color plex = DesignTokens.colorServicePlex;

  /// Emby green: the brand value, used unchanged. Registry data like the rest
  /// of the class; the interface never paints with it.
  static const Color emby = DesignTokens.colorServiceEmby;

  /// Tracearr cyan: the brand value, used unchanged. Registry data like the
  /// rest of the class; the interface never paints with it.
  static const Color tracearr = DesignTokens.colorServiceTracearr;

  // === DARK THEME SURFACES ===
  //
  // The dark room's floor and its steps: ground, slab, raised, menu.
  static const Color surfaceDark = DesignTokensDark.colorSurface; // room ground
  static const Color surfaceContainerLowestDark =
      DesignTokensDark.colorSurfaceContainerLowest;
  static const Color surfaceContainerDark =
      DesignTokensDark.colorSurfaceContainer;
  static const Color surfaceContainerHighDark =
      DesignTokensDark.colorSurfaceContainerHigh;

  // === LIGHT THEME SURFACES ===
  static const Color surfaceLight = DesignTokensLight.colorSurface;

  // === PLATE (artwork stand-ins) ===
  //
  // The one region of the app that does **not** follow the theme. A plate
  // stands in for artwork: a poster that has not loaded, an album with no
  // cover, the letterboxed well a backdrop sits in, and artwork is not
  // palette. A missing poster rendered as a white rectangle on the light theme
  // does not read as "art that is not here yet", it reads as a hole in the
  // layout; and the instant the real image arrives the well flips from white to
  // a dark photograph, which is the flash the plate exists to prevent.
  //
  // So these are the dark room's own bytes, painted in both brightnesses.
  static const Color plateSurface = DesignTokens.colorPlateSurface;
  static const Color plateWell = DesignTokens.colorPlateWell;
  static const Color plateOutline = DesignTokens.colorPlateOutline;
  static const Color plateInk = DesignTokens.colorPlateInk;

  /// The plate's secondary ink: the tertiary ink flattened on the ground,
  /// 6.6:1 on [plateSurface] and 7.3:1 on [plateWell].
  static const Color plateDimInk = DesignTokens.colorPlateDimInk;

  // === TEXT COLORS - DARK ===
  //
  // The room's inks are white at 72 and 60%; the scheme carries them flattened
  // on the ground so that a contrast can be measured against any surface.
  static const Color onSurfaceVariantDark =
      DesignTokensDark.colorOnSurfaceVariant; // secondary ink
  static const Color onSurfaceDimDark =
      DesignTokensDark.colorDimText; // tertiary ink

  // === TEXT COLORS - LIGHT ===
  //
  // Spaced against the **worst paper surface the theme actually paints text
  // on**, not against the scaffold: the chip and input fill
  // (`surfaceContainerHighest`) carries `onSurfaceVariant` as its label. On it
  // the secondary ink measures 5.9:1 and the tertiary 4.9:1.
  static const Color onSurfaceDimLight =
      DesignTokensLight.colorDimText; // 4.9:1 worst

  // === OUTLINE / BORDER ===

  // === SEMANTIC COLORS ===
  //
  // The dark room's tone bytes. The day room has its own set (see
  // [CupolaRoom.toneGreen] and its siblings); `statusToneFill` and
  // `statusToneColor` pick the one for the theme they are handed, and nothing
  // paints these raw.
  static const Color success = DesignTokens.colorStatusSuccess;
  static const Color successContainer =
      DesignTokens.colorStatusSuccessContainer;

  /// The fault tone: a yellow amber, and deliberately not Radarr's amber-500.
  ///
  /// The tone rule rests on amber meaning "something is wrong", so a fault chip
  /// and a service accent that cannot be told apart would break it on every
  /// Radarr surface. Measured in CIE Lab this value sits ΔE2000 11.6 (12° of
  /// LCh hue) from [radarr] and 7.4 from [sabnzbd]: near enough that the
  /// accents left the interface altogether: nothing but a fault is amber.
  static const Color warning = DesignTokens.colorStatusWarning;
  static const Color error = DesignTokens.colorStatusError;
  static const Color errorContainer = DesignTokens.colorStatusErrorContainer;
  static const Color info = DesignTokens.colorStatusInfo;

  /// The neutral lamp: the light of a room with no artwork, and of a title
  /// whose artwork has too little colour to light anything. Never a service's
  /// colour.
  static const Color lamp = DesignTokens.colorTitleLightFallback;
}

/// The room's own vocabulary, for the theme in use: its steps, lines, fills,
/// inks and the five tones as the room draws them.
///
/// The colour scheme carries the opaque steps and the inks flattened on the
/// ground, which is what the contrast machinery measures. This carries the
/// room as drawn: translucent lines, fills and inks that sit on whatever step
/// they land on, for the surfaces built on it.
@immutable
class CupolaRoom extends ThemeExtension<CupolaRoom> {
  const CupolaRoom({
    required this.ground,
    required this.slab,
    required this.raised,
    required this.door,
    required this.enamel,
    required this.menu,
    required this.toast,
    required this.scrim,
    required this.hair,
    required this.edge,
    required this.focus,
    required this.fillQuiet,
    required this.fillControl,
    required this.fillStrong,
    required this.fillTrack,
    required this.fillSkeleton,
    required this.fillSkeletonGlint,
    required this.ink,
    required this.inkSecondary,
    required this.inkTertiary,
    required this.inkDisabled,
    required this.onInk,
    required this.toneGreen,
    required this.toneGreenDot,
    required this.toneAmber,
    required this.toneAmberInk,
    required this.toneAmberFill,
    required this.toneAmberWash,
    required this.toneRed,
    required this.toneRedDot,
    required this.toneBlue,
    required this.toneNeutral,
    required this.lamp,
  });

  /// The floor.
  final Color ground;

  /// A section, a card, grouped rows.
  final Color slab;

  /// Sheets and dialogs.
  final Color raised;

  /// Doors and tiles.
  final Color door;

  /// Floating bars, at [DesignTokensDark.opacityGlassSurface]: lit enamel,
  /// never a live blur.
  final Color enamel;

  /// Popover menus.
  final Color menu;

  /// A toast.
  final Color toast;

  /// Behind sheets and dialogs.
  final Color scrim;

  /// A slab's edge, a divider.
  final Color hair;

  /// A control's edge.
  final Color edge;

  /// The focus ring.
  final Color focus;

  final Color fillQuiet;
  final Color fillControl;
  final Color fillStrong;
  final Color fillTrack;

  /// A skeleton block at rest, and the band that sweeps it: an alpha of the
  /// room's ink and a brighter one, so the block reads on any ground and the
  /// sweep passes as light, in both rooms.
  final Color fillSkeleton;
  final Color fillSkeletonGlint;

  /// Primary text and the ink button.
  final Color ink;
  final Color inkSecondary;
  final Color inkTertiary;
  final Color inkDisabled;

  /// Text on the ink button.
  final Color onInk;

  final Color toneGreen;
  final Color toneGreenDot;
  final Color toneAmber;
  final Color toneAmberInk;
  final Color toneAmberFill;
  final Color toneAmberWash;
  final Color toneRed;
  final Color toneRedDot;
  final Color toneBlue;
  final Color toneNeutral;

  /// The neutral lamp.
  final Color lamp;

  static const CupolaRoom dark = CupolaRoom(
    ground: DesignTokensDark.colorRoomGround,
    slab: DesignTokensDark.colorRoomSlab,
    raised: DesignTokensDark.colorRoomRaised,
    door: DesignTokensDark.colorRoomDoor,
    enamel: DesignTokensDark.colorRoomEnamel,
    menu: DesignTokensDark.colorRoomMenu,
    toast: DesignTokensDark.colorRoomToast,
    scrim: DesignTokensDark.colorRoomScrim,
    hair: DesignTokensDark.colorLineHair,
    edge: DesignTokensDark.colorLineEdge,
    focus: DesignTokensDark.colorLineFocus,
    fillQuiet: DesignTokensDark.colorFillQuiet,
    fillControl: DesignTokensDark.colorFillControl,
    fillStrong: DesignTokensDark.colorFillStrong,
    fillTrack: DesignTokensDark.colorFillTrack,
    fillSkeleton: DesignTokensDark.colorFillSkeleton,
    fillSkeletonGlint: DesignTokensDark.colorFillSkeletonGlint,
    ink: DesignTokensDark.colorInkPrimary,
    inkSecondary: DesignTokensDark.colorInkSecondary,
    inkTertiary: DesignTokensDark.colorInkTertiary,
    inkDisabled: DesignTokensDark.colorInkDisabled,
    onInk: DesignTokensDark.colorInkOnInk,
    toneGreen: DesignTokensDark.colorToneGreen,
    toneGreenDot: DesignTokensDark.colorToneGreenDot,
    toneAmber: DesignTokensDark.colorToneAmber,
    toneAmberInk: DesignTokensDark.colorToneAmberInk,
    toneAmberFill: DesignTokensDark.colorToneAmberFill,
    toneAmberWash: DesignTokensDark.colorToneAmberWash,
    toneRed: DesignTokensDark.colorToneRed,
    toneRedDot: DesignTokensDark.colorToneRedDot,
    toneBlue: DesignTokensDark.colorToneBlue,
    toneNeutral: DesignTokensDark.colorToneNeutral,
    lamp: DesignTokens.colorTitleLightFallback,
  );

  static const CupolaRoom light = CupolaRoom(
    ground: DesignTokensLight.colorRoomGround,
    slab: DesignTokensLight.colorRoomSlab,
    raised: DesignTokensLight.colorRoomRaised,
    door: DesignTokensLight.colorRoomDoor,
    enamel: DesignTokensLight.colorRoomEnamel,
    menu: DesignTokensLight.colorRoomMenu,
    toast: DesignTokensLight.colorRoomToast,
    scrim: DesignTokensLight.colorRoomScrim,
    hair: DesignTokensLight.colorLineHair,
    edge: DesignTokensLight.colorLineEdge,
    focus: DesignTokensLight.colorLineFocus,
    fillQuiet: DesignTokensLight.colorFillQuiet,
    fillControl: DesignTokensLight.colorFillControl,
    fillStrong: DesignTokensLight.colorFillStrong,
    fillTrack: DesignTokensLight.colorFillTrack,
    fillSkeleton: DesignTokensLight.colorFillSkeleton,
    fillSkeletonGlint: DesignTokensLight.colorFillSkeletonGlint,
    ink: DesignTokensLight.colorInkPrimary,
    inkSecondary: DesignTokensLight.colorInkSecondary,
    inkTertiary: DesignTokensLight.colorInkTertiary,
    inkDisabled: DesignTokensLight.colorInkDisabled,
    onInk: DesignTokensLight.colorInkOnInk,
    toneGreen: DesignTokensLight.colorToneGreen,
    toneGreenDot: DesignTokensLight.colorToneGreenDot,
    toneAmber: DesignTokensLight.colorToneAmber,
    toneAmberInk: DesignTokensLight.colorToneAmberInk,
    toneAmberFill: DesignTokensLight.colorToneAmberFill,
    toneAmberWash: DesignTokensLight.colorToneAmberWash,
    toneRed: DesignTokensLight.colorToneRed,
    toneRedDot: DesignTokensLight.colorToneRedDot,
    toneBlue: DesignTokensLight.colorToneBlue,
    toneNeutral: DesignTokensLight.colorToneNeutral,
    lamp: DesignTokens.colorTitleLightFallback,
  );

  /// The room for [brightness], for code that holds a scheme but no context.
  static CupolaRoom forBrightness(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// The room of [context]'s theme, falling back to the one for its brightness
  /// in a widget test that pumps a bare `MaterialApp`.
  static CupolaRoom of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<CupolaRoom>() ?? forBrightness(theme.brightness);
  }

  List<Color> get _colors => [
    ground, slab, raised, door, enamel, menu, toast, scrim, hair, edge, //
    focus, fillQuiet, fillControl, fillStrong, fillTrack, ink, inkSecondary,
    inkTertiary, inkDisabled, onInk, toneGreen, toneGreenDot, toneAmber,
    toneAmberInk, toneAmberFill, toneAmberWash, toneRed, toneRedDot, toneBlue,
    toneNeutral, lamp, fillSkeleton, fillSkeletonGlint,
  ];

  factory CupolaRoom._fromList(List<Color> c) => CupolaRoom(
    ground: c[0],
    slab: c[1],
    raised: c[2],
    door: c[3],
    enamel: c[4],
    menu: c[5],
    toast: c[6],
    scrim: c[7],
    hair: c[8],
    edge: c[9],
    focus: c[10],
    fillQuiet: c[11],
    fillControl: c[12],
    fillStrong: c[13],
    fillTrack: c[14],
    ink: c[15],
    inkSecondary: c[16],
    inkTertiary: c[17],
    inkDisabled: c[18],
    onInk: c[19],
    toneGreen: c[20],
    toneGreenDot: c[21],
    toneAmber: c[22],
    toneAmberInk: c[23],
    toneAmberFill: c[24],
    toneAmberWash: c[25],
    toneRed: c[26],
    toneRedDot: c[27],
    toneBlue: c[28],
    toneNeutral: c[29],
    lamp: c[30],
    fillSkeleton: c[31],
    fillSkeletonGlint: c[32],
  );

  @override
  CupolaRoom copyWith() => this;

  @override
  CupolaRoom lerp(covariant ThemeExtension<CupolaRoom>? other, double t) {
    if (other is! CupolaRoom) return this;
    final from = _colors;
    final to = other._colors;
    return CupolaRoom._fromList([
      for (var i = 0; i < from.length; i++) Color.lerp(from[i], to[i], t)!,
    ]);
  }
}

@immutable
class CupolaThemeColors extends ThemeExtension<CupolaThemeColors> {
  final Color statusBadgeBackground;
  final Color statusBadgeForeground;

  /// Dimmer tertiary text tone for editorial captions / metadata, sitting a
  /// step below [ColorScheme.onSurfaceVariant].
  final Color dimText;

  /// The floating bars' lit enamel: translucent, and never blurred live.
  final Color glassSurface;

  const CupolaThemeColors({
    required this.statusBadgeBackground,
    required this.statusBadgeForeground,
    required this.dimText,
    required this.glassSurface,
  });

  /// The bundle for [context]'s theme, falling back to [defaults] when the
  /// extension is absent, which happens in any widget test that pumps a bare
  /// `MaterialApp`.
  ///
  /// The fallback is why this is worth a helper: without it every call site
  /// writes `theme.extension<CupolaThemeColors>()?.dimText ?? <something>`, and
  /// the `<something>` is where a dark-theme literal gets in. Eleven files were
  /// skipping the lookup entirely and painting `AppColors.onSurfaceDimDark` in
  /// both themes.
  static CupolaThemeColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<CupolaThemeColors>() ??
        CupolaThemeColors.defaults(
          brightness: theme.brightness,
          colorScheme: theme.colorScheme,
        );
  }

  factory CupolaThemeColors.defaults({
    required Brightness brightness,
    required ColorScheme colorScheme,
  }) {
    final isDark = brightness == Brightness.dark;
    return CupolaThemeColors(
      statusBadgeBackground: colorScheme.surface.withValues(
        alpha: DesignTokens.opacityStatusBadge,
      ),
      statusBadgeForeground: colorScheme.onSurface,
      dimText: isDark
          ? AppColors.onSurfaceDimDark
          : AppColors.onSurfaceDimLight,
      // Lit enamel: the bar's own step at the glass opacity, a tint over what
      // scrolls beneath and never a backdrop blur.
      glassSurface: isDark
          ? DesignTokensDark.colorRoomEnamel.withValues(
              alpha: DesignTokensDark.opacityGlassSurface,
            )
          : DesignTokensLight.colorRoomEnamel.withValues(
              alpha: DesignTokensLight.opacityGlassSurface,
            ),
    );
  }

  @override
  CupolaThemeColors copyWith({
    Color? statusBadgeBackground,
    Color? statusBadgeForeground,
    Color? dimText,
    Color? glassSurface,
  }) {
    return CupolaThemeColors(
      statusBadgeBackground:
          statusBadgeBackground ?? this.statusBadgeBackground,
      statusBadgeForeground:
          statusBadgeForeground ?? this.statusBadgeForeground,
      dimText: dimText ?? this.dimText,
      glassSurface: glassSurface ?? this.glassSurface,
    );
  }

  @override
  CupolaThemeColors lerp(
    covariant ThemeExtension<CupolaThemeColors>? other,
    double t,
  ) {
    if (other is! CupolaThemeColors) {
      return this;
    }

    return CupolaThemeColors(
      statusBadgeBackground:
          Color.lerp(statusBadgeBackground, other.statusBadgeBackground, t) ??
          statusBadgeBackground,
      statusBadgeForeground:
          Color.lerp(statusBadgeForeground, other.statusBadgeForeground, t) ??
          statusBadgeForeground,
      dimText: Color.lerp(dimText, other.dimText, t) ?? dimText,
      glassSurface:
          Color.lerp(glassSurface, other.glassSurface, t) ?? glassSurface,
    );
  }
}

/// The type roles as styles, for surfaces built on the room's own vocabulary.
///
/// The Material slots of the text theme each stand for one of these (see
/// `design/tokens/core.json`, `type.display` onwards); these are the roles
/// themselves, including the ones no slot carries: the figures and the media
/// title. No colour: a role inherits the ink of the text it sets.
abstract final class AppType {
  /// Tab-root titles: Bricolage 36/36, 600, 92% wide.
  static final TextStyle screen = _type(
    DesignTokens.typeRoleScreenFontFamily,
    DesignTokens.typeRoleScreenFontFamilyFallback,
    DesignTokens.typeRoleScreenFontSize,
    DesignTokens.typeRoleScreenLineHeight,
    DesignTokens.typeRoleScreenFontWeight,
    DesignTokens.typeRoleScreenWght,
    DesignTokens.typeRoleScreenFontWidth,
    DesignTokens.typeRoleScreenLetterSpacing,
  );

  /// A title on its Media page: Bricolage 42/41, 600, 90% wide.
  static final TextStyle media = _type(
    DesignTokens.typeRoleMediaFontFamily,
    DesignTokens.typeRoleMediaFontFamilyFallback,
    DesignTokens.typeRoleMediaFontSize,
    DesignTokens.typeRoleMediaLineHeight,
    DesignTokens.typeRoleMediaFontWeight,
    DesignTokens.typeRoleMediaWght,
    DesignTokens.typeRoleMediaFontWidth,
    DesignTokens.typeRoleMediaLetterSpacing,
  );

  /// Pushed screen and service room titles: Bricolage 30/31.
  static final TextStyle room = _type(
    DesignTokens.typeRoleRoomFontFamily,
    DesignTokens.typeRoleRoomFontFamilyFallback,
    DesignTokens.typeRoleRoomFontSize,
    DesignTokens.typeRoleRoomLineHeight,
    DesignTokens.typeRoleRoomFontWeight,
    DesignTokens.typeRoleRoomWght,
    DesignTokens.typeRoleRoomFontWidth,
    DesignTokens.typeRoleRoomLetterSpacing,
  );

  /// A featured title, a sheet title: Bricolage 26/27.
  static final TextStyle feature = _type(
    DesignTokens.typeRoleFeatureFontFamily,
    DesignTokens.typeRoleFeatureFontFamilyFallback,
    DesignTokens.typeRoleFeatureFontSize,
    DesignTokens.typeRoleFeatureLineHeight,
    DesignTokens.typeRoleFeatureFontWeight,
    DesignTokens.typeRoleFeatureWght,
    DesignTokens.typeRoleFeatureFontWidth,
    DesignTokens.typeRoleFeatureLetterSpacing,
  );

  /// Section headings: Bricolage 21/24, 96% wide.
  static final TextStyle section = _type(
    DesignTokens.typeRoleSectionFontFamily,
    DesignTokens.typeRoleSectionFontFamilyFallback,
    DesignTokens.typeRoleSectionFontSize,
    DesignTokens.typeRoleSectionLineHeight,
    DesignTokens.typeRoleSectionFontWeight,
    DesignTokens.typeRoleSectionWght,
    DesignTokens.typeRoleSectionFontWidth,
    DesignTokens.typeRoleSectionLetterSpacing,
  );

  /// One hero readout per room: Bricolage 44/44, 90% wide, tabular.
  static final TextStyle figureHero = _type(
    DesignTokens.typeRoleFigureHeroFontFamily,
    DesignTokens.typeRoleFigureHeroFontFamilyFallback,
    DesignTokens.typeRoleFigureHeroFontSize,
    DesignTokens.typeRoleFigureHeroLineHeight,
    DesignTokens.typeRoleFigureHeroFontWeight,
    DesignTokens.typeRoleFigureHeroWght,
    DesignTokens.typeRoleFigureHeroFontWidth,
    DesignTokens.typeRoleFigureHeroLetterSpacing,
    tabular: true,
  );

  /// KPI figures, big numbers: Bricolage 24/24, tabular.
  static final TextStyle figure = _type(
    DesignTokens.typeRoleFigureFontFamily,
    DesignTokens.typeRoleFigureFontFamilyFallback,
    DesignTokens.typeRoleFigureFontSize,
    DesignTokens.typeRoleFigureLineHeight,
    DesignTokens.typeRoleFigureFontWeight,
    DesignTokens.typeRoleFigureWght,
    DesignTokens.typeRoleFigureFontWidth,
    DesignTokens.typeRoleFigureLetterSpacing,
    tabular: true,
  );

  /// Times and figures in rows: Bricolage 20/20, tabular.
  static final TextStyle figureSmall = _type(
    DesignTokens.typeRoleFigureSFontFamily,
    DesignTokens.typeRoleFigureSFontFamilyFallback,
    DesignTokens.typeRoleFigureSFontSize,
    DesignTokens.typeRoleFigureSLineHeight,
    DesignTokens.typeRoleFigureSFontWeight,
    DesignTokens.typeRoleFigureSWght,
    DesignTokens.typeRoleFigureSFontWidth,
    DesignTokens.typeRoleFigureSLetterSpacing,
    tabular: true,
  );

  /// Paragraphs: Onest 15/22, 400.
  static final TextStyle body = _type(
    DesignTokens.typeRoleBodyFontFamily,
    DesignTokens.typeRoleBodyFontFamilyFallback,
    DesignTokens.typeRoleBodyFontSize,
    DesignTokens.typeRoleBodyLineHeight,
    DesignTokens.typeRoleBodyFontWeight,
    DesignTokens.typeRoleBodyWght,
    DesignTokens.typeRoleBodyFontWidth,
    DesignTokens.typeRoleBodyLetterSpacing,
  );

  /// Row titles: Onest 15/20, 600.
  static final TextStyle row = _type(
    DesignTokens.typeRoleRowFontFamily,
    DesignTokens.typeRoleRowFontFamilyFallback,
    DesignTokens.typeRoleRowFontSize,
    DesignTokens.typeRoleRowLineHeight,
    DesignTokens.typeRoleRowFontWeight,
    DesignTokens.typeRoleRowWght,
    DesignTokens.typeRoleRowFontWidth,
    DesignTokens.typeRoleRowLetterSpacing,
  );

  /// Primary buttons: Onest 16/20, 600.
  static final TextStyle button = _type(
    DesignTokens.typeRoleButtonFontFamily,
    DesignTokens.typeRoleButtonFontFamilyFallback,
    DesignTokens.typeRoleButtonFontSize,
    DesignTokens.typeRoleButtonLineHeight,
    DesignTokens.typeRoleButtonFontWeight,
    DesignTokens.typeRoleButtonWght,
    DesignTokens.typeRoleButtonFontWidth,
    DesignTokens.typeRoleButtonLetterSpacing,
  );

  /// Small buttons, links, chips: Onest 14/18, 600.
  static final TextStyle label = _type(
    DesignTokens.typeRoleLabelFontFamily,
    DesignTokens.typeRoleLabelFontFamilyFallback,
    DesignTokens.typeRoleLabelFontSize,
    DesignTokens.typeRoleLabelLineHeight,
    DesignTokens.typeRoleLabelFontWeight,
    DesignTokens.typeRoleLabelWght,
    DesignTokens.typeRoleLabelFontWidth,
    DesignTokens.typeRoleLabelLetterSpacing,
  );

  /// Secondary lines: Onest 13/18, 500.
  static final TextStyle meta = _type(
    DesignTokens.typeRoleMetaFontFamily,
    DesignTokens.typeRoleMetaFontFamilyFallback,
    DesignTokens.typeRoleMetaFontSize,
    DesignTokens.typeRoleMetaLineHeight,
    DesignTokens.typeRoleMetaFontWeight,
    DesignTokens.typeRoleMetaWght,
    DesignTokens.typeRoleMetaFontWidth,
    DesignTokens.typeRoleMetaLetterSpacing,
  );

  /// Captions, badges: Onest 12/16, 500.
  static final TextStyle caption = _type(
    DesignTokens.typeRoleCaptionFontFamily,
    DesignTokens.typeRoleCaptionFontFamilyFallback,
    DesignTokens.typeRoleCaptionFontSize,
    DesignTokens.typeRoleCaptionLineHeight,
    DesignTokens.typeRoleCaptionFontWeight,
    DesignTokens.typeRoleCaptionWght,
    DesignTokens.typeRoleCaptionFontWidth,
    DesignTokens.typeRoleCaptionLetterSpacing,
  );

  /// Tab labels, poster marks (the floor: Onest 11/14, 600).
  static final TextStyle micro = _type(
    DesignTokens.typeRoleMicroFontFamily,
    DesignTokens.typeRoleMicroFontFamilyFallback,
    DesignTokens.typeRoleMicroFontSize,
    DesignTokens.typeRoleMicroLineHeight,
    DesignTokens.typeRoleMicroFontWeight,
    DesignTokens.typeRoleMicroWght,
    DesignTokens.typeRoleMicroFontWidth,
    DesignTokens.typeRoleMicroLetterSpacing,
  );

  /// Release names, paths, logs, the terminal: Geist Mono 13/18, 450.
  static final TextStyle mono = _type(
    DesignTokens.typeRoleMonoFontFamily,
    DesignTokens.typeRoleMonoFontFamilyFallback,
    DesignTokens.typeRoleMonoFontSize,
    DesignTokens.typeRoleMonoLineHeight,
    DesignTokens.typeRoleMonoFontWeight,
    DesignTokens.typeRoleMonoWght,
    DesignTokens.typeRoleMonoFontWidth,
    DesignTokens.typeRoleMonoLetterSpacing,
  );

  static TextStyle _type(
    String family,
    List<String> fallback,
    double size,
    double height,
    FontWeight weight,
    double wght,
    double width,
    double letterSpacing, {
    bool tabular = false,
  }) => _role(
    family: family,
    fallback: fallback,
    fontSize: size,
    fontWeight: weight,
    wght: wght,
    width: width,
    height: height,
    letterSpacing: letterSpacing,
    fontFeatures: tabular ? const [FontFeature.tabularFigures()] : null,
  );
}

/// Material Design 3 Theme configuration for Cupola
class AppTheme {
  AppTheme._();

  /// A page's one primary action (brand book *Sizes*: `button-l`): the ink
  /// button full width at 52, growing with its label, `radius.button` (16),
  /// continuous, ringed when focused. A sheet's submit, the walk's Continue;
  /// a button in a row or a dialog is the medium one, the theme's own.
  static ButtonStyle primaryButtonStyle(BuildContext context) =>
      FilledButton.styleFrom(
        visualDensity: VisualDensity.standard,
        minimumSize: Size.fromHeight(
          TextScaleMetrics.boxHeight(
            context,
            base: DesignTokens.sizeButtonL,
            textHeight: 20,
          ),
        ),
      ).copyWith(
        shape: focusRingShape(
          RoundedSuperellipseBorder(
            borderRadius: BorderRadius.circular(AppRadius.button),
          ),
          ring: CupolaRoom.of(context).focus,
        ),
      );

  /// The text family: every Material slot that is not display type.
  static const String fontFamily = DesignTokens.typeFamilySans;

  /// The display family: titles, headings and figures.
  static const String displayFontFamily = DesignTokens.typeFamilyDisplay;

  /// Family for release names, paths, logs, hashes and anything read in
  /// columns.
  ///
  /// **Not** the string `'monospace'`, which is the mistake this token exists to
  /// stop repeating. `'monospace'` is an Android family alias; CoreText has no
  /// family by that name, so on iOS and macOS Flutter finds nothing and falls
  /// back to the proportional system face. Geist Mono is bundled, so it is the
  /// same face on all five targets.
  static const String monoFontFamily = DesignTokens.typeFamilyMono;

  /// Fallbacks for [monoFontFamily], in resolution order: the platform mono
  /// faces, which carry the glyphs Geist Mono lacks (⌘ and ⌥ among them).
  static const List<String> monoFontFamilyFallback =
      DesignTokens.typeFamilyMonoFallback;

  // === VARIABLE AXES ===
  //
  // Bricolage Grotesque exposes `opsz` (12–96), `wdth` (75–100) and `wght`
  // (200–800); Onest and Geist Mono expose `wght` (100–900). Flutter drives none
  // of them from a plain `TextStyle`, and it does not apply an optical size by
  // itself, so every role names each axis its face has.

  /// Lower bound of Bricolage's optical-size axis: the text drawing.
  static const double _opticalSizeMin = 12;

  /// Upper bound of Bricolage's optical-size axis: the poster drawing.
  static const double _opticalSizeMax = 96;

  /// The optical size display type should be *drawn* at for text rendered at
  /// [fontSize]: the size itself, within the axis.
  ///
  /// The axis is a drawing, not a size: small sizes open their counters and
  /// loosen, large ones tighten and gain contrast. Tracking the authored size
  /// is the whole point of it.
  static double opticalSize(double fontSize) =>
      fontSize.clamp(_opticalSizeMin, _opticalSizeMax);

  /// The axes a role sets on [family]: `wght` on every face, and on the display
  /// face its width and an optical size equal to [fontSize].
  static List<FontVariation> variations(
    String family, {
    required double wght,
    double width = 100,
    required double fontSize,
  }) => <FontVariation>[
    FontVariation('wght', wght),
    if (family == displayFontFamily) ...[
      FontVariation('wdth', width),
      FontVariation('opsz', opticalSize(fontSize)),
    ],
  ];

  /// The four roles the Material ramp has no slot for.
  ///
  /// They exist because the alternative is what the codebase actually had:
  /// thirty-nine bare `TextStyle(fontSize: …)` literals, mostly across the
  /// desktop shell. A bare `TextStyle` is not a smaller version of a ramp role,
  /// it is a *different* style; it never reaches the `wght` axis, so every
  /// one of those weights rendered at the face's default instance.
  ///
  /// Each still takes a [Brightness], which the type no longer reads (tracking
  /// is the same in both rooms); the parameter is kept so the call sites stand.
  ///
  /// **Panel header**: an `h2` inside a page: a Dockge stack, an NPM host, a
  /// TrueNAS console section. The section role.
  static TextStyle panelHeader(Brightness brightness) => _slot(
    DesignTokens.typeTitlePanelHeaderFontFamily,
    DesignTokens.typeTitlePanelHeaderFontFamilyFallback,
    DesignTokens.typeTitlePanelHeaderFontSize,
    DesignTokens.typeTitlePanelHeaderLineHeight,
    DesignTokens.typeTitlePanelHeaderFontWeight,
    DesignTokens.typeTitlePanelHeaderWght,
    DesignTokens.typeTitlePanelHeaderFontWidth,
    DesignTokens.typeTitlePanelHeaderLetterSpacing,
  );

  /// **Row title** (600, 15): the primary line of a list row that is a *name*
  /// rather than a sentence: a device, a now-playing session, a proxy host.
  static TextStyle rowTitle(Brightness brightness) => _slot(
    DesignTokens.typeTitleRowTitleFontFamily,
    DesignTokens.typeTitleRowTitleFontFamilyFallback,
    DesignTokens.typeTitleRowTitleFontSize,
    DesignTokens.typeTitleRowTitleLineHeight,
    DesignTokens.typeTitleRowTitleFontWeight,
    DesignTokens.typeTitleRowTitleWght,
    DesignTokens.typeTitleRowTitleFontWidth,
    DesignTokens.typeTitleRowTitleLetterSpacing,
  );

  /// **Data** (500, 13): the answer in a row: the title of an attention item,
  /// a queue entry, a table cell. The meta role.
  ///
  /// It sits *above* Label on purpose. The thing that needs a human must never
  /// be smaller than the word describing it.
  static TextStyle data(Brightness brightness) => _slot(
    DesignTokens.typeLabelDataFontFamily,
    DesignTokens.typeLabelDataFontFamilyFallback,
    DesignTokens.typeLabelDataFontSize,
    DesignTokens.typeLabelDataLineHeight,
    DesignTokens.typeLabelDataFontWeight,
    DesignTokens.typeLabelDataWght,
    DesignTokens.typeLabelDataFontWidth,
    DesignTokens.typeLabelDataLetterSpacing,
  );

  /// The dense chrome styles the desktop shell needs: the micro role, through
  /// the axes.
  ///
  /// Every one of these used to be a bare `TextStyle(fontSize: …)`, which never
  /// reaches `fontVariations` and so renders the face's default instance
  /// whatever weight it asks for.
  ///
  /// [size] is clamped to 11, which is how the floor stays *enforced* rather
  /// than asserted. Tracking follows the role in em, so a larger [size] keeps
  /// the role's proportion unless [letterSpacing] is given.
  static TextStyle chrome(
    BuildContext context, {
    double size = DesignTokens.typeLabelChromeFontSize,
    FontWeight weight = DesignTokens.typeLabelChromeFontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
  }) {
    final fontSize = size < DesignTokens.typeLabelChromeFontSize
        ? DesignTokens.typeLabelChromeFontSize
        : size;
    return _role(
      color: color,
      family: DesignTokens.typeLabelChromeFontFamily,
      fallback: DesignTokens.typeLabelChromeFontFamilyFallback,
      fontSize: fontSize,
      fontWeight: weight,
      wght: weight.value.toDouble(),
      height: height ?? DesignTokens.typeLabelChromeLineHeight,
      letterSpacing:
          letterSpacing ??
          DesignTokens.typeLabelChromeLetterSpacing /
              DesignTokens.typeLabelChromeFontSize *
              fontSize,
    );
  }

  static TextStyle _slot(
    String family,
    List<String> fallback,
    double size,
    double height,
    FontWeight weight,
    double wght,
    double width,
    double letterSpacing,
  ) => _role(
    family: family,
    fallback: fallback,
    fontSize: size,
    fontWeight: weight,
    wght: wght,
    width: width,
    height: height,
    letterSpacing: letterSpacing,
  );

  // === DARK THEME (Primary) ===
  //
  // Both themes are deliberately fixed, and the experience is meant to be
  // identical on every OS, so platform dynamic color (Material You) is not
  // harmonised in.
  static ThemeData darkTheme() {
    return _buildTheme(
      brightness: Brightness.dark,
      colorScheme: _darkColorScheme,
      room: CupolaRoom.dark,
      navigationBarBackground: AppColors.surfaceContainerDark,
      bottomSheetBackground: _darkColorScheme.surfaceContainerHigh,
      dialogBackground: _darkColorScheme.surfaceContainerHigh,
    );
  }

  // === LIGHT THEME ===
  static ThemeData lightTheme() {
    return _buildTheme(
      brightness: Brightness.light,
      colorScheme: _lightColorScheme,
      room: CupolaRoom.light,
      navigationBarBackground: _lightColorScheme.surface,
      bottomSheetBackground: _lightColorScheme.surfaceContainer,
      dialogBackground: _lightColorScheme.surfaceContainer,
    );
  }

  static ThemeData _buildTheme({
    required Brightness brightness,
    required ColorScheme colorScheme,
    required CupolaRoom room,
    required Color navigationBarBackground,
    required Color bottomSheetBackground,
    required Color dialogBackground,
  }) {
    final TextTheme textTheme = _buildTextTheme(
      brightness == Brightness.dark
          ? ThemeData.dark().textTheme
          : ThemeData.light().textTheme,
    );
    // Component text comes off the ramp rather than re-declaring sizes: the
    // app-bar title *is* titleLarge, a small button label *is* labelLarge.
    // Restating a size here is how a component drifts out of the ladder it is
    // supposed to belong to.
    final TextStyle labelLarge = textTheme.labelLarge!;
    final TextStyle labelMedium = textTheme.labelMedium!;
    // A 44pt button's label is the row role's 15/600 (the button role is the
    // 52pt primary's 16).
    final TextStyle buttonLabel = rowTitle(brightness);

    // Corners are continuous wherever a shape takes an `OutlinedBorder`.
    RoundedSuperellipseBorder corners(double radius, {BorderSide? side}) =>
        RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(radius),
          side: side ?? BorderSide.none,
        );

    // A button's shape, with the keyboard's focus ring outside it while
    // focused (`line.focus`, brand book *Lines and fills*).
    final controlShape = focusRingShape(
      corners(AppRadius.control),
      ring: room.focus,
    );

    // The fault tone, as a field's refusal draws it: a field that answered
    // and refused is a fault, amber; red is reserved for unreachable.
    final Color fault = room.toneAmber;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      extensions: [
        CupolaThemeColors.defaults(
          brightness: brightness,
          colorScheme: colorScheme,
        ),
        room,
      ],
      textTheme: textTheme,
      scaffoldBackgroundColor: colorScheme.surface,

      // AppBar
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        // A transparent bar would guess its glyphs from its own colour, and
        // transparent reads as dark: white glyphs on the light room. The
        // room decides, as it does for every screen without a bar.
        systemOverlayStyle: ThemedSystemBars.styleFor(brightness),
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge!.copyWith(
          color: colorScheme.onSurface,
        ),
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),

      // NavigationBar
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: navigationBarBackground,
        indicatorColor: colorScheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return labelMedium
                .weight(FontWeight.w600)
                .copyWith(color: colorScheme.primary);
          }
          return labelMedium.copyWith(color: colorScheme.onSurfaceVariant);
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: colorScheme.primary);
          }
          return IconThemeData(color: colorScheme.onSurfaceVariant);
        }),
      ),

      // Card: a slab, with its hairline edge.
      cardTheme: CardThemeData(
        color: colorScheme.surfaceContainer,
        elevation: 0,
        shape: corners(
          AppRadius.slab,
          side: BorderSide(color: colorScheme.outlineVariant),
        ),
      ),

      // Chip: a pill at rest on the quiet fill with an edge; selected is the
      // ink fill. The label's colour follows the state (the chip resolves the
      // colour, not the style): a FilterChip reads only `labelStyle`, so a
      // plain colour painted a selected one's label in the ink of its fill.
      chipTheme: ChipThemeData(
        backgroundColor: room.fillQuiet,
        selectedColor: colorScheme.primary,
        checkmarkColor: colorScheme.onPrimary,
        labelStyle: labelLarge.copyWith(
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colorScheme.onPrimary
                : colorScheme.onSurface,
          ),
        ),
        secondaryLabelStyle: labelLarge.copyWith(color: colorScheme.onPrimary),
        side: BorderSide(color: room.edge),
        shape: const StadiumBorder(),
      ),

      // Buttons keep standard density on every platform. The theme leaves
      // `visualDensity` to Flutter, which picks compact (-2, -2) on the
      // desktop: that took 8 off every button's height, and it silently
      // cancels `minimumSize`. The 44pt minimum is the medium button's height
      // and the touch floor.
      //
      // FilledButton: the ink button.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          visualDensity: VisualDensity.standard,
          minimumSize: const Size(64, DesignTokens.sizeButtonM),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          textStyle: buttonLabel,
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceLg,
            vertical: DesignTokens.spaceMd,
          ),
        ).copyWith(shape: controlShape),
      ),

      // OutlinedButton: the ghost button, on the control fill with an edge.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          visualDensity: VisualDensity.standard,
          minimumSize: const Size(64, DesignTokens.sizeButtonM),
          foregroundColor: colorScheme.onSurface,
          backgroundColor: room.fillControl,
          textStyle: buttonLabel,
          side: BorderSide(color: room.edge),
          padding: const EdgeInsets.symmetric(
            horizontal: DesignTokens.spaceLg,
            vertical: DesignTokens.spaceMd,
          ),
        ).copyWith(shape: controlShape),
      ),

      // TextButton
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.standard,
          minimumSize: const Size(64, DesignTokens.sizeButtonM),
          foregroundColor: colorScheme.primary,
          textStyle: labelLarge,
        ).copyWith(shape: controlShape),
      ),

      // FloatingActionButton: the ink button. A screen's one floating action is
      // its primary, and the primary is ink, never a service's colour, which
      // is what the four TrueNAS consoles used to fill theirs with.
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),

      // IconButton: the same floor. Compact density shrank a bare icon button
      // to 32pt on the desktop. Its shape is Material's stadium, ringed.
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.standard,
          shape: focusRingShape(const StadiumBorder(), ring: room.focus),
        ),
      ),

      // SegmentedButton: the selected segment is the ink fill.
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          visualDensity: VisualDensity.standard,
          textStyle: WidgetStatePropertyAll(labelLarge),
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colorScheme.primary
                : room.fillQuiet,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant,
          ),
          iconColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colorScheme.onPrimary
                : colorScheme.onSurfaceVariant,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: room.hair)),
        ),
      ),

      // Input Decoration: a field on the quiet fill with an edge; focus is the
      // secondary ink, a refusal is the fault tone.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: room.fillQuiet,
        border: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusField,
          borderSide: BorderSide(color: room.edge),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusField,
          borderSide: BorderSide(color: room.edge),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusField,
          borderSide: BorderSide(color: room.focus, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusField,
          borderSide: BorderSide(color: fault, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadius.borderRadiusField,
          borderSide: BorderSide(color: fault, width: 1.5),
        ),
        errorStyle: textTheme.bodySmall!.copyWith(color: fault),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceLg,
          vertical: DesignTokens.spaceMd,
        ),
        hintStyle: textTheme.bodyMedium!.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),

      // BottomSheet: raised, its top corners the sheet's.
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: bottomSheetBackground,
        modalBarrierColor: room.scrim,
        shape: const RoundedSuperellipseBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.sheet),
          ),
        ),
      ),

      // Dialog: raised, a slab's corners, over the room's scrim.
      dialogTheme: DialogThemeData(
        backgroundColor: dialogBackground,
        barrierColor: room.scrim,
        shape: corners(AppRadius.slab, side: BorderSide(color: room.edge)),
      ),

      // Popover menus sit on their own step.
      popupMenuTheme: PopupMenuThemeData(
        color: room.menu,
        shape: corners(AppRadius.lg, side: BorderSide(color: room.edge)),
      ),

      // Divider
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
      ),

      // SnackBar: the toast.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium!.copyWith(
          color: colorScheme.onInverseSurface,
        ),
        actionTextColor: colorScheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        shape: corners(AppRadius.button, side: BorderSide(color: room.edge)),
      ),

      // ListTile
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.spaceLg,
        ),
        shape: corners(AppRadius.md),
      ),

      // TabBar: the active tab in ink, the rest in the tertiary ink.
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: brightness == Brightness.dark
            ? AppColors.onSurfaceDimDark
            : AppColors.onSurfaceDimLight,
        indicatorColor: colorScheme.primary,
        labelStyle: labelLarge,
        unselectedLabelStyle: labelLarge,
      ),

      // ProgressIndicator: the ink on the room's track. A tone that means
      // something (a download's blue) is the caller's to pass.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        linearTrackColor: room.fillTrack,
        circularTrackColor: room.fillTrack,
      ),
    );
  }

  // === COLOR SCHEMES ===
  //
  // Monochrome: the interactive colour is the primary ink, in both rooms. The
  // inks and lines the room draws translucent are carried here flattened on
  // the ground, so a contrast can be measured against any surface; see
  // [CupolaRoom] for the translucent originals.

  static final ColorScheme _darkColorScheme = ColorScheme(
    brightness: Brightness.dark,
    // Primary
    primary: DesignTokensDark.colorPrimary,
    onPrimary: DesignTokensDark.colorOnPrimary,
    primaryContainer: DesignTokensDark.colorPrimaryContainer,
    onPrimaryContainer: DesignTokensDark.colorOnPrimaryContainer,
    // Secondary
    secondary: DesignTokensDark.colorSecondary,
    onSecondary: DesignTokensDark.colorOnSecondary,
    secondaryContainer: DesignTokensDark.colorSecondaryContainer,
    onSecondaryContainer: DesignTokensDark.colorOnSecondaryContainer,
    // Tertiary
    tertiary: DesignTokensDark.colorTertiary,
    onTertiary: DesignTokensDark.colorOnTertiary,
    tertiaryContainer: DesignTokensDark.colorTertiaryContainer,
    onTertiaryContainer: DesignTokensDark.colorOnTertiaryContainer,
    // Error
    error: DesignTokensDark.colorError,
    onError: DesignTokensDark.colorOnError,
    errorContainer: DesignTokensDark.colorErrorContainer,
    onErrorContainer: DesignTokensDark.colorOnErrorContainer,
    // Surface
    surface: DesignTokensDark.colorSurface,
    onSurface: DesignTokensDark.colorOnSurface,
    surfaceContainerLowest: DesignTokensDark.colorSurfaceContainerLowest,
    surfaceContainerLow: DesignTokensDark.colorSurfaceContainerLow,
    surfaceContainer: DesignTokensDark.colorSurfaceContainer,
    surfaceContainerHigh: DesignTokensDark.colorSurfaceContainerHigh,
    surfaceContainerHighest: DesignTokensDark.colorSurfaceContainerHighest,
    onSurfaceVariant: DesignTokensDark.colorOnSurfaceVariant,
    // Outline
    outline: DesignTokensDark.colorOutline,
    outlineVariant: DesignTokensDark.colorOutlineVariant,
    // Other
    shadow: DesignTokensDark.colorShadow,
    scrim: DesignTokensDark.colorScrim,
    inverseSurface: DesignTokensDark.colorInverseSurface,
    onInverseSurface: DesignTokensDark.colorOnInverseSurface,
    inversePrimary: DesignTokensDark.colorInversePrimary,
  );

  static final ColorScheme _lightColorScheme = ColorScheme(
    brightness: Brightness.light,
    // Primary
    primary: DesignTokensLight.colorPrimary,
    onPrimary: DesignTokensLight.colorOnPrimary,
    primaryContainer: DesignTokensLight.colorPrimaryContainer,
    onPrimaryContainer: DesignTokensLight.colorOnPrimaryContainer,
    // Secondary
    //
    // `secondaryContainer` is what Material paints behind a tonal button and a
    // selected segment. It must stay visibly off paper (1.23:1 here), because
    // a selected state that cannot be seen is not a state.
    secondary: DesignTokensLight.colorSecondary,
    onSecondary: DesignTokensLight.colorOnSecondary,
    secondaryContainer: DesignTokensLight.colorSecondaryContainer,
    onSecondaryContainer: DesignTokensLight.colorOnSecondaryContainer,
    // Tertiary
    tertiary: DesignTokensLight.colorTertiary,
    onTertiary: DesignTokensLight.colorOnTertiary,
    tertiaryContainer: DesignTokensLight.colorTertiaryContainer,
    onTertiaryContainer: DesignTokensLight.colorOnTertiaryContainer,
    // Error
    error: DesignTokensLight.colorError,
    onError: DesignTokensLight.colorOnError,
    errorContainer: DesignTokensLight.colorErrorContainer,
    onErrorContainer: DesignTokensLight.colorOnErrorContainer,
    // Surface
    surface: DesignTokensLight.colorSurface,
    onSurface: DesignTokensLight.colorOnSurface,
    surfaceContainerLowest: DesignTokensLight.colorSurfaceContainerLowest,
    surfaceContainerLow: DesignTokensLight.colorSurfaceContainerLow,
    surfaceContainer: DesignTokensLight.colorSurfaceContainer,
    surfaceContainerHigh: DesignTokensLight.colorSurfaceContainerHigh,
    surfaceContainerHighest: DesignTokensLight.colorSurfaceContainerHighest,
    onSurfaceVariant: DesignTokensLight.colorOnSurfaceVariant,
    // Outline
    outline: DesignTokensLight.colorOutline,
    outlineVariant: DesignTokensLight.colorOutlineVariant,
    // Other
    //
    // Ink, not black. Every `AppElevation` level paints `scheme.shadow`, and on
    // paper a pure-black drop shadow reads as grime under a card rather than as
    // depth. `AppElevation.glass()` is the deliberate exception and paints its
    // own black, so it is unaffected by this line.
    shadow: DesignTokensLight.colorShadow,
    scrim: DesignTokensLight.colorScrim,
    inverseSurface: DesignTokensLight.colorInverseSurface,
    onInverseSurface: DesignTokensLight.colorOnInverseSurface,
    inversePrimary: DesignTokensLight.colorInversePrimary,
  );

  // === TEXT THEME ===

  /// The type ramp: each Material slot set in the role it stands for.
  ///
  /// Display, headline and the large title are Bricolage Grotesque; every other
  /// slot is Onest. The mapping is stated once, in `design/tokens/core.json`
  /// (`type.display` onwards), and read here through the generated constants.
  ///
  /// Line height is a decision per role, and it keeps the reasoning it had: the
  /// display end is tight (1.0 on the screen role, where the display face's
  /// ascenders are short enough to allow it), prose opens to 22 on 15, and
  /// labels stay near 1.3 because they are chrome and sit in fixed-height pills
  /// and cells where extra leading buys nothing.
  static TextTheme _buildTextTheme(TextTheme base) {
    return base
        .apply(fontFamily: fontFamily)
        .copyWith(
          displayLarge: _slot(
            DesignTokens.typeDisplayLargeFontFamily,
            DesignTokens.typeDisplayLargeFontFamilyFallback,
            DesignTokens.typeDisplayLargeFontSize,
            DesignTokens.typeDisplayLargeLineHeight,
            DesignTokens.typeDisplayLargeFontWeight,
            DesignTokens.typeDisplayLargeWght,
            DesignTokens.typeDisplayLargeFontWidth,
            DesignTokens.typeDisplayLargeLetterSpacing,
          ),
          displayMedium: _slot(
            DesignTokens.typeDisplayMediumFontFamily,
            DesignTokens.typeDisplayMediumFontFamilyFallback,
            DesignTokens.typeDisplayMediumFontSize,
            DesignTokens.typeDisplayMediumLineHeight,
            DesignTokens.typeDisplayMediumFontWeight,
            DesignTokens.typeDisplayMediumWght,
            DesignTokens.typeDisplayMediumFontWidth,
            DesignTokens.typeDisplayMediumLetterSpacing,
          ),
          displaySmall: _slot(
            DesignTokens.typeDisplaySmallFontFamily,
            DesignTokens.typeDisplaySmallFontFamilyFallback,
            DesignTokens.typeDisplaySmallFontSize,
            DesignTokens.typeDisplaySmallLineHeight,
            DesignTokens.typeDisplaySmallFontWeight,
            DesignTokens.typeDisplaySmallWght,
            DesignTokens.typeDisplaySmallFontWidth,
            DesignTokens.typeDisplaySmallLetterSpacing,
          ),
          headlineLarge: _slot(
            DesignTokens.typeHeadlineLargeFontFamily,
            DesignTokens.typeHeadlineLargeFontFamilyFallback,
            DesignTokens.typeHeadlineLargeFontSize,
            DesignTokens.typeHeadlineLargeLineHeight,
            DesignTokens.typeHeadlineLargeFontWeight,
            DesignTokens.typeHeadlineLargeWght,
            DesignTokens.typeHeadlineLargeFontWidth,
            DesignTokens.typeHeadlineLargeLetterSpacing,
          ),
          headlineMedium: _slot(
            DesignTokens.typeHeadlineMediumFontFamily,
            DesignTokens.typeHeadlineMediumFontFamilyFallback,
            DesignTokens.typeHeadlineMediumFontSize,
            DesignTokens.typeHeadlineMediumLineHeight,
            DesignTokens.typeHeadlineMediumFontWeight,
            DesignTokens.typeHeadlineMediumWght,
            DesignTokens.typeHeadlineMediumFontWidth,
            DesignTokens.typeHeadlineMediumLetterSpacing,
          ),
          headlineSmall: _slot(
            DesignTokens.typeHeadlineSmallFontFamily,
            DesignTokens.typeHeadlineSmallFontFamilyFallback,
            DesignTokens.typeHeadlineSmallFontSize,
            DesignTokens.typeHeadlineSmallLineHeight,
            DesignTokens.typeHeadlineSmallFontWeight,
            DesignTokens.typeHeadlineSmallWght,
            DesignTokens.typeHeadlineSmallFontWidth,
            DesignTokens.typeHeadlineSmallLetterSpacing,
          ),
          titleLarge: _slot(
            DesignTokens.typeTitleLargeFontFamily,
            DesignTokens.typeTitleLargeFontFamilyFallback,
            DesignTokens.typeTitleLargeFontSize,
            DesignTokens.typeTitleLargeLineHeight,
            DesignTokens.typeTitleLargeFontWeight,
            DesignTokens.typeTitleLargeWght,
            DesignTokens.typeTitleLargeFontWidth,
            DesignTokens.typeTitleLargeLetterSpacing,
          ),
          titleMedium: _slot(
            DesignTokens.typeTitleMediumFontFamily,
            DesignTokens.typeTitleMediumFontFamilyFallback,
            DesignTokens.typeTitleMediumFontSize,
            DesignTokens.typeTitleMediumLineHeight,
            DesignTokens.typeTitleMediumFontWeight,
            DesignTokens.typeTitleMediumWght,
            DesignTokens.typeTitleMediumFontWidth,
            DesignTokens.typeTitleMediumLetterSpacing,
          ),
          titleSmall: _slot(
            DesignTokens.typeTitleSmallFontFamily,
            DesignTokens.typeTitleSmallFontFamilyFallback,
            DesignTokens.typeTitleSmallFontSize,
            DesignTokens.typeTitleSmallLineHeight,
            DesignTokens.typeTitleSmallFontWeight,
            DesignTokens.typeTitleSmallWght,
            DesignTokens.typeTitleSmallFontWidth,
            DesignTokens.typeTitleSmallLetterSpacing,
          ),
          bodyLarge: _slot(
            DesignTokens.typeBodyLargeFontFamily,
            DesignTokens.typeBodyLargeFontFamilyFallback,
            DesignTokens.typeBodyLargeFontSize,
            DesignTokens.typeBodyLargeLineHeight,
            DesignTokens.typeBodyLargeFontWeight,
            DesignTokens.typeBodyLargeWght,
            DesignTokens.typeBodyLargeFontWidth,
            DesignTokens.typeBodyLargeLetterSpacing,
          ),
          bodyMedium: _slot(
            DesignTokens.typeBodyMediumFontFamily,
            DesignTokens.typeBodyMediumFontFamilyFallback,
            DesignTokens.typeBodyMediumFontSize,
            DesignTokens.typeBodyMediumLineHeight,
            DesignTokens.typeBodyMediumFontWeight,
            DesignTokens.typeBodyMediumWght,
            DesignTokens.typeBodyMediumFontWidth,
            DesignTokens.typeBodyMediumLetterSpacing,
          ),
          bodySmall: _slot(
            DesignTokens.typeBodySmallFontFamily,
            DesignTokens.typeBodySmallFontFamilyFallback,
            DesignTokens.typeBodySmallFontSize,
            DesignTokens.typeBodySmallLineHeight,
            DesignTokens.typeBodySmallFontWeight,
            DesignTokens.typeBodySmallWght,
            DesignTokens.typeBodySmallFontWidth,
            DesignTokens.typeBodySmallLetterSpacing,
          ),
          labelLarge: _slot(
            DesignTokens.typeLabelLargeFontFamily,
            DesignTokens.typeLabelLargeFontFamilyFallback,
            DesignTokens.typeLabelLargeFontSize,
            DesignTokens.typeLabelLargeLineHeight,
            DesignTokens.typeLabelLargeFontWeight,
            DesignTokens.typeLabelLargeWght,
            DesignTokens.typeLabelLargeFontWidth,
            DesignTokens.typeLabelLargeLetterSpacing,
          ),
          labelMedium: _slot(
            DesignTokens.typeLabelMediumFontFamily,
            DesignTokens.typeLabelMediumFontFamilyFallback,
            DesignTokens.typeLabelMediumFontSize,
            DesignTokens.typeLabelMediumLineHeight,
            DesignTokens.typeLabelMediumFontWeight,
            DesignTokens.typeLabelMediumWght,
            DesignTokens.typeLabelMediumFontWidth,
            DesignTokens.typeLabelMediumLetterSpacing,
          ),
          labelSmall: _slot(
            DesignTokens.typeLabelSmallFontFamily,
            DesignTokens.typeLabelSmallFontFamilyFallback,
            DesignTokens.typeLabelSmallFontSize,
            DesignTokens.typeLabelSmallLineHeight,
            DesignTokens.typeLabelSmallFontWeight,
            DesignTokens.typeLabelSmallWght,
            DesignTokens.typeLabelSmallFontWidth,
            DesignTokens.typeLabelSmallLetterSpacing,
          ),
        );
  }
}
