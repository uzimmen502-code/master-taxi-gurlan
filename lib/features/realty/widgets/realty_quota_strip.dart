import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../repositories/realty_repository.dart';
import 'realty_feedback.dart';

/// «Эълон қўшиш» экранидаги банд ўрин йўлакчаси — статик «2 тагача бепул»
/// ёзуви ўрнига.
///
/// Ўрин тугаган бўлса шу ернинг ўзида «Пакетни кўриш» тугмаси чиқади:
/// фойдаланувчи формани тўлдиришдан ОЛДИН билиб олсин. Тугма пакет экранини
/// БЕВОСИТА очади — тугма тагидаги матн огоҳлантиришнинг ўзи, шунинг учун
/// такрорий диалог керак эмас (қурилмада сезилди, 2026-10-18).
///
/// Маълумот юкланмаган ёки номаълум (`limit == 0`, масалан тармоқ узилди)
/// бўлса «лимит тугади» ДЕБ ЁЛҒОН айтилмайди: статик ёрдам матни кўринади,
/// лимитни сервер юборишда айтади.
class RealtyQuotaStrip extends StatelessWidget {
  const RealtyQuotaStrip({
    super.key,
    required this.loaded,
    required this.quota,
    required this.busy,
    required this.onOpenPackage,
  });

  final bool loaded;
  final RealtyQuota quota;
  final bool busy;
  final VoidCallback onOpenPackage;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    if (!loaded || !quota.isKnown) {
      return Center(
        child: Text(
          context.tr('realty_free_limit_hint'),
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: AppText.labelTiny, color: c.ink3),
        ),
      );
    }
    return Column(
      children: [
        RealtyQuotaBar(quota: quota, compact: true),
        if (quota.isFull) ...[
          const SizedBox(height: 6),
          Text(
            context.tr('realty_limit_dialog_body'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: AppText.labelTiny, color: c.ink3),
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            key: const ValueKey('realty-open-package'),
            onPressed: busy ? null : onOpenPackage,
            icon: const Icon(Icons.workspace_premium_outlined, size: 18),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.brand,
              side: BorderSide(color: c.brand),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            label: Text(context.tr('realty_limit_dialog_cta')),
          ),
        ],
      ],
    );
  }
}
