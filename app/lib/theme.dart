import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// EcoPulse "Endüstriyel Kontrol Odası" renk tokenları (yüksek performanslı HMI yaklaşımı:
/// nötr mat zemin, renk yalnızca durum bildirdiğinde). Uygulamadaki tüm renkler buradan gelir.
class AppColors {
  // Zemin: endüstriyel antrasit ve mat koyu gri
  static const background = Color(0xFF181A1B);
  static const surface = Color(0xFF212529);
  static const surfaceHigh = Color(0xFF2A2F34);
  static const inset = Color(0xFF1C1F21);
  static const line = Color(0xFF343A40);

  // Metin
  static const text = Color(0xFFE6E9EC);
  static const muted = Color(0xFF9AA3AB);

  // Normal durum: mat zümrüt (dolgu) ve okunur açık tonu (metin / rakam)
  static const primary = Color(0xFF2E7D32);
  static const accent = Color(0xFF7CB98A);
  static const emerald = Color(0xFF6FAF7C);
  static const terminal = Color(0xFF8FA9BF);
  static const onPrimary = Color(0xFFFFFFFF);

  // Bilgi / gezinme: endüstriyel çelik mavisi
  static const steel = Color(0xFF5B8DB8);

  // Alarm yönetimi: yumuşak ama dikkat çekici
  static const amber = Color(0xFFE0A43A);
  static const orange = Color(0xFFD9823B);
  static const alarm = Color(0xFFD0534B);

  // Trend kalemleri: pastel, ayırt edilebilir tonlar
  static const voltage = Color(0xFFB39DDB);
  static const current = Color(0xFF8BC48A);
  static const temperature = Color(0xFFF2B66D);
  static const water = Color(0xFF6FA8DC);
}

/// Eş aralıklı rakam yazısı (kontrol odası okumaları için).
class EcoText {
  static const _mono = 'Consolas';
  static const _fallback = ['Cascadia Mono', 'Menlo', 'RobotoMono', 'monospace'];

  static TextStyle mono({
    double size = 12,
    Color? color,
    FontWeight weight = FontWeight.w500,
    double letterSpacing = 0,
    List<Shadow>? shadows,
  }) {
    return TextStyle(
      fontFamily: _mono,
      fontFamilyFallback: _fallback,
      fontSize: size,
      color: color,
      fontWeight: weight,
      letterSpacing: letterSpacing,
      shadows: shadows,
      fontFeatures: const [ui.FontFeature.tabularFigures()],
    );
  }
}

/// Düz antrasit zemin.
class EcoBackground extends StatelessWidget {
  const EcoBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(color: AppColors.background, child: child);
  }
}

/// Mat panel: düz yüzey, ince gri kenar. [glow] yalnızca durum vurgusu için kenarı renklendirir.
class GlassCard extends StatelessWidget {
  const GlassCard({
    required this.child,
    this.padding = 16,
    this.accent,
    this.glow = false,
    this.radius = 8,
    super.key,
  });

  final Widget child;
  final double padding;
  final Color? accent;
  final bool glow;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final edge = glow && accent != null ? accent!.withValues(alpha: 0.75) : AppColors.line;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: edge, width: glow ? 1.4 : 1),
      ),
      child: Padding(padding: EdgeInsets.all(padding), child: child),
    );
  }
}

enum GlowTone { primary, danger, warn, ghost }

/// Endüstriyel buton: mat dolgu, üzerine gelince açılan ton, basınca hafif çökme ve titreşim.
class GlowButton extends StatefulWidget {
  const GlowButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.tone = GlowTone.primary,
    this.compact = false,
    this.expand = false,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final GlowTone tone;
  final bool compact;
  final bool expand;

