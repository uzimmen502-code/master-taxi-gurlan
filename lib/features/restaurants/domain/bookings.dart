// Стол бронь (S5, D-REST-23/38; docs/kafe_restoran_taklifi_uz.md §10.1).
//
// Эга қарори (2026-10-19): AVA хизмат ҳақи 1–5 киши 50 000 · 6–10 киши 150 000 · 11+ киши 400 000 сўм; ҳақни
// РЕСТОРАН тўлайди (ресторан ҳамёнидан, бронни қабул қилишда); мижоз бекор қилса/келмаса ёки қабулдан кейин ресторан
// бекор қилса ҳам ҳақ қайтарилмайди. Ҳақиқий қоида, сиғим ва пул — СЕРВЕРДА (`functions/restaurant_bookings.js`,
// 18-қоида); бу ерда фақат созламани ўқиш, мижозга аниқ хато кўрсатиш ва рўйхат ҳолатлари. Сон-чегаралар
// `settings/restaurant_bookings` дан (версияланган, 9-қоида); ҳужжат йўқ/ўқилмаса бронь КЎРИНМАЙДИ (хавфсиз томон).

import 'package:cloud_firestore/cloud_firestore.dart';

import 'restaurant_models.dart';

/// Ҳақ поғонаси: `guests <= upTo` бўлган биринчи поғона.
class BookingTier {
  const BookingTier({required this.upTo, required this.fee});

  final int upTo;
  final int fee;
}

/// `settings/restaurant_bookings`.
class BookingConfig {
  const BookingConfig({
    this.stage = 'off',
    this.testerIds = const [],
    this.tiers = defaultTiers,
    this.slotMin = 120,
    this.minLeadMin = 60,
    this.maxDays = 30,
    this.maxActivePerGuest = 5,
    this.version = 0,
  });

  /// Сервердаги `DEFAULTS.tiers` нусхаси (ҳужжатда поғона бўлмаса); мослиги `bookings_test.dart` да қулфланган.
  static const defaultTiers = [
    BookingTier(upTo: 5, fee: 50000),
    BookingTier(upTo: 10, fee: 150000),
    BookingTier(upTo: 100, fee: 400000),
  ];

  static const off = BookingConfig();

  final String stage;
  final List<String> testerIds;
  final List<BookingTier> tiers;
  final int slotMin;
  final int minLeadMin;
  final int maxDays;
  final int maxActivePerGuest;
  final int version;

  /// Фойдаланувчи [uid] (12 рақам) учун бронь ёқилганми: `public`; `internal` — фақат синовчи; `off` — ҳеч ким.
  bool visibleFor(String? uid) {
    if (stage == 'public') return true;
    if (stage == 'internal') return uid != null && uid.isNotEmpty && testerIds.contains(uid);
    return false;
  }

  /// Энг кўп меҳмон (охирги поғона).
  int get maxGuests => tiers.isEmpty ? 0 : tiers.last.upTo;

  /// [guests] учун ҳақ поғонаси; чегарадан ошса/нотўғри — `null`.
  BookingTier? tierFor(int guests) {
    if (guests < 1) return null;
    for (final t in tiers) {
      if (guests <= t.upTo) return t;
    }
    return null;
  }

