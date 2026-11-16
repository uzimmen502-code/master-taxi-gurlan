import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/relative_location.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../services/location_service.dart';
import '../../deal_chat/open_deal_chat.dart';
import '../../tv_market/domain/price_unit.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/screens/tv_shop_item_detail_screen.dart';
import '../../wholesale/models/wholesale_product.dart';
import '../../wholesale/screens/wholesale_product_detail_screen.dart';
import '../models/price_offer.dart';
import '../services/assistant_service.dart';

/// Сервердан келган хато коди → фойдаланувчи матни калити (ички кодлар кўрсатилмайди, 25-қоида).
String priceSearchErrorKey(String code) => switch (code) {
      'price_search_limit' => 'ps_err_limit',
      'location_required' => 'ps_err_location',
      'query_too_short' => 'ps_err_query',
      'price_search_off' => 'ps_err_off',
      _ => 'ps_err_generic',
    };

/// «Нарх қидириш» (AVA AI Plus, эга 2026-11-17). Матн → AVA бозорларидаги таклифлар (чакана + улгуржи),
/// жами (маҳсулот + етказиш) бўйича тартибланган — ҳисоб ФАҚАТ серверда. Ички тушунчалар (зона, LEG)
/// кўрсатилмайди (45-қоида). Буюртма — таклиф тафсилотидаги мавжуд оқим орқали.
class PriceSearchScreen extends StatefulWidget {
  const PriceSearchScreen({
    super.key,
    required this.phone,
    this.service,
    this.onPlusRequired,
    this.coords,
    this.area,
    this.initialQuery,
  });

  final String phone;
  final AssistantService? service;

  /// Сервер `plus_required` — Plus варақасини очиш (чат экрани беради).
  final Future<void> Function()? onPlusRequired;

  /// Тест учун: координата манбаи (бўлмаса — рухсат бўлса GPS, диалогсиз).
  final Future<({double lat, double lng})?> Function()? coords;

  /// Тест учун: харидор ҳудуди (бўлмаса [GeoContext.active]).
  final ({String districtId, String regionId}) Function()? area;
  final String? initialQuery;

  @override
  State<PriceSearchScreen> createState() => _PriceSearchScreenState();
}

class _PriceSearchScreenState extends State<PriceSearchScreen> {
  late final AssistantService _service = widget.service ?? AssistantService();
  late final TextEditingController _ctrl = TextEditingController(text: widget.initialQuery ?? '');
  bool _busy = false;
  String? _errorKey;
  PriceSearchResult? _result;

  ({String districtId, String regionId}) get _area {
    if (widget.area != null) return widget.area!();
    final a = GeoContext.active;
    return (districtId: a.districtId, regionId: a.regionId);
  }

  Future<({double lat, double lng})?> _coords() async {
    if (widget.coords != null) return widget.coords!();
    final c = await const LocationService().getCoordsIfAllowed();
    return c == null ? null : (lat: c.lat, lng: c.lng);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final q = _ctrl.text.trim();
    if (_busy) return;
    if (q.length < 2) return setState(() => _errorKey = 'ps_err_query');
    final area = _area;
    if (area.districtId.trim().isEmpty) return setState(() => _errorKey = 'ps_err_location');
    FocusScope.of(context).unfocus();
    setState(() {
      _busy = true;
      _errorKey = null;
    });
    try {
      final c = await _coords();
      final r = await _service.priceSearch(query: q, districtId: area.districtId, lat: c?.lat, lng: c?.lng);
      if (!mounted) return;
      setState(() => _result = r);
    } on AssistantException catch (e) {
      if (!mounted) return;
      if (e.isPlusRequired) {
        setState(() => _busy = false);
        await widget.onPlusRequired?.call();
        return;
      }
      setState(() => _errorKey = priceSearchErrorKey(e.code));
    } catch (_) {
      if (mounted) setState(() => _errorKey = 'ps_err_generic');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(PriceOffer o) async {
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final gone = context.tr('ps_err_gone');
    try {
      final snap = await FirebaseFirestore.instance.collection(o.source).doc(o.id).get();
      final d = snap.data();
      if (d == null) {
        messenger.showSnackBar(SnackBar(content: Text(gone)));
        return;
      }
      final Widget page = o.wholesale
          ? WholesaleProductDetailScreen(product: WholesaleProduct.fromMap(o.id, d))
          : TvShopItemDetailScreen(item: TvShopItem.fromMap(o.id, d), showShopButton: true, source: 'price_search');
      await nav.push(MaterialPageRoute<void>(builder: (_) => page));
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(gone)));
    }
  }

