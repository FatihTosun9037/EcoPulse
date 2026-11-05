import 'package:flutter/material.dart';

import 'main.dart';
import 'motion.dart';
import 'session.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit(String username, String password) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final scope = AppScope.of(context);
      final result = await scope.api.login(username, password);
      scope.session.signIn(result);
      await scope.api.registerDevice(scope.session.deviceToken);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error is Exception ? error.toString().replaceFirst('ApiException: ', '') : 'Giriş yapılamadı.');
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: EcoBackground(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: FadeSlideIn(
                  child: GlassCard(
                    padding: 24,
                    radius: 18,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 60),
                          child: Row(
                            children: [
                              const BrandMark(size: 52),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'EcoPulse OSB',
                                      style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: 0.2),
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const PulseDot(size: 7),
                                        const SizedBox(width: 6),
                                        Text(
                                          'SİSTEM ÇEVRİMİÇİ',
                                          style: EcoText.mono(
                                            size: 11,
                                            color: AppColors.accent,
                                            weight: FontWeight.w600,
                                            letterSpacing: 1.4,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 18),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 120),
                          child: const Text(
                            'Sanayide dijital izleme, enerjide yeşil dönüşüm.',
                            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 4),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 140),
                          child: const Text(
                            'Enerji kaçağı ve ısı kaybını erken yakala, TL ve CO₂ olarak gör, müdahaleyi doğrula.',
                            style: TextStyle(color: AppColors.muted, fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const FadeSlideIn(
                          delay: Duration(milliseconds: 160),
                          child: Row(
                            children: [
                              Expanded(child: _Pillar(icon: Icons.factory_outlined, label: 'Endüstri')),
                              SizedBox(width: 8),
                              Expanded(child: _Pillar(icon: Icons.sensors, label: 'Sensör')),
                              SizedBox(width: 8),
                              Expanded(child: _Pillar(icon: Icons.eco_outlined, label: 'Karbon')),
                              SizedBox(width: 8),
                              Expanded(child: _Pillar(icon: Icons.water_drop_outlined, label: 'Kaynak')),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 180),
                          child: TextField(
                            controller: _username,
                            decoration: const InputDecoration(
                              labelText: 'Kullanıcı adı',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                        const SizedBox(height: 12),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 240),
                          child: TextField(
                            controller: _password,
                            decoration: const InputDecoration(
                              labelText: 'Parola',
                              prefixIcon: Icon(Icons.lock_outline),
                            ),
                            obscureText: true,
                            onSubmitted: (_) => _submit(_username.text, _password.text),
                          ),
                        ),
                        if (_error != null) ...[
                          const SizedBox(height: 12),
                          FadeSlideIn(
                            child: Row(
                              children: [
                                const Icon(Icons.error_outline, size: 16, color: AppColors.alarm),
                                const SizedBox(width: 6),
                                Expanded(child: Text(_error!, style: const TextStyle(color: AppColors.alarm))),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(height: 18),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 300),
                          child: GlowButton(
                            label: _busy ? 'Bağlanıyor…' : 'Giriş',
                            icon: Icons.login,
                            expand: true,
                            onPressed: _busy ? null : () => _submit(_username.text, _password.text),
                          ),
                        ),
                        const SizedBox(height: 14),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 340),
                          child: Text(
                            '> HIZLI DEMO GİRİŞİ',
                            style: EcoText.mono(size: 11, color: AppColors.muted, letterSpacing: 1.4),
                          ),
                        ),
                        const SizedBox(height: 8),
                        FadeSlideIn(
                          delay: const Duration(milliseconds: 380),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              GlowButton(
                                label: 'Saha olarak gir',
                                icon: Icons.engineering_outlined,
                                tone: GlowTone.ghost,
                                expand: true,
                                onPressed: _busy ? null : () => _submit('operator', 'operator'),
                              ),
                              const SizedBox(height: 8),
                              GlowButton(
                                label: 'Yönetici olarak gir',
                                icon: Icons.insights_outlined,
                                tone: GlowTone.ghost,
                                expand: true,
                                onPressed: _busy ? null : () => _submit('manager', 'manager'),
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
          ),
        ),
      ),
    );
  }
}

class _Pillar extends StatelessWidget {
  const _Pillar({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.accent.withValues(alpha: 0.22)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: AppColors.accent),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11, color: AppColors.muted)),
        ],
      ),
    );
  }
}
