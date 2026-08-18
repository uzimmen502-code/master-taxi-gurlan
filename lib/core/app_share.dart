import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'brand_labels.dart';
import 'l10n/l10n_extension.dart';

/// Иловани юклаш саҳифаси (QR + APK тугмаси). Play Store кейинроқ.
const kAvaAppDownloadPage = 'https://master-taxi-gurlan.web.app/downloads/';

/// Тўғридан APK файл.
const kAvaAppDownloadApk =
    'https://master-taxi-gurlan.web.app/downloads/master-taxi-gurlan.apk';

/// Телефоннинг улашиш ойнаси — downloads саҳифаси (ишончли йўл).
Future<bool> shareAvaApp(BuildContext context) async {
  final body = context
      .tr('app_share_body')
      .replaceAll('{brand}', BrandLabels.brand)
      .replaceAll('{url}', kAvaAppDownloadPage);
  try {
    await Share.share(body, subject: BrandLabels.brand);
    return true;
  } catch (e) {
    debugPrint('[shareAvaApp] $e');
    return false;
  }
}
