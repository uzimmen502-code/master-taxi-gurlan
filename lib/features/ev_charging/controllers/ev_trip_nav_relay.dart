// ⚡ EV сафар — Google Maps'га тўхташларни БЎЛАКЛАБ юбориш (эга қарори,
// 2026-10-16: «бутун маршрут бир марта, кўп оралиқ нуқта билан»).
//
// Тоза Dart (плагинсиз): `flutter test`да тўғридан-тўғри текширилади.
//
// Қоида: Google Maps оралиқ нуқталарнинг сонини чеклайди
// (`mapsMaxWaypoints()`: мобил веб 3, бошқа 9). Танланганлар чекловдан кўп
// бўлса, навигация БЛОКЛАНМАЙДИ ва иловa ўзбошимчалик билан ҳам
// «қирқмайди»:
//  * биринчи чақирувга йўл бўйича ЭНГ ЯҚИН `limit` та тўхташ юборилади
//    (манзил — ҲАМИША охирги манзил);
//  * қолгани «кейинги тўхташлар» сифатида сақланади;
//  * машина юборилган охирги тўхташдан [EvNavigationRelay.passedMarginKm]
//    ўтгач (ёки ҳайдовчи ўзи босса) «Давом этиш» таклиф қилинади — яна
//    навбатдаги `limit` та, то қолмагунча.

import 'ev_trip_selection.dart';

/// [evNavigationChunk] натижаси: Google Maps'га ҳозир юбориладиганлар ва
/// кейинга қолганлар (иккаласи ҳам йўл бўйича тартибда).
typedef EvNavigationChunk<T> = ({List<T> sent, List<T> remaining});

/// [selected] (йўл бўйича тартибланган) дан биринчи [limit] тасини
/// «юбориладиган», қолганини «қолган» қилиб ажратади. [limit] < 1 бўлса 1
/// деб олинади (бўлмаса «Давом этиш» чексиз такрорланар эди).
EvNavigationChunk<T> evNavigationChunk<T>(List<T> selected, int limit) {
  final n = limit < 1 ? 1 : limit;
  if (selected.length <= n) {
    return (sent: List<T>.of(selected), remaining: <T>[]);
  }
  return (
    sent: List<T>.of(selected.sublist(0, n)),
    remaining: List<T>.of(selected.sublist(n)),
  );
}

/// Бўлаклаб юборишнинг ҳолати: нималар юборилди ва машина охирги юборилган
/// тўхташдан ўтдими. Экранда яшайди (илова фонда бўлса ҳам ҳолат шу ерда).
class EvNavigationRelay {
  /// Машина охирги юборилган тўхташдан шунча км ўтгач «Давом этиш»
  /// карточкаси ўзи чиқади.
  static const double passedMarginKm = 1.5;

  final Set<String> _sentIds = <String>{};
  final Set<String> _sentCoords = <String>{};
  double? _lastSentAlongKm;

  /// Камида битта бўлак юборилган ва ҳали давом этилмоқда.
  bool get active => _lastSentAlongKm != null;

  /// Юборилган охирги тўхташнинг йўл бошидан масофаси (км).
  double? get lastSentAlongKm => _lastSentAlongKm;

  void reset() {
    _sentIds.clear();
    _sentCoords.clear();
    _lastSentAlongKm = null;
  }

  /// [sent] Google Maps'га юборилди.
  void markSent(List<EvTripCandidate> sent) {
    for (final c in sent) {
      _sentIds.add(c.id);
      _sentCoords.add(evStationCoordKey(c.station));
      final last = _lastSentAlongKm;
      if (last == null || c.alongKm > last) _lastSentAlongKm = c.alongKm;
    }
  }

  /// Ҳали юборилмаган тўхташлар: [navigable] (танланганлар, йўл бўйича,
  /// координата бўйича ягона) орасидан юборилмаганлари ва юборилган охирги
  /// тўхташдан орқада қолмаганлари. Танлов ўзгарса (олиб ташланди/қўшилди)
  /// шунга мос ўзгаради — алоҳида нусха сақланмайди.
  List<EvTripCandidate> pending(List<EvTripCandidate> navigable) {
    final last = _lastSentAlongKm;
    if (last == null) return const [];
    return [
      for (final c in navigable)
        if (!_sentIds.contains(c.id) &&
            !_sentCoords.contains(evStationCoordKey(c.station)) &&
            c.alongKm >= last)
          c,
    ];
  }

  /// Машина (йўл бошидан [carAlongKm] км) юборилган охирги тўхташдан
  /// [passedMarginKm] дан кўпроқ ўтдими. Позиция номаълум (GPS йўқ ёки
  /// машина йўлда эмас) — `false`: карточка ўзи чиқмайди, чип қолади.
  bool hasPassedLastSent(double? carAlongKm) {
    final last = _lastSentAlongKm;
    if (last == null || carAlongKm == null) return false;
    return carAlongKm >= last + passedMarginKm;
  }
}
