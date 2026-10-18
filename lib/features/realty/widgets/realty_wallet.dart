import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../repositories/realty_repository.dart';
import '../../../shared/widgets/wallet_topup_ui.dart';
import 'realty_feedback.dart';

/// Кўчмас мулк: баланс етмаслиги хатоси. Баланс қатори, варақ ичидаги хато ва
/// ҳамёнга ўтиш — УМУМИЙ қатламда (`shared/widgets/wallet_topup_ui.dart`).

/// Хато баланс етмаслигиданми («Ҳамённи тўлдириш» тугмаси чиқарилиши керак).
bool realtyNeedsTopUp(RealtyException e) => e.code == 'insufficient_balance';

/// Оддий экрандаги (варақ эмас) харид хатоси. Баланс етмаса snackbar'да
/// «Ҳамённи тўлдириш» ТУГМАСИ бўлади.
///
/// [messenger] ва [navigator] `await` дан ОЛДИН олиб қўйилади (контекст
/// ишончсиз). [openWallet] — тест учун алмаштириладиган ҳаракат.
void showRealtyPurchaseError({
  required BuildContext context,
  required ScaffoldMessengerState messenger,
  required NavigatorState navigator,
  required RealtyException error,
  VoidCallback? openWallet,
}) {
  final text = realtyErrorText(context, error);
  if (!realtyNeedsTopUp(error)) {
    showRealtyError(messenger, text);
    return;
  }
  showRealtyError(
    messenger,
    text,
    actionLabel: context.tr('wlt_topup_btn'),
    onAction: openWallet ?? () => openWalletTopUp(navigator),
  );
}
