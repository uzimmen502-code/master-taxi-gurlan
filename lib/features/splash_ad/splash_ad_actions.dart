import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/utils/formatters.dart';
import '../chat/screens/chat_screen.dart';
import 'splash_ad.dart';

/// «Реклама бериш» қаерга олиб боради.
///
/// Мавжуд йўллар текширилди (2026-11-28): «＋ → Эълон бериш» (`JobsScreen`, AdKind.ad) — эълонлар доскаси;
/// «Видео жойлаштириш»/«Реклама ва Эълонлар» (`TvPublishScreen`) — AVAGram пуллик клипи (web'да ёпиқ).
/// Иккаласи ҳам splash ўрнини СОТМАЙДИ. Splash креативини админ жойлайди — шунинг учун мавжуд
/// «Админ билан чат» (`support_chats`, `ChatScreen`) тайёр матн билан очилади (юбориш — фойдаланувчининг ўзи).
enum SplashAdvertiseTarget { supportChat, needLogin }

SplashAdvertiseTarget splashAdvertiseTargetFor({required String phone, required bool signedIn}) =>
    signedIn && canonicalPhoneId(phone).length >= 9 ? SplashAdvertiseTarget.supportChat : SplashAdvertiseTarget.needLogin;

/// Splash ёпилгач чақирилади (`MyApp.navigatorKey`).
Future<void> openSplashAdvertise(
  NavigatorState nav, {
  required String lang,
  Future<String> Function()? readPhone,
  bool Function()? isSignedIn,
  Widget Function(String chatId, String draft)? chatBuilder,
}) async {
  final phone = readPhone != null
      ? await readPhone()
      : (await SharedPreferences.getInstance()).getString('user_phone') ?? '';
  final signedIn = isSignedIn != null
      ? isSignedIn()
      : (FirebaseAuth.instance.currentUser != null && !FirebaseAuth.instance.currentUser!.isAnonymous);
  if (!nav.mounted) return;
  switch (splashAdvertiseTargetFor(phone: phone, signedIn: signedIn)) {
    case SplashAdvertiseTarget.supportChat:
      final chatId = canonicalPhoneId(phone);
      final draft = SplashAdTexts.chatDraft(lang);
      await nav.push(MaterialPageRoute<void>(
        builder: (_) => chatBuilder != null ? chatBuilder(chatId, draft) : ChatScreen(targetPhone: chatId, initialDraft: draft),
      ));
    case SplashAdvertiseTarget.needLogin:
      ScaffoldMessenger.maybeOf(nav.context)?.showSnackBar(
        SnackBar(content: Text(SplashAdTexts.needLogin(lang)), duration: const Duration(seconds: 5)),
      );
  }
}

/// Креатив ҳаволаси (фақат `https://`; сервер ҳам шуни текширади).
Future<void> openSplashAdLink(SplashAd ad) async {
  final uri = Uri.tryParse(ad.linkUrl);
  if (uri == null || uri.scheme != 'https') return;
  try {
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (e) {
    debugPrint('openSplashAdLink: $e');
  }
}
