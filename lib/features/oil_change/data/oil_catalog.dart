/// Мой/фильтр каталоги ва тавсия мантиғи (прототип B).
/// Матнлар `assets/lang/{uz_Cyrl,uz_Latn,ru}.json` — `oil_*` калитлар.
library;

import 'package:flutter/widgets.dart';

import '../../../core/l10n/l10n_extension.dart';

class OilTypeInfo {
  const OilTypeInfo({
    required this.key,
    required this.width,
    required this.targetKm,
  });

  final String key;
  final double width; // 0..1
  /// Анимация якуни: 5000 / 7000 / 10000.
  final int targetKm;

  String title(BuildContext c) => c.tr('oil_type_${key}_title');
  String km(BuildContext c) => c.tr('oil_type_${key}_km');
  String short(BuildContext c) => c.tr('oil_type_${key}_short');
  String detailTitle(BuildContext c) => c.tr('oil_type_${key}_detail_title');
  String detail(BuildContext c) => c.tr('oil_type_${key}_detail');
}

class OilProduct {
  const OilProduct({
    required this.id,
    required this.nameKey,
    required this.metaKey,
    required this.price,
    required this.reasonKey,
    required this.specKeys,
    this.fixedName,
    this.plainMeta,
    this.plainReason,
    this.plainSpecs,
    this.imageUrl = '',
    this.isFilter = false,
    this.must = false,
    this.dust = false,
    this.gas = false,
    this.sortOrder = 0,
    this.active = true,
  });

  final String id;
  /// Бренд номи ўзгармас бўлса (Liqui Moly…) — [fixedName], акс ҳолда [nameKey].
  final String? fixedName;
  final String nameKey;
  final String metaKey;
  final int price;
  final String reasonKey;
  /// spec labelKey → value (value бренд/код бўлиши мумкин).
  final Map<String, String> specKeys;
  /// Firestore дан келган тайёр матнлар (l10n калитсиз).
  final String? plainMeta;
  final String? plainReason;
  final Map<String, String>? plainSpecs;
  final String imageUrl;
  final bool isFilter;
  final bool must;
  final bool dust;
  final bool gas;
  final int sortOrder;
  final bool active;

  bool get isOil => !isFilter;

  String displayName(BuildContext c) =>
      fixedName ?? c.tr(nameKey);

  String displayMeta(BuildContext c) =>
      (plainMeta != null && plainMeta!.isNotEmpty)
          ? plainMeta!
          : c.tr(metaKey);

  String displayReason(BuildContext c) =>
      (plainReason != null && plainReason!.isNotEmpty)
          ? plainReason!
          : c.tr(reasonKey);

  Map<String, String> localizedSpecs(BuildContext c) {
    if (plainSpecs != null && plainSpecs!.isNotEmpty) {
      return Map<String, String>.from(plainSpecs!);
    }
    return {
      for (final e in specKeys.entries) c.tr(e.key): e.value.startsWith('oil_')
          ? c.tr(e.value)
          : e.value,
    };
  }

  OilProduct copyWith({
    String? fixedName,
    String? plainMeta,
    String? plainReason,
    Map<String, String>? plainSpecs,
    String? imageUrl,
    int? price,
    int? sortOrder,
    bool? active,
    bool? must,
    bool? dust,
    bool? gas,
    bool? isFilter,
  }) {
    return OilProduct(
      id: id,
      nameKey: nameKey,
      metaKey: metaKey,
      price: price ?? this.price,
      reasonKey: reasonKey,
      specKeys: specKeys,
      fixedName: fixedName ?? this.fixedName,
      plainMeta: plainMeta ?? this.plainMeta,
      plainReason: plainReason ?? this.plainReason,
      plainSpecs: plainSpecs ?? this.plainSpecs,
      imageUrl: imageUrl ?? this.imageUrl,
      isFilter: isFilter ?? this.isFilter,
      must: must ?? this.must,
      dust: dust ?? this.dust,
      gas: gas ?? this.gas,
      sortOrder: sortOrder ?? this.sortOrder,
      active: active ?? this.active,
    );
  }
}

class OilRecoResult {
  const OilRecoResult({
    required this.ranked,
    required this.premium,
    required this.optimal,
    required this.acceptable,
    required this.introKey,
    required this.bundle,
  });

