import '../../../models/relative_person.dart';
import '../../supermarket/domain/sm_holiday.dart';

/// Рўйхат бошида кўрсатиладиган яқин туғилган кунлар (эга 2026-11-26): «Мен» эмас, [withinDays] кун ичида,
/// энг яқини олдин, кўпи билан [max] та. Ойна (30 кун) — PROPOSED.
List<RelativePerson> upcomingBirthdaysWithin(
  Iterable<RelativePerson> people, {
  int withinDays = 30,
  int max = 3,
}) {
  final out = [
    for (final p in people)
      if (!p.isSelf && p.daysUntilBirthday != null && p.daysUntilBirthday! <= withinDays) p,
  ]..sort((a, b) => a.daysUntilBirthday!.compareTo(b.daysUntilBirthday!));
  return out.take(max).toList(growable: false);
}

/// «Саватча тайёрлаш» → туғилган кун саватчаси: телефони тўғри бўлса — совға олдиндан тўлдирилади (қабул қилувчи
/// = қариндош); телефон йўқ/нотўғри — совғасиз (мижоз ўзи танлайди).
SmHolidayCheckout relativeGiftCheckout(RelativePerson p) {
  final phone = smGiftPhone(p.phone);
  if (phone.isEmpty) return const SmHolidayCheckout();
  return SmHolidayCheckout(asGift: true, recipientName: p.fullName.trim(), recipientPhone: phone);
}
