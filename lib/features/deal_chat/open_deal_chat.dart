import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/utils/formatters.dart';
import '../../core/utils/user_error.dart';
import '../profile/screens/profile_screen.dart';
import '../wholesale/models/wholesale_product.dart';
import 'data/deal_chat_repository.dart';
import 'deal_chat_support.dart';
import 'screens/deal_chat_screen.dart';

/// Чат манбалари — сервер `functions/deal_chats.js` SOURCES билан бир хил.
abstract final class DealChatSource {
  static const wholesale = 'wholesale';

  /// Аралаш бозор эълони (`ads`, cheap_product).
  static const ad = 'ad';

  /// Аралаш бозор дўкон маҳсулоти (`tv_shop_items`).
  static const shopItem = 'shop_item';
}

/// «Ёзиш» тугмаси кўринсинми: меҳмонга кўринади (босганда рўйхатдан ўтишга чақирилади),
/// ЎЗ эълонида — йўқ (сервер ҳам OWN_PRODUCT билан рад этади).
bool dealChatShowWrite({required String myUid, required String ownerPhone}) {
  final me = canonicalPhoneId(myUid);
  final owner = canonicalPhoneId(ownerPhone);
  if (owner.length < 11) return false;
  return me != owner;
}

/// «Буюртма ёзиш» / «Ёзиш» → эълон эгаси билан чат (эга қарори 2026-11-01).
///
/// Меҳмон (телефонсиз) — рўйхатдан ўтишга чақирилади (сервер ҳам: PHONE_REQUIRED).
/// Хато — фойдаланувчи тилида (сервер коди → [kDealChatServerErrors]).
Future<void> openDealChatFlow(
  BuildContext context, {
  required String productId,
  required String myUid,
  String source = DealChatSource.wholesale,
  WholesaleProduct? initialProduct,
  DealChatRepository? repository,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);
  if (myUid.length < 11) {
    messenger.showSnackBar(SnackBar(
      content: Text(context.tr('deal_chat_login_required')),
      action: SnackBarAction(
        label: context.tr('deal_chat_login_cta'),
        onPressed: () => navigator.push(
          MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
        ),
      ),
    ));
    return;
  }
  final repo = repository ?? DealChatRepository();
  try {
    final chatId = await repo.openChat(productId, source: source);
    if (!context.mounted) return;
    await navigator.push(MaterialPageRoute<void>(
      builder: (_) => DealChatScreen(
        chatId: chatId,
        myUid: myUid,
        initialProduct: initialProduct,
        repository: repo,
      ),
    ));
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(
      content: Text(userErrorMessage(context, e,
          fallbackKey: 'deal_chat_open_failed', byServerMessage: kDealChatServerErrors)),
    ));
  }
}
