import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/admin_pin.dart';
import '../controllers/profile_controller.dart';

/// Admin rolini PIN bilan faollashtirish — web admin panel uchun.
class AdminPinPromoteCard extends StatelessWidget {
  const AdminPinPromoteCard({super.key, this.embedded = false});

  /// Profil ichidagi oq kartochkada — tashqi margin yo'q.
  final bool embedded;

  static bool shouldShow(String role) =>
      role != 'admin' && role != 'superadmin';

  static Future<void> showPinDialog(BuildContext context) async {
    final c = context.read<ProfileController>();
    if (!shouldShow(c.role)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Сиз аллақачон админсиз'),
        backgroundColor: Colors.green,
      ));
      return;
    }

    final pinCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(children: [
          Icon(Icons.admin_panel_settings, color: Color(0xFF0D47A1)),
          SizedBox(width: 8),
          Expanded(child: Text('Админ роли')),
        ]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'PIN: $kAdminPanelPin\n\n'
              'Keyin web admin panelga (${c.phone.isEmpty ? "telefon" : c.phone}) kirishingiz mumkin.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: pinCtrl,
              keyboardType: TextInputType.number,
              obscureText: true,
              autofocus: true,
              maxLength: 8,
              decoration: const InputDecoration(
                labelText: 'PIN-kod',
                counterText: '',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бекор'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Фаоллаштириш'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) {
      pinCtrl.dispose();
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(
      content: Text('Текширилмоқда...'),
      duration: Duration(seconds: 2),
    ));

    final err = await c.promoteToAdminWithPin(pinCtrl.text);
    pinCtrl.dispose();
    if (!context.mounted) return;

    if (err != null) {
      messenger.showSnackBar(SnackBar(
        content: Text(err),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ));
      return;
    }

    messenger.showSnackBar(const SnackBar(
      content: Text(
        '✅ Админ роли берилди. Endi web panelga kiring yoki «АДМИН ПАНЕЛИ»ни очинг.',
      ),
      backgroundColor: Colors.green,
      duration: Duration(seconds: 4),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ProfileController>();
    if (!shouldShow(c.role)) return const SizedBox.shrink();

    return Container(
      margin: embedded
          ? const EdgeInsets.only(top: 4)
          : const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFE3F2FD),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF90CAF9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(children: [
            Icon(Icons.admin_panel_settings, color: Color(0xFF0D47A1), size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Web админ панели',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF0D47A1),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 6),
          const Text(
            'Operator paneliga kirish uchun avval bu yerda admin rolini faollashtiring (PIN).',
            style: TextStyle(fontSize: 12, color: Color(0xFF1565C0), height: 1.35),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 44,
            child: FilledButton.icon(
              onPressed: () => showPinDialog(context),
              icon: const Icon(Icons.lock_open, size: 18),
              label: const Text(
                '🔒 Админ ролини faollashtirish',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0D47A1),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