  /// Биринчи танловлар (орқага мослик): премиум / оптимал / мақбул боши.
  final List<OilProduct> ranked;
  final List<OilProduct> premium;
  final List<OilProduct> optimal;
  final List<OilProduct> acceptable;
  final String introKey;
  final List<OilProduct> bundle;

  String intro(BuildContext c) => c.tr(introKey);
}

abstract final class OilCatalog {
  static const types = <OilTypeInfo>[
    OilTypeInfo(key: 'full', width: 1, targetKm: 10000),
    OilTypeInfo(key: 'semi', width: 0.7, targetKm: 7000),
    OilTypeInfo(key: 'mineral', width: 0.5, targetKm: 5000),
  ];

  static const oils = <OilProduct>[
    OilProduct(
      id: 'o1',
      fixedName: 'Liqui Moly 5W-30',
      nameKey: 'oil_prod_o1_name',
      metaKey: 'oil_prod_o1_meta',
      price: 185000,
      reasonKey: 'oil_prod_o1_reason',
      specKeys: {
        'oil_spec_sae': '5W-30',
        'oil_spec_api': 'SP',
        'oil_spec_acea': 'C3',
        'oil_spec_type': 'oil_spec_val_full_syn',
        'oil_spec_country': 'DE',
      },
    ),
    OilProduct(
      id: 'o2',
      fixedName: 'Mobil 1 ESP 5W-30',
      nameKey: 'oil_prod_o2_name',
      metaKey: 'oil_prod_o2_meta',
      price: 210000,
      reasonKey: 'oil_prod_o2_reason',
      specKeys: {
        'oil_spec_sae': '5W-30',
        'oil_spec_api': 'SP',
        'oil_spec_acea': 'C3',
        'oil_spec_type': 'oil_spec_val_full_syn',
        'oil_spec_country': 'US',
      },
    ),
    OilProduct(
      id: 'o3',
      fixedName: 'Shell Helix HX8',
      nameKey: 'oil_prod_o3_name',
      metaKey: 'oil_prod_o3_meta',
      price: 165000,
      reasonKey: 'oil_prod_o3_reason',
      specKeys: {
        'oil_spec_sae': '5W-30',
        'oil_spec_api': 'SN',
        'oil_spec_acea': 'A3/B4',
        'oil_spec_type': 'oil_spec_val_full_syn',
        'oil_spec_country': 'NL',
      },
    ),
    OilProduct(
      id: 'o4',
      fixedName: 'Castrol Magnatec',
      nameKey: 'oil_prod_o4_name',
      metaKey: 'oil_prod_o4_meta',
      price: 175000,
      reasonKey: 'oil_prod_o4_reason',
      specKeys: {
        'oil_spec_sae': '5W-30',
        'oil_spec_api': 'SP',
        'oil_spec_acea': 'C2',
        'oil_spec_type': 'oil_spec_val_full_syn',
        'oil_spec_country': 'EU',
      },
    ),
    OilProduct(
      id: 'o5',
      fixedName: 'Local Pro 5W-30',
      nameKey: 'oil_prod_o5_name',
      metaKey: 'oil_prod_o5_meta',
      price: 145000,
      reasonKey: 'oil_prod_o5_reason',
      specKeys: {
        'oil_spec_sae': '5W-30',
        'oil_spec_api': 'SP',
        'oil_spec_acea': 'C3',
        'oil_spec_type': 'oil_spec_val_full_syn',
        'oil_spec_country': 'UZ',
      },
    ),
    OilProduct(
      id: 'o6',
      fixedName: 'Semi City 10W-40',
      nameKey: 'oil_prod_o6_name',
      metaKey: 'oil_prod_o6_meta',
      price: 98000,
      reasonKey: 'oil_prod_o6_reason',
      specKeys: {
        'oil_spec_sae': '10W-40',
        'oil_spec_api': 'SN',
        'oil_spec_type': 'oil_spec_val_semi',
        'oil_spec_country': 'UZ',
      },
    ),
  ];

