import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'api.dart';
import 'main.dart';
import 'motion.dart';
import 'sparkline.dart';

/// Tesis su akışı: anlık toplam debi, canlı trend grafiği ve pompa hattı çubukları (SCADA görünümü).
class WaterFlowPanel extends StatelessWidget {
  const WaterFlowPanel({required this.dashboard, this.large = false, super.key});

  final Dashboard dashboard;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final impact = dashboard.water;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.inset,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.line),
      ),
      child: Padding(
        padding: EdgeInsets.all(large ? 14 : 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.water_drop, size: 16, color: AppColors.water),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'SU AKIŞI · SOĞUTMA HATLARI',
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
                const PulseDot(color: AppColors.water, size: 5),
                const SizedBox(width: 2),
                Text('CANLI', style: EcoText.mono(size: 10, color: AppColors.water, weight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 260),
                      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
                      child: Text(
                        dashboard.totalFlowText,
                        key: ValueKey(dashboard.totalFlowText),
                        style: EcoText.mono(
                          size: large ? 30 : 26,
                          color: AppColors.water,
                          weight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: Text(
                    'nominal ${dashboard.nominalFlowText}',
                    style: const TextStyle(color: AppColors.muted, fontSize: 11),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Sparkline(
              label: 'Tesis toplam debi',
              icon: Icons.waves,
              valueText: dashboard.totalFlowText,
              values: dashboard.totalFlowSeries,
              color: AppColors.water,
              height: large ? 78 : 64,
            ),
            const SizedBox(height: 10),
            for (final machine in dashboard.machines) _FlowBar(machine: machine),
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.eco_outlined, size: 14, color: AppColors.accent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Önlenen su (dolaylı): '),
                        TextSpan(
                          text: impact?.configured == true ? impact!.avoidedText : '—',
                          style: EcoText.mono(size: 12, color: AppColors.accent, weight: FontWeight.w700),
                        ),
                      ],
                    ),
                    style: const TextStyle(color: AppColors.muted, fontSize: 11.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (impact != null)
                  GlowButton(
                    label: 'Kaynak',
                    icon: Icons.info_outline,
                    tone: GlowTone.ghost,
                    compact: true,
                    onPressed: () => showWaterSource(context, impact),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Tek pompa hattının anlık debisini nominale göre gösteren çubuk.
/// Soğutma yetersizse (nominalin %75'i altı) kırmızı, fazlaysa (%110 üstü) amber.
class _FlowBar extends StatelessWidget {
  const _FlowBar({required this.machine});

  final Machine machine;

  static double? _number(String text) {
    final match = RegExp(r'[\d.,]+').firstMatch(text);
    if (match == null) {
      return null;
    }
    return double.tryParse(match.group(0)!.replaceAll('.', '').replaceAll(',', '.'));
  }

  @override
  Widget build(BuildContext context) {
    final flow = machine.flowSeries.isEmpty ? null : machine.flowSeries.last;
    final nominal = _number(machine.nominalFlowText);
    final ratio = flow != null && nominal != null && nominal > 0 ? flow / nominal : 0.0;
    final color = ratio == 0
        ? AppColors.muted
        : ratio < 0.75
        ? AppColors.alarm
        : ratio > 1.10
        ? AppColors.amber
        : AppColors.water;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(
              machine.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: AppColors.muted),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: SizedBox(
                height: 7,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(color: AppColors.line.withValues(alpha: 0.8)),
                    // Nominal debi çizgisi (%100 = çubuğun %80'i).
                    FractionallySizedBox(
                      alignment: Alignment.centerLeft,
                      widthFactor: 0.8,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(width: 1.5, color: AppColors.text.withValues(alpha: 0.35)),
                      ),
                    ),
                    TweenAnimationBuilder<double>(
                      tween: Tween(end: (ratio * 0.8).clamp(0.0, 1.0)),
                      duration: const Duration(milliseconds: 600),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) => FractionallySizedBox(
                        alignment: Alignment.centerLeft,
                        widthFactor: value,
                        child: child,
                      ),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 82,
            child: Text(
              machine.flowText,
              textAlign: TextAlign.right,
              style: EcoText.mono(size: 11, color: color, weight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

/// Önlenen su hesabının formülünü, katsayısını ve kaynağını gösterir.
Future<void> showWaterSource(BuildContext context, WaterImpact impact) {
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppColors.water.withValues(alpha: 0.4)),
      ),
      title: const Row(
        children: [
          Icon(Icons.water_drop_outlined, color: AppColors.water),
          SizedBox(width: 10),
          Expanded(child: Text('Hesap katsayıları ve kaynakları', style: TextStyle(fontSize: 18))),
        ],
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SingleChildScrollView(child: _WaterSourceDetails(impact: impact)),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Kapat')),
      ],
    ),
  );
}

class _WaterSourceDetails extends StatelessWidget {
  const _WaterSourceDetails({required this.impact});

  final WaterImpact impact;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, String value, {bool mono = false}) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: EcoText.mono(size: 10.5, color: AppColors.muted, letterSpacing: 1.2)),
            const SizedBox(height: 3),
            SelectableText(
              value.isEmpty ? '—' : value,
              style: mono
                  ? EcoText.mono(size: 12.5, color: AppColors.text)
                  : const TextStyle(fontSize: 13, color: AppColors.text, height: 1.35),
            ),
          ],
        ),
      );
    }

    Widget link(String url, Color color) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Expanded(child: SelectableText(url, style: EcoText.mono(size: 12, color: color))),
            const SizedBox(width: 8),
            GlowButton(
              label: 'Kopyala',
              icon: Icons.copy,
              tone: GlowTone.ghost,
              compact: true,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                  const SnackBar(content: Text('Kaynak bağlantısı kopyalandı.')),
                );
              },
            ),
          ],
        ),
      );
    }

    Widget heading(String text, IconData icon, Color color) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 6),
            Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 13.5)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        heading('Önlenen su (dolaylı)', Icons.water_drop_outlined, AppColors.water),
        row('FORMÜL', impact.formulaText, mono: true),
        row('KATSAYI', impact.factorText, mono: true),
        row('KAPSAM', impact.scopeText),
        row('KAYNAK', impact.sourceText),
        if (impact.sourceUrl.isNotEmpty) link(impact.sourceUrl, AppColors.water),
        if (impact.configured) row('DOĞRULANAN ENERJİ TASARRUFU', impact.avoidedKwhText, mono: true),
        if (impact.co2FactorText.isNotEmpty) ...[
          const Divider(height: 22, color: AppColors.line),
          heading('CO₂ emisyonu', Icons.co2, AppColors.emerald),
          row('FORMÜL', 'CO₂ (kg/saat) = kayıp gücü (kW) × emisyon faktörü (kg CO₂/kWh)', mono: true),
          row('KATSAYI', impact.co2FactorText, mono: true),
          row('KAYNAK', impact.co2SourceText),
          if (impact.co2SourceUrl.isNotEmpty) link(impact.co2SourceUrl, AppColors.emerald),
        ],
        const SizedBox(height: 4),
        const Text(
          'Canlı debi grafikleri, voltaj / akım / sıcaklık gibi simüle edilmiş sensör akışıdır (pompa salınımı + '
          'arıza tepkisi). Önlenen su, fabrikada tasarruf edilen elektriğin santral soğutmasında önlediği dolaylı sudur; '
          'tesisin kendi sayacında görünmez. Yıllık değer 7/24 sürme varsayımına dayanır.',
          style: TextStyle(color: AppColors.muted, fontSize: 11.5, height: 1.4),
        ),
      ],
    );
  }
}
