/// Taksi billing callable'lari (`quoteTaxiFee`, `publishTaxiTrip`,
/// `rescheduleTaxiTrip`, `cancelTaxiTrip`) `HttpsError.details.reason`
/// qiymatini foydalanuvchiga ko'rsatiladigan l10n kalitiga aylantiradi.
///
/// Manba: `functions/taxi_billing.js` (reason: no_user, no_capability,
/// agreement_required, taxi_verification_required, taxi_not_allowed,
/// outstanding_debt, not_published, trip_changed) va server auditi
/// (departure_in_past, route_required, seats_invalid, schedule_invalid).
/// Mijozga ichki sabab kodi ko'rsatilmaydi (25-qoida) — faqat sodda matn.
///
/// Noma'lum sabab → umumiy `taxi_publish_failed`.
const String kTaxiGenericFailureKey = 'taxi_publish_failed';

/// Server bilgan va matni bor barcha sabablar (test shu ro'yxatni 3 tilda
/// tekshiradi). Yangi sabab qo'shilsa — bu yerga VA 3 ta til fayliga.
const Map<String, String> kTaxiReasonKeys = {
  'agreement_required': 'taxi_reason_agreement_required',
  'taxi_verification_required': 'taxi_verification_required',
  'payment_required': 'taxi_fee_insufficient',
  'insufficient': 'taxi_fee_insufficient',
  'outstanding_debt': 'taxi_reason_outstanding_debt',
  'taxi_not_allowed': 'taxi_not_allowed',
  'no_user': 'taxi_not_allowed',
  'no_capability': 'taxi_reason_no_capability',
  'departure_in_past': 'taxi_reason_departure_in_past',
  'route_required': 'taxi_reason_route_required',
  'seats_invalid': 'taxi_reason_seats_invalid',
  'schedule_invalid': 'taxi_reason_schedule_invalid',
  'not_published': 'taxi_reason_not_published',
  'trip_changed': 'taxi_reason_trip_changed',
};

/// l10n kaliti (`context.tr(...)` ga beriladi).
String taxiReasonKey(String? reason) =>
    kTaxiReasonKeys[(reason ?? '').trim()] ?? kTaxiGenericFailureKey;
