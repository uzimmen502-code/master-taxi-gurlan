// ТАКЛИФЧИ ТОМОНИ — сўров тафсилоти (13.4.8, 13.4.10).
//
// МАНБА: ФАҚАТ `demand_matches` проекцияси. Бу экран `demands`
// ҳужжатига УМУМАН мурожаат қилмайди — Firestore қоидаси рад этади ва
// шунинг учун бунга уриниш ҳам йўқ.
//
// Push тап қилинганда ҳам шу экран очилади (`PushNavigation`).
//
// КОНТАКТ БОСҚИЧМА-БОСҚИЧ (Т-9):
//   қабул қилингунча     — ҳеч қандай контакт
//   `accepted` (1-поғона) — юборувчи телефони + олиш манзили
//   `in_progress` (2-п.)  — қабул қилувчи телефони + етказиш манзили

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/ava_tokens.dart';
import '../../data/match_repository.dart';
import '../../domain/demand_enums.dart';
import '../../domain/demand_match.dart';
import '../../ui_adapters/demand_ui_adapter.dart';
import '../capabilities/provider_capabilities_screen.dart';
import '../offer_create/offer_create_sheet.dart';

class DemandMatchDetailScreen extends StatelessWidget {
  const DemandMatchDetailScreen({
    super.key,
    required this.demandId,
    required this.providerId,
    required this.repository,
    required this.adapters,
    this.categories = const {},
  });

  final String demandId;
  final String providerId;
  final MatchRepository repository;
  final Map<DemandModule, DemandUiAdapter> adapters;

  /// Розилик экрани учун категория номлари.
  final Map<String, String> categories;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;

    return StreamBuilder<DemandMatch?>(
      stream: repository.watchMatch(demandId, providerId),
      builder: (context, snap) {
        final match = snap.data;

        return Scaffold(
          backgroundColor: c.bg,
          appBar: AppBar(
            backgroundColor: c.surface,
            surfaceTintColor: c.surface,
            elevation: 0,
            title: Text(
              match?.projection.title.isNotEmpty == true
                  ? match!.projection.title
                  : context.tr('activity_incoming'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          body: snap.connectionState == ConnectionState.waiting
              ? const Center(child: CircularProgressIndicator())
              : match == null
                  // Match йўқ — талаб ёпилган ёки мослик бекор қилинган.
                  // Хато кўрсатмаймиз: бу нормал ҳолат.
                  ? _closed(context)
                  : _body(context, match),
        );
      },
    );
  }

  Widget _closed(BuildContext context) {
    final c = context.ava;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox_outlined, size: 40, color: c.ink3),
            const SizedBox(height: 10),
            Text(
              context.tr('demand_error_taken'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.ink2),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context, DemandMatch match) {
    final c = context.ava;
    final adapter = adapters[match.module];

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // Карточка — adapter чизади (проекциядан).
        if (adapter != null) adapter.buildMatchCard(context, match),
        const SizedBox(height: 12),

        // РОЗИЛИК ТАКЛИФИ (cold start).
        //
        // Бу одам `ads` эълонидан номзод бўлиб тушган ва push ОЛМАГАН.
        // Концепция: «Сиз телефон сотгансиз. Шу йўналишда талаблар
        // олишни хоҳлайсизми?»
        if (match.needsConsentPrompt) ...[
          _consentCard(context, match),
          const SizedBox(height: 12),
        ],

        // КОНТАКТ — фақат қабул қилингандан кейин (Т-9).
        if (match.contact != null) ...[
          _contactCard(context, match.contact!),
          const SizedBox(height: 12),
        ],

        // Амаллар.
        if (match.status.canOffer)
          FilledButton(
            onPressed: () => _makeOffer(context, match),
            style: FilledButton.styleFrom(
              backgroundColor: c.brand,
              foregroundColor: c.brandInk,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(
              context.tr(
                match.status == MatchStatus.offered
                    ? 'match_revise'
                    : 'match_make_offer',
              ),
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

        if (match.status == MatchStatus.offered) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _withdraw(context, match),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.danger,
              side: BorderSide(color: c.line),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(context.tr('match_withdraw')),
          ),
        ],

        if (match.status == MatchStatus.accepted) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => _cancelAssignment(context, match),
            style: OutlinedButton.styleFrom(
              foregroundColor: c.danger,
              side: BorderSide(color: c.line),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(context.tr('assignment_cancel')),
          ),
        ],

        if (match.status.isClosed) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: c.chip,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              context.tr('match_taken'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: c.ink2),
            ),
          ),
        ],

        if (match.status == MatchStatus.offered) ...[
          const SizedBox(height: 10),
          Text(
            context.tr('match_offer_sent'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: c.ok),
          ),
        ],
      ],
    );
  }

  Widget _consentCard(BuildContext context, DemandMatch match) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.brandSoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.brand.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('consent_title'),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.brand,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            context.tr('consent_body'),
            style: TextStyle(fontSize: 12, color: c.ink2),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => _openConsent(context, match),
                  style: FilledButton.styleFrom(
                    backgroundColor: c.brand,
                    foregroundColor: c.brandInk,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(
                    context.tr('consent_yes'),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Т-9 — босқичма-босқич очилган контакт.
  Widget _contactCard(BuildContext context, MatchContact contact) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: c.okSoft,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (contact.pickupAddress.isNotEmpty) ...[
            Row(
              children: [
                Icon(Icons.location_on, size: 14, color: c.ok),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    contact.pickupAddress,
                    style: TextStyle(fontSize: 13, color: c.ink),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (contact.ownerPhone != null)
            _phoneRow(context, contact.ownerPhone!),
          // 2-поғона — фақат иш бошлангандан кейин.
          if (contact.hasRecipient) ...[
            const SizedBox(height: 6),
            _phoneRow(context, contact.recipientPhone!),
          ],
        ],
      ),
    );
  }

  Widget _phoneRow(BuildContext context, String phone) {
    final c = context.ava;
    return InkWell(
      onTap: () => launchUrl(Uri.parse('tel:+$phone')),
      child: Row(
        children: [
          Icon(Icons.phone, size: 14, color: c.ok),
          const SizedBox(width: 6),
          Text(
            '+$phone',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: c.ok,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openConsent(BuildContext context, DemandMatch match) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProviderCapabilitiesScreen(
          userId: providerId,
          module: match.module,
          categories: categories.isNotEmpty
              ? categories
              : {
                  if (match.projection.categoryId != null)
                    match.projection.categoryId!: match.projection.categoryId!,
                },
          initialCategoryIds: [
            if (match.projection.categoryId != null)
              match.projection.categoryId!,
          ],
          initialRegionIds: [
            if (match.projection.regionId != null) match.projection.regionId!,
          ],
          consentPrompt: true,
        ),
      ),
    );
  }

  Future<void> _makeOffer(BuildContext context, DemandMatch match) async {
    final sent = await showOfferCreateSheet(
      context,
      match: match,
      repository: repository,
    );
    if (sent == true && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('match_offer_sent'))),
      );
    }
  }

  Future<void> _withdraw(BuildContext context, DemandMatch match) async {
    try {
      await repository.withdrawOffer(match.demandId);
    } catch (_) {
      // Қайтариб олиш муваффақиятсиз бўлса — stream ҳолатни барибир
      // кўрсатади, қўшимча хабар керак эмас.
    }
  }

  Future<void> _cancelAssignment(
    BuildContext context,
    DemandMatch match,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('assignment_cancel')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('consent_no')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('confirm_ok')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repository.cancelAssignment(match.demandId);
    } catch (_) {
      // Юқоридаги каби — stream ҳолатни кўрсатади.
    }
  }
}
