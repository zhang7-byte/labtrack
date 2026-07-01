import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The Section 9 design-language tokens — a warm-paper palette. Sidebar, top bar,
/// content and input all draw from one background family; `surface` is reserved
/// for genuinely lifted things (input, dialogs, hovered rows). These are the
/// "CSS variables" the whole app themes through.
class _Tokens {
  const _Tokens({
    required this.bg,
    required this.bgSidebar,
    required this.surface,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.hover,
    required this.selected,
    required this.shadow,
  });

  final Color bg; // main surface (warm paper)
  final Color bgSidebar; // a touch deeper, for gentle zoning
  final Color surface; // lifted cards/inputs/dialogs
  final Color border; // hairline dividers only
  final Color text;
  final Color textMuted;
  final Color hover;
  final Color selected;
  final Color shadow; // soft float shadow tone

  static const light = _Tokens(
    bg: Color(0xFFFAF9F5),
    bgSidebar: Color(0xFFF2F1EB),
    surface: Color(0xFFFFFFFF),
    border: Color(0x12141310), // rgba(20,19,15,0.07)
    text: Color(0xFF1A1915),
    textMuted: Color(0xFF6B6A63),
    hover: Color(0x0A141310), // 0.04
    selected: Color(0x0F141310), // 0.06
    shadow: Color(0x14141310), // soft, ~0.08
  );

  static const dark = _Tokens(
    bg: Color(0xFF1E1D1A),
    bgSidebar: Color(0xFF191815),
    surface: Color(0xFF262421),
    border: Color(0x14FFFFFF), // 0.08
    text: Color(0xFFECEAE3),
    textMuted: Color(0xFF9C9A92),
    hover: Color(0x0DFFFFFF), // 0.05
    selected: Color(0x14FFFFFF), // 0.08
    shadow: Color(0x66000000), // 0.4
  );
}

/// Default accent — warm terracotta (Section 9). Lightened slightly in dark.
const labAccentLight = Color(0xFFC96442);
const labAccentDark = Color(0xFFD97757);

Color _accentFor(Color a, bool dark) {
  if (!dark) return a;
  final hsl = HSLColor.fromColor(a);
  return hsl.withLightness((hsl.lightness + 0.08).clamp(0.0, 1.0)).toColor();
}

Color _onAccent(Color a) =>
    a.computeLuminance() > 0.55 ? const Color(0xFF1A1915) : Colors.white;

