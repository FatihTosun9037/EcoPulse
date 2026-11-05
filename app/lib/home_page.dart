import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'alerts.dart';
import 'api.dart';
import 'main.dart';
import 'motion.dart';
import 'session.dart';
import 'sparkline.dart';
import 'water_flow.dart';

class OperatorPage extends StatefulWidget {
  const OperatorPage({super.key});

  @override
  State<OperatorPage> createState() => _OperatorPageState();
}

class _OperatorPageState extends State<OperatorPage> {
  Timer? _timer;
  List<Machine> _machines = const [];
  List<Alarm> _alarms = const [];
  int? _selectedId;
  String _status = 'Makine seçip arıza basabilirsiniz.';
  String? _error;
  bool _busy = false;
  bool _reloadBusy = false;
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _reload());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_machines.isEmpty && _error == null) {
      _reload();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    // Yavaş ağda (USB tüneli) istekler üst üste binip eski veriyi yazmasın.
    if (_reloadBusy) {
      return;
    }
    _reloadBusy = true;
    final api = AppScope.of(context).api;
    try {
      final machines = await api.machines();
      final alarms = await api.alarms();
      if (!mounted) {
        return;
      }
      setState(() {
        _machines = machines;
        _alarms = alarms;
        _error = null;
        _selectedId ??= machines.isEmpty ? null : machines.first.id;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      _reloadBusy = false;
    }
  }

  Future<void> _run(Future<String> Function() action) async {
    setState(() => _busy = true);
    try {
      final message = await action();
      if (!mounted) {
        return;
      }
      setState(() => _status = message);
      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _status = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final api = AppScope.of(context).api;
    final selected = _machines.where((machine) => machine.id == _selectedId).firstOrNull;
    final active = _alarms
        .where((alarm) => alarm.machineId == _selectedId && alarm.canMaintain)
        .firstOrNull;
    final narrow = MediaQuery.sizeOf(context).width < 960;
    final pad = narrow ? 12.0 : 16.0;
    final activeCount = _alarms.where((alarm) => alarm.canMaintain).length;

    final controls = GlassCard(
      padding: pad,
      glow: selected?.faultActive ?? false,
      accent: (selected?.faultActive ?? false) ? AppColors.alarm : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            'KONTROL PANELİ',
            icon: Icons.tune,
            trailing: selected == null
                ? null
                : Text(
                    selected.name,
                    style: EcoText.mono(size: 11, color: AppColors.muted),
                  ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: GlowButton(
                  label: 'Arıza',
                  icon: Icons.warning_amber_rounded,
                  tone: GlowTone.danger,
                  expand: true,
                  compact: narrow,
                  onPressed: _busy || selected == null ? null : () => _run(() => api.fault(selected.id)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlowButton(
                  label: 'Normal',
                  icon: Icons.restart_alt,
                  tone: GlowTone.ghost,
                  expand: true,
                  compact: narrow,
                  onPressed: _busy || selected == null ? null : () => _run(() => api.normal(selected.id)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GlowButton(
                  label: 'Bakım',
                  icon: Icons.handyman_outlined,
                  expand: true,
                  compact: narrow,
                  onPressed: _busy || active == null ? null : () => _run(() => api.maintenance(active.id)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _StatusStrip(text: _status, emphasize: selected?.faultActive ?? false),
          if (selected != null) ...[
            const SizedBox(height: 10),
            _Readings(machine: selected, compact: narrow),
          ],
        ],
      ),
    );

    final machineList = GlassCard(
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('MAKİNELER · SENSÖR AKIŞI', icon: Icons.sensors, trailing: PulseDot(size: 5)),
          const SizedBox(height: 10),
          Expanded(
            child: ListView(
              children: [
                for (final machine in _machines)
                  _MachineTile(
                    machine: machine,
                    selected: machine.id == _selectedId,
                    onTap: () => setState(() => _selectedId = machine.id),
                    compact: narrow,
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    final machines = _error != null
        ? _ErrorState(message: _error!)
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              controls,
              const SizedBox(height: 10),
              Expanded(child: machineList),
            ],
          );

    final alarmList = _AlarmPanel(
      alarms: _alarms,
      activeCount: activeCount,
      busy: _busy,
      compact: narrow,
      onMaintain: (item) => _run(() => api.maintenance(item.id)),
    );

    return _Shell(
      title: 'Saha',
      onSignOut: _signOut,
      bottom: narrow
          ? NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) => setState(() => _tab = index),
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.precision_manufacturing_outlined),
                  label: 'Makineler',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: activeCount > 0,
                    backgroundColor: AppColors.alarm,
                    label: Text('$activeCount'),
                    child: const Icon(Icons.notification_important_outlined),
                  ),
                  label: 'Alarmlar',
                ),
              ],
            )
          : null,
      child: narrow
          ? AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: KeyedSubtree(
                key: ValueKey(_tab),
                child: _tab == 1 ? alarmList : machines,
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 3, child: machines),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: alarmList),
              ],
            ),
    );
  }

  Future<void> _signOut() async {
    final scope = AppScope.of(context);
    await scope.api.unregisterDevice(scope.session.deviceToken);
    scope.session.signOut();
  }
}

class ManagerPage extends StatefulWidget {
  const ManagerPage({super.key});

  @override
  State<ManagerPage> createState() => _ManagerPageState();
}

class _ManagerPageState extends State<ManagerPage> {
  Timer? _timer;
  Dashboard? _dashboard;
  int? _selectedId;
  String? _error;
  String _status = 'Alarm seçilince bakım bildirilebilir.';
  String? _banner;
  bool _busy = false;
  bool _reloadBusy = false;
  final Set<int> _shownAlarmIds = {};
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _reload());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_dashboard == null && _error == null) {
      _reload();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _reload() async {
    if (_reloadBusy) {
      return;
    }
    _reloadBusy = true;
    try {
      final api = AppScope.of(context).api;
      final dashboard = await api.dashboard();
      final notes = await api.notifications();
      var banner = _banner;
      var jumpAlarms = false;
      for (final note in notes) {
        final firstShow = _shownAlarmIds.add(note.alarmId);
        if (firstShow) {
          await Alerts.show(note.alarmId, note.title, note.body);
          banner = '${note.title}: ${note.body}';
          jumpAlarms = true;
        }
        await api.ack(note.id);
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _dashboard = dashboard;
        _banner = banner;
        _error = null;
        if (jumpAlarms && MediaQuery.sizeOf(context).width < 960) {
          _tab = 2;
        }
        _selectedId ??= dashboard.machines.isEmpty ? null : dashboard.machines.first.id;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      _reloadBusy = false;
    }
  }

  Future<void> _maintain(Alarm alarm) async {
    setState(() => _busy = true);
    try {
      final message = await AppScope.of(context).api.maintenance(alarm.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _status = message;
        _banner = null;
      });
      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _status = error.toString());
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;
    final narrow = MediaQuery.sizeOf(context).width < 960;
    final activeAlarms = dashboard?.activeAlarms ?? 0;
    return _Shell(
      title: 'Tesis panosu',
      onSignOut: _signOut,
      onPersonnel: () => context.push('/manager/personnel'),
      bottom: narrow
          ? NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (index) {
                if (index == 3) {
                  context.push('/manager/personnel');
                } else {
                  setState(() => _tab = index);
                }
              },
              destinations: [
                const NavigationDestination(icon: Icon(Icons.eco_outlined), label: 'Özet'),
                const NavigationDestination(icon: Icon(Icons.show_chart), label: 'Tesis'),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: activeAlarms > 0,
                    backgroundColor: AppColors.alarm,
                    label: Text('$activeAlarms'),
                    child: const Icon(Icons.notification_important_outlined),
                  ),
                  label: 'Alarmlar',
                ),
                const NavigationDestination(icon: Icon(Icons.badge_outlined), label: 'Personel'),
              ],
            )
          : null,
      child: _error != null
          ? _ErrorState(message: _error!)
          : dashboard == null
          ? const Center(child: CircularProgressIndicator())
          : AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: KeyedSubtree(
                key: ValueKey(narrow ? _tab : -1),
                child: _ManagerBoard(
                  dashboard: dashboard,
                  selectedId: _selectedId,
                  status: _banner ?? _status,
                  busy: _busy,
                  tab: narrow ? _tab : null,
                  onSelect: (id) => setState(() => _selectedId = id),
                  onMaintain: _maintain,
                ),
              ),
            ),
    );
  }

  Future<void> _signOut() async {
    final scope = AppScope.of(context);
    await scope.api.unregisterDevice(scope.session.deviceToken);
    scope.session.signOut();
  }
}

