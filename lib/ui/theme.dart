import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Couleurs de l'application. Les maquettes validées sont en mode nuit ;
/// le mode jour reprend les mêmes teintes, éclaircies, pour être lisible
/// en plein soleil.
///
/// Les couleurs changent avec [Palette.use] : l'application reconstruit
/// alors tous les écrans (voir `main.dart`).
abstract final class Palette {
  static bool _dark = true;
  static bool get isDark => _dark;
  static void use(Brightness b) => _dark = b == Brightness.dark;

  static Color _pick(int dark, int light) => Color(_dark ? dark : light);

  static Color get ground => _pick(0xFF111614, 0xFFF3F6F4);
  static Color get card => _pick(0xFF1B2420, 0xFFFFFFFF);
  static Color get cardHigh => _pick(0xFF222E29, 0xFFEBF0ED);
  static Color get line => _pick(0xFF2E3D36, 0xFFDCE4DF);
  static Color get text => _pick(0xFFFFFFFF, 0xFF14201B);
  static Color get muted => _pick(0xFF9AA8A1, 0xFF5D6B64);
  static Color get green => _pick(0xFF1F6B4F, 0xFF1F6B4F);
  static Color get mint => _pick(0xFF7FD3A8, 0xFF13774F);
  static Color get amber => _pick(0xFFF2B544, 0xFFB07400);
  static Color get red => _pick(0xFFF28B7A, 0xFFC0392B);
  static Color get blue => _pick(0xFF8DB6F2, 0xFF2F68C4);
  static Color get grey => _pick(0xFF8A948F, 0xFF7A847F);
  static Color get purple => _pick(0xFFCFA6E8, 0xFF8246AE);

  /// Texte sur fond clair (bulles de l'assistant, boutons ambre) : ne change
  /// pas avec le mode.
  static const ink = Color(0xFF13201B);

  /// Grand encadré vert du tableau de bord.
  static Color get hero => _pick(0xFF18302A, 0xFFE2F1E9);

  /// Petites cases posées sur [hero].
  static Color get heroTile => _pick(0xFF1D2D26, 0xFFFFFFFF);

  /// Barres du graphique des 7 jours (sauf aujourd'hui).
  static Color get bar => _pick(0xFF2F4239, 0xFFBFD8CB);

  /// Fonds teintés des bandeaux d'alerte, d'avertissement et de succès.
  static Color get redSoft => _pick(0xFF3A1F1B, 0xFFFCE9E6);
  static Color get amberSoft => _pick(0xFF2A2414, 0xFFFFF3D9);
  static Color get mintSoft => _pick(0xFF1F3A2F, 0xFFDDF0E5);

  /// Fond de l'écran de l'assistant et bulle de l'utilisateur.
  static Color get deep => _pick(0xFF0E1814, 0xFFE9EFEC);
  static Color get bubble => _pick(0xFF22332C, 0xFFD3E6DC);

  /// Contour discret (cases vides du code secret).
  static Color get faint => _pick(0xFF4A5A52, 0xFFB5C1BA);
}

/// Police de l'application : Inter, embarquée (pas besoin d'internet).
const appFont = 'Inter';

/// Chiffres de même largeur : les montants restent alignés en colonne et ne
/// « sautent » pas quand ils changent.
const tabular = [FontFeature.tabularFigures()];

/// Durées et courbes communes, pour des animations cohérentes partout.
abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 600);
  static const curve = Curves.easeOutCubic;
}

