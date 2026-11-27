import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/geo/geo_context.dart';
import '../../core/utils/formatters.dart';
import '../chat/screens/chat_screen.dart';
import 'splash_ad.dart';
import 'splash_ad_purchase_screen.dart';

/// «Реклама бериш» қаерга олиб боради (эга 2026-11-28): кирган фойдаланувчи — пуллик харид оқими
/// ([SplashAdPurchaseScreen]; харид ёпиқ бўлса, ичида мавжуд «Админ билан чат» тугмаси);
/// кирмаган — рўйхатдан ўтиш хабари.
enum SplashAdvertiseTarget { purchase, needLogin }

SplashAdvertiseTarget splashAdvertiseTargetFor({required String phone, required bool signedIn}) =>
    signedIn && canonicalPhoneId(phone).length >= 9 ? SplashAdvertiseTarget.purchase : SplashAdvertiseTarget.needLogin;

/// Splash ёпилгач чақирилади (`MyApp.navigatorKey`).
Future<void> openSplashAdvertise(
  NavigatorState nav, {
  required String lang,
  Future<String> Function()? readPhone,
  bool Function()? isSignedIn,
  Widget Function(String chatId, String draft)? chatBuilder,
  Widget Function(String phone, VoidCallback onAdminChat)? purchaseBuilder,
}) async {
  final phone = readPhone != null
      ? await readPhone()
      : (await SharedPreferences.getInstance()).getString('user_phone') ?? '';
  final signedIn = isSignedIn != null
      ? isSignedIn()
      : (FirebaseAuth.instance.currentUser != null && !FirebaseAuth.instance.currentUser!.isAnonymous);
  if (!nav.mounted) return;
  switch (splashAdvertiseTargetFor(phone: phone, signedIn: signedIn)) {
    case SplashAdvertiseTarget.purchase:
      final id = canonicalPhoneId(phone);
      void openChat() {
        final draft = SplashAdTexts.chatDraft(lang);
        nav.push(MaterialPageRoute<void>(
          builder: (_) => chatBuilder != null ? chatBuilder(id, draft) : ChatScreen(targetPhone: id, initialDraft: draft),
        ));
      }

      await nav.push(MaterialPageRoute<void>(
        builder: (_) => purchaseBuilder != null
            ? purchaseBuilder(id, openChat)
            : SplashAdPurchaseScreen(
                ownerPhone: id,
                initialRegionId: GeoContext.active.regionId,
                initialDistrictId: GeoContext.active.districtId,
                onAdminChat: openChat,
              ),
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
