import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/fair_mix.dart';
import '../../../models/platform_product.dart';
import '../../../repositories/platform_products_repository.dart';
import '../../ads/widgets/platform_market_card.dart';
import '../models/wholesale_product.dart';
import '../models/wholesale_seller.dart';
import '../repositories/wholesale_products_repository.dart';
import '../repositories/wholesale_sellers_repository.dart';
import '../services/wholesale_storage_service.dart';
import '../services/wholesale_video_link.dart';
import '../widgets/wholesale_product_card.dart';
import 'wholesale_product_detail_screen.dart';
import 'wholesale_product_form_screen.dart';

/// Улгуржи/кичик улгуржи бозор — умумий кириш нуқтаси.
/// "Бозор" (ҳамма кўради) + "Мен сотувчиман" (рўйхатдан ўтиш → admin
/// тасдиғи → маҳсулот қўшиш).
///
/// Хитой бозори ҳам ШУ экран — архитектураси бир хил (эга қарори), фақат
/// [market] билан ажралади: ўша коллекция, ўша сотувчи рўйхати, ўша
/// модерация. Сотувчи иккала бозорга ҳам маҳсулот қўя олади.
class WholesaleMarketScreen extends StatefulWidget {
  const WholesaleMarketScreen({
    super.key,
    required this.userPhone,
    this.initialTabIndex = 0,
    this.market = WholesaleProduct.marketWholesale,
  });

  /// [WholesaleProduct.marketWholesale] ёки [WholesaleProduct.marketChina].
  final String market;

  /// 0 — «Бозор», 1 — «Мен сотувчиман». Бош саҳифадаги «＋ → Сотувчи
  /// бўлиш» дарҳол иккинчи табни очади.
  final int initialTabIndex;

  /// Жорий фойдаланувчи телефони — бош экрандан узатилади (`HomeController`
  /// фақат Home subtree'ида мавжуд, push қилинган экранда `context.read`
  /// ишламайди — ProviderNotFound, қурилмада бўш экран бўлган).
  final String userPhone;

  @override
  State<WholesaleMarketScreen> createState() => _WholesaleMarketScreenState();
}

class _WholesaleMarketScreenState extends State<WholesaleMarketScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  final _searchCtrl = TextEditingController();
  final _productsRepo = WholesaleProductsRepository();
  final _platformRepo = PlatformProductsRepository();
  String _query = '';

  /// AVA дўконининг улгуржи товарлари — эга қарори (2026-09-29):
  /// «АВА дўкони бундан кейин Улгуржи бозор мақомида». Лентада улар
  /// сотувчилар товари билан НАВБАТМА-НАВБАТ туради (`FairMix`), яъни
  /// AVA юқорида тўпланиб қолмайди — Аҳоли бозоридаги қоида билан бир хил.
  List<PlatformProduct> _platform = const [];

  /// Хитой бозорида AVA товари кўрсатилмайди: у ердаги товар хорижий
  /// етказиб берувчиники, валюта ва етказиш муддати ҳам бошқа.
  bool get _showPlatform => !_isChina;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 1),
    );
    if (_showPlatform) unawaited(_loadPlatform());
  }

  Future<void> _loadPlatform() async {
    try {
      final list = await _platformRepo.fetchForWholesale();
      if (!mounted) return;
      setState(() => _platform = list);
    } catch (e) {
      // AVA товарлари юкланмаса ҳам лента сотувчилар товари билан
      // ишлайверсин.
      debugPrint('[Wholesale] loadPlatform $e');
    }
  }

  /// Қидирувга мос AVA товарлари. Қидирув бўш бўлса — ҳаммаси.
  List<PlatformProduct> _filteredPlatform() {
    final q = _query.trim().toLowerCase();
    if (!_showPlatform) return const [];
    if (q.isEmpty) return _platform;
    return _platform
        .where((p) =>
            p.name.toLowerCase().contains(q) ||
            p.description.toLowerCase().contains(q))
        .toList(growable: false);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  bool get _isChina => widget.market == WholesaleProduct.marketChina;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          context.tr(_isChina ? 'wholesale_title_china' : 'wholesale_title'),
        ),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: Colors.black,
          unselectedLabelColor: Colors.black54,
          indicatorColor: Colors.black,
          tabs: [
            Tab(text: context.tr('wholesale_tab_market')),
            Tab(text: context.tr('wholesale_tab_seller')),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _marketTab(),
          _SellerAreaTab(phone: widget.userPhone, market: widget.market),
        ],
      ),
    );
  }

  Widget _marketTab() {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.all(12),
        child: TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: context.tr('wholesale_search_hint'),
            prefixIcon: const Icon(Icons.search),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            isDense: true,
          ),
        ),
      ),
      Expanded(
        child: StreamBuilder<List<WholesaleProduct>>(
          stream: _query.trim().isEmpty
              ? _productsRepo.getActiveProducts(market: widget.market)
              : _productsRepo.searchActiveProducts(_query,
                  market: widget.market),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting &&
                !snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final items = snap.data ?? const <WholesaleProduct>[];
            final platform = _filteredPlatform();
            if (items.isEmpty && platform.isEmpty) {
              return Center(
                child: Text(context.tr('wholesale_empty_products')),
              );
            }
            // Навбатма-навбат: AVA товари лентанинг бошида тўпланиб
            // қолмасин, сотувчилар товари ҳам кўринсин.
            final entries = FairMix.roundRobin<_MarketEntry>([
              platform.map(_MarketEntry.platform).toList(growable: false),
              items.map(_MarketEntry.seller).toList(growable: false),
            ]);
            return GridView.builder(
              padding: const EdgeInsets.all(12),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 0.72,
              ),
              itemCount: entries.length,
              itemBuilder: (_, i) {
                final e = entries[i];
                final avaProduct = e.platform;
                if (avaProduct != null) {
                  return PlatformMarketCard(
                    product: avaProduct,
                    catalog: platform,
                    wholesale: true,
                  );
                }
                final p = e.seller!;
                return WholesaleProductCard(
                  product: p,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => WholesaleProductDetailScreen(product: p),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    ]);
  }
}

