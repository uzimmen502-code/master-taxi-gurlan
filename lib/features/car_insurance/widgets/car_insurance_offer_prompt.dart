import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../car_insurance_service.dart';
import 'car_insurance_home_section.dart' show carInsuranceStateCached;

/// Машина рағбати таклифи кўрсатиладими (соф): кампания бор, машина тўлиқ, ҳали танланмаган.
bool carInsuranceOfferDue(InsuranceState s) =>
    s.available && s.carComplete && s.enrollment == null && s.campaign != null &&
    (s.campaign!.bonusEnabled || s.campaign!.oilEnabled);

/// Машина сақлангандан кейин (эга 2026-11-28): «100 000 AVA бонус» ёки «мой алмаштириш дастури» танлови.
/// Танлов — сервер `insuranceChooseCarOffer` (бир номер + бир шахс, кампания йили). Кампания йўқ — ҳеч нарса.
Future<void> maybeOfferCarInsuranceIncentive(
  BuildContext context,
  String phone, {
  CarInsuranceService? service,
  Future<InsuranceState> Function()? loader,
}) async {
  final svc = service ?? CarInsuranceService();
  final s = await carInsuranceStateCached(phone, service: svc, loader: loader, refresh: true);
  if (!context.mounted || !carInsuranceOfferDue(s)) return;
  final c = s.campaign!;
  final oilText = [
    for (final st in c.oilSteps)
      context.tr('ins_offer_oil_step').replaceAll('{n}', '${st.count}').replaceAll('{pct}', '${st.pct}'),
  ].join(' · ');
  final option = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(ctx.tr('ins_offer_title'), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(height: 4),
            Text(ctx.tr('ins_offer_sub')),
            if (c.bonusEnabled) ...[
              const SizedBox(height: 12),
              FilledButton.icon(
                key: const ValueKey('ins_prompt_bonus'),
                onPressed: () => Navigator.pop(ctx, 'bonus'),
                icon: const Icon(Icons.card_giftcard),
                label: Text(ctx.tr('ins_offer_bonus').replaceAll('{amount}', formatMoney(c.bonusAmount))),
              ),
            ],
            if (c.oilEnabled) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const ValueKey('ins_prompt_oil'),
                onPressed: () => Navigator.pop(ctx, 'oil'),
                icon: const Icon(Icons.oil_barrel),
                label: Text('${ctx.tr('ins_offer_oil')}: $oilText'),
              ),
            ],
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('ins_later'))),
          ],
        ),
      ),
    ),
  );
  if (option == null || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  final lang = context.contentLang;
  final ok = context.tr(option == 'bonus' ? 'ins_offer_bonus_done' : 'ins_offer_oil_done');
  final generic = context.tr('ins_err_generic');
  try {
    await svc.chooseCarOffer(option);
    messenger.showSnackBar(SnackBar(content: Text(ok)));
  } catch (e) {
    final x = insuranceErrorOf(e, lang);
    debugPrint('[CarInsurance] ${x.code}');
    messenger.showSnackBar(SnackBar(content: Text(x.message ?? generic)));
  }
  await carInsuranceStateCached(phone, service: svc, loader: loader, refresh: true);
}
