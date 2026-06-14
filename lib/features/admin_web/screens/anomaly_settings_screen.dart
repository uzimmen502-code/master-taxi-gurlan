import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../services/admin_auth_service.dart';

/// Аномалия детектори чеги ва чиқим лимитлари — `settings/anomaly_settings`.
class AnomalySettingsScreen extends StatefulWidget {
  const AnomalySettingsScreen({super.key});

  @override
  State<AnomalySettingsScreen> createState() => _AnomalySettingsScreenState();
}

class _AnomalySettingsScreenState extends State<AnomalySettingsScreen> {
  static const _orange = Color(0xFFFF9800);

  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _anomalyThresholdCtrl;
  late final TextEditingController _maxWithdrawalCtrl;
  late final TextEditingController _maxWithdrawalPerHourCtrl;
  bool _notificationsEnabled = true;
  bool _isLoading = false;
  bool _initialLoad = true;
  String? _lastUpdatedBy;

  @override
  void initState() {
    super.initState();
    _anomalyThresholdCtrl = TextEditingController();
    _maxWithdrawalCtrl = TextEditingController();
    _maxWithdrawalPerHourCtrl = TextEditingController();
    _loadSettings();
  }

  @override
  void dispose() {
    _anomalyThresholdCtrl.dispose();
    _maxWithdrawalCtrl.dispose();
    _maxWithdrawalPerHourCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('anomaly_settings')
          .get();

      if (doc.exists) {
        final data = doc.data()!;
        _anomalyThresholdCtrl.text =
            (data['anomalyAmountThreshold'] ?? 100000).toString();
        _maxWithdrawalCtrl.text =
            (data['maxWithdrawalPerUser'] ?? 1000000).toString();
        _maxWithdrawalPerHourCtrl.text =
            (data['maxWithdrawalPerHour'] ?? 1000000).toString();
        _notificationsEnabled = data['anomalyNotificationEnabled'] ?? true;
        _lastUpdatedBy = (data['updatedBy'] ?? '').toString();
      } else {
        _anomalyThresholdCtrl.text = '100000';
        _maxWithdrawalCtrl.text = '1000000';
        _maxWithdrawalPerHourCtrl.text = '1000000';
        _notificationsEnabled = true;
      }
    } finally {
      if (mounted) setState(() => _initialLoad = false);
    }
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    final messenger = ScaffoldMessenger.of(context);
    final adminPhone = context.read<AdminAuthService>().phoneDigits ??
        context.read<AdminAuthService>().phone ??
        'unknown';

    try {
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('anomaly_settings')
          .set({
        'anomalyAmountThreshold':
            int.parse(_anomalyThresholdCtrl.text.trim()),
        'maxWithdrawalPerUser': int.parse(_maxWithdrawalCtrl.text.trim()),
        'maxWithdrawalPerHour':
            int.parse(_maxWithdrawalPerHourCtrl.text.trim()),
        'anomalyNotificationEnabled': _notificationsEnabled,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': adminPhone,
      }, SetOptions(merge: true));

      if (!mounted) return;
      setState(() => _lastUpdatedBy = adminPhone);
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Созламалар сақланди'),
          backgroundColor: AppColors.button,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Хатолик: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_initialLoad) {
      return const Column(
        children: [
          _AnomalyHeader(),
          Expanded(child: Center(child: CircularProgressIndicator())),
        ],
      );
    }

    return Column(
      children: [
        const _AnomalyHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.warning_amber, color: _orange, size: 28),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Аномалия детектори — катта ёки шубҳали транзакцияларни аниқлайди',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_lastUpdatedBy != null && _lastUpdatedBy!.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Охирги ўзгартирувчи: $_lastUpdatedBy',
                      style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _settingsCard(
                    title: 'Аномалия чеги (сўм)',
                    icon: Icons.attach_money,
                    helper:
                        'Шу суммадан юқори транзакция аномалия деб ҳисобланади',
                    field: _anomalyThresholdCtrl,
                  ),
                  const SizedBox(height: 14),
                  _settingsCard(
                    title: 'Бир марталик максимал чиқим (сўм)',
                    icon: Icons.block,
                    helper: 'Бир операцияда ечиб олинадиган максимал сумма',
                    field: _maxWithdrawalCtrl,
                  ),
                  const SizedBox(height: 14),
                  _settingsCard(
                    title: '1 соатда максимал чиқим (сўм)',
                    icon: Icons.timer,
                    helper:
                        '1 соат ичида жами ечиб олинадиган максимал сумма',
                    field: _maxWithdrawalPerHourCtrl,
                  ),
                  const SizedBox(height: 14),
                  Card(
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(color: Colors.grey.shade200),
                    ),
                    child: SwitchListTile(
                      title: const Text('Telegram хабар юбориш'),
                      subtitle: const Text(
                        'Аномалия топилганда админга хабар юборилади (бот токени CF да)',
                      ),
                      value: _notificationsEnabled,
                      onChanged: (val) =>
                          setState(() => _notificationsEnabled = val),
                      secondary: Icon(
                        _notificationsEnabled
                            ? Icons.notifications_active
                            : Icons.notifications_off,
                        color: _notificationsEnabled
                            ? Colors.green
                            : Colors.grey,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isLoading ? null : _saveSettings,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save),
                      label: Text(
                        _isLoading ? 'Сақланмоқда...' : 'СОЗЛАМАЛАРНИ САҚЛАШ',
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _orange,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _settingsCard({
    required String title,
    required IconData icon,
    required String helper,
    required TextEditingController field,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            TextFormField(
              controller: field,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                prefixIcon: Icon(icon),
                border: const OutlineInputBorder(),
                helperText: helper,
              ),
              validator: (v) =>
                  v == null || int.tryParse(v.trim()) == null ? 'Сон киритинг' : null,
            ),
          ],
        ),
      ),
    );
  }
}

class _AnomalyHeader extends StatelessWidget {
  const _AnomalyHeader();

  static const _orange = Color(0xFFFF9800);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.settings, color: _orange),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Аномалия созламалари',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 3),
                Text(
                  'Чеги, чиқим лимити ва Telegram хабарлар',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