/// "Мен сотувчиман" — сотувчи ҳолатига қараб: рўйхатдан ўтиш формаси,
/// кутилмоқда/рад этилган ҳолат, ёки ўз маҳсулотлари рўйхати.
class _SellerAreaTab extends StatefulWidget {
  const _SellerAreaTab({required this.phone, required this.market});

  final String phone;

  /// Маҳсулотлар шу бозорга қўшилади ва шу бозорники кўрсатилади.
  final String market;

  @override
  State<_SellerAreaTab> createState() => _SellerAreaTabState();
}

class _SellerAreaTabState extends State<_SellerAreaTab> {
  final _sellersRepo = WholesaleSellersRepository();
  final _companyCtrl = TextEditingController();
  final _ownerCtrl = TextEditingController();
  String _sellerType = '';
  bool _registering = false;

  @override
  void dispose() {
    _companyCtrl.dispose();
    _ownerCtrl.dispose();
    super.dispose();
  }

  String get _phone => widget.phone;

  Future<void> _register() async {
    final company = _companyCtrl.text.trim();
    if (company.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('wholesale_err_company_name'))),
      );
      return;
    }
    if (_sellerType.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('wholesale_err_seller_type'))),
      );
      return;
    }
    setState(() => _registering = true);
    try {
      await _sellersRepo.register(
        phone: _phone,
        companyName: company,
        ownerName: _ownerCtrl.text.trim(),
        sellerType: _sellerType,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('wholesale_register_sent'))),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            context.tr('error_generic').replaceAll('{error}', '$e'),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _registering = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final phone = _phone;
    if (phone.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            context.tr('wholesale_need_phone'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    return StreamBuilder<WholesaleSeller?>(
      stream: _sellersRepo.watchByPhone(phone),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final seller = snap.data;
        if (seller == null) return _registerForm();
        if (seller.isPending) return _statusCard(seller);
        if (seller.isRejected) return _statusCard(seller);
        return _MyProductsView(seller: seller, market: widget.market);
      },
    );
  }

  Widget _registerForm() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text(
          context.tr('wholesale_register_title'),
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        Text(
          // Рўйхат битта — иккала бозор ҳам `wholesale_sellers`дан
          // фойдаланади, шунинг учун Хитой бозорида буни айтиб қўямиз.
          context.tr('wholesale_register_body') +
              (widget.market == WholesaleProduct.marketChina
                  ? context.tr('wholesale_register_body_china')
                  : ''),
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 20),
        Text(context.tr('wholesale_who_are_you'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, children: [
          for (final t in WholesaleSeller.sellerTypes)
            ChoiceChip(
              label: Text(context.tr(WholesaleSeller.typeLabelKey(t))),
              selected: _sellerType == t,
              onSelected: (_) => setState(() => _sellerType = t),
            ),
        ]),
        const SizedBox(height: 16),
        TextField(
          controller: _companyCtrl,
          decoration: InputDecoration(
            labelText: context.tr('wholesale_field_company'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _ownerCtrl,
          decoration: InputDecoration(
            labelText: context.tr('wholesale_field_owner'),
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton(
          onPressed: _registering ? null : _register,
          child: _registering
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(context.tr('wholesale_register_cta')),
        ),
      ],
    );
  }

  Widget _statusCard(WholesaleSeller seller) {
    final pending = seller.isPending;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              pending ? Icons.hourglass_top : Icons.block,
              size: 48,
              color: pending ? Colors.orange : Colors.red,
            ),
            const SizedBox(height: 12),
            Text(
              pending
                  ? context.tr('wholesale_status_pending_title')
                  : context.tr('wholesale_status_rejected_title'),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            if (!pending && seller.adminNote.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                  context
                      .tr('wholesale_reason')
                      .replaceAll('{note}', seller.adminNote),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey.shade700)),
            ],
          ],
        ),
      ),
    );
  }
}

