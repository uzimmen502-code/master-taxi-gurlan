import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Расмий ChatGPT иловаси — фойдаланувчининг ЎЗ обунаси (Plus ва ҳ.к.)
/// бўлса, AVA пакети ўрнига шуни ишлатиши мумкин. Илова обуна даражасини
/// била олмайди — фақат илова ўрнатилган/ўрнатилмаганини текширади,
/// танловни фойдаланувчи қилади ([AssistantEntry]).
const _chatGptAndroidPackage = 'com.openai.chatgpt';
const _chatGptWebUrl = 'https://chatgpt.com/';
const _chatGptIosScheme = 'chatgpt://';

const _externalAppChannel = MethodChannel('uz.ava.gurlan/external_app');

/// ChatGPT иловаси қурилмада борми (Android — package, iOS — URL scheme).
/// Хато/номаълум бўлса `false` — таклиф кўрсатилмайди.
Future<bool> isChatGptAppInstalled() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final ok = await _externalAppChannel.invokeMethod<bool>(
        'isAppInstalled',
        <String, String>{'package': _chatGptAndroidPackage},
      );
      return ok ?? false;
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return await canLaunchUrl(Uri.parse(_chatGptIosScheme));
    }
  } catch (_) {}
  return false;
}

/// Расмий ChatGPT иловасини очади (ўрнатилган бўлса). Бўлмаса — веб сайт.
Future<bool> openChatGptApp() async {
  try {
    if (defaultTargetPlatform == TargetPlatform.android) {
      final opened = await _externalAppChannel.invokeMethod<bool>(
        'openApp',
        <String, String>{'package': _chatGptAndroidPackage},
      );
      if (opened ?? false) return true;
    } else {
      if (await launchUrl(
        Uri.parse(_chatGptWebUrl),
        mode: LaunchMode.externalNonBrowserApplication,
      )) {
        return true;
      }
    }
  } catch (_) {}
  try {
    return await launchUrl(
      Uri.parse(_chatGptWebUrl),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}
