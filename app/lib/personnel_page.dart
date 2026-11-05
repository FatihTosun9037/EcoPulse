import 'package:flutter/material.dart';

import 'api.dart';
import 'main.dart';
import 'motion.dart';
import 'session.dart';

class PersonnelPage extends StatefulWidget {
  const PersonnelPage({super.key});

  @override
  State<PersonnelPage> createState() => _PersonnelPageState();
}

class _PersonnelPageState extends State<PersonnelPage> {
  List<Personnel> _people = const [];
  List<Machine> _machines = const [];
  int? _selectedId;
  String? _message;
  bool _warning = false;
  bool _busy = false;
  bool _loading = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_people.isEmpty && _error == null) {
      _reload();
    }
  }

  Future<void> _reload() async {
    if (_loading) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    final api = AppScope.of(context).api;
    try {
      final people = await api.personnel();
      final machines = await api.machines();
      if (!mounted) {
        return;
      }
      setState(() {
        _people = people;
        _machines = machines;
        _selectedId ??= people.isEmpty ? null : people.first.id;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() => _error = error.toString());
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Personnel? get _selected =>
      _people.where((person) => person.id == _selectedId).firstOrNull;

  Future<void> _assign(Machine machine) async {
    final person = _selected;
    if (person == null) {
      return;
    }
    setState(() => _busy = true);
    try {
      final result = await AppScope.of(context).api
          .assignMachine(person.id, machine.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _message = result.message;
        _warning = result.expertiseMismatch || !result.saved;
      });
      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = error.toString();
        _warning = true;
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _unassign(Machine machine) async {
    setState(() => _busy = true);
    try {
      final result = await AppScope.of(context).api.unassignMachine(machine.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _message = result.message;
        _warning = !result.saved;
      });
      await _reload();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _message = error.toString();
        _warning = true;
      });
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final person = _selected;
    final narrow = MediaQuery.sizeOf(context).width < 960;
    final assigned = _machines
        .where((machine) => machine.personnelId == person?.id)
        .toList();
    final compatible = _machines
        .where(
          (machine) =>
              person != null &&
              machine.domain == person.expertise &&
              machine.personnelId != person.id,
        )
        .toList();
    final incompatible = _machines
        .where(
          (machine) =>
              person != null &&
              machine.domain != person.expertise &&
              machine.personnelId != person.id,
        )
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      body: EcoBackground(
        child: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(narrow ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FadeSlideIn(
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 4),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Personel',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Yalnızca yönetici atama yapar. Uymayan makine de atanabilir; uyarı gösterilir.',
                            style: TextStyle(
                              color: AppColors.muted,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_loading && _people.isEmpty)
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text(
                          'Personel listesi yükleniyor...',
                          style: TextStyle(color: AppColors.muted),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_error != null)
                Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _error!,
                          style: const TextStyle(color: AppColors.muted),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _loading ? null : _reload,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Yeniden dene'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                Expanded(
                  child: narrow
                      ? ListView(
                          children: [
                            _peopleCard(),
                            const SizedBox(height: 12),
                            if (person != null)
                              _detailCard(
                                person,
                                assigned,
                                compatible,
                                incompatible,
                                scrollable: false,
                              ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SizedBox(width: 280, child: _peopleCard()),
                            const SizedBox(width: 12),
                            Expanded(
                              child: person == null
                                  ? const Center(
                                      child: Text(
                                        'Personel seçin',
                                        style: TextStyle(
                                          color: AppColors.muted,
                                        ),
                                      ),
                                    )
                                  : _detailCard(
                                      person,
                                      assigned,
                                      compatible,
                                      incompatible,
                                      scrollable: true,
                                    ),
                            ),
                          ],
                        ),
                ),
              if (_message != null) ...[
                const SizedBox(height: 10),
                Text(
                  _message!,
                  style: TextStyle(
                    color: _warning ? AppColors.amber : AppColors.accent,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _peopleCard() {
    return GlassCard(
      padding: 0,
      child: ListView(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        children: [
          const SectionLabel('EKİP', icon: Icons.groups_2_outlined),
          const SizedBox(height: 8),
          ..._people.map((person) {
            final selected = person.id == _selectedId;
            return Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Material(
                color: selected ? AppColors.accent.withValues(alpha: 0.10) : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _selectedId = person.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          domainIcon(person.expertise),
                          size: 18,
                          color: selected ? AppColors.accent : AppColors.muted,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            person.fullName,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: selected ? AppColors.accent : AppColors.text,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _detailCard(
    Personnel person,
    List<Machine> assigned,
    List<Machine> compatible,
    List<Machine> incompatible, {
    required bool scrollable,
  }) {
    return GlassCard(
      padding: 0,
      child: scrollable
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: _detailContent(
                person,
                assigned,
                compatible,
                incompatible,
              ),
            )
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _detailContent(
                  person,
                  assigned,
                  compatible,
                  incompatible,
                ),
              ),
            ),
    );
  }

  List<Widget> _detailContent(
    Personnel person,
    List<Machine> assigned,
    List<Machine> compatible,
    List<Machine> incompatible,
  ) {
    return [
      Text(
        person.fullName,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 4),
      Text(
        'Uzmanlık: ${person.expertiseLabel}',
        style: const TextStyle(color: AppColors.muted),
      ),
      const SizedBox(height: 16),
      _section(
        'ATANAN MAKİNELER',
        assigned,
        actionLabel: 'Atamayı kaldır',
        onAction: _unassign,
        tone: _Tone.muted,
      ),
      const SizedBox(height: 14),
      _section(
        'UYUMLU MAKİNELER',
        compatible,
        actionLabel: 'Seçilen makineyi ata',
        onAction: _assign,
        tone: _Tone.primary,
      ),
      const SizedBox(height: 14),
      _section(
        'UYUMSUZ MAKİNELER',
        incompatible,
        actionLabel: 'Yine de ata',
        onAction: _assign,
        tone: _Tone.warn,
        showDomain: true,
      ),
    ];
  }

  Widget _section(
    String title,
    List<Machine> machines, {
    required String actionLabel,
    required Future<void> Function(Machine) onAction,
    required _Tone tone,
    bool showDomain = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(title),
        const SizedBox(height: 8),
        if (machines.isEmpty)
          const Text(
            'Liste boş',
            style: TextStyle(color: AppColors.muted, fontSize: 13),
          )
        else
          ...machines.map((machine) {
            final label = showDomain
                ? '${machine.name} · ${machine.location} · ${machine.assigneeName.isEmpty ? 'atanmadı' : machine.assigneeName} · ${machine.domainLabel}'
                : '${machine.name} · ${machine.location} · ${machine.assigneeName.isEmpty ? 'atanmadı' : machine.assigneeName}${machine.expertiseMismatch ? ' · uzmanlık uyuşmuyor' : ''}';
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(label),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _ActionButton(
                      label: actionLabel,
                      enabled: !_busy,
                      tone: tone,
                      onPressed: () => onAction(machine),
                    ),
                  ),
                ],
              ),
            );
          }),
      ],
    );
  }
}

enum _Tone { primary, warn, muted }

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.label,
    required this.enabled,
    required this.tone,
    required this.onPressed,
  });

  final String label;
  final bool enabled;
  final _Tone tone;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return GlowButton(
      label: label,
      compact: true,
      icon: switch (tone) {
        _Tone.primary => Icons.link,
        _Tone.warn => Icons.report_gmailerrorred,
        _Tone.muted => Icons.link_off,
      },
      tone: switch (tone) {
        _Tone.primary => GlowTone.primary,
        _Tone.warn => GlowTone.warn,
        _Tone.muted => GlowTone.ghost,
      },
      onPressed: enabled ? onPressed : null,
    );
  }
}
