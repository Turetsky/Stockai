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

  // ── Midnight Violet brand palette (shared with the web app) ──
  static const Color brandBg = Color(0xFF07070E); // page background
  static const Color brandSurface = Color(0xFF0D0D18); // cards / panels
  static const Color brandAccent = Color(0xFF8B7BFF); // primary accent
  static const Color brandMid = Color(0xFFB06AD6); // gradient mid stop
  static const Color brandEnd = Color(0xFF667EEA); // gradient end stop
  static const Color textPrimary = Color(0xFFECEDF6);
  static const Color textSecondary = Color(0xFF9A9BB4);
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

  /// The Midnight Violet brand gradient (~110°): accent → mid → indigo.
  /// Anchored on the scheme's primary so a custom seed still leads, falling
  /// through the brand mid/end stops.
  static LinearGradient accentGradient(ColorScheme s) => LinearGradient(
        begin: const Alignment(-0.8, -1),
        end: const Alignment(0.8, 1),
        colors: [s.primary, brandMid, brandEnd],
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
