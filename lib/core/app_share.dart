import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'brand_labels.dart';
import 'l10n/l10n_extension.dart';

/// Android пакет номи — Play ҳаволаси ва App Links учун ягона манба.
const kAvaAndroidPackage = 'uz.ava.gurlan';

/// Google Play саҳифаси («AVA Zona», dasturchi: mastertaxi).
///
/// Иловани тарқатишда асосий йўл шу: Play автоматик янгилайди ва
/// «номаълум манбадан ўрнатиш» огоҳлантириши чиқмайди. `market://`
/// атайин ишлатилмайди — Transsion (TECNO) қурилмаларида уни Google Play
/// ушламайди (қаранг: `payment_provider_launcher.dart`).
const kAvaPlayStoreUrl =
    'https://play.google.com/store/apps/details?id=$kAvaAndroidPackage';

/// Иловани юклаш саҳифаси (QR + APK тугмаси) — Play'га кира олмайдиган
/// қурилмалар учун заҳира йўл.
const kAvaAppDownloadPage = 'https://master-taxi-gurlan.web.app/downloads/';

/// Тўғридан APK файл.
const kAvaAppDownloadApk =
    'https://master-taxi-gurlan.web.app/downloads/master-taxi-gurlan.apk';

/// Айнан битта AVAGram клипига очиладиган ҳавола.
///
/// Бу манзилни Firebase Hosting `clipPage` функциясига узатади
/// (қаранг: `firebase.json` → rewrites `/clip/**`). Саҳифа серверда
/// тайёр HTML қайтаради — шунинг учун Telegram/Facebook/Instagram
/// ҳаволани превью карточкаси (расм + сарлавҳа) билан кўрсатади.
String avaClipShareUrl(String clipId) =>
    'https://master-taxi-gurlan.web.app/clip/$clipId';

/// Телефоннинг улашиш ойнаси — Google Play саҳифаси.
Future<bool> shareAvaApp(BuildContext context) async {
  final body = context
      .tr('app_share_body')
      .replaceAll('{brand}', BrandLabels.brand)
      .replaceAll('{url}', kAvaPlayStoreUrl);
  try {
    await Share.share(body, subject: BrandLabels.brand);
    return true;
  } catch (e) {
    debugPrint('[shareAvaApp] $e');
    return false;
  }
}
