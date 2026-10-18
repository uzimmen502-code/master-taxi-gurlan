/// Депозит картаси ҳолати (админ «Telegram ҳамён» созламаси): карта йўқ/нотўғри
/// бўлса админ дарҳол кўради — фойдаланувчилар эса ботга боргач «Карта ҳали
/// созланмаган» жавобини олар эди. Қоида серверники билан бир хил
/// (`functions/wallet_topup_support.js`: 16 рақам + Луна); ҳал қилувчи — сервер.
library;

enum WalletBotCardState { ok, botOff, missing, invalid }

/// 16 рақам + Луна алгоритми.
bool walletCardIsValid(String raw) {
  final s = raw.replaceAll(RegExp(r'[\s-]'), '');
  if (!RegExp(r'^\d{16}$').hasMatch(s)) return false;
  var sum = 0;
  for (var i = 0; i < 16; i++) {
    var d = int.parse(s[15 - i]);
    if (i.isOdd) {
      d *= 2;
      if (d > 9) d -= 9;
    }
    sum += d;
  }
  return sum % 10 == 0;
}

WalletBotCardState evaluateWalletBotCard({required bool enabled, required String card}) {
  if (!enabled) return WalletBotCardState.botOff;
  final c = card.replaceAll(RegExp(r'\s+'), '');
  if (c.isEmpty) return WalletBotCardState.missing;
  if (!walletCardIsValid(c)) return WalletBotCardState.invalid;
  return WalletBotCardState.ok;
}
