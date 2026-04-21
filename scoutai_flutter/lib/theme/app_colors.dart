import 'package:flutter/material.dart';

class AppColors {
  // ── Dark palette (default) ──
  static const background = Color(0xFF0B1220);
  static const surface = Color(0xFF121B2B);
  static const surface2 = Color(0xFF0F1726);
  static const primary = Color(0xFF1D63FF);
  static const accent = Color(0xFFB7F408);
  static const text = Color(0xFFE9EEF8);
  static const textMuted = Color(0xFF9AA6BD);
  static const border = Color(0xFF27314A);
  static const success = Color(0xFF32D583);
  static const warning = Color(0xFFFDB022);
  static const danger = Color(0xFFFF4D4F);

  // ── Light palette ──
  static const backgroundLight = Color(0xFFF5F6FA);
  static const surfaceLight = Color(0xFFFFFFFF);
  static const surface2Light = Color(0xFFF0F1F5);
  static const textLight = Color(0xFF1A1D26);
  static const textMutedLight = Color(0xFF6B7280);
  static const borderLight = Color(0xFFD1D5DB);

  /// Resolve a color based on current brightness.
  static Color resolve(BuildContext context, Color dark, Color light) {
    return Theme.of(context).brightness == Brightness.dark ? dark : light;
  }

  // Convenience resolvers for the most-used colors
  static Color bg(BuildContext context) => resolve(context, background, backgroundLight);
  static Color surf(BuildContext context) => resolve(context, surface, surfaceLight);
  static Color surf2(BuildContext context) => resolve(context, surface2, surface2Light);
  static Color tx(BuildContext context) => resolve(context, text, textLight);
  static Color txMuted(BuildContext context) => resolve(context, textMuted, textMutedLight);
  static Color bdr(BuildContext context) => resolve(context, border, borderLight);
}
