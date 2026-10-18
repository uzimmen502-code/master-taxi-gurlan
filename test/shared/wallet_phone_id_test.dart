import 'package:ava_gurlan/shared/widgets/wallet_topup_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Қурилмада кўрилди: Кабинетдаги «Ҳамён» қаторида баланс чиқмади, чунки
/// Firebase телефони бўш эди. Илованинг ўз телефони (`user_phone`) захира.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('REGRESSION: Firebase тайёр эмас/телефони бўш — сақланган телефондан каноник ID', () async {
    SharedPreferences.setMockInitialValues({'user_phone': '+998 90 123 45 67'});
    expect(await walletPhoneId(), '998901234567');
  });

  test('9 хонали сақланган рақам — 998 билан тўлдирилади', () async {
    SharedPreferences.setMockInitialValues({'user_phone': '901234567'});
    expect(await walletPhoneId(), '998901234567');
  });

  test('телефон умуман йўқ — бўш (ёлғон ID эмас)', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await walletPhoneId(), '');
  });

  test('телефон йўқ — баланс оқими БЎШ (ёлғон «0» эмас)', () async {
    SharedPreferences.setMockInitialValues({});
    expect(await walletBalanceStream().toList(), isEmpty);
  });
}
