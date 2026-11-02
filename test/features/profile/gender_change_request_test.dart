import 'package:ava_gurlan/features/profile/controllers/profile_controller.dart';
import 'package:flutter_test/flutter_test.dart';

/// Эга 2026-11-03: жинс рўйхатда бир марта; профилда фақат админ тасдиғи учун СЎРОВ.
void main() {
  test('бошқа жинсга сўров — рухсат', () {
    expect(ProfileController.validateGenderRequest('male', 'female'), isNull);
    expect(ProfileController.validateGenderRequest('female', 'male'), isNull);
  });
  test('ўша жинс — prof_gender_same', () {
    expect(ProfileController.validateGenderRequest('female', 'female'), 'prof_gender_same');
  });
  test('нотўғри қиймат — рад', () {
    expect(ProfileController.validateGenderRequest('male', ''), 'prof_gender_request_failed');
    expect(ProfileController.validateGenderRequest('male', 'other'), 'prof_gender_request_failed');
  });
}
