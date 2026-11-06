import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cupola/core/service_theme.dart';
import 'package:cupola/core/generated/design_tokens.g.dart';
import 'package:cupola/core/theme.dart';
import 'package:cupola/features/settings/domain/service_key.dart';

/// The alphas the selected nav pill and the Activity segment pills actually use.
const _darkTintAlpha = 0.16;
const _lightTintAlpha = 0.13;

double _contrast(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

/// The background a label is really drawn on: the tint composited over the
/// surface, not the accent on its own.
///
/// Measuring against the accent alone is the mistake that makes this class of bug
/// invisible: it passes combinations that fail on screen.
Color _tintOverSurface(Color accent, double alpha, Color surface) =>
    Color.alphaBlend(accent.withValues(alpha: alpha), surface);

void main() {
  group('ServiceTheme.onTint', () {
    test('every service accent clears AA over its own tint, in both themes', () {
      for (final service in ServiceKey.values) {
        for (final (surface, alpha) in const [
          (AppColors.surfaceLight, _lightTintAlpha),
          (AppColors.surfaceDark, _darkTintAlpha),
        ]) {
          final background = _tintOverSurface(service.accent, alpha, surface);
          final label = ServiceTheme.onTint(
            service.accent,
            surface: surface,
            tintAlpha: alpha,
          );

          expect(
            _contrast(label, background),
            greaterThanOrEqualTo(4.5),
            reason:
                '${service.name} on ${surface == AppColors.surfaceLight ? 'light' : 'dark'}',
          );
        }
      }
    });

    test('a label asked of the lamp is the room\'s primary ink', () {
      // The brand book: a selected or emphasised label is ink, never a hue. Every service
      // paints the lamp now, so walking the lamp's grey would have set every
      // such label in a dim cool grey, below the dark room's tertiary ink.
      for (final (surface, alpha, ink) in const [
        (
          AppColors.surfaceDark,
          _darkTintAlpha,
          DesignTokensDark.colorOnSurface,
        ),
        (AppColors.surfaceDark, 0.0, DesignTokensDark.colorOnSurface),
        (
          AppColors.surfaceLight,
          _lightTintAlpha,
          DesignTokensLight.colorOnSurface,
        ),
        (AppColors.surfaceLight, 0.0, DesignTokensLight.colorOnSurface),
      ]) {
        expect(
          ServiceTheme.onTint(
            AppColors.lamp,
            surface: surface,
            tintAlpha: alpha,
          ),
          ink,
          reason: 'lamp over $surface at $alpha',
        );
      }
    });

    test('an accent that already passes is returned untouched', () {
      // Dark theme is the case that always worked. The helper must not "correct"
      // it, or every pill in the app shifts colour for no reason.
      expect(
        ServiceTheme.onTint(
          AppColors.radarr,
          surface: AppColors.surfaceDark,
          tintAlpha: _darkTintAlpha,
        ),
        AppColors.radarr,
      );
    });

    test(
      'the light-theme amber that used to ship was nowhere near the line',
      () {
        // The concrete defect: the nav bar painted this exact combination.
        final background = _tintOverSurface(
          AppColors.radarr,
          _lightTintAlpha,
          AppColors.surfaceLight,
        );

        expect(_contrast(AppColors.radarr, background), lessThan(2.5));
        expect(
          ServiceTheme.onTint(
            AppColors.radarr,
            surface: AppColors.surfaceLight,
            tintAlpha: _lightTintAlpha,
          ),
          isNot(AppColors.radarr),
        );
      },
    );

    test('the accent hue survives the adjustment', () {
      // This is the whole reason for deriving a tone instead of dropping the
      // label to a neutral: the pill has to stay recognisably that colour.
      for (final accent in [AppColors.radarr, AppColors.nzbget]) {
        final tuned = ServiceTheme.onTint(
          accent,
          surface: AppColors.surfaceLight,
          tintAlpha: _lightTintAlpha,
        );

        expect(
          HSLColor.fromColor(tuned).hue,
          closeTo(HSLColor.fromColor(accent).hue, 1.0),
          reason: '$accent should keep its hue',
        );
      }
    });
  });

  group('the monochrome registry', () {
    test('every service paints the lamp', () {
      // Principle 3 of the brand book: colour is information. `ServiceKey.accent` is what the
      // interface paints for a service: its room light, its glow, its walked
      // labels, and it is the neutral lamp for all eighteen.
      for (final service in ServiceKey.values) {
        expect(service.accent, AppColors.lamp, reason: service.name);
        expect(serviceThemeFor(service).accent, AppColors.lamp);
      }
    });

    test('each brand colour survives as registry data, one per service', () {
      // Retired from the paint, not from the registry: the brand colours are
      // still distinct and still the tokens' bytes, for the few places a
      // colour is the information itself (a chart series).
      final brands = ServiceKey.values.map((s) => s.brandAccent).toSet();
      expect(brands, hasLength(ServiceKey.values.length));
      expect(ServiceKey.radarr.brandAccent, AppColors.radarr);
      expect(ServiceKey.plex.brandAccent, AppColors.plex);
      expect(brands, isNot(contains(AppColors.lamp)));
    });
  });
}
