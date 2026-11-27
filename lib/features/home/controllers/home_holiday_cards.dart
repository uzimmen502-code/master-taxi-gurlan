import 'package:flutter/foundation.dart';

import '../../../core/utils/formatters.dart';
import '../../../repositories/relatives_repository.dart';
import '../../supermarket/data/holiday_repository.dart';
import '../../supermarket/domain/sm_holiday.dart';

/// Бош саҳифадаги «Байрам саватчаси» ва «Яқинларингиз туғилган кунини қўшинг» карточкалари ҳолати
/// (эга 2026-11-26). Кўриниш қоидалари — `sm_holiday.dart` (тоза, тестланади).
@immutable
class HomeHolidayState {
  const HomeHolidayState({
    this.holiday = false,
    this.birthdays = kRelativesPromptHideAt,
    this.bonusActive = false,
    this.market,
  });

  static const none = HomeHolidayState();

  /// Байрам саватчаси очиқми (супермаркет рухсати + сервер каталоги).
  final bool holiday;

  /// Туғилган куни киритилган қариндошлар (≤ [kRelativesPromptHideAt]); номаълум — шу чегара (карточка чиқмайди).
  final int birthdays;

  /// «Яқинлар» бонус дастури фаол ва шу фойдаланувчига тегишли (сервер `NOT_ENOUGH_RELATIVES` жавоби).
  final bool bonusActive;

  /// Бозор мақсадли фаол байрам (Қурбон ҳайит → Мол бозори) — супермаркет рухсатига БОҒЛИҚ ЭМАС (эга 2026-11-28).
  /// [holiday] (саватча) ва «Яқинлар» карточкасига таъсир қилмайди.
  final HolidayOccasion? market;

  bool get showRelativesPrompt => relativesPromptVisible(holidayAvailable: holiday, birthdaysCount: birthdays);

  @override
  bool operator ==(Object other) =>
      other is HomeHolidayState &&
      other.holiday == holiday &&
      other.birthdays == birthdays &&
      other.bonusActive == bonusActive &&
      other.market?.id == market?.id &&
      other.market?.target?.market == market?.target?.market;

  @override
  int get hashCode => Object.hash(holiday, birthdays, bonusActive, market?.id, market?.target?.market);

  HomeHolidayState withMarket(HolidayOccasion? m) =>
      HomeHolidayState(holiday: holiday, birthdays: birthdays, bonusActive: bonusActive, market: m);
}

/// Ҳолатни йиғади. Тармоқ хатоси — карточка кўрсатилмайди (хавфсиз томон). Бонус ҳолати (`claimRelativesBonus`,
/// идемпотент) фақат қариндошлар карточкаси керак бўлганда, сессияда бир марта сўралади (37-банд).
class HomeHolidayCards {
  HomeHolidayCards({
    Future<bool> Function()? holidayCheck,
    Future<int> Function(String userId)? countBirthdays,
    Future<Object?> Function()? claimBonus,
    Future<HolidayOccasion?> Function()? marketCheck,
  })  : _holidayCheck = holidayCheck,
        _count = countBirthdays,
        _claim = claimBonus,
        _marketCheck = marketCheck;

  final Future<bool> Function()? _holidayCheck;
  final Future<HolidayOccasion?> Function()? _marketCheck;
  final Future<int> Function(String userId)? _count;
  final Future<Object?> Function()? _claim;

  bool? _bonusActive;

  /// Саватча ([_basket], супермаркет рухсати керак) ва бозор мақсадли байрам (рухсатсиз) — алоҳида; бирининг хатоси
  /// иккинчисини яширмайди.
  Future<HomeHolidayState> resolve({required bool smOpenable, required String phone}) async {
    final basket = await _basket(smOpenable: smOpenable, phone: phone);
    HolidayOccasion? market;
    try {
      market = await (_marketCheck?.call() ?? holidayMarketAvailable());
    } catch (e) {
      debugPrint('[Home] HOLIDAY_MARKET_CHECK_FAILED: $e');
    }
    return basket.withMarket(market);
  }

  Future<HomeHolidayState> _basket({required bool smOpenable, required String phone}) async {
    try {
      final ok = await (_holidayCheck?.call() ?? holidayAvailable(smOpenable: smOpenable));
      if (!ok) return HomeHolidayState.none;
      final uid = canonicalPhoneId(phone);
      if (uid.length < 12) return const HomeHolidayState(holiday: true);
      final n = await (_count?.call(uid) ?? RelativesRepository().countBirthdays(uid, cap: kRelativesPromptHideAt));
      // Бонус мақсадига (3) етган — бонус сўралмайди (сервер granted/duplicate қайтаради), карточка 5 гача умумий матн билан.
      if (n >= kRelativesBirthdayGoal) return HomeHolidayState(holiday: true, birthdays: n);
      if (_bonusActive == null) {
        try {
          _bonusActive = relativesBonusFromClaim(await (_claim?.call() ?? FirebaseHolidayApi().claimRelativesBonus())).active;
        } catch (e) {
          debugPrint('[Home] HOLIDAY_BONUS_CHECK_FAILED: $e');
          _bonusActive = false;
        }
      }
      return HomeHolidayState(holiday: true, birthdays: n, bonusActive: _bonusActive!);
    } catch (e) {
      debugPrint('[Home] HOLIDAY_CARDS_FAILED: $e');
      return HomeHolidayState.none;
    }
  }

  /// Тортиб янгилашда бонус ҳам қайта сўралади.
  void invalidate() => _bonusActive = null;
}