class _MyProductsView extends StatelessWidget {
  const _MyProductsView({required this.seller, required this.market});

  final WholesaleSeller seller;

  /// Фақат шу бозордаги маҳсулотлар кўрсатилади ва янгиси ҳам шу
  /// бозорга қўшилади.
  final String market;

  @override
  Widget build(BuildContext context) {
    final repo = WholesaleProductsRepository();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                WholesaleProductFormScreen(seller: seller, market: market),
          ),
        ),
        icon: const Icon(Icons.add),
        label: Text(context.tr('wholesale_new_product')),
      ),
      body: StreamBuilder<List<WholesaleProduct>>(
        stream: repo.watchBySeller(seller.phone, market: market),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final items = snap.data ?? const <WholesaleProduct>[];
          if (items.isEmpty) {
            return Center(
                child: Text(context.tr('wholesale_no_products_yet')));
          }
          // Расмлар AVA Дўкон (Сотувчи POS) каби — катта, cover, грид карта
          // (эга қарори, 2026-09-24). Аввал кичик CircleAvatarли ListTile эди.
          return GridView.builder(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 80),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 0.78,
            ),
            itemCount: items.length,
            itemBuilder: (_, i) => _myProductTile(context, repo, items[i]),
          );
        },
      ),
    );
  }

  /// Ўчириш — ТАСДИҚ билан (2026-09-29).
  ///
  /// Аввал меню банди босилиши биланоқ маҳсулот ўчиб кетар эди: битта
  /// нотўғри тегиш сотувчининг маҳсулотини бутунлай йўқотарди.
  /// Ҳужжат ўчгач расмлар ҳам Storage'дан тозаланади — уларга бошқа
  /// ҳеч ким мурожаат қилмайди, аввал эса улар у ерда абадий қолиб
  /// кетар эди (`WholesaleStorageService.deleteImages` ёзилган, лекин
  /// ҳеч қаердан чақирилмас эди).
  Future<void> _confirmDelete(
    BuildContext context,
    WholesaleProductsRepository repo,
    WholesaleProduct p,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final deletedText = context.tr('wholesale_deleted');
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(dialogCtx.tr('wholesale_delete_title')),
        content: Text(
          dialogCtx
              .tr('wholesale_delete_body')
              .replaceAll('{title}', p.title),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: Text(dialogCtx.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(dialogCtx.tr('delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await repo.delete(p.id);
    // Расмлар ҳужжатдан КЕЙИН ўчирилади: Storage хатоси эълоннинг
    // ўчишига тўсқинлик қилмасин.
    if (p.imageUrls.isNotEmpty) {
      await WholesaleStorageService().deleteImages(p.imageUrls);
    }
    messenger.showSnackBar(SnackBar(content: Text(deletedText)));
  }

  Widget _myProductTile(
    BuildContext context,
    WholesaleProductsRepository repo,
    WholesaleProduct p,
  ) {
    void onMenu(String action) async {
      if (action == 'edit') {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) =>
                WholesaleProductFormScreen(seller: seller, existing: p),
          ),
        );
      } else if (action == 'hide') {
        await repo.deactivate(p.id);
      } else if (action == 'delete') {
        await _confirmDelete(context, repo, p);
      } else if (action == 'add_video') {
        await _addVideo(context, repo, p);
      } else if (action == 'view_video') {
        await _viewVideo(context, p);
      }
    }

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.cardBorderMuted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: ColoredBox(
                      color: Colors.grey.shade100,
                      child: p.imageUrls.isEmpty
                          ? const Icon(Icons.inventory_2_outlined, size: 40)
                          : CachedNetworkImage(
                              imageUrl: p.imageUrls.first,
                              width: double.infinity,
                              height: double.infinity,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => const Icon(
                                  Icons.image_not_supported_outlined),
                            ),
                    ),
                  ),
                  if (p.videoClipIds.isNotEmpty)
                    Positioned(
                      top: 4,
                      left: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(Icons.play_circle_fill,
                            color: Colors.white, size: 16),
                      ),
                    ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Material(
                      color: Colors.black45,
                      shape: const CircleBorder(),
                      child: PopupMenuButton<String>(
                        onSelected: onMenu,
                        icon: const Icon(Icons.more_vert,
                            color: Colors.white, size: 20),
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        itemBuilder: (_) => [
                          PopupMenuItem(
                              value: 'edit', child: Text(context.tr('edit'))),
                          PopupMenuItem(
                            value: 'add_video',
                            child: Text(context.tr('wholesale_menu_add_video')),
                          ),
                          if (p.videoClipIds.isNotEmpty)
                            PopupMenuItem(
                              value: 'view_video',
                              child:
                                  Text(context.tr('wholesale_menu_view_video')),
                            ),
                          if (p.isActive)
                            PopupMenuItem(
                                value: 'hide',
                                child: Text(context.tr('wholesale_menu_hide'))),
                          PopupMenuItem(
                              value: 'delete',
                              child: Text(context.tr('delete'))),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                p.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: AppText.bodyMedium,
                ),
              ),
            ),
            Text(
              p.priceLine,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.primaryDark,
                fontSize: AppText.titleSmall,
              ),
            ),
            Text(
              '${context.tr('wholesale_moq_line').replaceAll('{qty}', '${p.moq}').replaceAll('{unit}', p.unit)}'
              ' · ${context.tr(_statusLabelKey(p.status))}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  /// AVAGram'да видео/реклама нашр қилиш — [WholesaleVideoLink].
  Future<void> _addVideo(
    BuildContext context,
    WholesaleProductsRepository repo,
    WholesaleProduct p,
  ) async {
    try {
      final linked = await WholesaleVideoLink.publishAndLink(
        context,
        sellerPhone: seller.phone,
        productId: p.id,
      );
      if (!context.mounted || !linked) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('wholesale_video_linked'))),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.red,
          content: Text(
            context.tr('error_generic').replaceAll('{error}', '$e'),
          ),
        ),
      );
    }
  }

  Future<void> _viewVideo(BuildContext context, WholesaleProduct p) {
    return WholesaleVideoLink.openLinkedClip(
      context,
      sellerPhone: seller.phone,
      clipIds: p.videoClipIds,
    );
  }

  String _statusLabelKey(String status) {
    switch (status) {
      case WholesaleProduct.statusPending:
        return 'wholesale_status_pending';
      case WholesaleProduct.statusActive:
        return 'wholesale_status_active';
      case WholesaleProduct.statusInactive:
        return 'wholesale_status_inactive';
      default:
        return status;
    }
  }
}


/// Улгуржи лентасидаги битта катак: ё сотувчи товари, ё AVA дўкони
/// товари (эга қарори, 2026-09-29).
class _MarketEntry {
  const _MarketEntry._({this.seller, this.platform});

  factory _MarketEntry.seller(WholesaleProduct p) =>
      _MarketEntry._(seller: p);
  factory _MarketEntry.platform(PlatformProduct p) =>
      _MarketEntry._(platform: p);

  final WholesaleProduct? seller;
  final PlatformProduct? platform;
}