ThemeData buildTheme([Brightness brightness = Brightness.dark]) {
  Palette.use(brightness);
  final dark = brightness == Brightness.dark;
  final scheme = (dark ? const ColorScheme.dark() : const ColorScheme.light())
      .copyWith(
        primary: Palette.mint,
        onPrimary: dark ? Palette.ink : Colors.white,
        secondary: Palette.amber,
        onSecondary: Palette.ink,
        surface: Palette.card,
        onSurface: Palette.text,
        onSurfaceVariant: Palette.muted,
        surfaceContainerHighest: Palette.cardHigh,
        outline: Palette.line,
        outlineVariant: Palette.line,
        error: Palette.red,
      );
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: appFont,
    scaffoldBackgroundColor: Palette.ground,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
  );
  TextStyle? tab(TextStyle? s) => s?.copyWith(fontFeatures: tabular);
  final t = base.textTheme.apply(
    bodyColor: Palette.text,
    displayColor: Palette.text,
  );
  return base.copyWith(
    textTheme: t.copyWith(
      displayLarge: tab(t.displayLarge),
      displayMedium: tab(t.displayMedium),
      displaySmall: tab(t.displaySmall),
      headlineLarge: tab(t.headlineLarge),
      headlineMedium: tab(t.headlineMedium),
      headlineSmall: tab(t.headlineSmall),
      titleLarge: tab(t.titleLarge),
      titleMedium: tab(t.titleMedium),
      titleSmall: tab(t.titleSmall),
      bodyLarge: tab(t.bodyLarge),
      bodyMedium: tab(t.bodyMedium),
      bodySmall: tab(t.bodySmall),
      labelLarge: tab(t.labelLarge),
      labelMedium: tab(t.labelMedium),
      labelSmall: tab(t.labelSmall),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Palette.ground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: false,
      systemOverlayStyle: overlayStyle(brightness),
      titleTextStyle: TextStyle(
        fontFamily: appFont,
        fontSize: 22,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        color: Palette.text,
      ),
    ),
    cardTheme: CardThemeData(
      color: Palette.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    dividerTheme: DividerThemeData(color: Palette.line, thickness: 1),
    listTileTheme: ListTileThemeData(
      iconColor: Palette.muted,
      subtitleTextStyle: TextStyle(
        fontFamily: appFont,
        fontSize: 13,
        color: Palette.muted,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Palette.card,
      indicatorColor: Palette.cardHigh,
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontFamily: appFont,
          fontSize: 12,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w500,
          color: s.contains(WidgetState.selected)
              ? Palette.text
              : Palette.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? Palette.text
              : Palette.muted,
        ),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: Palette.green,
        foregroundColor: Colors.white,
        disabledBackgroundColor: Palette.cardHigh,
        disabledForegroundColor: Palette.muted,
        minimumSize: const Size(48, 54),
        textStyle: const TextStyle(
          fontFamily: appFont,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Palette.text,
        minimumSize: const Size(48, 48),
        side: BorderSide(color: Palette.line),
        textStyle: const TextStyle(
          fontFamily: appFont,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: Palette.mint,
        textStyle: const TextStyle(
          fontFamily: appFont,
          fontSize: 15,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Palette.card,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Palette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Palette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Palette.mint, width: 2),
      ),
      hintStyle: TextStyle(color: Palette.muted),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Palette.card,
      selectedColor: Palette.amber,
      side: BorderSide(color: Palette.line),
      labelStyle: const TextStyle(
        fontFamily: appFont,
        fontWeight: FontWeight.w700,
      ),
      secondaryLabelStyle: const TextStyle(
        fontFamily: appFont,
        fontWeight: FontWeight.w700,
        color: Palette.ink,
      ),
      showCheckmark: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: Palette.card,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: Palette.card,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: Palette.line,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: Palette.mint,
      linearTrackColor: Palette.cardHigh,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? Palette.cardHigh : Palette.ink,
      contentTextStyle: const TextStyle(
        fontFamily: appFont,
        color: Colors.white,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      actionTextColor: Palette.isDark ? Palette.mint : const Color(0xFF7FD3A8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
    ),
  );
}

/// Icônes claires sur fond sombre, et l'inverse, pour la barre d'état et la
/// barre de navigation du téléphone.
SystemUiOverlayStyle overlayStyle(Brightness b) =>
    (b == Brightness.dark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(
          statusBarColor: Colors.transparent,
          systemNavigationBarColor: Palette.card,
        );
