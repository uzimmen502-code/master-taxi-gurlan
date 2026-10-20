import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../data/china_inquiry_repository.dart';

/// «Менинг сўровларим» (Хитой бозори). Таклифлар сўров ичида; таъминотчи номи/ички изоҳ
/// мижозга умуман келмайди (сервер `offers` нусхаси таъминотчисиз).
class ChinaInquiriesScreen extends StatelessWidget {
  const ChinaInquiriesScreen({super.key, required this.phone, ChinaInquiryRepository? repository})
      : _repo = repository;

  final String phone;
  final ChinaInquiryRepository? _repo;

  @override
  Widget build(BuildContext context) {
    final repo = _repo ?? ChinaInquiryRepository();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('china_inq_my'))),
      body: StreamBuilder<List<ChinaInquiry>>(
        stream: repo.watchMine(phone),
        builder: (context, snap) {
          if (snap.hasError) {
            debugPrint('[ChinaInquiries] ${snap.error}');
            return Center(child: Text(context.tr('china_inq_load_failed')));
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) return Center(child: Text(context.tr('china_inq_empty')));
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final q = items[i];
              return Card(
                child: ListTile(
                  title: Text('${q.refNo} · ${q.text}', maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    context.tr('china_inq_status_${q.status}'),
                    style: TextStyle(color: _statusColor(q.status)),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ChinaInquiryDetailScreen(inquiry: q, repository: repo),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

Color _statusColor(String s) {
  switch (s) {
    case 'quoted':
      return Colors.green.shade700;
    case 'new':
    case 'sent':
      return Colors.orange.shade800;
    default:
      return Colors.grey.shade600;
  }
}

class ChinaInquiryDetailScreen extends StatefulWidget {
  const ChinaInquiryDetailScreen({super.key, required this.inquiry, required this.repository});

  final ChinaInquiry inquiry;
  final ChinaInquiryRepository repository;

  @override
  State<ChinaInquiryDetailScreen> createState() => _ChinaInquiryDetailScreenState();
}

class _ChinaInquiryDetailScreenState extends State<ChinaInquiryDetailScreen> {
  bool _busy = false;

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('china_inq_cancel_confirm')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('china_inq_no'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: Text(context.tr('china_inq_yes'))),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await widget.repository.cancel(widget.inquiry.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      debugPrint('[ChinaInquiryDetail] cancel $e');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text(context.tr('china_inq_cancel_failed'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = widget.inquiry;
    return Scaffold(
      appBar: AppBar(title: Text(q.refNo)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(context.tr('china_inq_status_${q.status}'),
              style: TextStyle(fontWeight: FontWeight.w600, color: _statusColor(q.status))),
          const SizedBox(height: 8),
          Text(q.text),
          if (q.quantity.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(q.quantity, style: const TextStyle(color: Colors.black54)),
          ],
          const Divider(height: 32),
          Text(context.tr('china_inq_offers'), style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          StreamBuilder<List<ChinaOffer>>(
            stream: widget.repository.watchOffers(q.id),
            builder: (context, snap) {
              if (snap.hasError) {
                debugPrint('[ChinaInquiryDetail] offers ${snap.error}');
                return Text(context.tr('china_inq_load_failed'));
              }
              final offers = snap.data ?? const <ChinaOffer>[];
              if (offers.isEmpty) return Text(context.tr('china_inq_offers_none'));
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final o in offers) _OfferCard(offer: o),
                  const SizedBox(height: 4),
                  Text(context.tr('china_inq_offers_note'),
                      style: const TextStyle(color: Colors.black54, fontSize: 12)),
                ],
              );
            },
          ),
          if (q.isOpen) ...[
            const SizedBox(height: 24),
            OutlinedButton(
              onPressed: _busy ? null : _cancel,
              child: Text(context.tr('china_inq_cancel')),
            ),
          ],
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  const _OfferCard({required this.offer});

  final ChinaOffer offer;

  @override
  Widget build(BuildContext context) {
    final muted = offer.withdrawn;
    final style = muted
        ? const TextStyle(decoration: TextDecoration.lineThrough, color: Colors.black45)
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context
                  .tr('china_inq_offer_price')
                  .replaceAll('{price}', offer.priceText)
                  .replaceAll('{cur}', offer.currency),
              style: (style ?? const TextStyle()).copyWith(fontWeight: FontWeight.w600),
            ),
            if (offer.minOrderQty != null)
              Text(
                context.tr('china_inq_offer_moq').replaceAll('{n}', '${offer.minOrderQty}'),
                style: style,
              ),
            if (offer.leadTimeDays != null)
              Text(
                context.tr('china_inq_offer_lead').replaceAll('{n}', '${offer.leadTimeDays}'),
                style: style,
              ),
            if (offer.customerNote.isNotEmpty) Text(offer.customerNote, style: style),
            if (muted)
              Text(context.tr('china_inq_offer_withdrawn'),
                  style: const TextStyle(color: Colors.black54)),
          ],
        ),
      ),
    );
  }
}