/// Builds the app theme from the warm-paper tokens. [accent] is the user's
/// chosen accent (default terracotta); [customBg] makes scaffolds transparent so
/// a custom background (8.1) shows through.
ThemeData buildAppTheme({
  required Brightness brightness,
  required Color accent,
  required VisualDensity density,
  required bool customBg,
}) {
  final dark = brightness == Brightness.dark;
  final t = dark ? _Tokens.dark : _Tokens.light;
  final acc = _accentFor(accent, dark);
  final accentSoft = acc.withValues(alpha: dark ? 0.16 : 0.10);
  final radius = BorderRadius.circular(10);
  final radiusLg = BorderRadius.circular(16);

  // iOS leans into the Liquid Glass aesthetic: controls are capsule "pills".
  // Other platforms keep the default rounded-rect buttons.
  final isIOS = defaultTargetPlatform == TargetPlatform.iOS;
  const pillShape = StadiumBorder();

  final scheme = ColorScheme.fromSeed(seedColor: acc, brightness: brightness)
      .copyWith(
    primary: acc,
    onPrimary: _onAccent(acc),
    primaryContainer: accentSoft,
    onPrimaryContainer: acc,
    secondaryContainer: accentSoft,
    onSecondaryContainer: t.text,
    surface: t.bg,
    onSurface: t.text,
    onSurfaceVariant: t.textMuted,
    // Lifted container roles (cards/dialogs/menus) use the raised surface;
    // the lowest tone is the sidebar paper.
    surfaceContainerLowest: t.bgSidebar,
    surfaceContainerLow: t.surface,
    surfaceContainer: t.surface,
    surfaceContainerHigh: t.surface,
    surfaceContainerHighest: t.surface,
    outline: t.border,
    outlineVariant: t.border,
    shadow: t.shadow,
  );

  final baseText = (dark ? Typography.material2021().white
          : Typography.material2021().black)
      .apply(bodyColor: t.text, displayColor: t.text);

  // Edge-to-edge on mobile: transparent system bars with the OS "contrast" scrim
  // off, so the app's frosted background runs under the status and gesture-nav
  // bars instead of leaving a dark band. Carried by every AppBar (which would
  // otherwise re-impose its own overlay) and matched by the global style in main.
  final systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    statusBarBrightness: dark ? Brightness.dark : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarContrastEnforced: false,
    systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    visualDensity: density,
    textTheme: baseText,
    scaffoldBackgroundColor: customBg ? Colors.transparent : t.bg,
    canvasColor: t.bg,
    dividerColor: t.border,
    hoverColor: t.hover,
    splashColor: t.selected,
    highlightColor: t.hover,
    shadowColor: t.shadow,
    dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),

    // Top bar reads as part of the content surface — no tint, no seam shadow.
    appBarTheme: AppBarTheme(
      backgroundColor: customBg ? Colors.transparent : t.bg,
      surfaceTintColor: Colors.transparent,
      foregroundColor: t.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      systemOverlayStyle: systemOverlay,
      titleTextStyle: baseText.titleLarge?.copyWith(fontWeight: FontWeight.w600),
    ),

    // Sidebar: a gentle tone shift, no hard edge.
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: customBg ? Colors.transparent : t.bgSidebar,
      indicatorColor: accentSoft,
      elevation: 0,
      selectedIconTheme: IconThemeData(color: acc),
      unselectedIconTheme: IconThemeData(color: t.textMuted),
      selectedLabelTextStyle:
          TextStyle(color: acc, fontWeight: FontWeight.w600, fontSize: 12),
      unselectedLabelTextStyle: TextStyle(color: t.textMuted, fontSize: 12),
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      indicatorColor: accentSoft,
      elevation: 0,
      iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
          color: s.contains(WidgetState.selected) ? acc : t.textMuted)),
      labelTextStyle: WidgetStateProperty.resolveWith((s) => TextStyle(
          fontSize: 12,
          color: s.contains(WidgetState.selected) ? acc : t.textMuted,
          fontWeight:
              s.contains(WidgetState.selected) ? FontWeight.w600 : null)),
    ),

    // Flat zones, not boxes: no elevation, no border, no surface tint. Over a
    // custom background the card is a plain semi-transparent fill on the single
    // frosted content surface (no nested blur).
    cardTheme: CardThemeData(
      color: customBg ? t.surface.withValues(alpha: 0.5) : t.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: radiusLg),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: radiusLg),
    ),

    popupMenuTheme: PopupMenuThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: radius),
    ),

    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(t.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),

    listTileTheme: ListTileThemeData(
      selectedColor: acc,
      selectedTileColor: accentSoft,
      iconColor: t.textMuted,
    ),

    // Capsule buttons on iOS (Liquid Glass); untouched elsewhere.
    filledButtonTheme: isIOS
        ? FilledButtonThemeData(style: FilledButton.styleFrom(shape: pillShape))
        : null,
    elevatedButtonTheme: isIOS
        ? ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(shape: pillShape))
        : null,
    outlinedButtonTheme: isIOS
        ? OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(shape: pillShape))
        : null,
    textButtonTheme: isIOS
        ? TextButtonThemeData(style: TextButton.styleFrom(shape: pillShape))
        : null,

    // Inputs are genuinely lifted: filled with the raised surface, hairline edge.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: t.surface,
      hintStyle: TextStyle(color: t.textMuted),
      labelStyle: TextStyle(color: t.textMuted),
      border: OutlineInputBorder(
          borderRadius: radius, borderSide: BorderSide(color: t.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: radius, borderSide: BorderSide(color: t.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: radius, borderSide: BorderSide(color: acc, width: 1.5)),
    ),

    searchBarTheme: SearchBarThemeData(
      backgroundColor: WidgetStatePropertyAll(t.surface),
      surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      overlayColor: WidgetStatePropertyAll(t.hover),
      elevation: const WidgetStatePropertyAll(1.5),
      shadowColor: WidgetStatePropertyAll(t.shadow),
      hintStyle: WidgetStatePropertyAll(TextStyle(color: t.textMuted)),
      shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: t.bgSidebar,
      side: BorderSide(color: t.border),
      surfaceTintColor: Colors.transparent,
      labelStyle: TextStyle(color: t.text, fontSize: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),

    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) =>
            s.contains(WidgetState.selected) ? accentSoft : Colors.transparent),
        side: WidgetStatePropertyAll(BorderSide(color: t.border)),
      ),
    ),

    // A thin, rounded, low-contrast thumb that floats over the content and
    // matches the muted-paper palette — instead of the chunky grey default.
    // It thickens and darkens a touch on hover/drag for grab-ability, with no
    // visible track.
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.hovered) || s.contains(WidgetState.dragged)
              ? 9
              : 6),
      radius: const Radius.circular(8),
      thumbColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.dragged)) {
          return t.textMuted.withValues(alpha: 0.6);
        }
        if (s.contains(WidgetState.hovered)) {
          return t.textMuted.withValues(alpha: 0.45);
        }
        return t.textMuted.withValues(alpha: 0.26);
      }),
      trackColor: const WidgetStatePropertyAll(Colors.transparent),
      trackBorderColor: const WidgetStatePropertyAll(Colors.transparent),
      crossAxisMargin: 3,
      mainAxisMargin: 4,
      minThumbLength: 40,
      interactive: true,
    ),
  );
}