  @override
  State<GlowButton> createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton> {
  bool _hover = false;
  bool _focus = false;
  bool _pressed = false;

  Color get _fill => switch (widget.tone) {
    GlowTone.primary => AppColors.primary,
    GlowTone.danger => const Color(0xFFB23B34),
    GlowTone.warn => const Color(0xFFB8812A),
    GlowTone.ghost => AppColors.surfaceHigh,
  };

  void _tap() {
    HapticFeedback.lightImpact();
    widget.onPressed?.call();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final ghost = widget.tone == GlowTone.ghost;
    final radius = BorderRadius.circular(6);

    final Color background;
    final Color foreground;
    final Color border;
    if (!enabled) {
      background = AppColors.inset;
      foreground = AppColors.muted.withValues(alpha: 0.7);
      border = AppColors.line;
    } else {
      final lift = _pressed ? 0.16 : (_hover ? 0.08 : 0.0);
      background = Color.lerp(_fill, Colors.white, lift)!;
      foreground = ghost ? AppColors.text : AppColors.onPrimary;
      border = ghost
          ? (_hover || _focus ? AppColors.steel : AppColors.line)
          : (_focus ? Colors.white.withValues(alpha: 0.6) : Colors.transparent);
    }

    return AnimatedScale(
      scale: _pressed ? 0.98 : 1,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: background,
          borderRadius: radius,
          border: Border.all(color: border),
        ),
        child: Material(
          type: MaterialType.transparency,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? _tap : null,
            onHover: (value) => setState(() => _hover = value),
            onFocusChange: (value) => setState(() => _focus = value),
            onHighlightChanged: (value) => setState(() => _pressed = value),
            splashColor: Colors.white.withValues(alpha: 0.10),
            highlightColor: Colors.transparent,
            borderRadius: radius,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: widget.compact ? 12 : 16,
                vertical: widget.compact ? 8 : 12,
              ),
              child: Row(
                mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(widget.icon, size: widget.compact ? 16 : 18, color: foreground),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                        fontSize: widget.compact ? 12.5 : 14,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel başlığı: ikon + aralıklı büyük harf, çelik gri.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {this.icon, this.trailing, super.key});

  final String text;
  final IconData? icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, size: 15, color: AppColors.terminal),
          const SizedBox(width: 7),
        ],
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: EcoText.mono(
              size: 11,
              color: AppColors.terminal,
              weight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// İkonlu, büyük rakamlı gösterge kutusu.
class MetricTile extends StatelessWidget {
  const MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.accent,
    this.caption,
    this.large = false,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? accent;
  final String? caption;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? AppColors.text;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.inset,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: EcoText.mono(size: large ? 22 : 18, color: color, weight: FontWeight.w700),
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: 2),
              Text(
                caption!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.muted, fontSize: 10.5),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Özetin ana göstergesi: büyük rakam, solda zümrüt durum şeridi.
class HeroMetric extends StatelessWidget {
  const HeroMetric({
    required this.label,
    required this.value,
    required this.caption,
    this.icon = Icons.eco,
    this.large = false,
    super.key,
  });

  final String label;
  final String value;
  final String caption;
  final IconData icon;
  final bool large;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.inset,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.line),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 4,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.horizontal(left: Radius.circular(6)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.all(large ? 16 : 12),
                child: Row(
                  children: [
                    Icon(icon, color: AppColors.accent, size: large ? 28 : 24),
                    SizedBox(width: large ? 14 : 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: EcoText.mono(
                              size: 11,
                              color: AppColors.terminal,
                              weight: FontWeight.w600,
                              letterSpacing: 1.4,
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              value,
                              maxLines: 1,
                              style: EcoText.mono(
                                size: large ? 34 : 28,
                                color: AppColors.accent,
                                weight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(caption, style: const TextStyle(color: AppColors.muted, fontSize: 11.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Makine alanına göre ikon.
IconData domainIcon(String domain) => switch (domain) {
  'ELEKTRIK' => Icons.bolt,
  'ISI' => Icons.local_fire_department_outlined,
  'URETIM' => Icons.precision_manufacturing_outlined,
  _ => Icons.factory_outlined,
};

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: const ColorScheme.dark(
      surface: AppColors.surface,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      secondary: AppColors.steel,
      onSurface: AppColors.text,
      error: AppColors.alarm,
    ),
    fontFamily: 'Segoe UI',
  );
  return base.copyWith(
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: AppColors.accent,
      selectionColor: AppColors.steel.withValues(alpha: 0.4),
      selectionHandleColor: AppColors.accent,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.accent),
    iconTheme: const IconThemeData(color: AppColors.text),
    dividerColor: AppColors.line,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.inset,
      prefixIconColor: AppColors.muted,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.steel, width: 1.4),
      ),
      labelStyle: const TextStyle(color: AppColors.muted),
      floatingLabelStyle: const TextStyle(color: AppColors.steel),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.text,
        side: const BorderSide(color: AppColors.line),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.steel),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      height: 64,
      labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      indicatorColor: AppColors.primary.withValues(alpha: 0.35),
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected) ? AppColors.text : AppColors.muted,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 11,
          fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
          color: states.contains(WidgetState.selected) ? AppColors.text : AppColors.muted,
        ),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: ZoomPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
  );
}
