import 'package:flutter/material.dart' show TimeOfDay;

/// Shaharlararo reys jo'nash vaqti qoidalari (haydovchi tomoni, faqat UI
/// yordamchisi): standart vaqtni tanlash va o'tib ketgan vaqtni to'sish.
///
/// Haqiqiy qoida SERVERDA (`publishTaxiTrip` / `rescheduleTaxiTrip` →
/// `departure_in_past`); bu yerda faqat foydalanuvchi to'lov oqimiga kirmay
/// turib xatoni ko'rishi uchun. Hamma funksiya `now` ni parametr sifatida
/// oladi (soat in'ektsiyasi) — testda real vaqt kerak emas.
class IntercityDeparture {
  IntercityDeparture._();

  /// Bugungi vaqt shundan kam oldinda bo'lsa standart sifatida yaroqsiz.
  static const Duration minLead = Duration(minutes: 10);

  /// Qo'lda tanlangan vaqt `now` dan shuncha ORQADA bo'lsa ham ruxsat
  /// (soat siljishi / bosish kechikishi uchun). Qat'iy hukm — serverda.
  static const Duration pastGrace = Duration(minutes: 2);

  /// Eski standart (08:00) — "ertaga" tanlanganda ishlatiladi.
  static const TimeOfDay morningDefault = TimeOfDay(hour: 8, minute: 0);

  /// Berilgan kun (bugun/ertaga) va vaqtdan to'liq sana-vaqt.
  static DateTime departureAt({
    required DateTime now,
    required bool tomorrow,
    required TimeOfDay time,
  }) {
    final day = DateTime(now.year, now.month, now.day + (tomorrow ? 1 : 0));
    return DateTime(day.year, day.month, day.day, time.hour, time.minute);
  }

  /// Tanlangan kun+vaqt o'tib ketganmi ([pastGrace] hisobga olingan).
  static bool isInPast({
    required DateTime now,
    required bool tomorrow,
    required TimeOfDay time,
  }) {
    final at = departureAt(now: now, tomorrow: tomorrow, time: time);
    return at.isBefore(now.subtract(pastGrace));
  }

  /// Bugun uchun yaqinroq keyingi yarim soatlik slot (`:00` yoki `:30`),
  /// u kamida [minLead] oldinda bo'lsin. Kun oxiriga to'g'ri kelsa
  /// (23:30 dan keyin) — ertaga [morningDefault].
  static ({TimeOfDay time, bool tomorrow}) nextSlot(DateTime now) {
    var slot = DateTime(now.year, now.month, now.day, now.hour,
        now.minute < 30 ? 30 : 60);
    if (slot.difference(now) < minLead) {
      slot = slot.add(const Duration(minutes: 30));
    }
    if (slot.day != now.day || slot.month != now.month) {
      return (time: morningDefault, tomorrow: true);
    }
    return (time: TimeOfDay(hour: slot.hour, minute: slot.minute), tomorrow: false);
  }

  /// Standart (yoki saqlangan) tanlovni bugungi vaqtga moslash.
  ///
  /// - "Ertaga" har doim kelajak — o'zgarmaydi;
  /// - "Bugun" va vaqt kamida [minLead] oldinda — o'zgarmaydi;
  /// - aks holda [nextSlot] (yoki ertaga 08:00, agar kun tugayotgan bo'lsa).
  static ({TimeOfDay time, bool tomorrow}) smartDefault({
    required DateTime now,
    required TimeOfDay preferred,
    required bool preferredTomorrow,
  }) {
    if (preferredTomorrow) return (time: preferred, tomorrow: true);
    final at = departureAt(now: now, tomorrow: false, time: preferred);
    if (!at.isBefore(now.add(minLead))) {
      return (time: preferred, tomorrow: false);
    }
    return nextSlot(now);
  }

  /// Qayta rejalashtirish (reschedule) dialogi uchun boshlang'ich vaqt:
  /// tanlangan sana bugun bo'lsa — [nextSlot]/oldinda bo'lsa o'zi; boshqa kun
  /// uchun — [morningDefault].
  static TimeOfDay initialRescheduleTime({
    required DateTime now,
    required DateTime pickedDay,
  }) {
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(pickedDay.year, pickedDay.month, pickedDay.day);
    if (day.isAfter(today)) return morningDefault;
    final r = smartDefault(
        now: now, preferred: morningDefault, preferredTomorrow: false);
    return r.tomorrow ? morningDefault : r.time;
  }

  /// Qayta rejalashtirishda: tanlangan sana+vaqt o'tib ketganmi.
  static bool isRescheduleInPast({
    required DateTime now,
    required DateTime pickedDay,
    required TimeOfDay time,
  }) {
    final at = DateTime(
        pickedDay.year, pickedDay.month, pickedDay.day, time.hour, time.minute);
    return at.isBefore(now.subtract(pastGrace));
  }
}
