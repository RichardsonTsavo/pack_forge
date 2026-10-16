// Tema do Pack Forge, baseado no design system do Linear
// (github.com/voltagent/awesome-design-md, design-md/linear.app).
//
// Canvas quase preto, escada de superfícies com bordas finas (sem sombras) e um
// único acento lavanda reservado para a ação principal e o foco.

import 'package:flutter/material.dart';

abstract final class AppColors {
  static const primary = Color(0xFF5E6AD2);
  static const primaryHover = Color(0xFF828FFF);
  static const primaryPressed = Color(0xFF5E69D1);
  static const onPrimary = Color(0xFFFFFFFF);

  static const ink = Color(0xFFF7F8F8);
  static const inkMuted = Color(0xFFD0D6E0);
  static const inkSubtle = Color(0xFF8A8F98);
  static const inkTertiary = Color(0xFF62666D);

  static const canvas = Color(0xFF010102);
  static const surface1 = Color(0xFF0F1011);
  static const surface2 = Color(0xFF141516);
  static const surface3 = Color(0xFF18191A);
  static const surface4 = Color(0xFF191A1B);

  static const hairline = Color(0xFF23252A);
  static const hairlineStrong = Color(0xFF34343A);
  static const hairlineTertiary = Color(0xFF3E3E44);

  static const success = Color(0xFF27A644);
  static const danger = Color(0xFFEB5757);
}

abstract final class AppRadius {
  static const xs = 4.0;
  static const sm = 6.0;
  static const md = 8.0;
  static const lg = 12.0;
}

const _fontFamily = 'Segoe UI';
const monoFontFamily = 'Cascadia Mono';
const monoFallback = ['Consolas', 'Courier New'];

abstract final class AppText {
  static const headline = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.2,
    letterSpacing: -0.6,
    color: AppColors.ink,
  );
  static const cardTitle = TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w500,
    height: 1.25,
    letterSpacing: -0.3,
    color: AppColors.ink,
  );
  static const body = TextStyle(fontSize: 14, height: 1.5, color: AppColors.ink);
  static const bodySubtle = TextStyle(fontSize: 14, height: 1.5, color: AppColors.inkSubtle);
  static const label = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w500,
    height: 1.3,
    color: AppColors.inkMuted,
  );
  static const caption = TextStyle(fontSize: 12, height: 1.4, color: AppColors.inkSubtle);
  static const eyebrow = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    height: 1.3,
    letterSpacing: 0.8,
    color: AppColors.inkSubtle,
  );
  static const mono = TextStyle(
    fontFamily: monoFontFamily,
    fontFamilyFallback: monoFallback,
    fontSize: 13,
    height: 1.5,
    fontWeight: FontWeight.w300,
    color: AppColors.inkMuted,
  );
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.primary,
    onPrimary: AppColors.onPrimary,
    secondary: AppColors.primary,
    onSecondary: AppColors.onPrimary,
    surface: AppColors.surface1,
    onSurface: AppColors.ink,
    onSurfaceVariant: AppColors.inkSubtle,
    outline: AppColors.hairlineStrong,
    outlineVariant: AppColors.hairline,
    error: AppColors.danger,
    onError: AppColors.onPrimary,
  );

  OutlineInputBorder border(Color color, [double width = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(AppRadius.md),
    borderSide: BorderSide(color: color, width: width),
  );

  final buttonShape = WidgetStatePropertyAll(
    RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
  );
  const buttonText = WidgetStatePropertyAll(
    TextStyle(fontFamily: _fontFamily, fontSize: 14, fontWeight: FontWeight.w500),
  );
  const buttonPadding = WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 14, vertical: 8));
  const buttonSize = WidgetStatePropertyAll(Size(0, 36));

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: AppColors.canvas,
    canvasColor: AppColors.canvas,
    dividerColor: AppColors.hairline,
    splashFactory: NoSplash.splashFactory,
    hoverColor: AppColors.surface3,
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.primary,
      selectionColor: AppColors.primary.withValues(alpha: 0.35),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: AppColors.surface4,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: AppColors.hairlineStrong),
      ),
      textStyle: AppText.caption.copyWith(color: AppColors.ink),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface2,
      hoverColor: AppColors.surface3,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      hintStyle: AppText.body.copyWith(color: AppColors.inkTertiary),
      errorStyle: AppText.caption.copyWith(color: AppColors.danger),
      border: border(AppColors.hairline),
      enabledBorder: border(AppColors.hairline),
      disabledBorder: border(AppColors.hairline),
      focusedBorder: border(AppColors.primary.withValues(alpha: 0.7), 1.5),
      errorBorder: border(AppColors.danger.withValues(alpha: 0.6)),
      focusedErrorBorder: border(AppColors.danger, 1.5),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        textStyle: buttonText,
        padding: buttonPadding,
        minimumSize: buttonSize,
        elevation: const WidgetStatePropertyAll(0),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? AppColors.inkTertiary : AppColors.onPrimary,
        ),
        backgroundColor: WidgetStateProperty.resolveWith((s) {
          if (s.contains(WidgetState.disabled)) return AppColors.surface3;
          if (s.contains(WidgetState.pressed)) return AppColors.primaryPressed;
          if (s.contains(WidgetState.hovered)) return AppColors.primaryHover;
          return AppColors.primary;
        }),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        textStyle: buttonText,
        padding: buttonPadding,
        minimumSize: buttonSize,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.disabled) ? AppColors.inkTertiary : AppColors.ink,
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.hovered) ? AppColors.surface4 : AppColors.surface2,
        ),
        side: WidgetStateProperty.resolveWith(
          (s) => BorderSide(
            color: s.contains(WidgetState.hovered)
                ? AppColors.hairlineTertiary
                : AppColors.hairlineStrong,
          ),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        shape: buttonShape,
        textStyle: buttonText,
        padding: buttonPadding,
        minimumSize: buttonSize,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.hovered) ? AppColors.ink : AppColors.inkSubtle,
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.hovered) ? AppColors.ink : AppColors.inkSubtle,
        ),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.primary,
      linearTrackColor: AppColors.hairline,
      linearMinHeight: 3,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.surface2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.hairlineStrong),
      ),
      titleTextStyle: AppText.cardTitle,
      contentTextStyle: AppText.bodySubtle,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(AppColors.hairlineTertiary.withValues(alpha: 0.8)),
      radius: const Radius.circular(AppRadius.xs),
      thickness: const WidgetStatePropertyAll(6),
    ),
  );
}
