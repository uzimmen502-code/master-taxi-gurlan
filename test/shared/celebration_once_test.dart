import 'package:ava_gurlan/shared/widgets/celebration_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Табрик ҳар объект учун БИР МАРТА (эга, 2026-10-31).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('биринчи чақирув true, кейингиси false (шу калит учун)', () async {
    expect(await CelebrationOnce.claim('first_clip_998901112233'), isTrue);
    expect(await CelebrationOnce.claim('first_clip_998901112233'), isFalse);
  });

  test('бошқа калит — мустақил (бошқа объект яна табрикланади)', () async {
    expect(await CelebrationOnce.claim('restaurant_first_order_r1'), isTrue);
    expect(await CelebrationOnce.claim('restaurant_first_order_r2'), isTrue);
  });

  test('аввал белгиланган (илова қайта очилгандан кейин) — false', () async {
    SharedPreferences.setMockInitialValues({'celebrated_v1_courier_approved_998': true});
    expect(await CelebrationOnce.claim('courier_approved_998'), isFalse);
  });
}
