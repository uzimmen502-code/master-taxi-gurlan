import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// ChatGPT расмий сайти (фолбэк) — iOS'да Universal Links орқали иловани
/// очади. `settings/app.assistantUrl` (Firestore) орқали "AVA ёрдамчиси"
/// Custom GPT ссылкасига релизсиз алмаштирилиши мумкин — бўш/хато бўлса шу
/// фолбэкка қайтади ([SettingsRepository.getAssistantUrl]).
const kChatGptUrl = 'https://chatgpt.com/';

const _chatGptAndroidPackage = 'com.openai.chatgpt';

/// Илова ўрнатилмаган бўлса — юклаб олиш саҳифалари.
///
/// `market://` ишлатилмайди: Transsion (TECNO) қурилмаларида уни Google Play
/// эмас, Palm Store тутиб олади. https ҳаволаси эса Play иловасини очади,
/// у бўлмаса браузерда шу саҳифани кўрсатади.
const _chatGptPlayUrl =
    'https://play.google.com/store/apps/details?id=$_chatGptAndroidPackage';
const _chatGptAppStoreUrl = 'https://apps.apple.com/app/id6448311069';

const _externalAppChannel = MethodChannel('uz.ava.gurlan/external_app');

/// ChatGPT'ни (ёки созланган "AVA ёрдамчиси" Custom GPT'ни) очади: илова
/// ўрнатилган бўлса — илова, акс ҳолда — иловани юклаб олиш саҳифаси
/// (Play Store / App Store).
///
/// [assistantUrl] — `settings/app.assistantUrl` (бўш/`null` бўлса
/// [kChatGptUrl] фолбэк сифатида ишлатилади).
///
/// Android'да пакет бўйича очамиз: баъзи қурилмаларда (TECNO/Transsion)
/// `FLAG_ACTIVITY_REQUIRE_NON_BROWSER` эътиборсиз қолади ва `chatgpt.com`
/// App Links тасдиқланган бўлса ҳам браузерга кетади. **Эслатма:** шу сабабли
/// Android'да илова умумий ҳолда (охирги очилган экран) очилади — пакет
/// бўйича очишда аниқ GPT'га (`assistantUrl`) тўғридан-тўғри ўтиб
/// бўлмайди; фақат иловани ўрнатиш ҳолати (бор/йўқ) текширилади.
/// iOS'да Universal Links ишончли — `externalNonBrowserApplication`
/// [assistantUrl]'ни аниқ GPT'га очади.
Future<bool> openChatGpt({String? assistantUrl}) async {
  final targetUrl = (assistantUrl != null && assistantUrl.trim().isNotEmpty)
      ? assistantUrl.trim()
      : kChatGptUrl;

  if (defaultTargetPlatform == TargetPlatform.android) {
    try {
      final opened = await _externalAppChannel.invokeMethod<bool>(
        'openApp',
        <String, String>{'package': _chatGptAndroidPackage},
      );
      if (opened ?? false) return true;
    } catch (_) {
      // Илова йўқ — юклаб олиш саҳифасига ўтамиз.
    }
    return _launchExternal(_chatGptPlayUrl);
  }

  try {
    if (await launchUrl(
      Uri.parse(targetUrl),
      mode: LaunchMode.externalNonBrowserApplication,
    )) {
      return true;
    }
  } catch (_) {
    // Илова йўқ — App Store'га ўтамиз.
  }
  return _launchExternal(_chatGptAppStoreUrl);
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