  static const filters = <OilProduct>[
    OilProduct(
      id: 'f1',
      nameKey: 'oil_filter_f1_name',
      metaKey: 'oil_filter_f1_meta',
      price: 45000,
      reasonKey: 'oil_filter_f1_reason',
      specKeys: {
        'oil_spec_role': 'oil_filter_f1_role',
        'oil_spec_when': 'oil_filter_f1_when',
        'oil_spec_ava': 'oil_filter_f1_ava',
      },
      isFilter: true,
      must: true,
    ),
    OilProduct(
      id: 'f2',
      nameKey: 'oil_filter_f2_name',
      metaKey: 'oil_filter_f2_meta',
      price: 55000,
      reasonKey: 'oil_filter_f2_reason',
      specKeys: {
        'oil_spec_role': 'oil_filter_f2_role',
        'oil_spec_city': 'oil_filter_f2_city',
        'oil_spec_rural': 'oil_filter_f2_rural',
      },
      isFilter: true,
      dust: true,
    ),
    OilProduct(
      id: 'f3',
      nameKey: 'oil_filter_f3_name',
      metaKey: 'oil_filter_f3_meta',
      price: 60000,
      reasonKey: 'oil_filter_f3_reason',
      specKeys: {
        'oil_spec_role': 'oil_filter_f3_role',
        'oil_spec_when': 'oil_filter_f3_when',
      },
      isFilter: true,
    ),
    OilProduct(
      id: 'f4',
      nameKey: 'oil_filter_f4_name',
      metaKey: 'oil_filter_f4_meta',
      price: 70000,
      reasonKey: 'oil_filter_f4_reason',
      specKeys: {
        'oil_spec_role': 'oil_filter_f4_role',
        'oil_spec_gas': 'oil_filter_f4_gas',
      },
      isFilter: true,
      gas: true,
    ),
  ];

  static List<OilProduct> hubGalleryPreviewFrom(List<OilProduct> all) {
    final oils = all.where((p) => p.isOil).take(3).toList();
    final filters = all.where((p) => p.isFilter).take(2).toList();
    return [...oils, ...filters];
  }

  static List<OilProduct> get hubGalleryPreview =>
      hubGalleryPreviewFrom([...oils, ...filters]);

  static OilRecoResult recommend({
    required String fuelType,
    required List<String> usageTags,
    List<OilProduct>? catalog,
  }) {
    final all = catalog ?? [...oils, ...filters];
    final oilList = all.where((p) => p.isOil && p.active).toList();
    final filterList = all.where((p) => p.isFilter && p.active).toList();
    final fallbackOils = oils;
    final fallbackFilters = filters;
    final O = oilList.isNotEmpty ? oilList : fallbackOils;
    final F = filterList.isNotEmpty ? filterList : fallbackFilters;

    final fuel = fuelType.trim().toLowerCase();
    final usage = usageTags.map((e) => e.trim().toLowerCase()).toSet();
    final heavy = usage.contains('taxi') ||
        usage.contains('dust') ||
        usage.contains('long');
    final gas = fuel == 'cng' || fuel == 'lpg';
    final dust = usage.contains('dust');

    OilProduct pick(List<OilProduct> list, int i) =>
        list[i.clamp(0, list.length - 1)];

    // Қаторларга ажратиш — фақат база/каталогдаги `price` бўйича.
    final priced = O.where((p) => p.price > 0).toList();
    final unpriced = O.where((p) => p.price <= 0).toList();
    final byPriceDesc = [...priced]
      ..sort((a, b) {
        final c = b.price.compareTo(a.price);
        if (c != 0) return c;
        return a.id.compareTo(b.id);
      });

    final tiers = _splitRecoTiersByPrice(byPriceDesc);
    final premium = tiers.$1;
    final optimal = tiers.$2;
    // Нархсиз (0) мойлар — мақбул қатори охирига.
    final acceptable = [...tiers.$3, ...unpriced];

    final rankedOrFallback = <OilProduct>[
      if (premium.isNotEmpty) premium.first,
      if (optimal.isNotEmpty) optimal.first,
      if (acceptable.isNotEmpty) acceptable.first,
    ];

    final introKey = gas
        ? 'oil_reco_intro_gas'
        : (heavy ? 'oil_reco_intro_heavy' : 'oil_reco_intro_normal');

    OilProduct? byFlag({bool? must, bool? dustFlag, bool? gasFlag}) {
      for (final f in F) {
        if (must == true && f.must) return f;
        if (dustFlag == true && f.dust) return f;
        if (gasFlag == true && f.gas) return f;
      }
      return null;
    }

    final bundle = <OilProduct>[
      byFlag(must: true) ?? pick(F, 0),
    ];
    if (dust || heavy) {
      final air = byFlag(dustFlag: true) ?? (F.length > 1 ? F[1] : F.first);
      if (!bundle.any((b) => b.id == air.id)) bundle.add(air);
    }
    if (gas) {
      final fuelF = byFlag(gasFlag: true) ?? pick(F, F.length - 1);
      if (!bundle.any((b) => b.id == fuelF.id)) bundle.add(fuelF);
    } else {
      final cabin = F.length > 2 ? F[2] : pick(F, F.length - 1);
      if (!bundle.any((b) => b.id == cabin.id)) bundle.add(cabin);
    }

    return OilRecoResult(
      ranked: rankedOrFallback,
      premium: premium,
      optimal: optimal,
      acceptable: acceptable,
      introKey: introKey,
      bundle: bundle,
    );
  }

