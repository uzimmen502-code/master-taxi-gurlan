import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../tv_market/models/tv_ad_prefill.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../../tv_market/screens/tv_publish_screen.dart';
import '../../tv_market/screens/tv_shop_public_screen.dart';
import '../../my_shop/widgets/shop_link_sheet.dart';
import '../domain/business.dart';
import '../domain/business_type_profile.dart';
import '../domain/product_kind.dart';
import 'business_product_form_screen.dart';

/// Формага узатиладиган олдиндан тўлдириш ([BusinessProductFormScreen.initialOffer] билан бир хил шакл).
typedef BusinessOfferPrefill = ({String title, String kind, String priceUnitWire});

/// Эганинг объекти маҳсулотлари: рўйхат, қўшиш, таҳрирлаш, ўчириш (юмшоқ ўчириш — `status: deleted`).
/// Сони чекланмаган (эга қарори, 2026-10-24).
///
/// S5 (2026-11-03): харита объектида сарлавҳа ва бўш ҳолат — тур профилидан ([BusinessTypeProfile]:
/// «Хизматлар» / «Маҳсулотлар» / «Маҳсулотлар ва хизматлар»); бўш каталогда «Тез бошлаш» шаблон чиплари
/// (босилса форма ном/тур/бирлик билан очилади); AppBar'да «Мижоз кўзи билан» ва «Ҳавола ва QR».
/// Дўкон (чакана) ва асосий дўкон ([Business.ownShop]) — аввалгидек (ҳаволаси «Менинг дўконим»да).
class BusinessProductsScreen extends StatefulWidget {
  const BusinessProductsScreen({
    super.key,
    required this.business,
    TvShopRepository? repository,
    this.onPromote,
    this.embedded = false,
    this.openFormOnStart = false,
    this.formScreen,
    this.customerViewScreen,
    this.loadLink,
  }) : _repo = repository;

  /// Тест учун: форма экрани ўрнига ([prefill] — шаблон чипидан; «қўшиш» ва таҳрирда `null`).
  final Widget Function(Business business, TvShopItem? existing, BusinessOfferPrefill? prefill)? formScreen;

  /// Тест учун: «Мижоз кўзи билан» экрани ўрнига (бўлмаса — [TvShopPublicScreen], шу объект танланган).
  final Widget Function(Business business)? customerViewScreen;

  /// Тест учун: доимий ҳавола (`BusinessRepository.getMyShopLink`) ўрнига.
  final Future<String> Function({String businessId})? loadLink;

  /// Харита объекти ёки эганинг ўз дўкони ([Business.ownShop], `id` бўш).
  final Business business;
  final TvShopRepository? _repo;

  /// «Менинг дўконим» ичида: ўз `AppBar`и йўқ (сарлавҳа ташқарида).
  final bool embedded;

  /// Биринчи киришда янги маҳсулот формаси дарҳол очилади (ёпилгач рўйхат ва «қўшиш» тугмаси турибди).
  final bool openFormOnStart;

  /// «Реклама қилиш» — тест учун алмаштирилади; бўлмаса пуллик реклама экрани (`TvPublishScreen`) очилади.
  final void Function(BuildContext context, TvShopItem item)? onPromote;

  @override
  State<BusinessProductsScreen> createState() => _BusinessProductsScreenState();
}

class _BusinessProductsScreenState extends State<BusinessProductsScreen> {
  late final TvShopRepository _repo = widget._repo ?? TvShopRepository();
  late Future<List<TvShopItem>> _future = _load();

  /// Админ блоки (2026-10-25): йўналиш ([Business.isBlocked]) ёки бутун онлайн дўкон (`tv_shops.status`).
  /// Блокда янги маҳсулот қўшиб бўлмайди (rules ҳам рад этади) — тугма яширилади, сабаб айтилади.
  late bool _blocked = widget.business.isBlocked;

  /// Тур профили — сарлавҳа, бўш ҳолат ва шаблонлар манбаи (S0, ягона манба).
  late final BusinessTypeProfile _profile = BusinessTypeProfile.forBusiness(widget.business);

