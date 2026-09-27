import 'dart:math';

import 'package:flutter/widgets.dart';

import '../../core/l10n/l10n_extension.dart';

/// Бош саҳифадаги бўлимлар бўш кўринмаслиги учун намунавий қаторлар.
///
/// Улар базада САҚЛАНМАЙДИ — фақат интерфейсда чизилади. Шунинг учун:
/// * реал эълон қанча кўп бўлса, намунавийлари шунча кам кўринади
///   (жой реал эълонга берилади — «аста-секин алмашиш»);
/// * реал эълонлар [capacity] га етганда намунавийлари БУТУНЛАЙ
///   йўқолади — базани тозалаш керак эмас, чунки у ерда улар йўқ;
/// * қатор босилса ўша бўлимнинг тўлиқ экрани очилади.
abstract final class HomeDemoFeed {
  /// Бир бўлимда кўрсатиладиган энг кўп қатор — реал эълонлар шунчага
  /// етганда намунавийлари қолмайди.
  static const int capacity = 10;

  /// «Яқиндаги эълонлар».
  static const List<String> adKeys = [
    'demo_ad_1',
    'demo_ad_2',
    'demo_ad_3',
    'demo_ad_4',
    'demo_ad_5',
    'demo_ad_6',
    'demo_ad_7',
    'demo_ad_8',
    'demo_ad_9',
    'demo_ad_10',
  ];

  /// «Яқиндаги хизматлар».
  static const List<String> serviceKeys = [
    'demo_service_1',
    'demo_service_2',
    'demo_service_3',
    'demo_service_4',
    'demo_service_5',
    'demo_service_6',
    'demo_service_7',
    'demo_service_8',
    'demo_service_9',
    'demo_service_10',
  ];

  /// «Шаҳарлараро такси» — йўналишлар.
  static const List<String> intercityKeys = [
    'demo_intercity_1',
    'demo_intercity_2',
    'demo_intercity_3',
    'demo_intercity_4',
    'demo_intercity_5',
    'demo_intercity_6',
    'demo_intercity_7',
    'demo_intercity_8',
    'demo_intercity_9',
    'demo_intercity_10',
  ];

  /// «Танишув» — аёл номлари (эркак кўрувчига).
  static const List<String> profileFemaleKeys = [
    'demo_profile_f_1',
    'demo_profile_f_2',
    'demo_profile_f_3',
    'demo_profile_f_4',
    'demo_profile_f_5',
    'demo_profile_f_6',
    'demo_profile_f_7',
    'demo_profile_f_8',
    'demo_profile_f_9',
    'demo_profile_f_10',
  ];

  /// «Танишув» — эркак номлари (аёл кўрувчига).
  static const List<String> profileMaleKeys = [
    'demo_profile_m_1',
    'demo_profile_m_2',
    'demo_profile_m_3',
    'demo_profile_m_4',
    'demo_profile_m_5',
    'demo_profile_m_6',
    'demo_profile_m_7',
    'demo_profile_m_8',
    'demo_profile_m_9',
    'demo_profile_m_10',
  ];

  /// Кўрувчига қарама-қарши жинс номлари — бўлимнинг ўз қоидасига мос.
  /// Жинс номаълум бўлса иккаласи аралаш.
  static List<String> profileKeysFor(String viewerGender) {
    final g = viewerGender.trim().toLowerCase();
    if (g == 'male') return profileFemaleKeys;
    if (g == 'female') return profileMaleKeys;
    return [...profileFemaleKeys, ...profileMaleKeys];
  }

  /// Реал эълонлардан кейин қолган жойни тўлдирувчи қаторлар.
  ///
  /// [random] — сеанс тасодифчиси: ҳар очилишда тартиб бошқача.
  static List<String> fill(
    BuildContext context, {
    required List<String> keys,
    required int realCount,
    required Random random,
  }) {
    final free = capacity - realCount;
    if (free <= 0) return const [];
    final pool = keys.map(context.tr).toList()..shuffle(random);
    return pool.take(free).toList(growable: false);
  }
}