  /// Базадаги нарх диапазонини 3 қисмга бўлади:
  /// юқори ⅓ → премиум, ўрта ⅓ → оптимал, паст ⅓ → мақбул.
  /// [orderedDesc] — `price` камайиш бўйича сараланган (price > 0).
  static (List<OilProduct>, List<OilProduct>, List<OilProduct>)
      _splitRecoTiersByPrice(List<OilProduct> orderedDesc) {
    if (orderedDesc.isEmpty) {
      return (const [], const [], const []);
    }
    if (orderedDesc.length == 1) {
      return ([orderedDesc.first], const [], const []);
    }

    final maxP = orderedDesc.first.price;
    final minP = orderedDesc.last.price;
    final span = maxP - minP;

    // Барча нархлар тенг → сони бўйича тенг бўлиш (барчаси бир хил қаторда эмас).
    if (span <= 0) {
      return _splitRecoTiersByCount(orderedDesc);
    }

    final highCut = minP + (span * 2 / 3); // >= → премиум
    final midCut = minP + (span / 3); // >= → оптимал, < → мақбул

    final premium = <OilProduct>[];
    final optimal = <OilProduct>[];
    final acceptable = <OilProduct>[];
    for (final p in orderedDesc) {
      if (p.price >= highCut) {
        premium.add(p);
      } else if (p.price >= midCut) {
        optimal.add(p);
      } else {
        acceptable.add(p);
      }
    }

    // Бирор қатор бўш қолмасин — чегаравий нархни қўшни қатордан сурамиз.
    if (premium.isEmpty && optimal.isNotEmpty) {
      premium.add(optimal.removeAt(0));
    }
    if (acceptable.isEmpty && optimal.isNotEmpty) {
      acceptable.add(optimal.removeLast());
    }
    if (optimal.isEmpty) {
      if (premium.length > 1) {
        optimal.add(premium.removeLast());
      } else if (acceptable.length > 1) {
        optimal.add(acceptable.removeAt(0));
      }
    }

    return (premium, optimal, acceptable);
  }

  /// Нархлар тенг бўлганда — рўйхат узунлиги бўйича 3 қатор.
  static (List<OilProduct>, List<OilProduct>, List<OilProduct>)
      _splitRecoTiersByCount(List<OilProduct> ordered) {
    if (ordered.isEmpty) {
      return (const [], const [], const []);
    }
    if (ordered.length == 1) {
      return ([ordered.first], const [], const []);
    }
    if (ordered.length == 2) {
      return ([ordered[0]], [ordered[1]], const []);
    }
    final n = ordered.length;
    final premiumCount = (n / 3).ceil().clamp(1, n - 2);
    final rest = n - premiumCount;
    final optimalCount = (rest / 2).ceil().clamp(1, rest - 1);
    final premium = ordered.sublist(0, premiumCount);
    final optimal =
        ordered.sublist(premiumCount, premiumCount + optimalCount);
    final acceptable = ordered.sublist(premiumCount + optimalCount);
    return (premium, optimal, acceptable);
  }
}