  /// Дўкон (асосий ёки чакана): S5 гача бўлган кўриниш ўзгармайди (сарлавҳа, бўш ҳолат, AppBar тугмаларисиз).
  late final bool _isShop = sellsOnlyProducts(widget.business);

  /// Шаблон чиплари: харита объекти, блокланмаган; овқатланиш объекти менюси — ресторан бўлимида (эга 2026-11-03).
  bool get _showTemplates =>
      !_isShop && !_blocked && _profile.group != BusinessOfferGroup.menu && _profile.templates.isNotEmpty;

  Future<List<TvShopItem>> _load() => widget.business.isOwnShop
      ? _repo.fetchOwnShopItems(widget.business.ownerId)
      : _repo.fetchByBusiness(widget.business.id, ownerPhone: widget.business.ownerId, onlyActive: false);

  Future<void> _checkShopBlock() async {
    if (_blocked) return;
    try {
      final shop = await _repo.fetchShop(widget.business.ownerId);
      if (mounted && (shop?.isBlocked ?? false)) setState(() => _blocked = true);
    } catch (e) {
      debugPrint('[BusinessProducts] shop status: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _checkShopBlock();
    if (widget.openFormOnStart && !_blocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openForm();
      });
    }
  }

  void _reload() => setState(() {
        _future = _load();
      });

