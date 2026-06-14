import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';

/// Driver app ўрнатилмаган бўлсa чиқадиган диалог.
///
/// Қайтариш қиймати:
///   - `true` — фойдаланувчи "APK юклaб олиш" тугмасини босди (caller
///     `DriverAppLauncher.openApkDownload()`'ни чақириши керак).
///   - `false`/`null` — фойдаланувчи "Бекор қилиш" ёки orqaga қайтди.
Future<bool?> showInstallDriverAppDialog(BuildContext context) {
  return showDialog<bool>(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => const _InstallDriverAppDialog(),
  );
}

class _InstallDriverAppDialog extends StatelessWidget {
  const _InstallDriverAppDialog();

  static const Color _blue = AppColors.primary;
  static const Color _orange = AppColors.primaryMid;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Hero icon
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_blue, Color(0xFF1976D2)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: _blue.withOpacity(0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: const Icon(Icons.local_taxi,
                  color: Colors.white, size: 36),
            ),
            const SizedBox(height: 14),
            Text(context.tr('local_driver_app_title'),
                textAlign: TextAlign.center,
                style:
                    TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Text(
              context.tr('install_driver_app_body'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 16),
            // Steps
            _step(
              num: '1',
              icon: Icons.download_outlined,
              title: context.tr('install_driver_step1_title'),
              subtitle: context.tr('install_driver_step1_sub'),
            ),
            const SizedBox(height: 8),
            _step(
              num: '2',
              icon: Icons.install_mobile,
              title: context.tr('install_driver_step2_title'),
              subtitle: context.tr('install_driver_step2_sub'),
            ),
            const SizedBox(height: 8),
            _step(
              num: '3',
              icon: Icons.touch_app,
              title: context.tr('install_driver_step3_title'),
              subtitle: context.tr('install_driver_step3_sub'),
            ),
            const SizedBox(height: 18),
            // CTA
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.cloud_download, size: 18),
                label: Text(context.tr('download_apk'),
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _orange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
              ),
              child: Text(context.tr('cancel')),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _step({
    required String num,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: _blue.withOpacity(0.12),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(num,
            style: const TextStyle(
                fontSize: 12, fontWeight: FontWeight.bold, color: _blue)),
      ),
      const SizedBox(width: 10),
      Icon(icon, size: 18, color: _blue),
      const SizedBox(width: 8),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Text(subtitle,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
        ]),
      ),
    ]);
  }
}
