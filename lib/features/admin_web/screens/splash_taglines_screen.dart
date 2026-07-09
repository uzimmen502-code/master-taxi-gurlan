import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/splash_settings.dart';
import '../../../repositories/settings_repository.dart';
import '../services/admin_auth_service.dart';

/// Admin — splash animatsiyasi tagline (`settings/splash`).
class SplashTaglinesScreen extends StatefulWidget {
  const SplashTaglinesScreen({super.key});

  @override
  State<SplashTaglinesScreen> createState() => _SplashTaglinesScreenState();
}

class _SplashTaglinesScreenState extends State<SplashTaglinesScreen> {
  final _formKey = GlobalKey<FormState>();

  bool _enabled = true;
  bool _loading = true;
  bool _saving = false;
  String? _updatedBy;
  final List<TextEditingController> _controllers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings =
          await context.read<SettingsRepository>().getSplashSettings();
      _enabled = settings.enabled;
      _setTaglines(settings.taglines);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _setTaglines(List<String> lines) {
    for (final c in _controllers) {
      c.dispose();
    }
    _controllers
      ..clear()
      ..addAll(lines.map((line) => TextEditingController(text: line)));
  }

  void _addLine() {
    if (_controllers.length >= SplashSettings.maxTaglines) return;
    setState(() => _controllers.add(TextEditingController()));
  }

  void _removeLine(int index) {
    if (_controllers.length <= 1) return;
    setState(() {
      _controllers.removeAt(index).dispose();
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final taglines = SplashSettings.sanitizeTaglines(
      _controllers.map((c) => c.text).toList(),
    );
    if (taglines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kamida bitta soʻz kiriting'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final adminPhone = context.read<AdminAuthService>().phoneDigits ??
        context.read<AdminAuthService>().phone ??
        'unknown';

    try {
      await context.read<SettingsRepository>().setSplashSettings(
            taglines: taglines,
            enabled: _enabled,
            updatedBy: adminPhone,
          );
      if (!mounted) return;
      setState(() => _updatedBy = adminPhone);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Splash soʻzlari saqlandi'),
          backgroundColor: AppColors.button,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Xatolik: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Splash soʻzlari',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'Ilova ochilganda logo pulsatsiyasidan keyin markazda koʻrinadi. '
                'Har ochilishda roʻyxatdan tasodifiy 3 ta soʻz tanlanadi.',
                style: TextStyle(color: Colors.black54),
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tagline koʻrsatish'),
                subtitle: const Text('Oʻchirilsa — faqat logo animatsiyasi'),
                value: _enabled,
                activeThumbColor: AppColors.primary,
                onChanged: _saving ? null : (v) => setState(() => _enabled = v),
              ),
              const SizedBox(height: 12),
              for (var i = 0; i < _controllers.length; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _controllers[i],
                          enabled: !_saving,
                          maxLength: SplashSettings.maxTaglineLength,
                          decoration: InputDecoration(
                            labelText: 'Soʻz ${i + 1}',
                            border: const OutlineInputBorder(),
                            counterText: '',
                          ),
                          validator: (v) {
                            if ((v ?? '').trim().isEmpty) {
                              return 'Boʻsh boʻlishi mumkin emas';
                            }
                            return null;
                          },
                        ),
                      ),
                      IconButton(
                        tooltip: 'Oʻchirish',
                        onPressed: _saving || _controllers.length <= 1
                            ? null
                            : () => _removeLine(i),
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                      ),
                    ],
                  ),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _saving ||
                          _controllers.length >= SplashSettings.maxTaglines
                      ? null
                      : _addLine,
                  icon: const Icon(Icons.add),
                  label: const Text('Soʻz qoʻshish'),
                ),
              ),
              const SizedBox(height: 16),
              if (_updatedBy != null && _updatedBy!.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    'Oxirgi yangilovchi: $_updatedBy',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Saqlash'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