  Future<void> _openForm([TvShopItem? item, BusinessOfferPrefill? prefill]) async {
    final custom = widget.formScreen;
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) =>
            custom?.call(widget.business, item, prefill) ??
            BusinessProductFormScreen(business: widget.business, existing: item, initialOffer: prefill),
      ),
    );
    if (changed == true && mounted) _reload();
  }

  /// «Тез бошлаш» чипи → форма шаблон номи (жорий тилда), тури ва нарх бирлиги билан.
  void _openTemplate(OfferTemplate t) => _openForm(null, (
        title: BusinessTypeProfile.templateTitle(t, context.contentLang),
        kind: t.kind.wire,
        priceUnitWire: t.unit.wire,
      ));

  /// Харидор кўрадиган саҳифа — шу объект танланган ҳолда (эгасининг ўз кўриши статистикада саналмайди — сервер).
  void _openCustomerView() {
    final b = widget.business;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) =>
          widget.customerViewScreen?.call(b) ??
          TvShopPublicScreen(ownerPhone: b.ownerId, businessId: b.id, source: 'shop'),
    ));
  }

  void _openLink() => showShopLinkSheet(
        context,
        title: widget.business.name,
        businessId: widget.business.id,
        loadLink: widget.loadLink,
      );

  /// Каталог маҳсулоти → пуллик АВАГрам рекламаси (алоҳида механизм): мавжуд реклама экрани ном/нарх/тавсиф
  /// олдиндан тўлдирилган ҳолда очилади; видео, тариф ва тўловни эга шу ерда танлайди.
  void _promote(TvShopItem item) {
    final custom = widget.onPromote;
    if (custom != null) return custom(context, item);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => TvPublishScreen(hideShopOption: true, adPrefill: TvAdPrefill.fromItem(item)),
    ));
  }

  Future<void> _delete(TvShopItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.tr('bizprod_delete_title')),
        content: Text(item.title),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(context.tr('cancel'))),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.tr('bizmap_delete'), style: TextStyle(color: Colors.red.shade700)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _repo.deleteItem(item.id);
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('bizprod_deleted'))));
      _reload();
    } catch (e) {
      debugPrint('[BusinessProducts] delete: $e');
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('bizprod_err_generic'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: widget.embedded
          ? null
          : AppBar(
              title: Text(
                widget.business.isOwnShop
                    ? widget.business.name
                    // Дўконда — «Маҳсулотлар» («хизмат» йўқ; эга, 2026-10-26); бошқа объектда — тур профилидан.
                    : '${context.tr(_isShop ? 'bizprod_title_products' : _profile.catalogTitleKey)} · '
                        '${widget.business.name}',
                maxLines: 1,
              ),
              actions: _isShop
                  ? null
                  : [
                      IconButton(
                        key: const ValueKey('bizprod_customer_view'),
                        tooltip: context.tr('biz_customer_view'),
                        icon: const Icon(Icons.visibility_outlined),
                        onPressed: _openCustomerView,
                      ),
                      IconButton(
                        key: const ValueKey('bizprod_link_qr'),
                        tooltip: context.tr('biz_link_qr'),
                        icon: const Icon(Icons.qr_code_2_rounded),
                        onPressed: _openLink,
                      ),
                    ],
            ),
      body: Column(
        children: [
          if (_blocked)
            MaterialBanner(
              key: const ValueKey('bizprod_blocked_banner'),
              content: Text(context.tr('bizprod_blocked_banner')),
              leading: Icon(Icons.block_rounded, color: Colors.red.shade700),
              backgroundColor: Colors.red.shade50,
              actions: const [SizedBox.shrink()],
            ),
          Expanded(child: _list()),
        ],
      ),
      floatingActionButton: _blocked
          ? null
          : FloatingActionButton.extended(
              key: const ValueKey('bizprod_fab'),
              onPressed: () => _openForm(),
              backgroundColor: AppColors.primaryDark,
              foregroundColor: AppColors.onPrimary,
              icon: const Icon(Icons.add_rounded),
              label: Text(context.tr('bizprod_add')),
            ),
    );
  }

  /// «Тез бошлаш»: сарлавҳа, изоҳ ва шаблон чиплари (S0 профили; номлар жорий тилда).
  List<Widget> _templates() {
    final lang = context.contentLang;
    return [
      const SizedBox(height: 20),
      Text(context.tr('biz_next_quick_title'), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
      const SizedBox(height: 4),
      Text(
        context.tr('biz_next_quick_sub'),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
      ),
      const SizedBox(height: 10),
      Wrap(
        key: const ValueKey('bizprod_templates'),
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          for (var i = 0; i < _profile.templates.length; i++)
            ActionChip(
              key: ValueKey('bizprod_tpl_$i'),
              avatar: const Icon(Icons.add_rounded, size: 18),
              label: Text(BusinessTypeProfile.templateTitle(_profile.templates[i], lang)),
              onPressed: () => _openTemplate(_profile.templates[i]),
            ),
        ],
      ),
    ];
  }

  Widget _list() {
    return FutureBuilder<List<TvShopItem>>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(context.tr('bizprod_err_generic')));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final items = snap.data!;
          if (items.isEmpty) {
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.inventory_2_outlined, size: 56, color: AppColors.primaryDark),
                    const SizedBox(height: 12),
                    Text(
                      context.tr(_isShop ? 'bizprod_empty' : _profile.emptyStateKey),
                      key: const ValueKey('bizprod_empty_text'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    if (_showTemplates) ..._templates(),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final it = items[i];
              final cover = it.coverPhotoUrl;
              return Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: SizedBox(
                    width: 52,
                    height: 52,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: cover.isEmpty
                          ? const ColoredBox(color: Color(0x11000000), child: Icon(Icons.image_not_supported_outlined))
                          : Image.network(cover, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                    ),
                  ),
                  title: Text(it.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                    [
                      if (it.isBlocked) context.tr('bizprod_status_blocked'),
                      if (it.hasPrice) formatMoney(it.price),
                      context.tr(it.kind == 'service' ? 'bizprod_kind_service' : 'bizprod_kind_product'),
                      if (it.hasVideo) context.tr('bizprod_has_video'),
                    ].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => _openForm(it),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (it.isActive)
                        IconButton(
                          key: ValueKey('bizprod_promote_${it.id}'),
                          tooltip: context.tr('bizprod_promote'),
                          icon: const Icon(Icons.campaign_outlined),
                          onPressed: () => _promote(it),
                        ),
                      IconButton(
                        tooltip: context.tr('bizmap_delete'),
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _delete(it),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
  }
}