class _Shell extends StatelessWidget {
  const _Shell({
    required this.title,
    required this.child,
    required this.onSignOut,
    this.onPersonnel,
    this.bottom,
  });

  final String title;
  final Widget child;
  final Future<void> Function() onSignOut;
  final VoidCallback? onPersonnel;
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    final narrow = MediaQuery.sizeOf(context).width < 960;
    final pad = narrow ? 12.0 : 22.0;
    return Scaffold(
      backgroundColor: AppColors.background,
      bottomNavigationBar: bottom,
      body: EcoBackground(
        child: SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(pad, narrow ? 8 : 16, pad, narrow ? 8 : 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FadeSlideIn(
                  child: Row(
                    children: [
                      BrandMark(size: narrow ? 30 : 42),
                      SizedBox(width: narrow ? 10 : 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'EcoPulse OSB',
                                  style: TextStyle(
                                    fontSize: narrow ? 18 : 24,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                PulseDot(size: narrow ? 6 : 7),
                              ],
                            ),
                            Text(
                              '$title · ${session.displayName ?? ''}',
                              style: TextStyle(color: AppColors.muted, fontSize: narrow ? 12 : 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      if (!narrow) ...[
                        const _LiveChip(),
                        const SizedBox(width: 12),
                        if (onPersonnel != null) ...[
                          GlowButton(label: 'Personel', icon: Icons.groups_2_outlined, onPressed: onPersonnel),
                          const SizedBox(width: 8),
                        ],
                        GlowButton(
                          label: 'Çıkış',
                          icon: Icons.logout,
                          tone: GlowTone.ghost,
                          onPressed: onSignOut,
                        ),
                      ] else
                        IconButton(
                          onPressed: onSignOut,
                          tooltip: 'Çıkış',
                          icon: const Icon(Icons.logout, size: 20),
                          visualDensity: VisualDensity.compact,
                        ),
                    ],
                  ),
                ),
                SizedBox(height: narrow ? 10 : 16),
                Expanded(
                  child: FadeSlideIn(delay: const Duration(milliseconds: 60), child: child),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LiveChip extends StatelessWidget {
  const _LiveChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sensors, size: 14, color: AppColors.accent),
          const SizedBox(width: 6),
          Text(
            'CANLI · 2 sn',
            style: EcoText.mono(size: 11, color: AppColors.accent, weight: FontWeight.w600, letterSpacing: 1),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassCard(
        accent: AppColors.amber,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.portable_wifi_off, color: AppColors.amber),
            const SizedBox(width: 12),
            Flexible(child: Text(message, style: const TextStyle(color: AppColors.text))),
          ],
        ),
      ),
    );
  }
}

class _ManagerBoard extends StatelessWidget {
  const _ManagerBoard({
    required this.dashboard,
    required this.selectedId,
    required this.status,
    required this.busy,
    required this.tab,
    required this.onSelect,
    required this.onMaintain,
  });

  final Dashboard dashboard;
  final int? selectedId;
  final String status;
  final bool busy;
  final int? tab;
  final ValueChanged<int> onSelect;
  final ValueChanged<Alarm> onMaintain;

  @override
  Widget build(BuildContext context) {
    final selected = dashboard.machines.where((machine) => machine.id == selectedId).firstOrNull;
    final wide = MediaQuery.sizeOf(context).width >= 960;
    final pad = wide ? 16.0 : 12.0;
    const gap = SizedBox(width: 10);
    const vgap = SizedBox(height: 10);

    final summary = GlassCard(
      padding: pad,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SectionLabel('ÖZET · YEŞİL DÖNÜŞÜM', icon: Icons.eco_outlined),
          const SizedBox(height: 12),
          HeroMetric(
            label: 'YILLIK KARŞILIK',
            value: dashboard.verifiedAnnualText,
            caption: 'Doğrulanan kayıp yıl boyu (7/24) sürseydi',
            large: wide,
          ),
          vgap,
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  icon: Icons.savings_outlined,
                  label: 'Kesilen kayıp',
                  value: dashboard.verifiedSavingsText,
                  accent: AppColors.accent,
                  large: wide,
                ),
              ),
              gap,
              Expanded(
                child: MetricTile(
                  icon: Icons.co2,
                  label: 'Önlenen CO₂',
                  value: dashboard.verifiedCo2Text,
                  accent: AppColors.emerald,
                  large: wide,
                ),
              ),
            ],
          ),
          vgap,
          WaterFlowPanel(dashboard: dashboard, large: wide),
          vgap,
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  icon: Icons.bolt,
                  label: 'Toplam güç',
                  value: dashboard.totalPowerText,
                  accent: AppColors.voltage,
                  large: wide,
                ),
              ),
              gap,
              Expanded(
                child: MetricTile(
                  icon: dashboard.activeAlarms > 0 ? Icons.warning_amber_rounded : Icons.verified_outlined,
                  label: 'Aktif alarm',
                  value: '${dashboard.activeAlarms}',
                  accent: dashboard.activeAlarms > 0 ? AppColors.alarm : AppColors.accent,
                  large: wide,
                ),
              ),
            ],
          ),
          vgap,
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  icon: Icons.trending_down,
                  label: 'Aktif kayıp',
                  value: dashboard.activeLossText,
                  accent: dashboard.activeAlarms > 0 ? AppColors.amber : AppColors.muted,
                  large: wide,
                ),
              ),
              gap,
              Expanded(
                child: MetricTile(
                  icon: Icons.factory_outlined,
                  label: 'Tesis',
                  value: '${dashboard.machineCount} makine',
                  caption: 'Doğrulaması süren: ${dashboard.verifyingWorkOrders}',
                  large: wide,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final machines = GlassCard(
      padding: pad,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionLabel('TESİS · CANLI SENSÖR AKIŞI', icon: Icons.sensors, trailing: PulseDot(size: 5)),
          if (selected != null) ...[
            const SizedBox(height: 10),
            _Charts(machine: selected, height: wide ? 72 : 52),
            const SizedBox(height: 8),
            _Readings(machine: selected, compact: !wide),
            const SizedBox(height: 10),
          ],
          Expanded(
            child: ListView(
              children: [
                for (final machine in dashboard.machines)
                  _MachineTile(
                    machine: machine,
                    selected: machine.id == selectedId,
                    onTap: () => onSelect(machine.id),
                    compact: !wide,
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    final alarms = _AlarmPanel(
      alarms: dashboard.alarms,
      activeCount: dashboard.activeAlarms,
      busy: busy,
      compact: !wide,
      status: status,
      onMaintain: onMaintain,
    );

    if (!wide) {
      return switch (tab ?? 0) {
        1 => machines,
        2 => alarms,
        _ => summary,
      };
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(flex: 3, child: summary),
        const SizedBox(width: 12),
        Expanded(flex: 4, child: machines),
        const SizedBox(width: 12),
        Expanded(flex: 3, child: alarms),
      ],
    );
  }
}

class _AlarmPanel extends StatelessWidget {
  const _AlarmPanel({
    required this.alarms,
    required this.activeCount,
    required this.busy,
    required this.compact,
    required this.onMaintain,
    this.status,
  });

  final List<Alarm> alarms;
  final int activeCount;
  final bool busy;
  final bool compact;
  final ValueChanged<Alarm> onMaintain;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final hot = activeCount > 0;
    return GlassCard(
      padding: compact ? 12 : 16,
      accent: hot ? AppColors.alarm : null,
      glow: hot,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionLabel(
            'ALARMLAR · OLAY AKIŞI',
            icon: Icons.notifications_active_outlined,
            trailing: hot ? _CountBadge(count: activeCount) : null,
          ),
          if (status != null) ...[
            const SizedBox(height: 10),
            _StatusStrip(text: status!, emphasize: hot),
          ],
          const SizedBox(height: 10),
          Expanded(
            child: alarms.isEmpty
                ? const _EmptyAlarms()
                : ListView(
                    children: [
                      for (final alarm in alarms)
                        _AlarmTile(alarm: alarm, busy: busy, onMaintain: onMaintain, compact: compact),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.alarm.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.alarm.withValues(alpha: 0.6)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const PulseDot(color: AppColors.alarm, size: 5),
          const SizedBox(width: 4),
          Text('$count AKTİF', style: EcoText.mono(size: 10.5, color: AppColors.alarm, weight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _EmptyAlarms extends StatelessWidget {
  const _EmptyAlarms();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.eco, size: 40, color: AppColors.accent.withValues(alpha: 0.7)),
          const SizedBox(height: 10),
          const Text('Tüm hatlar verimli çalışıyor.', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          const Text('Henüz alarm yok.', style: TextStyle(color: AppColors.muted)),
        ],
      ),
    );
  }
}

class _Charts extends StatelessWidget {
  const _Charts({required this.machine, this.height = 88});

  final Machine machine;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Sparkline(
          label: 'Voltaj',
          icon: Icons.electrical_services,
          valueText: machine.voltageText,
          values: machine.voltageSeries,
          color: AppColors.voltage,
          height: height,
        ),
        Sparkline(
          label: 'Akım',
          icon: Icons.bolt,
          valueText: machine.currentText,
          values: machine.currentSeries,
          color: AppColors.current,
          height: height,
        ),
        Sparkline(
          label: 'Sıcaklık',
          icon: Icons.thermostat,
          valueText: machine.temperatureText,
          values: machine.temperatureSeries,
          color: AppColors.temperature,
          height: height,
        ),
        Sparkline(
          label: 'Su debisi',
          icon: Icons.water_drop_outlined,
          valueText: machine.flowText,
          values: machine.flowSeries,
          color: AppColors.water,
          height: height,
        ),
      ],
    );
  }
}

class _Readings extends StatelessWidget {
  const _Readings({required this.machine, this.compact = false});

  final Machine machine;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.electrical_services, machine.voltageText, AppColors.voltage),
      (Icons.bolt, machine.currentText, AppColors.current),
      (Icons.thermostat, machine.temperatureText, AppColors.temperature),
      (Icons.water_drop_outlined, machine.flowText, AppColors.water),
      (Icons.speed, machine.powerText, AppColors.text),
    ];
    return Wrap(
      spacing: compact ? 6 : 8,
      runSpacing: 6,
      children: [
        for (final item in items)
          Container(
            padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 4 : 6),
            decoration: BoxDecoration(
              color: item.$3.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: item.$3.withValues(alpha: 0.35)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(item.$1, size: compact ? 12 : 14, color: item.$3),
                const SizedBox(width: 5),
                Text(
                  item.$2,
                  style: EcoText.mono(size: compact ? 11 : 12, color: item.$3, weight: FontWeight.w700),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Terminal satırı gibi görünen durum mesajı; mesaj değişince kayarak yenilenir.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.text, this.emphasize = false});

  final String text;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final color = emphasize ? AppColors.amber : AppColors.terminal;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      decoration: BoxDecoration(
        color: AppColors.inset.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            Text('>', style: EcoText.mono(size: 13, color: color, weight: FontWeight.w700)),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 260),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(animation),
                    child: child,
                  ),
                ),
                child: Align(
                  key: ValueKey(text),
                  alignment: Alignment.centerLeft,
                  child: Text(
                    text,
                    style: EcoText.mono(size: 12, color: AppColors.text.withValues(alpha: 0.92)),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MachineTile extends StatelessWidget {
  const _MachineTile({
    required this.machine,
    required this.selected,
    required this.onTap,
    this.compact = false,
  });

  final Machine machine;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final accent = machine.faultActive ? AppColors.alarm : AppColors.accent;
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 6 : 8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.08) : AppColors.inset.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: machine.faultActive
                ? AppColors.alarm.withValues(alpha: 0.65)
                : selected
                ? AppColors.accent.withValues(alpha: 0.55)
                : AppColors.line,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            splashColor: accent.withValues(alpha: 0.15),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: compact ? 8 : 10),
              child: Row(
                children: [
                  Container(
                    width: compact ? 30 : 34,
                    height: compact ? 30 : 34,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(domainIcon(machine.domain), size: compact ? 16 : 18, color: accent),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                machine.name,
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: compact ? 13 : 14),
                              ),
                            ),
                            if (machine.faultActive) ...[
                              const PulseDot(color: AppColors.alarm, size: 5),
                              Text(
                                'ARIZA',
                                style: EcoText.mono(size: 10.5, color: AppColors.alarm, weight: FontWeight.w700),
                              ),
                            ] else
                              Text(
                                machine.powerText,
                                style: EcoText.mono(size: 11, color: AppColors.muted),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${machine.location} · ${machine.meta}',
                          style: TextStyle(color: AppColors.muted, fontSize: compact ? 11 : 12),
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
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

class _AlarmTile extends StatelessWidget {
  const _AlarmTile({
    required this.alarm,
    required this.busy,
    required this.onMaintain,
    this.compact = false,
  });

  final Alarm alarm;
  final bool busy;
  final ValueChanged<Alarm> onMaintain;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Kırmızı yalnızca gerçek (kritik, aktif) alarmda; doğrulanan kayıplar yeşil parlar.
    final (color, icon) = switch (alarm.status) {
      'ACTIVE' when alarm.severityLabel == 'Kritik' => (AppColors.alarm, Icons.error_outline),
      'ACTIVE' => (AppColors.amber, Icons.warning_amber_rounded),
      'VERIFYING' => (AppColors.orange, Icons.hourglass_top_rounded),
      _ => (AppColors.accent, Icons.verified_outlined),
    };
    return Padding(
      padding: EdgeInsets.only(bottom: compact ? 8 : 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.45)),
        ),
        child: Padding(
          padding: EdgeInsets.all(compact ? 10 : 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            alarm.machineName,
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: compact ? 13 : 14),
                          ),
                        ),
                        Text(
                          alarm.severityLabel.toUpperCase(),
                          style: EcoText.mono(size: 10.5, color: color, weight: FontWeight.w700, letterSpacing: 0.8),
                        ),
                      ],
                    ),
                    Text(alarm.typeLabel, style: TextStyle(color: AppColors.muted, fontSize: compact ? 11 : 12)),
                    const SizedBox(height: 4),
                    Text(
                      alarm.lossText,
                      style: EcoText.mono(size: compact ? 14 : 15, color: color, weight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      alarm.metaText,
                      style: TextStyle(color: AppColors.muted, fontSize: compact ? 11 : 12),
                      maxLines: compact ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (alarm.canMaintain) ...[
                      const SizedBox(height: 8),
                      GlowButton(
                        label: 'Bakım Bildir',
                        icon: Icons.handyman_outlined,
                        compact: true,
                        onPressed: busy ? null : () => onMaintain(alarm),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
