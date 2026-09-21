import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

const _externalAppChannel = MethodChannel('uz.ava.gurlan/external_app');

/// Click / Payme / Paynet каби маҳаллий тўлов иловалари — қурилмада мавжуд
/// бўлса очилади, акс ҳолда Play Store / App Store саҳифаси.
class PaymentProviderApp {
  const PaymentProviderApp({
    required this.id,
    required this.label,
    required this.androidPackage,
    required this.appStoreId,
    required this.universalWebUrl,
  });

  /// `kKnownModuleIds` даги модул ID (admin ёқиш/ўчириш учун).
  final String id;
  final String label;
  final String androidPackage;
  final String appStoreId;

  /// iOS'да Universal Links орқали иловани очиш учун расмий сайт.
  final String universalWebUrl;

  /// `market://` ишлатилмайди: Transsion (TECNO) қурилмаларида уни Google
  /// Play эмас, бошқа магазин тутиб олиши мумкин.
  String get playUrl =>
      'https://play.google.com/store/apps/details?id=$androidPackage';

  String get appStoreUrl => 'https://apps.apple.com/app/id$appStoreId';
}

const kClickApp = PaymentProviderApp(
  id: 'pay_click',
  label: 'Click',
  androidPackage: 'air.com.ssdsoftwaresolutions.clickuz',
  appStoreId: '768132591',
  universalWebUrl: 'https://click.uz/',
);

const kPaymeApp = PaymentProviderApp(
  id: 'pay_payme',
  label: 'Payme',
  androidPackage: 'uz.dida.payme',
  appStoreId: '1093525667',
  universalWebUrl: 'https://payme.uz/',
);

const kPaynetApp = PaymentProviderApp(
  id: 'pay_paynet',
  label: 'Paynet',
  androidPackage: 'uz.paynet.app',
  appStoreId: '1307888692',
  universalWebUrl: 'https://paynet.uz/',
);

/// Провайдер иловасини очади: ўрнатилган бўлса — илова,
/// акс ҳолда — Play Store / App Store саҳифаси.
///
/// Android'да пакет бўйича очамиз (native `openApp` — ChatGPT
/// launcher'дагидек). iOS'да Universal Links ишончли —
/// `externalNonBrowserApplication` етарли.
Future<bool> openPaymentProviderApp(PaymentProviderApp app) async {
  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      final opened = await _externalAppChannel.invokeMethod<bool>(
        'openApp',
        <String, String>{'package': app.androidPackage},
      );
      if (opened ?? false) return true;
    } catch (_) {
      // Илова йўқ ёки manifest queries'да кўрсатилмаган.
    }
    return _launchExternal(app.playUrl);
  }

  try {
    if (await launchUrl(
      Uri.parse(app.universalWebUrl),
      mode: LaunchMode.externalNonBrowserApplication,
    )) {
      return true;
    }
  } catch (_) {
    // Илова йўқ — App Store'га ўтамиз.
  }
  return _launchExternal(app.appStoreUrl);
}

Future<bool> _launchExternal(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
