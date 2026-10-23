import 'business_category.dart';
import 'business_pin.dart';

/// Харитадаги нуқталарни тур ва ном бўйича фильтрлаш — соф функция (тест учун).
///
/// [category] `null` = ҳаммаси. [query] — ном/кичик тур/манзил бўйича, регистрсиз, бўш бўлса фильтр йўқ.
List<BusinessPin> filterPins(
  Iterable<BusinessPin> pins, {
  BusinessCategory? category,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final p in pins)
      if ((category == null || p.category == category) &&
          (q.isEmpty ||
              p.name.toLowerCase().contains(q) ||
              p.subtitle.toLowerCase().contains(q) ||
              p.address.toLowerCase().contains(q)))
        p,
  ];
}

/// Харитада мавжуд турлар (қолган чипларни яширмаслик учун — барча 14 тур эмас, фақат бор бўлганлари).
List<BusinessCategory> categoriesPresent(Iterable<BusinessPin> pins) {
  final present = {for (final p in pins) p.category};
  return [for (final c in BusinessCategory.values) if (present.contains(c)) c];
}
