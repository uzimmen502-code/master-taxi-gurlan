import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart' show FieldValue;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../product_badges/product_promo_sheet.dart';
import '../../../core/service_config_holder.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../markets/data/market_listings_source.dart' show resolveRegionIdForDistrict;
import '../../markets/data/market_taxonomy_repository.dart';
import '../../markets/domain/market_taxonomy.dart';
import '../../markets/widgets/market_form_fields.dart';
import '../../tv_market/domain/listing_status_view.dart';
import '../../tv_market/domain/price_unit.dart';
import '../../tv_market/models/tv_shop.dart';
import '../../tv_market/repositories/tv_shop_repository.dart';
import '../../tv_market/screens/tv_publish_screen.dart';
import '../../tv_market/screens/tv_shop_item_photos_screen.dart';
import '../../tv_market/services/tv_storage_service.dart';
import '../../wholesale/models/shipping_dims.dart' show parseWeightKgToGrams, weightKgFieldText;
import '../domain/business.dart';
import '../domain/business_market_map.dart';
import '../domain/business_type_profile.dart';
import '../domain/product_kind.dart';

/// Объектнинг маҳсулот/хизмати: ном, нарх, тавсиф, 7 тагача расм, ихтиёрий 1 видео (эга қарори, 2026-10-24).
///
/// Маҳсулот — мавжуд АВАГрам витринаси ҳужжати (`tv_shop_items`) + `businessId`: Аҳоли бозорида (расм бор) ва
/// видео қўшилса АВАГрамда ўзи чиқади. «Бозорлар» 2b (эга 2026-11-15): олдиндан модерация — янги эълон `pending`,
/// админ тасдиқлагач `active` (30 кун); контент таҳририда сервер қайта текширувга ўтказади.
class BusinessProductFormScreen extends StatefulWidget {
  const BusinessProductFormScreen({
    super.key,
    required this.business,
    this.existing,
    TvShopRepository? repository,
    this.ownerPhone,
    this.pickPhotos,
    this.uploadPhotos,
    this.addVideo,
    this.initialOffer,
    this.initialMarket,
    this.initialCategory,
    this.showMarketChoice,
    this.loadTaxonomy,
    this.isModuleOpenable,
    this.resolveRegionId,
  }) : _repo = repository;

  /// «Бозорлар» 5-босқич (эга 2026-11-15). Бозор ичидаги қизил «+» — бозор ва жорий бўлим олдиндан танланган
  /// (бозор чиплари кўрсатилмайди). Бўш/`null` — Аралаш (бозор майдонисиз).
  final String? initialMarket;
  final String? initialCategory;

  /// «Қаерда сотасиз?» чиплари (Аралаш + очиқ бозорлар). `null` — ўзи: янги маҳсулот ва бозор олдиндан
  /// танланмаган (ўз дўкони ҳам, харита объекти ҳам; объектда бозор фаолият туридан олдиндан танланади, 2026-11-16).
  final bool? showMarketChoice;

  /// Тест учун: таксономия (бўлмаса [MarketTaxonomyRepository.load] — сеансда бир марта).
  final Future<MarketTaxonomy> Function()? loadTaxonomy;

  /// Тест учун: модул дарвозаси (бўлмаса [ServiceConfigHolder.isOpenable] — фаол туман бўйича).
  final bool Function(String moduleId)? isModuleOpenable;

  /// Тест учун: туман → вилоят (бўлмаса [resolveRegionIdForDistrict]).
  final Future<String> Function(String districtId)? resolveRegionId;

  /// Янги таклиф учун олдиндан тўлдириш (каталогдаги «Тез бошлаш» шаблони, S5): ном (жорий тилда), тур
  /// (`product`/`service`) ва нарх бирлиги wire қиймати (`PriceUnit.wire`; S2 форма танлови ўқийди).
  /// Таҳрирда ([existing]) ишлатилмайди; дўконда тур доим `product`.
  final ({String title, String kind, String priceUnitWire})? initialOffer;

  final Business business;
  final TvShopItem? existing;
  final TvShopRepository? _repo;

  /// Тест учун; бўлмаса — жорий фойдаланувчи телефони.
  final String? ownerPhone;