  Future<void> _write(PriceOffer o) => openDealChatFlow(
        context,
        productId: o.id,
        myUid: canonicalPhoneId(widget.phone),
        source: o.wholesale ? DealChatSource.wholesale : DealChatSource.shopItem,
      );

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final me = canonicalPhoneId(widget.phone);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('ps_title'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const ValueKey('ps_query'),
                    controller: _ctrl,
                    enabled: !_busy,
                    maxLength: 100,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: InputDecoration(
                      hintText: context.tr('ps_hint'),
                      counterText: '',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  key: const ValueKey('ps_go'),
                  onPressed: _busy ? null : _search,
                  child: _busy
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(context.tr('ps_search')),
                ),
              ],
            ),
          ),
          if (_errorKey != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Text(context.tr(_errorKey!), key: const ValueKey('ps_error'), style: TextStyle(color: Colors.red.shade700)),
            ),
          Expanded(
            child: r == null
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: Text(context.tr('ps_intro'), textAlign: TextAlign.center, style: TextStyle(color: context.ava.ink2)),
                  )
                : r.offers.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(context.tr('ps_empty'), key: const ValueKey('ps_empty'), textAlign: TextAlign.center),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                        itemCount: r.offers.length + (r.partial ? 1 : 0),
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (_, i) {
                          if (r.partial && i == 0) {
                            return Text(context.tr('ps_partial'), key: const ValueKey('ps_partial'), style: TextStyle(color: context.ava.ink2, fontSize: 12.5));
                          }
                          final o = r.offers[i - (r.partial ? 1 : 0)];
                          return PriceOfferTile(
                            offer: o,
                            area: _area,
                            showWrite: dealChatShowWrite(myUid: me, ownerPhone: o.ownerPhone),
                            onOpen: () => _open(o),
                            onWrite: () => _write(o),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

/// Етказиш устуни матни (соф — тестланади).
String priceOfferDeliveryText(String Function(String) tr, String Function(String, Map<String, String>) trMsg, PriceOffer o) {
  final fee = o.delivery.fee;
  if (fee == null) return tr('ps_delivery_none');
  if (o.delivery.fromPrice) return trMsg('ps_amount_from', {'amount': formatPrice(fee)});
  return formatMoney(fee);
}

class PriceOfferTile extends StatelessWidget {
  const PriceOfferTile({
    super.key,
    required this.offer,
    required this.area,
    required this.showWrite,
    required this.onOpen,
    required this.onWrite,
  });

  final PriceOffer offer;
  final ({String districtId, String regionId}) area;
  final bool showWrite;
  final VoidCallback onOpen;
  final VoidCallback onWrite;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final o = offer;
    String trMsg(String k, Map<String, String> p) => context.trMsg(k, params: p);
    final place = relativeLocationLabel(
      itemDistrictId: o.sellerDistrictId,
      itemRegionId: o.sellerRegionId,
      userDistrictId: area.districtId,
      userRegionId: area.regionId,
      lang: context.contentLang,
    );
    final unitText = o.wholesale
        ? (o.unit.isEmpty ? '' : ' / ${o.unit}')
        : (PriceUnit.fromWire(o.priceUnit) == PriceUnit.fixed ? '' : ' / ${context.tr(PriceUnit.fromWire(o.priceUnit).labelKey)}');
    final rows = <Widget>[
      _row(context, context.tr('ps_price'),
          '${o.priceFrom ? trMsg('ps_amount_from', {'amount': formatPrice(o.price)}) : formatMoney(o.price)}$unitText'),
      if (o.wholesale && (o.moq ?? 1) > 1)
        _row(context, context.tr('ps_goods_for_moq'), '${formatMoney(o.goodsTotal)} · ${trMsg('ps_moq', {'qty': '${o.moq}', 'unit': o.unit})}'),
      _row(context, context.tr('ps_delivery'), priceOfferDeliveryText(context.tr, trMsg, o), key: ValueKey('ps_delivery_${o.id}')),
      if (o.delivery.fee != null && o.delivery.fromPrice)
        Text(context.tr('ps_weight_note'), style: TextStyle(fontSize: 11.5, color: c.ink2)),
      if (o.delivery.fee == null && o.delivery.reason == PriceDeliveryReason.buyerLocationMissing)
        Text(context.tr('ps_need_location'), style: TextStyle(fontSize: 11.5, color: c.ink2)),
      const Divider(height: 10),
      _row(
        context,
        context.tr('ps_total'),
        o.total == null
            ? '—'
            : (o.totalFrom ? trMsg('ps_amount_from', {'amount': formatPrice(o.total!)}) : formatMoney(o.total!)),
        bold: true,
        key: ValueKey('ps_total_${o.id}'),
      ),
    ];
    return Material(
      color: c.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        key: ValueKey('ps_offer_${o.id}'),
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), border: Border.all(color: c.line)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      width: 64,
                      height: 64,
                      child: o.photoUrl.isEmpty
                          ? ColoredBox(color: c.chip, child: const Icon(Icons.image_outlined))
                          : CachedNetworkImage(imageUrl: o.photoUrl, fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => ColoredBox(color: c.chip, child: const Icon(Icons.broken_image_outlined))),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          _badge(context, context.tr(o.wholesale ? 'ps_badge_wholesale' : 'ps_badge_retail'), o.wholesale ? c.brandSoft : c.chip),
                          if (o.sponsored) _badge(context, context.tr('ps_sponsored'), c.chip),
                        ]),
                        const SizedBox(height: 4),
                        Text(o.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(
                          [if (o.sellerName.isNotEmpty) o.sellerName, if (place.isNotEmpty) place].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: c.ink2),
                        ),
                        if (o.packLabel.isNotEmpty)
                          Text(trMsg('ps_pack', {'label': o.packLabel}), style: TextStyle(fontSize: 12, color: c.ink2)),
                        if (o.listedAt != null)
                          Text(trMsg('ps_listed', {'date': formatDateShort(o.listedAt)}), style: TextStyle(fontSize: 11.5, color: c.ink2)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...rows,
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      key: ValueKey('ps_open_${o.id}'),
                      onPressed: onOpen,
                      child: Text(context.tr('ps_open')),
                    ),
                  ),
                  if (showWrite) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: FilledButton(
                        key: ValueKey('ps_write_${o.id}'),
                        onPressed: onWrite,
                        child: Text(context.tr('ps_write')),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(BuildContext context, String label, String value, {bool bold = false, Key? key}) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 1.5),
        child: Row(
          children: [
            Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: context.ava.ink2))),
            Text(value, key: key, style: TextStyle(fontSize: bold ? 15 : 13, fontWeight: bold ? FontWeight.w800 : FontWeight.w600)),
          ],
        ),
      );

  Widget _badge(BuildContext context, String text, Color bg) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: context.ava.ink)),
      );
}
