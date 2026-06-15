import 'dart:ui';
import 'package:flutter/material.dart';

/// Centralized "AI console" design language for StockAI.
///
/// Dark-first, premium look built from gradient + glass accents that adapt to
/// the active [ColorScheme] (and therefore the user's seed color + light/dark
/// theme). Screens compose the helpers/widgets here instead of hand-rolling
/// colors, so the look stays consistent and easy to tune in one place.
class AppStyle {
  AppStyle._();

  // ── Midnight Violet dark baseline (shared with the web app) ──
  // The dark canvas/panels stay MV by default (web keeps these fixed too: the
  // decorative mesh is hardcoded, glass is theme-neutral white-alpha). The
  // THEME-DYNAMIC piece is the accent gradient (below), which mirrors web's
  // --clr-start / --clr-end exactly.
  static const Color brandBg = Color(0xFF07070E); // page background (dark)
  static const Color brandSurface = Color(0xFF0D0D18); // cards / panels (dark)
  static const Color brandAccent = Color(0xFF8B7BFF); // default seed color
  static const Color textPrimary = Color(0xFFECEDF6); // dark-mode primary text
  static const Color textSecondary = Color(0xFF9A9BB4); // dark-mode secondary
  static const Color textFaint = Color(0xFF8A8BA2);

  // ── Accent gradient stops (theme-dynamic, web-parity) ──
  // Mirrors the web app-screens' `--clr-start` / `--clr-end`. Defaults are the
  // literal CSS defaults so a brand-new user (no ui_settings) matches web
  // pixel-for-pixel. `main.dart` syncs these from the active ThemeSettings
  // (sourced from the `primary_color_start` / `primary_color_end` keys) before
  // building the themes, so every `accentGradient` call site re-tints with no
  // per-site change.
  static const Color gradientStartDefault = Color(0xFF8B7BFF); // --clr-start
  static const Color gradientEndDefault = Color(0xFF667EEA); // --clr-end
  static Color gradientStart = gradientStartDefault;
  static Color gradientEnd = gradientEndDefault;

  /// INTERIM companion-stop derivation for app-side seed/preset changes.
  ///
  /// The app's Settings has a single "Primary" picker, but the gradient needs
  /// two stops. This derives the END stop from a chosen START using the same
  /// relationship the default pair has (#8B7BFF → #667EEA): hue −18°, sat ×0.80,
  /// lightness ×0.90. Returns the literal #667EEA default when given the default
  /// start, so the no-change case stays pixel-identical to web.
  ///
  /// TODO(parity): replace with web's exact per-preset start/end pairs +
  /// custom-edit formula once site confirms, so app writes match web writes.
  static Color deriveGradientEnd(Color start) {
    if (start.toARGB32() == gradientStartDefault.toARGB32()) {
      return gradientEndDefault;
    }
    final hsl = HSLColor.fromColor(start);
    return hsl
        .withHue((hsl.hue - 18 + 360) % 360)
        .withSaturation((hsl.saturation * 0.80).clamp(0.0, 1.0))
        .withLightness((hsl.lightness * 0.90).clamp(0.0, 1.0))
        .toColor();
  }
  // Status colors
  static const Color ok = Color(0xFF4ADE80);
  static const Color lowStock = Color(0xFFFB7185);
  static const Color edit = Color(0xFFFBBF24);
  static const Color cyan = Color(0xFF59D6E6);

  // Corner radii
  static const double rCard = 18;
  static const double rBubble = 20;
  static const double rPill = 28;

  // Motion
  static const Duration fast = Duration(milliseconds: 180);
  static const Duration med = Duration(milliseconds: 280);

  /// The signature accent gradient — THEME-DYNAMIC, mirroring the web
  /// app-screens. Two stops (`gradientStart` 0% → `gradientEnd` 100%) on a 110°
  /// diagonal, matching CSS `linear-gradient(110deg, START 0%, END 100%)`.
  /// The `s` parameter is retained so existing `accentGradient(scheme)` call
  /// sites are untouched; the stops come from the synced theme colors.
  ///
  /// 110° → Flutter alignment: begin (-1.0, -0.36) → end (1.0, 0.36).
  static LinearGradient accentGradient(ColorScheme s) => LinearGradient(
        begin: const Alignment(-1.0, -0.36),
        end: const Alignment(1.0, 0.36),
        colors: [gradientStart, gradientEnd],
      );

  /// Hairline border color appropriate to the active brightness.
  static Color hairline(ColorScheme s) => s.brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.black.withValues(alpha: 0.07);

  /// Translucent "glass" fill for cards/bubbles (no blur — cheap for lists).
  static Color glassFill(ColorScheme s) => s.brightness == Brightness.dark
      ? Colors.white.withValues(alpha: 0.06)
      : Colors.white.withValues(alpha: 0.72);
}

/// A frosted-glass surface: translucent fill + hairline border, optionally a
/// real backdrop blur (reserve `blur: true` for a handful of elements such as
/// the top bar — blurring long lists is expensive).
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool blur;
  final Color? color;

  const GlassCard({
    super.key,
    required this.child,
    this.padding,
    this.radius = AppStyle.rCard,
    this.blur = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fill = color ?? AppStyle.glassFill(scheme);
    final border = Border.all(color: AppStyle.hairline(scheme), width: 1);
    final shape = BorderRadius.circular(radius);

    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fill,
        borderRadius: shape,
        border: border,
      ),
      child: child,
    );

    if (!blur) return content;
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: content,
      ),
    );
  }
}

/// A soft radial accent glow, meant to sit behind headers / empty states to
/// give the screen depth without a heavy gradient background.
class AccentGlow extends StatelessWidget {
  final Alignment alignment;
  final double radius;
  final double opacity;

  const AccentGlow({
    super.key,
    this.alignment = Alignment.topCenter,
    this.radius = 220,
    this.opacity = 0.22,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                scheme.primary.withValues(alpha: opacity),
                scheme.primary.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
