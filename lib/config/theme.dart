import 'package:flutter/material.dart';

/// Sistema de Diseño 60-30-10 para Flutter Mobile (Light & Dark Mode)
class AppTheme {
  // ── PALETA MODO CLARO ──────────────────────────────────────────────────────
  static const Color lightBg          = Color(0xFFEFECE6); // Warm off-white
  static const Color lightSurface     = Color(0xFFE5E0D6); // Warm surface
  static const Color lightCard        = Color(0xFFFFFFFF); // Clean white card
  static const Color lightInput       = Color(0xFFFFFFFF); // Clean white input
  static const Color lightTextPrimary = Color(0xFF132537); // Deep navy
  static const Color lightTextSecondary = Color(0xFF395267); // Slate navy muted
  static const Color lightTextMuted   = Color(0xFF627B8E); // Dim slate
  static const Color lightBorder      = Color(0x24132537); // rgba(19, 37, 55, 0.14)
  static const Color lightAccent      = Color(0xFFD97706); // Amber
  static const Color lightAccentGlow  = Color(0x1FD97706); // rgba(217, 119, 6, 0.12)
  static const Color lightAccentBorder= Color(0x40D97706); // rgba(217, 119, 6, 0.25)

  // ── PALETA MODO OSCURO ─────────────────────────────────────────────────────
  static const Color darkBg           = Color(0xFF0A1120); // Deep Navy Dark
  static const Color darkSurface      = Color(0xFF0F192C); // Dark Navy Surface
  static const Color darkCard         = Color(0xFF131F33); // Dark Card Surface
  static const Color darkInput        = Color(0xFF0E1726); // Dark Input Surface
  static const Color darkTextPrimary  = Color(0xFFF4F1EA); // Warm high contrast
  static const Color darkTextSecondary= Color(0xFF94A3B8); // Slate 400
  static const Color darkTextMuted    = Color(0xFF64748B); // Slate 500
  static const Color darkBorder       = Color(0x1AF4F1EA); // rgba(244, 241, 234, 0.10)
  static const Color darkAccent       = Color(0xFFF59E0B); // Amber Bright
  static const Color darkAccentGlow   = Color(0x24F59E0B); // rgba(245, 158, 11, 0.14)
  static const Color darkAccentBorder = Color(0x4DF59E0B); // rgba(245, 158, 11, 0.30)

  // ── Constantes y Estados ───────────────────────────────────────────────────
  static const Color accentColor      = Color(0xFFD97706);
  static const Color successColor     = Color(0xFF059669);
  static const Color successBg        = Color(0x1A059669);
  static const Color errorColor       = Color(0xFFDC2626);
  static const Color errorBg          = Color(0x1ADC2626);
  static const Color warningColor     = Color(0xFFD97706);

  // ── Compatibilidad Directa ─────────────────────────────────────────────────
  static const Color backgroundColor = lightBg;
  static const Color cardColor       = lightCard;
  static const Color textPrimary     = lightTextPrimary;
  static const Color textSecondary   = lightTextSecondary;
  static const Color textMuted       = lightTextMuted;
  static const Color borderColor     = lightBorder;
  static const Color accentLight     = lightAccent;

  // ── Radios del Sistema ────────────────────────────────────────────────────
  static const double borderRadiusSmall  = 6.0;
  static const double borderRadiusMedium = 10.0;
  static const double borderRadiusLarge  = 16.0;

  // ── Helpers dinámicos según contexto ──────────────────────────────────────
  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color getBg(BuildContext context) =>
      isDark(context) ? darkBg : lightBg;

  static Color getCardBg(BuildContext context) =>
      isDark(context) ? darkCard : lightCard;

  static Color getInputBg(BuildContext context) =>
      isDark(context) ? darkInput : lightInput;

  static Color getTextPrimary(BuildContext context) =>
      isDark(context) ? darkTextPrimary : lightTextPrimary;

  static Color getTextSecondary(BuildContext context) =>
      isDark(context) ? darkTextSecondary : lightTextSecondary;

  static Color getTextMuted(BuildContext context) =>
      isDark(context) ? darkTextMuted : lightTextMuted;

  static Color getBorder(BuildContext context) =>
      isDark(context) ? darkBorder : lightBorder;

  static Color getAccent(BuildContext context) =>
      isDark(context) ? darkAccent : lightAccent;

  static BoxDecoration cardDecorationOf(BuildContext context) {
    final dark = isDark(context);
    return BoxDecoration(
      color: dark ? darkCard : lightCard,
      borderRadius: BorderRadius.circular(borderRadiusLarge),
      border: Border.all(
        color: dark ? darkBorder : lightBorder,
        width: 1,
      ),
      boxShadow: [
        BoxShadow(
          color: dark ? const Color(0x50000000) : const Color(0x12000000),
          blurRadius: dark ? 12 : 6,
          offset: const Offset(0, 2),
        ),
      ],
    );
  }

  static BoxDecoration logoBadgeDecorationOf(BuildContext context) {
    final dark = isDark(context);
    return BoxDecoration(
      color: dark ? darkAccentGlow : lightAccentGlow,
      borderRadius: BorderRadius.circular(borderRadiusMedium),
      border: Border.all(
        color: dark ? darkAccentBorder : lightAccentBorder,
        width: 1,
      ),
    );
  }

  static InputDecoration inputDecorationOf(
    BuildContext context, {
    required IconData icon,
    String? hint,
    Widget? suffixIcon,
  }) {
    final dark = isDark(context);
    final border = dark ? darkBorder : lightBorder;
    final accent = dark ? darkAccent : lightAccent;
    final muted = dark ? darkTextMuted : lightTextMuted;
    final fill = dark ? darkInput : lightInput;

    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon, color: muted, size: 20),
      suffixIcon: suffixIcon,
      hintStyle: TextStyle(color: muted, fontSize: 14),
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: BorderSide(color: border, width: 1),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: BorderSide(color: border, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: BorderSide(color: accent, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: const BorderSide(color: errorColor, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(borderRadiusMedium),
        borderSide: const BorderSide(color: errorColor, width: 1.5),
      ),
      errorStyle: const TextStyle(color: errorColor, fontSize: 12),
    );
  }

  // ── Light Theme ───────────────────────────────────────────────────────────
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBg,
      primaryColor: lightAccent,
      colorScheme: const ColorScheme.light(
        primary: lightAccent,
        secondary: Color(0xFFB45309),
        surface: lightCard,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: lightTextPrimary,
        onError: Colors.white,
      ),
      fontFamily: 'Roboto',
      dividerColor: lightBorder,
      cardColor: lightCard,
    );
  }

  // ── Dark Theme ────────────────────────────────────────────────────────────
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBg,
      primaryColor: darkAccent,
      colorScheme: const ColorScheme.dark(
        primary: darkAccent,
        secondary: Color(0xFFD97706),
        surface: darkCard,
        error: errorColor,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: darkTextPrimary,
        onError: Colors.white,
      ),
      fontFamily: 'Roboto',
      dividerColor: darkBorder,
      cardColor: darkCard,
    );
  }
}
