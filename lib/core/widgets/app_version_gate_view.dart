import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_version_gate.dart';
import '../l10n/l10n_extension.dart';
import '../theme/app_theme.dart';

/// Иловани [AppVersionGate] билан ўрайди.
///
/// Мажбурий янгилаш талаб қилинса — [child] умуман чизилмайди, ўрнига
/// [ForceUpdateScreen] кўринади. Акс ҳолда ҳеч нарса сезилмайди.
///
/// Ҳолат `AppVersionGate.revision` орқали кузатилади: тармоқдан янги
/// конфиг келганда экран ўзи алмашади, қайта ишга тушириш керак эмас.
class AppVersionGateView extends StatelessWidget {
  const AppVersionGateView({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: AppVersionGate.revision,
      builder: (context, _, __) {
        if (AppVersionGate.mustUpdate) return const ForceUpdateScreen();
        return child;
      },
    );
  }
}

/// «Янгиланг» экрани — ортга йўл йўқ.
///
/// Атайлаб содда: илованинг қолган қисми эскирган бўлиши мумкин,
/// шунинг учун бу экран ҳеч қайси модулга, репозиторийга ёки
/// маълумотга боғланмайди.
class ForceUpdateScreen extends StatelessWidget {
  const ForceUpdateScreen({super.key});

  /// Play саҳифасини очади. `market://` иловани бевосита очади, у
  /// ишламаса (эмулятор, Play'сиз қурилма) веб ҳаволага тушади.
  static Future<void> openStore(String packageName) async {
    final pkg = packageName.trim().isEmpty ? 'uz.ava.gurlan' : packageName;
    final market = Uri.parse('market://details?id=$pkg');
    final web =
        Uri.parse('https://play.google.com/store/apps/details?id=$pkg');
    try {
      if (await launchUrl(market, mode: LaunchMode.externalApplication)) {
        return;
      }
    } catch (_) {
      // Play ilovasi yo'q — pastdagi veb havola ishlaydi.
    }
    try {
      await launchUrl(web, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    // Серверда матн ёзилган бўлса ўша, бўлмаса локал таржима.
    final server = AppVersionGate.serverMessage.trim();
    final body =
        server.isNotEmpty ? server : context.tr('update_required_body');

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.system_update_rounded,
                    size: 44,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  context.tr('update_required_title'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.4,
                    color: Colors.grey.shade700,
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () =>
                        openStore(AppVersionGate.packageName),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      minimumSize: const Size.fromHeight(50),
                    ),
                    child: Text(context.tr('update_required_button')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
