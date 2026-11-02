import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/utils/formatters.dart';
import '../../shared/car/car_edit_dialog.dart';
import '../../shared/widgets/celebration_dialog.dart';
import 'incentive_service.dart';

/// Рўйхатдан ўтгандан кейинги рағбат оқими (эга қарори 2026-11-02):
///  • аёл — салют ва «Ҳамёнингизга 100 000 сўм қўшилди», кейин «машинангиз бўлса — яна 200 000» таклифи;
///  • эркак — «Номингизда машина бўлса … 200 000» → «Олиш» → машина маълумоти → 200 000 + салют.
/// Ҳақиқий шартлар (жинс, ёш, фақат янги фойдаланувчи, бюджет, босқич) — СЕРВЕРДА; бу ерда фақат кўриниш.
class IncentiveOffersFlow {
  IncentiveOffersFlow._();

  static bool _ranThisSession = false;
  static const _kEmptyCheckedAt = 'incentive_offers_empty_at_v1';
  static const _kCarSnoozeUntil = 'incentive_car_snooze_until_v1';

  /// Бўш жавобдан кейин қайта сўраш оралиғи (ортиқча чақирув йўқ — 37-банд).
  static const emptyRecheck = Duration(hours: 12);
  static const carSnooze = Duration(days: 3);

  @visibleForTesting
  static void resetForTest() => _ranThisSession = false;

  /// Бош саҳифада телефон тайёр бўлганда бир марта (сессияда).
  static Future<void> run(BuildContext context, String uid, {IncentiveService? service, DateTime? accountCreatedAt}) async {
    if (_ranThisSession || canonicalPhoneId(uid).length < 9) return;
    _ranThisSession = true;
    final svc = service ?? IncentiveService();
    final prefs = await SharedPreferences.getInstance();
    // Янги аккаунт (2 кун) — ҳар сессияда сўралади: профиль рўйхатдан кейин тўлиши мумкин.
    final created = accountCreatedAt ?? FirebaseAuth.instance.currentUser?.metadata.creationTime;
    final isNewAccount = created != null && DateTime.now().difference(created) < const Duration(days: 2);
    final emptyAt = prefs.getInt(_kEmptyCheckedAt) ?? 0;
    if (!isNewAccount && DateTime.now().millisecondsSinceEpoch - emptyAt < emptyRecheck.inMilliseconds) return;
    List<IncentiveOffer> offers;
    try {
      offers = await svc.myOffers();
    } catch (e) {
      debugPrint('[Incentive] offers: $e');
      return;
    }
    final steps = planIncentiveSteps(offers);
    if (steps.autoClaim.isEmpty && steps.carOffers.isEmpty) {
      await prefs.setInt(_kEmptyCheckedAt, DateTime.now().millisecondsSinceEpoch);
      return;
    }
    for (final o in steps.autoClaim) {
      if (!context.mounted) return;
      await _claimAndCelebrate(context, svc, uid, o, subtitleKey: 'incentive_granted_sub');
    }
    final snoozeUntil = prefs.getInt(_kCarSnoozeUntil) ?? 0;
    if (DateTime.now().millisecondsSinceEpoch < snoozeUntil) return;
    for (final o in steps.carOffers) {
      if (!context.mounted) return;
      final took = await offerCar(context, uid, o, service: svc);
      if (!took) {
        await prefs.setInt(_kCarSnoozeUntil, DateTime.now().add(carSnooze).millisecondsSinceEpoch);
        return;
      }
    }
  }

  /// Машина таклифи ойнаси. «Олиш» → (керак бўлса машина маълумоти) → олиш + салют. → олдими.
  static Future<bool> offerCar(BuildContext context, String uid, IncentiveOffer offer, {IncentiveService? service}) async {
    final svc = service ?? IncentiveService();
    final amount = formatPrice(offer.amount);
    final take = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const ValueKey('incentive_car_offer'),
        icon: const Icon(Icons.directions_car_filled, size: 36),
        title: Text(ctx.tr('incentive_car_offer_title')),
        content: Text(ctx.tr('incentive_car_offer_body').replaceAll('{amount}', amount), textAlign: TextAlign.center),
        actions: [
          TextButton(
            key: const ValueKey('incentive_car_later'),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('incentive_later')),
          ),
          FilledButton(
            key: const ValueKey('incentive_car_take'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('incentive_car_take')),
          ),
        ],
      ),
    );
    if (take != true || !context.mounted) return false;
    if (offer.needsCar && !offer.eligible) {
      final saved = await showCarEditDialog(context, uid: canonicalPhoneId(uid));
      if (saved != true || !context.mounted) return false;
    }
    return _claimAndCelebrate(context, svc, uid, offer, subtitleKey: 'incentive_car_granted_sub');
  }

  static Future<bool> _claimAndCelebrate(
    BuildContext context,
    IncentiveService svc,
    String uid,
    IncentiveOffer o, {
    required String subtitleKey,
  }) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    int amount;
    try {
      amount = await svc.claim(o.programId);
    } on FirebaseFunctionsException catch (e) {
      final code = (e.details is Map ? (e.details as Map)['code'] : null)?.toString() ?? e.message ?? '';
      if (context.mounted) {
        messenger?.showSnackBar(SnackBar(
          content: Text(context.tr(code == 'CAR_PROFILE_REQUIRED' ? 'incentive_car_need_profile' : 'incentive_claim_failed')),
        ));
      }
      return false;
    } catch (e) {
      debugPrint('[Incentive] claim: $e');
      if (context.mounted) messenger?.showSnackBar(SnackBar(content: Text(context.tr('incentive_claim_failed'))));
      return false;
    }
    if (amount <= 0 || !context.mounted) return amount > 0;
    // Бир қурилмада бир дастур учун бир марта (такрор олиш сервердан duplicate келади).
    if (await CelebrationOnce.claim('incentive_${o.programId}_${canonicalPhoneId(uid)}') && context.mounted) {
      await showCelebration(
        context,
        icon: Icons.card_giftcard,
        title: context.tr('incentive_congrats_title'),
        subtitle: context.tr(subtitleKey).replaceAll('{amount}', formatPrice(amount)),
        buttonLabel: context.tr('celebration_continue'),
      );
    }
    return true;
  }
}
