// ХАРИДОР ТОМОНИ — сўров тафсилоти ва таклифлар рўйхати (13.4.8).
//
// Концепция: «Таклифлар рўйхатида тартиблаш: нарх, рейтинг, масофа ва
// етказиб бериш бўйича.»
//
// МАХФИЙЛИК: бу экран ФАҚАТ талаб эгасига кўринади (Firestore қоидаси
// `isOwner(resource.data.ownerId)`). Таклифчилар бир-бирининг нархини
// кўрмайди — улар умуман бу экранни очолмайди.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/ava_tokens.dart';
import '../../../../core/utils/user_error.dart';
import '../../data/demand_repository.dart';
import '../../domain/demand.dart';
import '../../domain/demand_enums.dart';
import '../../domain/offer.dart';
import '../../ui_adapters/demand_ui_adapter.dart';

class DemandDetailScreen extends StatefulWidget {
  const DemandDetailScreen({
    super.key,
    required this.demandId,
    required this.repository,
    required this.adapters,
  });

  final String demandId;
  final DemandRepository repository;
  final Map<DemandModule, DemandUiAdapter> adapters;

  @override
  State<DemandDetailScreen> createState() => _DemandDetailScreenState();
}

class _DemandDetailScreenState extends State<DemandDetailScreen> {
  OfferSort _sort = OfferSort.priceAsc;
  bool _busy = false;

  Future<void> _accept(Demand demand, Offer offer) async {
    final c = context.ava;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        title: Text(ctx.tr('offer_choose')),
        content: Text(
          offer.price != null
              ? '${offer.price} ${ctx.tr('sum')}'
              : ctx.tr('offer_price_negotiable'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('confirm_edit')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('confirm_ok')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.repository.acceptOffer(
        demandId: demand.id,
        providerId: offer.providerId,
      );
    } on DemandException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'failed-precondition'
                ? context.tr('demand_error_taken')
                : _errorText(e),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel(Demand demand) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('request_cancel_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(ctx.tr('consent_no')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(ctx.tr('request_cancel')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      await widget.repository.cancelDemand(demand.id);
      if (mounted) Navigator.of(context).pop();
    } on DemandException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_errorText(e))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// `DemandException.message` — server/developer matni: foydalanuvchiga
  /// ko'rsatilmaydi, kod bo'yicha umumiy l10n matni tanlanadi (xom matn logga).
  String _errorText(DemandException e) => userErrorMessage(
        context,
        FirebaseFunctionsException(message: e.message, code: e.code),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.ava;

    return StreamBuilder<Demand?>(
      stream: widget.repository.watchDemand(widget.demandId),
      builder: (context, demandSnap) {
        final demand = demandSnap.data;

        return Scaffold(
          backgroundColor: c.bg,
          appBar: AppBar(
            backgroundColor: c.surface,
            surfaceTintColor: c.surface,
            elevation: 0,
            title: Text(
              demand?.title.isNotEmpty == true
                  ? demand!.title
                  : context.tr('activity_my_requests'),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: c.ink,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              if (demand != null && demand.status.isOpenForOffers)
                IconButton(
                  tooltip: context.tr('request_cancel'),
                  onPressed: _busy ? null : () => _cancel(demand),
                  icon: Icon(Icons.close, color: c.ink2),
                ),
            ],
          ),
          body: demand == null
              ? const Center(child: CircularProgressIndicator())
              : _body(context, demand),
        );
      },
    );
  }

  Widget _body(BuildContext context, Demand demand) {
    final c = context.ava;
    final adapter = widget.adapters[demand.module];

    return StreamBuilder<OfferList>(
      stream: widget.repository.watchOffers(demand.id),
      builder: (context, snap) {
        final list = snap.data ?? const OfferList([]);
        final offers = list.sorted(_sort);

        return ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Ҳолат — техник сўзсиз.
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: c.line),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: c.ink3),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      demand.matching.state.showsWaitingMessage
                          ? context.tr('request_no_providers')
                          : '${demand.matching.matchedBucket} '
                              '${context.tr('request_sent_to')}',
                      style: TextStyle(fontSize: 12, color: c.ink2),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Таклифлар сарлавҳаси + тартиблаш.
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${list.activeCount} ${context.tr('offers_count')}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: c.ink,
                    ),
                  ),
                ),
                if (list.activeCount > 1)
                  PopupMenuButton<OfferSort>(
                    initialValue: _sort,
                    onSelected: (v) => setState(() => _sort = v),
                    itemBuilder: (ctx) => [
                      for (final s in OfferSort.values)
                        PopupMenuItem(
                          value: s,
                          child: Text(ctx.tr(s.l10nKey)),
                        ),
                    ],
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            context.tr(_sort.l10nKey),
                            style: TextStyle(fontSize: 12, color: c.brand),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Icon(Icons.expand_more, size: 16, color: c.brand),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            if (offers.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    context.tr('offers_empty'),
                    style: TextStyle(fontSize: 13, color: c.ink2),
                  ),
                ),
              )
            else
              for (final o in offers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: adapter != null
                      ? adapter.buildOfferCard(
                          context,
                          o,
                          // Таклиф танлаш ФАҚАТ талаб ҳали очиқ бўлса.
                          demand.status.isOpenForOffers && !_busy
                              ? () => _accept(demand, o)
                              : null,
                        )
                      : const SizedBox.shrink(),
                ),
          ],
        );
      },
    );
  }
}
