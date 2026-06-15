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

  // ── Reference palette ──
  // These are the *default-seed* (Midnight Violet) reference values, kept only
  // as the fallback seed and as the neutral dark text ramp. Everything visual
  // (gradients, surfaces, glass, glow) is now DERIVED from the active
  // ColorScheme / user seed below, so the premium look adapts to ANY preset
  // instead of always reading as fixed violet.
  static const Color brandAccent = Color(0xFF8B7BFF); // default seed color
  static const Color textPrimary = Color(0xFFECEDF6); // dark-mode primary text
  static const Color textSecondary = Color(0xFF9A9BB4); // dark-mode secondary
  static const Color textFaint = Color(0xFF8A8BA2);
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

  /// The signature accent gradient (~110°), fully DERIVED from the active
  /// scheme. The lead stop is `scheme.primary`; the mid/end stops are the
  /// primary hue rotated a touch warm then cool, so any seed yields a rich,
  /// harmonious three-stop sweep (the default violet seed reproduces the old
  /// accent→magenta→indigo Midnight Violet look automatically).
  ///
  /// Stop mapping (shared contract with the web app, see site teammate):
  ///   stop 0 = primary
  ///   stop 1 = hue +26°,  sat ×0.90,  light +0.04
  ///   stop 2 = hue −24°,  sat ×0.85,  light −0.02
  static LinearGradient accentGradient(ColorScheme s) {
    final base = HSLColor.fromColor(s.primary);
    final mid = base
        .withHue((base.hue + 26) % 360)
        .withSaturation((base.saturation * 0.90).clamp(0.45, 1.0))
        .withLightness((base.lightness + 0.04).clamp(0.0, 0.85))
        .toColor();
    final end = base
        .withHue((base.hue - 24 + 360) % 360)
        .withSaturation((base.saturation * 0.85).clamp(0.40, 1.0))
        .withLightness((base.lightness - 0.02).clamp(0.0, 0.85))
        .toColor();
    return LinearGradient(
      begin: const Alignment(-0.8, -1),
      end: const Alignment(0.8, 1),
      colors: [s.primary, mid, end],
    );
  }

  /// Near-black page background, tinted by the user's seed hue so the dark
  /// canvas belongs to the active theme instead of a fixed violet-black.
  /// Replaces the old hardcoded `brandBg` (#07070E).
  static Color darkBg(Color seed) {
    final hsl = HSLColor.fromColor(seed);
    return HSLColor.fromAHSL(
      1,
      hsl.hue,
      (hsl.saturation * 0.55).clamp(0.14, 0.50),
      0.045,
    ).toColor();
  }

  /// Slightly lifted panel/card surface for dark mode, same seed tint as
  /// [darkBg]. Replaces the old hardcoded `brandSurface` (#0D0D18).
  static Color darkPanel(Color seed) {
    final hsl = HSLColor.fromColor(seed);
    return HSLColor.fromAHSL(
      1,
      hsl.hue,
      (hsl.saturation * 0.42).clamp(0.10, 0.40),
      0.085,
    ).toColor();
  }

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