  factory BookingConfig.fromMap(Map<String, dynamic>? d) {
    if (d == null) return off;
    int intOr(Object? v, int def) => v is num && v == v.truncate() ? v.toInt() : def;
    final rawTiers = d['tiers'];
    var tiers = defaultTiers;
    if (rawTiers is List) {
      final parsed = <BookingTier>[];
      var prev = 0;
      var ok = rawTiers.isNotEmpty;
      for (final t in rawTiers) {
        if (t is! Map) {
          ok = false;
          break;
        }
        final upTo = t['upTo'];
        final fee = t['fee'];
        if (upTo is! num || fee is! num || upTo != upTo.truncate() || fee != fee.truncate() || upTo.toInt() <= prev || fee < 0) {
          ok = false;
          break;
        }
        prev = upTo.toInt();
        parsed.add(BookingTier(upTo: prev, fee: fee.toInt()));
      }
      if (ok) tiers = parsed;
    }
    return BookingConfig(
      stage: const ['off', 'internal', 'public'].contains(d['stage']) ? d['stage'] as String : 'off',
      testerIds: (d['testerIds'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      tiers: tiers,
      slotMin: intOr(d['slotMin'], 120),
      minLeadMin: intOr(d['minLeadMin'], 60),
      maxDays: intOr(d['maxDays'], 30),
      maxActivePerGuest: intOr(d['maxActivePerGuest'], 5),
      version: intOr(d['version'], 0),
    );
  }
}

/// Бронь ҳолатлари (`functions/restaurant_bookings.js` `BS`).
abstract final class BookingStatus {
  static const requested = 'requested';
  static const confirmed = 'confirmed';
  static const rejected = 'rejected';
  static const expired = 'expired';
  static const cancelledByGuest = 'cancelled_by_guest';
  static const cancelledByRestaurant = 'cancelled_by_restaurant';

  static const all = [requested, confirmed, rejected, expired, cancelledByGuest, cancelledByRestaurant];

  /// Ҳали кучда: жавоб кутилмоқда ёки тасдиқланган.
  static bool isActive(String s) => s == requested || s == confirmed;
}

/// `restaurant_bookings/{id}` (мижоз ва ресторан а'зоси ўқийди; ёзув — фақат сервер).
class RestaurantBooking {
  const RestaurantBooking({
    required this.id,
    required this.restaurantId,
    required this.restaurantName,
    required this.guests,
    required this.startAt,
    required this.status,
    this.restaurantAddress = '',
    this.userName = '',
    this.userPhone = '',
    this.note = '',
    this.bookingNote = '',
    this.feeAmount = 0,
    this.feeCharged = false,
    this.feeRefunded = false,
    this.acceptDeadlineAt,
    this.createdAt,
  });

  final String id;
  final String restaurantId;
  final String restaurantName;
  final String restaurantAddress;
  final String userName;
  final String userPhone;
  final int guests;
  final DateTime startAt;
  final String status;
  final String note;

  /// Бронь пайтидаги рестораннинг закалат матни (снапшот).
  final String bookingNote;

  /// AVA ҳақи (ресторан тўлайди) — мижозга кўрсатилмайди, ресторан панелида кўринади.
  final int feeAmount;
  final bool feeCharged;
  final bool feeRefunded;
  final DateTime? acceptDeadlineAt;
  final DateTime? createdAt;

  bool get isActive => BookingStatus.isActive(status);

  /// Мижоз бекор қила оладими: фаол ва вақти ўтмаган.
  bool canGuestCancel(DateTime now) => isActive && startAt.isAfter(now);

  /// Ресторан қабул/рад қила оладими: жавоб кутилмоқда, муддат ва вақт ўтмаган.
  bool canRestaurantAnswer(DateTime now) =>
      status == BookingStatus.requested && startAt.isAfter(now) && (acceptDeadlineAt == null || acceptDeadlineAt!.isAfter(now));

  /// Ресторан тасдиқланган бронни бекор қила оладими (ҳақ қайтмайди!).
  bool canRestaurantCancel(DateTime now) => status == BookingStatus.confirmed && startAt.isAfter(now);

  factory RestaurantBooking.fromMap(String id, Map<String, dynamic> d) {
    DateTime? ts(Object? v) => v is Timestamp ? v.toDate() : (v is DateTime ? v : null);
    String s(Object? v) => v is String ? v : '';
    final fee = d['fee'] is Map ? Map<String, dynamic>.from(d['fee'] as Map) : const <String, dynamic>{};
    return RestaurantBooking(
      id: id,
      restaurantId: s(d['restaurantId']),
      restaurantName: s(d['restaurantName']),
      restaurantAddress: s(d['restaurantAddress']),
      userName: s(d['userName']),
      userPhone: s(d['userPhone']),
      guests: d['guests'] is num ? (d['guests'] as num).toInt() : 0,
      startAt: ts(d['startAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      status: BookingStatus.all.contains(d['status']) ? d['status'] as String : BookingStatus.requested,
      note: s(d['note']),
      bookingNote: s(d['bookingNote']),
      feeAmount: fee['amount'] is num ? (fee['amount'] as num).toInt() : 0,
      feeCharged: fee['charged'] == true,
      feeRefunded: fee['refunded'] == true,
      acceptDeadlineAt: ts(d['acceptDeadlineAt']),
      createdAt: ts(d['createdAt']),
    );
  }

  factory RestaurantBooking.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) =>
      RestaurantBooking.fromMap(doc.id, doc.data() ?? const {});
}

abstract final class Booking {
  /// Вақт танлаш қадами (дақиқа).
  static const stepMin = 15;

  /// Хато калитлари → `restaurants_booking_err_<калит>` (3 тилда). Сервер қоидаси билан бир хил тартиб.
  static const errSoon = 'soon';
  static const errFar = 'far';
  static const errPaused = 'paused';
  static const errClosed = 'closed_at_time';
  static const errGuests = 'guests';
  static const errSeats = 'seats';

  /// Танланган вақт/меҳмонлар сони ярайдими: `null` — ҳа; акс ҳолда хато калити. Фақат тугмани ўчириш ва
  /// аниқ матн кўрсатиш учун; сиғим (бошқа бронлар) факат серверда текширилади.
  static String? check({
    required DateTime now,
    required DateTime start,
    required int guests,
    required Restaurant restaurant,
    required BookingConfig config,
  }) {
    if (guests < 1 || guests > config.maxGuests) return errGuests;
    if (restaurant.bookingSeats < 1 || guests > restaurant.bookingSeats) return errSeats;
    final lead = start.difference(now);
    if (lead < Duration(minutes: config.minLeadMin)) return errSoon;
    if (lead > Duration(days: config.maxDays)) return errFar;
    final paused = restaurant.pausedUntil;
    if (paused != null && paused.isAfter(start)) return errPaused;
    if (!(restaurant.openingHours?.isOpenAt(start) ?? true)) return errClosed;
    return null;
  }

  /// Бошланғич таклиф: ҳозирдан энг камида `minLeadMin + 60` дақиқа кейин, [stepMin] га юқорига яхлитланган.
  static DateTime suggest(DateTime now, BookingConfig config) {
    final t = now.add(Duration(minutes: config.minLeadMin + 60));
    final rem = t.minute % stepMin;
    final rounded = rem == 0 ? t : t.add(Duration(minutes: stepMin - rem));
    return DateTime(rounded.year, rounded.month, rounded.day, rounded.hour, rounded.minute);
  }

  /// Танлаш мумкин кунлар: бугундан бошлаб `maxDays` кун (ярим тундан), энг кўпи 14 та чип.
  static List<DateTime> days(DateTime now, BookingConfig config, {int chips = 14}) {
    final n = config.maxDays < chips ? config.maxDays : chips;
    return [for (var i = 0; i <= n; i++) DateTime(now.year, now.month, now.day + i)];
  }

  /// Кўрсатиш: `21.10 19:00`.
  static String format(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }
}
