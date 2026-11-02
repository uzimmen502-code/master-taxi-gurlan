import 'package:ava_gurlan/features/onboarding/controllers/onboarding_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эга 2026-11-03: «жинс белгиланиши шарт, мажбурий». Аввал сукут 'male' эди — танламаган аёл
/// «эркак» бўлиб қоларди (аёллар рағбатидан четда).
void main() {
  String? v({String name = 'Ali', String phone = '+998 90 123 45 67', String gender = '', String birth = '15.05.1995'}) =>
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
  // Эга 2026-11-03: туғилган сана ҳам МАЖБУРИЙ.
  test('туғилган сана мажбурий: бўш — ob_err_birth_required', () {
    expect(v(gender: 'female', birth: ''), 'ob_err_birth_required');
    expect(v(gender: 'female', birth: '   '), 'ob_err_birth_required');
  });
  test('туғилган сана: нотўғри формат, келажак, 1900 дан олдин — ўтмайди; тўғри — ўтади', () {
    expect(v(gender: 'female', birth: '15.05.1995'), isNull);
    expect(v(gender: 'female', birth: '1995-05-15'), isNull);
    expect(v(gender: 'female', birth: '1995/05/15'), 'ob_birth_invalid_format');
    expect(v(gender: 'female', birth: '31.02.2000'), 'ob_birth_invalid_format');
    final next = DateTime.now().add(const Duration(days: 400));
    expect(v(gender: 'female', birth: '1.1.${next.year}'), 'ob_birth_invalid_format');
    expect(v(gender: 'female', birth: '1.1.1899'), 'ob_birth_invalid_format');
  });
}
