import 'package:ava_gurlan/features/onboarding/controllers/onboarding_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эга 2026-11-03: «жинс белгиланиши шарт, мажбурий». Аввал сукут 'male' эди — танламаган аёл
/// «эркак» бўлиб қоларди (аёллар рағбатидан четда).
void main() {
  String? v({String name = 'Ali', String phone = '+998 90 123 45 67', String gender = '', String birth = ''}) =>
      OnboardingController.validateOnboardingInput(name: name, phone: phone, gender: gender, birthDate: birth);

  test('жинс танланмаса — ўтказмайди', () => expect(v(), 'ob_err_gender'));
  test('нотўғри қиймат — ўтказмайди', () => expect(v(gender: 'other'), 'ob_err_gender'));
  test('эркак ёки аёл — ўтади', () {
    expect(v(gender: 'male'), isNull);
    expect(v(gender: 'female'), isNull);
  });
  test('тартиб: аввал исм ва телефон хатоси', () {
    expect(v(name: ' '), 'ob_err_name');
    expect(v(phone: '12345'), 'ob_phone_required');
  });
  test('туғилган сана ихтиёрий, лекин нотўғри формат ўтмайди', () {
    expect(v(gender: 'female', birth: '15.05.1995'), isNull);
    expect(v(gender: 'female', birth: '1995/05/15'), 'ob_birth_invalid_format');
  });
}