  /// Тест учун алмаштирилади (платформа плагинлари). `room` — яна неча расм сиғади.
  final Future<List<String>> Function(int room)? pickPhotos;
  final Future<List<String>> Function(String ownerPhone, List<String> paths)? uploadPhotos;

  /// Расм сақлангандан кейин видео қўшиш (бўлмаса — АВАГрам нашр экрани очилади).
  final Future<void> Function(BuildContext context, String itemId)? addVideo;

  @override
  State<BusinessProductFormScreen> createState() => _BusinessProductFormScreenState();
}

class _BusinessProductFormScreenState extends State<BusinessProductFormScreen> {
  late final TvShopRepository _repo = widget._repo ?? TvShopRepository();
  late final String _phone =
      widget.ownerPhone ?? canonicalPhoneId(FirebaseAuth.instance.currentUser?.phoneNumber ?? '');

  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.title ?? widget.initialOffer?.title ?? '');
  late final TextEditingController _price = TextEditingController(
      text: (widget.existing?.price ?? 0) > 0 ? '${widget.existing!.price}' : '');
  late final TextEditingController _desc = TextEditingController(text: widget.existing?.description ?? '');

  /// AVA AI нарх қидируви (эга 2026-11-17, А вариант): ихтиёрий «тахминий вазн», кг → unitWeightG (грамм).
  late final TextEditingController _weight = TextEditingController(
      text: widget.existing?.unitWeightG != null ? weightKgFieldText(widget.existing!.unitWeightG!) : '');
  late String _kind = widget.existing?.kind ??
      (sellsOnlyProducts(widget.business)
          ? 'product'
          : widget.initialOffer?.kind ?? defaultProductKind(widget.business.category, subtype: widget.business.subtype));

  /// Дўконда «Хизмат» танлови йўқ ([sellsOnlyProducts]). Аввал хизмат деб сақланган эски дўкон ёзуви — танлов
  /// кўринади, эга уни маҳсулотга ўтказа олсин.
  late final bool _showKindChoice = !sellsOnlyProducts(widget.business) || widget.existing?.kind == 'service';
  final List<String> _photos = [];

  /// Нарх бирлиги танлови (S2): объект тури профилидаги рўйхат; таҳрирда сақланган бирлик рўйхатда бўлмаса ҳам
  /// кўрсатилади (тур кейин ўзгарган бўлиши мумкин — эга қийматини йўқотмасин).
  late final BusinessTypeProfile _profile = BusinessTypeProfile.forBusiness(widget.business);
  // Таҳрир — сақланган бирлик; «Тез бошлаш» шаблони — шаблон бирлиги (S5); акс ҳолда тур бошланғичи.
  late PriceUnit _unit = widget.existing?.priceUnit ??
      (widget.initialOffer != null
          ? PriceUnit.fromWire(widget.initialOffer!.priceUnitWire) // '' = аниқ нарх
          : _profile.defaultPriceUnit);
  late final List<PriceUnit> _profileUnits = [
    for (final u in PriceUnit.values)
      if (_profile.priceUnits.contains(u) || u == widget.existing?.priceUnit) u,
  ];

  /// Бозор танланган бўлса — таксономиядаги бирликлар (Гўшт: фақат `kg` — танлов йўқ, мажбурий); акс ҳолда профил.
  List<PriceUnit> get _units {
    final m = _marketDef;
    if (m == null) return _profileUnits;
    final saved = widget.existing?.priceUnit;
    return [...m.priceUnits, if (saved != null && widget.existing!.market == m.id && !m.priceUnits.contains(saved)) saved];
  }

  // ── «Бозорлар» (5-босқич) ──
  MarketTaxonomy? _taxonomy;
  bool _taxonomyFailed = false;
  late String _market = widget.existing?.market ?? (widget.initialMarket ?? '').trim();
  late String _category = widget.existing?.category ?? (widget.initialCategory ?? '').trim();
  final Map<String, Object?> _attrValues = {};
  late bool _imported = widget.existing?.imported ?? false;
  Map<String, MarketFieldError> _fieldErrors = const {};

  // 2026-11-16: харита объекти учун ҳам (аввал фақат ўз дўкони) — бозор фаолият туридан олдиндан танланади.
  bool get _showMarketChoice =>
      widget.showMarketChoice ?? (!_isEdit && (widget.initialMarket ?? '').trim().isEmpty);
  bool get _needsTaxonomy => _showMarketChoice || _market.isNotEmpty;
  MarketDef? get _marketDef => _market.isEmpty ? null : _taxonomy?.market(_market);

  /// Ҳозирги бўлим: битта бўлимли бозорда — ўзи (`all`).
  String get _effectiveCategory => _marketDef?.autoCategory ?? _category;

  @override
  void initState() {
    super.initState();
    if (_needsTaxonomy) _loadTaxonomy();
  }

  Future<void> _loadTaxonomy() async {
    setState(() => _taxonomyFailed = false);
    try {
      final t = await (widget.loadTaxonomy ?? MarketTaxonomyRepository.load)();
      if (!mounted) return;
      setState(() {
        _taxonomy = t;
        if (_isEdit) {
          final m = _marketDef;
          if (m != null) {
            for (final f in m.fields) {
              _attrValues[f.key] = f.toFormValue(widget.existing!.attrs[f.key]);
            }
          }
        } else if (_market.isNotEmpty) {
          _applyMarket(_market, keepCategory: true);
        } else {
          _preselectFromBusiness(t);
        }
      });
    } catch (e) {
      debugPrint('[BusinessProductForm] taxonomy: $e');
      if (mounted) setState(() => _taxonomyFailed = true);
    }
  }

  /// Харита объектига янги маҳсулот: фаолият туридан бозор/бўлим таклифи ([marketForBusiness]). Бозор таксономияда
  /// йўқ ёки шу туманда очилмаса — танланмайди (Аралаш). Сотувчи чиплар орқали алмаштира олади. setState ичида.
  void _preselectFromBusiness(MarketTaxonomy t) {
    if (!_showMarketChoice || widget.business.isOwnShop) return;
    final match = marketForBusiness(widget.business.category, widget.business.subtype);
    if (match == null) return;
    final open = openableMarkets(t, widget.isModuleOpenable ?? ServiceConfigHolder.isOpenable);
    if (!open.any((m) => m.id == match.marketId)) return;
    _category = match.categoryId ?? '';
    _applyMarket(match.marketId, keepCategory: true);
  }

  /// Бозор танланди ([id] бўш — Аралаш): бўлим ва нарх бирлиги бозорга мосланади. setState ичида чақирилади.
  void _applyMarket(String id, {bool keepCategory = false}) {
    if (id != _market) _attrValues.clear();
    _market = id;
    _fieldErrors = const {};
    final m = _marketDef;
    if (m == null) {
      _category = '';
      if (id.isEmpty || !_profileUnits.contains(_unit)) _unit = _profile.defaultPriceUnit;
      return;
    }
    if (!keepCategory || m.category(_category) == null) _category = m.autoCategory ?? '';
    if (!m.priceUnits.contains(_unit)) _unit = m.priceUnits.first;
  }

  /// Янги маҳсулот: «Видео (ихтиёрий)» белгиланган — сақлангандан кейин видео экрани дарров очилади.
  bool _wantVideo = false;
  bool _busy = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _desc.dispose();
    _weight.dispose();
    super.dispose();
  }

  Future<List<String>> _defaultPick(int room) async {
    final picked = await ImagePicker().pickMultiImage(imageQuality: 88, limit: room >= 2 ? room : null);
    return [for (final f in picked) f.path];
  }

  Future<void> _pick() async {
    final room = TvShopItem.maxPhotos - _photos.length;
    if (room <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.tr('tv_shop_photos_max'))));
      return;
    }
    final paths = await (widget.pickPhotos ?? _defaultPick)(room);
    if (paths.isEmpty || !mounted) return;
    setState(() => _photos.addAll(paths.take(room)));
  }

  Future<List<String>> _defaultUpload(String phone, List<String> paths) =>
      TvStorageService().uploadShopPhotos(ownerPhone: phone, filePaths: paths);

  Future<void> _defaultAddVideo(BuildContext context, String itemId) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TvPublishScreen(attachItemId: itemId)));

  Future<void> _save() async {
    // Қайта кириш ҳимояси (C-2): бир кадр ичидаги иккинчи босиш иккинчи маҳсулот ёзмасин.
    if (_busy) return;
    final name = _name.text.trim();
    if (name.length < 2) return setState(() => _error = context.tr('bizprod_err_name'));
    final price = parseProductPrice(_price.text);
    if (price == null) return setState(() => _error = context.tr('bizprod_err_price'));
    if (!_isEdit && _photos.isEmpty) return setState(() => _error = context.tr('tv_shop_photo_required'));
    if (_phone.isEmpty) return setState(() => _error = context.tr('bizprod_err_generic'));
    // Тахминий вазн — ихтиёрий; киритилса тўғри бўлиши шарт (хизматда ёзилмайди).
    final int? weightG = _kind == 'product' && _weight.text.trim().isNotEmpty ? parseWeightKgToGrams(_weight.text) : null;
    if (_kind == 'product' && _weight.text.trim().isNotEmpty && weightG == null) {
      return setState(() => _error = context.tr('bizprod_err_weight'));
    }
    // «Бозорлар»: бозор танланган — таксономия, бўлим ва динамик майдонлар текширилади.
    final market = _marketDef;
    if (_market.isNotEmpty && market == null) {
      return setState(() => _error = context.tr('market_err_taxonomy'));
    }
    final category = _effectiveCategory;
    Map<String, Object> attrs = const {};
    if (market != null) {
      if (market.category(category) == null) return setState(() => _error = context.tr('market_err_category'));
      final errors = validateAttrs(market, category, _attrValues);
      if (errors.isNotEmpty) {
        return setState(() {
          _fieldErrors = errors;
          _error = context.tr('market_err_fields');
        });
      }
      attrs = serializeAttrs(market, category, _attrValues);
    }

    setState(() {
      _busy = true;
      _error = null;
      _fieldErrors = const {};
    });
    try {
      String itemId;
      var submitted = !_isEdit; // янги эълон — доим текширувга
      if (_isEdit) {
        itemId = widget.existing!.id;
        final old = widget.existing!;
        final marketChanged = market != null &&
            (old.category != category || !mapEquals(old.attrs, attrs) || (market.hasImported && (old.imported ?? false) != _imported));
        // Таҳрирда статус ЮБОРИЛМАЙДИ (rules: эга фақат сақлайди ёки `deleted`); контент ўзгарса сервер
        // `active`/`expired`ни `pending`га ўтказади (`CONTENT_FIELDS`: title, price, priceUnit, description, …).
        submitted = editResubmitsForModeration(
          widget.existing!,
          title: name,
          price: price,
          description: _desc.text.trim(),
          priceUnit: _unit,
          marketChanged: marketChanged,
        );
        await _repo.updateItem(itemId, {
          // Бозор эълони: бўлим/майдонлар/импорт (бозорнинг ўзи таҳрирда ўзгармайди).
          if (market != null) ...{
            'category': category,
            if (attrs.isNotEmpty) 'attrs': attrs else if (old.attrs.isNotEmpty) 'attrs': FieldValue.delete(),
            if (market.hasImported) 'imported': _imported,
          },
          'title': name,
          'price': price,
          'description': _desc.text.trim(),
          'kind': _kind,
          if (weightG != null)
            'unitWeightG': weightG
          else if (old.unitWeightG != null)
            'unitWeightG': FieldValue.delete(),
          // Белгиланган нарх — майдон ёзилмайди; аввал бирлик бор эди — ўчирилади (эски ҳужжат шакли).
          if (_unit != PriceUnit.fixed)
            'priceUnit': _unit.wire
          else if (widget.existing!.priceUnit != PriceUnit.fixed)
            'priceUnit': FieldValue.delete(),
        });
      } else {
        final urls = await (widget.uploadPhotos ?? _defaultUpload)(_phone, List.of(_photos));
        if (urls.isEmpty) throw StateError('no photos uploaded');
        await _repo.ensureShop(ownerPhone: _phone, name: widget.business.name);
        // Ҳалқалар ва нисбий жой учун эълон туманининг вилояти (фақат бозор эълонида).
        final regionId = market == null
            ? ''
            : await (widget.resolveRegionId ?? resolveRegionIdForDistrict)(widget.business.districtId);
        itemId = await _repo.createItem(TvShopItem(
          id: '',
          ownerPhone: _phone,
          ownerName: widget.business.name,
          title: name,
          price: price,
          photoUrl: urls.first,
          photoUrls: urls,
          kind: _kind,
          districtId: widget.business.districtId,
          // Ўз дўкони (харитасиз): туман номи ҳам ёзилади — лентада кўринади; харита объектида аввалгидек бўш.
          districtLabel: widget.business.isOwnShop ? ServiceConfigHolder.districtLabel.trim() : '',
          description: _desc.text.trim(),
          // «Бозорлар» 2b (эга 2026-11-15): олдиндан модерация — админ тасдиқлагунча бозорда кўринмайди.
          // Сервер (`onShopItemModeration`) ҳам `active`ни `pending`га ўтказади; клиент ўзи ҳам `pending` юборади.
          status: 'pending',
          businessId: widget.business.id,
          priceUnit: _unit,
          market: market?.id ?? '',
          category: market == null ? '' : category,
          attrs: attrs,
          imported: (market?.hasImported ?? false) ? _imported : null,
          regionId: regionId,
          taxonomyVersion: market == null ? 0 : (_taxonomy?.version ?? 0),
          unitWeightG: weightG,
        ));
      }
      if (!mounted) return;
      // Ҳужжат ёзилди: спиннер тўхтайди (видео сўрови очиқ турганда ҳам «банд» кўринмасин).
      setState(() => _busy = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        key: ValueKey(submitted ? 'bizprod_snack_submitted' : 'bizprod_snack_saved'),
        content: Text(context.tr(submitted ? 'listing_mod_submitted' : 'bizprod_saved')),
      ));
      // Видео формадаги ягона жойда танланади (эга, 2026-10-26) — аввалги «Видео қўшасизми?» ойнаси йўқ.
      if (!_isEdit && _wantVideo) await (widget.addVideo ?? _defaultAddVideo)(context, itemId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      debugPrint('[BusinessProductForm] save: $e');
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = context.tr('bizprod_err_generic');
      });
    }
  }

  /// Видео — расмлардан кейин, ЯГОНА жойда (эга, 2026-10-26: «расм ва видео жойлаштириш битта жойда бўлгани
  /// яхши», «дубликат бўлмасин»). Янги маҳсулотда — белгилаш (ҳужжат ҳали йўқ, видео сақлангандан кейин уланади);
  /// таҳрирда — видео экрани дарров очилади. Аввалги «Видео қўшасизми?» ойнаси ва алоҳида тугма олиб ташланди.
  Widget _videoSection() {
    final hasVideo = widget.existing?.hasVideo ?? false;
    final selected = !_isEdit && _wantVideo;
    final c = AppColors.primaryDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(context.tr('bizprod_video_label'), style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        if (hasVideo)
          Row(children: [
            Icon(Icons.check_circle_rounded, color: c, size: 20),
            const SizedBox(width: 6),
            Text(context.tr('bizprod_has_video')),
          ])
        else
          InkWell(
            key: const ValueKey('bizprod_video_tile'),
            onTap: _busy
                ? null
                : () => _isEdit
                    ? (widget.addVideo ?? _defaultAddVideo)(context, widget.existing!.id)
                    : setState(() => _wantVideo = !_wantVideo),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(
                border: Border.all(color: selected ? c : Colors.grey.shade400, width: selected ? 2 : 1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(selected ? Icons.check_circle_rounded : Icons.videocam_outlined, color: selected ? c : null),
                  const SizedBox(height: 4),
                  Text(context.tr('bizprod_video_add'), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                ],
              ),
            ),
          ),
        if (selected)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              context.tr('bizprod_video_after_save'),
              key: const ValueKey('bizprod_video_after_save'),
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ),
      ],
    );
  }

  /// Нарх майдони остида харидор кўрадиган кўриниш («50 000 сўм / соат», «Келишилади»). Белгиланган нархда ва
  /// кўрсатиладиган нарх йўқ бўлса — `null` (ортиқча матн йўқ).
  String? _pricePreview() {
    if (_unit == PriceUnit.fixed) return null;
    final price = parseProductPrice(_price.text) ?? 0;
    final s = formatOfferPrice(price, _unit, context.tr);
    return s.isEmpty ? null : s;
  }

  /// Нарх бирлиги — тур профилидаги рўйхат (чиплар). «Келишилади»да нарх бўш қолиши мумкин (майдон ихтиёрий).
  Widget _unitSection() {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(context.tr('price_unit_label'), style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Wrap(
            key: const ValueKey('bizprod_unit'),
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final u in _units)
                ChoiceChip(
                  key: ValueKey('bizprod_unit_${u.name}'),
                  label: Text(context.tr(u.labelKey)),
                  selected: _unit == u,
                  showCheckmark: false,
                  onSelected: _busy ? null : (_) => setState(() => _unit = u),
                  selectedColor: c.brandSoft,
                  backgroundColor: c.chip,
                  side: BorderSide(color: _unit == u ? c.brand : c.line, width: _unit == u ? 1.5 : 1),
                  labelStyle: TextStyle(
                    fontSize: 13,
                    color: c.ink,
                    fontWeight: _unit == u ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// Форма тепаси: таксономия юкланиши/хатоси, «Қаерда сотасиз?» ва бўлим чиплари.
  List<Widget> _marketHeader() {
    if (!_needsTaxonomy) return const [];
    if (_taxonomyFailed) {
      return [
        Row(
          key: const ValueKey('market_tax_error'),
          children: [
            Expanded(child: Text(context.tr('market_err_taxonomy'), style: TextStyle(color: Colors.red.shade700))),
            TextButton(
              key: const ValueKey('market_tax_retry'),
              onPressed: _busy ? null : _loadTaxonomy,
              child: Text(context.tr('err_retry')),
            ),
          ],
        ),
        const SizedBox(height: 12),
      ];
    }
    final t = _taxonomy;
    if (t == null) return const [LinearProgressIndicator(key: ValueKey('market_tax_loading')), SizedBox(height: 12)];
    final out = <Widget>[];
    if (_showMarketChoice) {
      final markets = openableMarkets(t, widget.isModuleOpenable ?? ServiceConfigHolder.isOpenable);
      // Бирорта бозор очиқ бўлмаса — чиплар йўқ (аввалги Аралаш формаси).
      if (markets.isNotEmpty) {
        out
          ..add(MarketChoiceChips(
            markets: markets,
            selected: _market,
            enabled: !_busy,
            onChanged: (id) => setState(() => _applyMarket(id)),
          ))
          ..add(const SizedBox(height: 12));
      }
    }
    final m = _marketDef;
    if (m != null && m.hasCategoryChoice) {
      out
        ..add(MarketCategoryChips(
          market: m,
          selected: _category,
          enabled: !_busy,
          onChanged: (c) => setState(() {
            _category = c;
            _fieldErrors = const {};
          }),
        ))
        ..add(const SizedBox(height: 12));
    }
    return out;
  }

  /// Нархдан кейин: «Импорт» (Гўшт) ва бўлим майдонлари (таксономиядан).
  List<Widget> _marketBody() {
    final m = _marketDef;
    if (m == null) return const [];
    final category = _effectiveCategory;
    return [
      if (m.hasImported)
        CheckboxListTile(
          key: const ValueKey('market_imported'),
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          value: _imported,
          title: Text(context.tr('market_imported')),
          onChanged: _busy ? null : (v) => setState(() => _imported = v == true),
        ),
      if (m.category(category) != null)
        MarketFieldsEditor(
          key: ValueKey('market_fields_${m.id}_$category'),
          fields: m.fieldsFor(category),
          values: _attrValues,
          errors: _fieldErrors,
          enabled: !_busy,
          onChanged: (k, v) => setState(() {
            _attrValues[k] = v;
            if (_fieldErrors.containsKey(k)) _fieldErrors = {..._fieldErrors}..remove(k);
          }),
        ),
    ];
  }

  Widget _thumb(String path) {
    Widget broken(BuildContext _, Object __, StackTrace? ___) => const ColoredBox(color: Color(0x11000000), child: Icon(Icons.broken_image_outlined));
    final img = kIsWeb
        ? Image.network(path, fit: BoxFit.cover, errorBuilder: broken)
        : Image.file(File(path), fit: BoxFit.cover, errorBuilder: broken);
    return ClipRRect(borderRadius: BorderRadius.circular(8), child: img);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr(_isEdit ? 'bizprod_edit' : (_showKindChoice ? 'bizprod_new' : 'bizprod_new_product'))),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ..._marketHeader(),
          if (_showKindChoice) ...[
            SegmentedButton<String>(
              key: const ValueKey('bizprod_kind'),
              segments: [
                ButtonSegment(value: 'product', label: Text(context.tr('bizprod_kind_product'))),
                ButtonSegment(value: 'service', label: Text(context.tr('bizprod_kind_service'))),
              ],
              selected: {_kind},
              onSelectionChanged: _busy ? null : (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            key: const ValueKey('bizprod_name'),
            controller: _name,
            enabled: !_busy,
            maxLength: 120,
            decoration: InputDecoration(labelText: context.tr('bizprod_f_name'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 4),
          TextField(
            key: const ValueKey('bizprod_price'),
            controller: _price,
            enabled: !_busy,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 ]'))],
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: context.tr('bizprod_f_price'),
              border: const OutlineInputBorder(),
              helperText: _pricePreview(),
            ),
          ),
          if (_units.length > 1) _unitSection(),
          if (_kind == 'product') ...[
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('bizprod_weight'),
              controller: _weight,
              enabled: !_busy,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
              decoration: InputDecoration(
                labelText: context.tr('bizprod_f_weight'),
                helperText: context.tr('bizprod_weight_help'),
                border: const OutlineInputBorder(),
              ),
            ),
          ],
          ..._marketBody(),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('bizprod_desc'),
            controller: _desc,
            enabled: !_busy,
            maxLines: 4,
            maxLength: 1000,
            decoration: InputDecoration(labelText: context.tr('bizprod_f_desc'), border: const OutlineInputBorder()),
          ),
          const SizedBox(height: 8),
          if (_isEdit) ...[
            OutlinedButton.icon(
              key: const ValueKey('bizprod_edit_photos'),
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute<void>(builder: (_) => TvShopItemPhotosScreen(item: widget.existing!)),
                      ),
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(context.tr('bizprod_edit_photos')),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ] else ...[
            Text('${context.tr('bizprod_photos')} ${_photos.length}/${TvShopItem.maxPhotos}',
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var i = 0; i < _photos.length; i++)
                  SizedBox(
                    width: 84,
                    height: 84,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _thumb(_photos[i]),
                        Positioned(
                          top: 2,
                          right: 2,
                          child: InkWell(
                            key: ValueKey('bizprod_photo_remove_$i'),
                            onTap: _busy ? null : () => setState(() => _photos.removeAt(i)),
                            child: const CircleAvatar(
                              radius: 11,
                              backgroundColor: Colors.black54,
                              child: Icon(Icons.close, size: 14, color: Colors.white),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (_photos.length < TvShopItem.maxPhotos)
                  InkWell(
                    key: const ValueKey('bizprod_add_photos'),
                    onTap: _busy ? null : _pick,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 84,
                      height: 84,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.add_a_photo_outlined),
                          const SizedBox(height: 4),
                          Text(context.tr('bizprod_add_photos'),
                              textAlign: TextAlign.center, style: const TextStyle(fontSize: 11)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          _videoSection(),
          // «Акция» (эга 2026-11-19): фақат сақланган товарда.
          if (_isEdit) ProductPromoTile(collection: 'tv_shop_items', docId: widget.existing!.id),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ),
          FilledButton(
            key: const ValueKey('bizprod_save'),
            onPressed: _busy ? null : _save,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primaryDark,
              foregroundColor: AppColors.onPrimary,
              minimumSize: const Size.fromHeight(50),
            ),
            child: _busy
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(context.tr('bizmap_save')),
          ),
        ],
      ),
    );
  }
}
