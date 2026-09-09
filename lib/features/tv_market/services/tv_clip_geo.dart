import '../../../core/brand_labels.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/service_config_repository.dart';
import '../../../repositories/user_repository.dart';

/// Ролик тумани — жойлаштирувчининг `users.districtId` (кеш эмас).
class TvClipGeo {
  TvClipGeo._();

  static final _labelCache = <String, String>{};

  static Future<({String districtId, String districtLabel, String regionId})>
      resolveForPublisher({String ownerPhone = ''}) async {
    final phone = canonicalPhoneId(ownerPhone);
    var districtId = '';
    if (phone.isNotEmpty) {
      try {
        final user = await UserRepository().getById(phone);
        districtId = (user?.districtId ?? '').trim();
      } catch (_) {}
    }
    if (districtId.isEmpty) {
      districtId = ServiceConfigHolder.districtId.trim();
    }
    final label = await labelFor(districtId);
    var regionId = ServiceConfigHolder.regionId.trim();
    // Эга (owner) ва жорий қурилма ҳудуди фарқли бўлиши мумкин (мас.
    // администратор бошқа фойдаланувчи номидан жойлаётганда) — шу
    // туманнинг ўз вилоятини ўқиймиз (реклама «вилоят» қамрови учун шарт).
    if (districtId.isNotEmpty) {
      try {
        final d = await ServiceConfigRepository().fetchDistrict(districtId);
        if (d != null && d.regionId.trim().isNotEmpty) {
          regionId = d.regionId.trim();
        }
      } catch (_) {}
    }
    return (
      districtId: districtId,
      districtLabel: label.isNotEmpty
          ? label
          : ServiceConfigHolder.districtLabel.trim(),
      regionId: regionId,
    );
  }

  static Future<String> labelFor(String districtId) async {
    final id = districtId.trim();
    if (id.isEmpty) return '';
    final cached = _labelCache[id];
    if (cached != null) return cached;
    try {
      final d = await ServiceConfigRepository().fetchDistrict(id);
      final raw = d?.displayName.trim() ?? '';
      final label = raw.isEmpty ? '' : BrandLabels.shortDistrictName(raw);
      _labelCache[id] = label;
      return label;
    } catch (_) {
      return '';
    }
  }

  /// Эга телефони → жорий туман ( treyder профили).
  static Future<Map<String, ({String id, String label})>> resolveForOwners(
    Iterable<String> phones,
  ) async {
    final ids = phones
        .map(canonicalPhoneId)
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();
    if (ids.isEmpty) return {};
    final out = <String, ({String id, String label})>{};
    await Future.wait(ids.map((id) async {
      try {
        final user = await UserRepository().getById(id);
        final districtId = (user?.districtId ?? '').trim();
        if (districtId.isEmpty) return;
        final label = await labelFor(districtId);
        if (label.isEmpty) return;
        out[id] = (id: districtId, label: label);
      } catch (_) {}
    }));
    return out;
  }
}
