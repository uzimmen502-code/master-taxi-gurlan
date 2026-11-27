import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/utils/formatters.dart';
import '../../repositories/service_config_repository.dart';
import 'splash_ad.dart';
import 'splash_ad_purchase_service.dart';

/// Ҳудуд манбаи (тестда сохтаси): вилоятлар ва вилоят туманлари, фойдаланувчи тилида.
abstract class SplashAreaSource {
  Future<List<({String id, String name})>> regions(String lang);
  Future<List<({String id, String name})>> districts(String regionId, String lang);
}

class GeoSplashAreaSource implements SplashAreaSource {
  GeoSplashAreaSource([ServiceConfigRepository? repo]) : _repo = repo ?? ServiceConfigRepository();
  final ServiceConfigRepository _repo;

  @override
  Future<List<({String id, String name})>> regions(String lang) async =>
      [for (final r in await _repo.fetchRegions()) (id: r.id, name: r.nameFor(lang))];

  @override
  Future<List<({String id, String name})>> districts(String regionId, String lang) async =>
      [for (final d in await _repo.fetchDistricts(regionId)) (id: d.id, name: d.nameFor(lang))];
}

/// Пуллик splash матнлари (3 тил; янги лотин: ö ğ ş ç).
class SplashBuyTexts {
  const SplashBuyTexts._();

  static const Map<String, List<String>> _t = {
    'title': ['Реклама бериш', 'Reklama beriş', 'Разместить рекламу'],
    'myAds': ['Менинг рекламаларим', 'Mening reklamalarim', 'Мои рекламы'],
    'intro': [
      'Илова очилганда 2 сония кўринади. Кўп тўлаганлар кўпроқ кўрсатилади.',
      'Ilova oçilganda 2 soniya körinadi. Köp tölaganlar köproq körsatiladi.',
      'Показывается 2 секунды при запуске приложения. Чем выше оплата, тем чаще показ.',
    ],
    'duration': ['Муддат', 'Muddat', 'Срок'],
    'days': ['{n} кун', '{n} kun', '{n} дн.'],
    'start': ['Бошланиш санаси', 'Boşlaniş sanasi', 'Дата начала'],
    'area': ['Ҳудуд', 'Hudud', 'Регион показа'],
    'district': ['Туман(лар)', 'Tuman(lar)', 'Район(ы)'],
    'region': ['Бутун вилоят', 'Butun viloyat', 'Вся область'],
    'republic': ['Бутун республика', 'Butun respublika', 'Вся республика'],
    'regionPick': ['Вилоят', 'Viloyat', 'Область'],
    'pickDistricts': ['Туманларни танланг (энг кўпи {n})', 'Tumanlarni tanlang (eng köpi {n})', 'Выберите районы (не более {n})'],
    'districtsN': ['{n} туман', '{n} tuman', 'районов: {n}'],
    'imageTitle': ['Расм', 'Rasm', 'Изображение'],
    'image': ['Расм танлаш', 'Rasm tanlaş', 'Выбрать изображение'],
    'imageRemove': ['Расмсиз', 'Rasmsiz', 'Без изображения'],
    'text': ['Матн (ихтиёрий, 140 белги)', 'Matn (ixtiyoriy, 140 belgi)', 'Текст (необязательно, 140 символов)'],
    'link': ['Ҳавола (ихтиёрий, https://…)', 'Havola (ixtiyoriy, https://…)', 'Ссылка (необязательно, https://…)'],
    'perDay': ['Кунлик нарх', 'Kunlik narx', 'Цена за день'],
    'quote': ['Нархни ҳисоблаш', 'Narxni hisoblaş', 'Рассчитать цену'],
    'confirm': ['Тўловни тасдиқланг', 'Tölovni tasdiqlang', 'Подтвердите оплату'],
    'total': ['Жами', 'Jami', 'Итого'],
    'balance': ['Ҳамёнда', 'Hamyonda', 'В кошельке'],
    'pay': ['Ҳамёндан тўлаш', 'Hamyondan tölaş', 'Оплатить из кошелька'],
    'cancel': ['Бекор', 'Bekor', 'Отмена'],
    'insufficient': [
      'Ҳамёнда маблағ етарли эмас. Ҳамённи тўлдиринг.',
      'Hamyonda mablağ yetarli emas. Hamyonni töldiring.',
      'Недостаточно средств в кошельке. Пополните кошелёк.',
    ],
    'moderation': [
      'Тўловдан кейин реклама модерациядан ўтади. Рад этилса, пул тўлиқ қайтарилади.',
      'Tölovdan keyin reklama moderatsiyadan ötadi. Rad etilsa, pul töliq qaytariladi.',
      'После оплаты реклама проходит модерацию. При отказе деньги возвращаются полностью.',
    ],
    'paid': ['Тўланди. Реклама модерацияда.', 'Tölandi. Reklama moderatsiyada.', 'Оплачено. Реклама на модерации.'],
    'needContent': ['Расм ёки матн киритинг.', 'Rasm yoki matn kiriting.', 'Добавьте изображение или текст.'],
    'needArea': ['Ҳудудни танланг.', 'Hududni tanlang.', 'Выберите регион.'],
    'badLink': ['Ҳавола https:// билан бошлансин.', 'Havola https:// bilan boşlansin.', 'Ссылка должна начинаться с https://.'],
    'uploadFailed': [
      'Расм юкланмади. Қайта уриниб кўринг.',
      'Rasm yuklanmadi. Qayta urinib köring.',
      'Не удалось загрузить изображение. Попробуйте ещё раз.',
    ],
    'error': ['Амал бажарилмади. Қайта уриниб кўринг.', 'Amal bajarilmadi. Qayta urinib köring.', 'Не удалось выполнить. Попробуйте ещё раз.'],
    'notAvailable': [
      'Реклама сотиб олиш ҳозирча мавжуд эмас. Админ билан боғланинг.',
      'Reklama sotib oliş hozirça mavjud emas. Admin bilan boğlaning.',
      'Покупка рекламы пока недоступна. Свяжитесь с админом.',
    ],
    'adminChat': ['Админ билан чат', 'Admin bilan çat', 'Чат с админом'],
    'pending': ['Модерацияда', 'Moderatsiyada', 'На модерации'],
    'active': ['Кўрсатилмоқда', 'Körsatilmoqda', 'Показывается'],
    'scheduled': ['Бошланишини кутмоқда', 'Boşlanişini kutmoqda', 'Ожидает начала'],
    'ended': ['Тугаган', 'Tugagan', 'Завершена'],
    'rejected': ['Рад этилди', 'Rad etildi', 'Отклонена'],
    'impressions': ['Кўрсатишлар', 'Körsatişlar', 'Показы'],
    'refunded': ['Қайтарилди', 'Qaytarildi', 'Возвращено'],
    'reason': ['Сабаб', 'Sabab', 'Причина'],
    'empty': ['Ҳали реклама йўқ.', 'Hali reklama yöq.', 'Пока нет рекламы.'],
    'newAd': ['Янги реклама', 'Yangi reklama', 'Новая реклама'],
    'loadFailed': ['Юклаб бўлмади. Қайта уриниб кўринг.', 'Yuklab bölmadi. Qayta urinib köring.', 'Не удалось загрузить. Попробуйте ещё раз.'],
    'retry': ['Қайта уриниш', 'Qayta uriniş', 'Повторить'],
  };

  static String of(String key, String lang, {Object? n}) {
    final v = _t[key]!;
    final s = v[lang == 'uz_Latn' ? 1 : lang == 'ru' ? 2 : 0];
    return n == null ? s : s.replaceAll('{n}', '$n');
  }
}

String _dayKey(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

DateTime _parseDay(String s) {
  final p = s.split('-').map(int.tryParse).toList();
  if (p.length == 3 && p.every((x) => x != null)) return DateTime(p[0]!, p[1]!, p[2]!);
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day);
}

/// «Реклама бериш» — пуллик splash харид оқими (эга 2026-11-28): муддат → сана → ҳудуд → креатив →
/// сервер нархи → ҳамёндан тўлов → модерация.
class SplashAdPurchaseScreen extends StatefulWidget {
  const SplashAdPurchaseScreen({
    super.key,
    required this.ownerPhone,
    this.service,
    this.areas,
    this.initialRegionId = '',
    this.initialDistrictId = '',
    this.pickImage,
    this.onAdminChat,
    this.myAdsBuilder,
  });

  /// Канон телефон (998…) — расм `ads/{телефон}/` га юкланади.
  final String ownerPhone;
  final SplashAdPurchaseService? service;
  final SplashAreaSource? areas;
  final String initialRegionId;
  final String initialDistrictId;
  final Future<XFile?> Function()? pickImage;

  /// Харид ёпиқ бўлса — мавжуд «Админ билан чат» йўли.
  final VoidCallback? onAdminChat;
  final WidgetBuilder? myAdsBuilder;

  static const quoteKey = Key('splash-buy-quote');
  static const payKey = Key('splash-buy-pay');
  static const textKey = Key('splash-buy-text');
  static const creativeSpecKey = Key('splash-buy-creative-spec');

  @override
  State<SplashAdPurchaseScreen> createState() => _SplashAdPurchaseScreenState();
}

class _SplashAdPurchaseScreenState extends State<SplashAdPurchaseScreen> {
  late final SplashAdPurchaseService _svc = widget.service ?? SplashAdPurchaseService();
  late final SplashAreaSource _areas = widget.areas ?? GeoSplashAreaSource();

  /// Экран сессиясида БИТТА — тармоқ узилиб қайта юборилса, сервер қайта ечмайди.
  final String _clientRequestId = const Uuid().v4().replaceAll('-', '');
  final _text = TextEditingController();
  final _link = TextEditingController();

  SplashAdPurchaseInfo? _info;
  bool _loadFailed = false;
  bool _busy = false;
  int _days = 1;
  DateTime _start = DateTime.now();
  String _level = 'district';
  late String _regionId = widget.initialRegionId;
  final Set<String> _districts = {};
  List<({String id, String name})> _regions = const [];
  final Map<String, List<({String id, String name})>> _districtsByRegion = {};
  XFile? _image;
  Uint8List? _imageBytes;
  String _uploadedUrl = '';

  String get _lang => context.contentLang;
  String _t(String k, {Object? n}) => SplashBuyTexts.of(k, _lang, n: n);

  @override
  void initState() {
    super.initState();
    if (widget.initialDistrictId.isNotEmpty) _districts.add(widget.initialDistrictId);
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _text.dispose();
    _link.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadFailed = false);
    try {
      final info = await _svc.getInfo();
      if (!mounted) return;
      setState(() {
        _info = info;
        _days = info.durations.isNotEmpty ? info.durations.first : 1;
        if (info.today.isNotEmpty) _start = _parseDay(info.today);
      });
      if (!info.available) return;
      final regions = await _areas.regions(_lang);
      if (!mounted) return;
      setState(() => _regions = regions);
      if (_regionId.isNotEmpty) await _ensureDistricts(_regionId);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  Future<void> _ensureDistricts(String regionId) async {
    if (regionId.isEmpty || _districtsByRegion.containsKey(regionId)) return;
    try {
      final list = await _areas.districts(regionId, _lang);
      if (mounted) setState(() => _districtsByRegion[regionId] = list);
    } catch (_) {}
  }

  Future<void> _pick() async {
    final f = widget.pickImage != null
        ? await widget.pickImage!()
        : await ImagePicker().pickImage(source: ImageSource.gallery, maxWidth: 1440, imageQuality: 80);
    if (f == null) return;
    final bytes = await f.readAsBytes();
    if (!mounted) return;
    setState(() {
      _image = f;
      _imageBytes = bytes;
      _uploadedUrl = '';
    });
  }

  void _snack(String s) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s)));

  /// Клиент текшируви — фақат UX учун (сервер барибир текширади).
  String? _validate() {
    if (_image == null && _text.text.trim().isEmpty) return _t('needContent');
    if (_level == 'district' && _districts.isEmpty) return _t('needArea');
    if (_level == 'region' && _regionId.isEmpty) return _t('needArea');
    final link = _link.text.trim();
    if (link.isNotEmpty && !link.startsWith('https://')) return _t('badLink');
    return null;
  }

  Future<SplashAdPurchaseRequest?> _request() async {
    if (_image != null && _uploadedUrl.isEmpty) {
      try {
        _uploadedUrl = await _svc.uploadImage(ownerPhone: widget.ownerPhone, image: _image!);
      } catch (_) {
        _snack(_t('uploadFailed'));
        return null;
      }
    }
    return SplashAdPurchaseRequest(
      clientRequestId: _clientRequestId,
      days: _days,
      startDay: _dayKey(_start),
      areaLevel: _level,
      districts: _districts.toList()..sort(),
      regionId: _regionId,
      imageUrl: _image == null ? '' : _uploadedUrl,
      text: _text.text.trim(),
      linkUrl: _link.text.trim(),
    );
  }

  Future<void> _quoteAndPay() async {
    final err = _validate();
    if (err != null) {
      _snack(err);
      return;
    }
    setState(() => _busy = true);
    try {
      final req = await _request();
      if (req == null) return;
      var q = await _svc.quote(req);
      while (mounted) {
        setState(() => _busy = false); // диалог орқасида айланувчи белги йўқ
        final ok = await _confirm(q);
        if (ok != true || !mounted) return;
        setState(() => _busy = true);
        try {
          await _svc.purchase(req, expectedAmount: q.amount);
          if (!mounted) return;
          _snack(_t('paid'));
          await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
            builder: widget.myAdsBuilder ?? (_) => MySplashAdsScreen(service: _svc),
          ));
          return;
        } on SplashAdPurchaseError catch (e) {
          if (e.code != 'PRICE_CHANGED') rethrow;
          q = await _svc.quote(req); // нарх ўзгарди — янги нархни қайта кўрсатиш
        }
      }
    } on SplashAdPurchaseError catch (e) {
      if (mounted) _snack(e.messageFor(_lang, _t('error')));
    } catch (_) {
      if (mounted) _snack(_t('error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm(SplashAdQuote q) => showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(_t('confirm')),
          content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${_t('perDay')}: ${formatMoney(q.pricePerDay)} × ${_t('days', n: _days)}'),
            const SizedBox(height: 6),
            Text('${_t('total')}: ${formatMoney(q.amount)}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
            Text('${_t('balance')}: ${formatMoney(q.balance)}'),
            const SizedBox(height: 10),
            if (!q.sufficient)
              Text(_t('insufficient'), style: TextStyle(color: Theme.of(c).colorScheme.error))
            else
              Text(_t('moderation'), style: const TextStyle(fontSize: 12)),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: Text(_t('cancel'))),
            FilledButton(
              key: SplashAdPurchaseScreen.payKey,
              onPressed: q.sufficient ? () => Navigator.pop(c, true) : null,
              child: Text(_t('pay')),
            ),
          ],
        ),
      );

  Future<void> _pickDate() async {
    final info = _info!;
    final first = info.today.isNotEmpty ? _parseDay(info.today) : DateTime.now();
    final d = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: first,
      lastDate: first.add(Duration(days: info.maxStartAheadDays)),
    );
    if (d != null) setState(() => _start = d);
  }

  Widget _section(String title, Widget child) => Padding(
        padding: const EdgeInsets.only(top: 16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          child,
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final info = _info;
    return Scaffold(
      appBar: AppBar(
        title: Text(_t('title')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: widget.myAdsBuilder ?? (_) => MySplashAdsScreen(service: _svc),
            )),
            child: Text(_t('myAds')),
          ),
        ],
      ),
      body: info == null
          ? Center(
              child: _loadFailed
                  ? Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_t('loadFailed')),
                      TextButton(onPressed: _load, child: Text(_t('retry'))),
                    ])
                  : const CircularProgressIndicator(),
            )
          : !info.available
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text(_t('notAvailable'), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      if (widget.onAdminChat != null)
                        FilledButton.icon(
                          onPressed: widget.onAdminChat,
                          icon: const Icon(Icons.chat_outlined),
                          label: Text(_t('adminChat')),
                        ),
                    ]),
                  ),
                )
              : _form(info),
    );
  }

  Widget _form(SplashAdPurchaseInfo info) {
    final districts = _districtsByRegion[_regionId] ?? const [];
    final perDay = info.perDay[_level];
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(_t('intro'), style: TextStyle(color: Theme.of(context).hintColor)),
        _section(
          _t('duration'),
          Wrap(spacing: 8, children: [
            for (final d in info.durations)
              ChoiceChip(label: Text(_t('days', n: d)), selected: _days == d, onSelected: (_) => setState(() => _days = d)),
          ]),
        ),
        _section(
          _t('start'),
          OutlinedButton.icon(onPressed: _pickDate, icon: const Icon(Icons.event), label: Text(_dayKey(_start))),
        ),
        _section(
          _t('area'),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Wrap(spacing: 8, children: [
              for (final l in const ['district', 'region', 'republic'])
                ChoiceChip(label: Text(_t(l)), selected: _level == l, onSelected: (_) => setState(() => _level = l)),
            ]),
            if (_level != 'republic') ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                key: ValueKey('splash-region-${_regions.length}-$_regionId'),
                initialValue: _regions.any((r) => r.id == _regionId) ? _regionId : null,
                decoration: InputDecoration(labelText: _t('regionPick'), border: const OutlineInputBorder(), isDense: true),
                items: [for (final r in _regions) DropdownMenuItem(value: r.id, child: Text(r.name))],
                onChanged: (id) {
                  setState(() {
                    _regionId = id ?? '';
                    _districts.clear();
                  });
                  _ensureDistricts(_regionId);
                },
              ),
            ],
            if (_level == 'district' && districts.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_t('pickDistricts', n: info.maxDistricts), style: const TextStyle(fontSize: 12)),
              Wrap(spacing: 6, runSpacing: 4, children: [
                for (final d in districts)
                  FilterChip(
                    label: Text(d.name),
                    selected: _districts.contains(d.id),
                    onSelected: (on) => setState(() {
                      if (!on) {
                        _districts.remove(d.id);
                      } else if (_districts.length < info.maxDistricts) {
                        _districts.add(d.id);
                      }
                    }),
                  ),
              ]),
            ],
            if (perDay != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  '${_t('perDay')}: ${formatMoney(perDay)}'
                  '${_level == 'district' ? ' × ${_t('districtsN', n: _districts.length)}' : ''}',
                ),
              ),
          ]),
        ),
        _section(
          _t('imageTitle'),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
              SplashAdTexts.creativeSpec(_lang),
              key: SplashAdPurchaseScreen.creativeSpecKey,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 8),
            Row(children: [
            if (_imageBytes != null)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(_imageBytes!, height: 96, fit: BoxFit.cover),
                ),
              ),
            OutlinedButton.icon(onPressed: _busy ? null : _pick, icon: const Icon(Icons.image_outlined), label: Text(_t('image'))),
            if (_imageBytes != null)
              TextButton(
                onPressed: _busy
                    ? null
                    : () => setState(() {
                          _image = null;
                          _imageBytes = null;
                          _uploadedUrl = '';
                        }),
                child: Text(_t('imageRemove')),
              ),
            ]),
          ]),
        ),
        const SizedBox(height: 12),
        TextField(
          key: SplashAdPurchaseScreen.textKey,
          controller: _text,
          maxLength: 140,
          decoration: InputDecoration(labelText: _t('text'), border: const OutlineInputBorder()),
        ),
        TextField(
          controller: _link,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(labelText: _t('link'), border: const OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        FilledButton(
          key: SplashAdPurchaseScreen.quoteKey,
          onPressed: _busy ? null : _quoteAndPay,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(_t('quote')),
          ),
        ),
      ],
    );
  }
}

/// Кўрсатиладиган ҳолат (сана бўйича, Тошкент куни): pending / scheduled / active / ended / rejected.
class MySplashAdsScreenStatus {
  const MySplashAdsScreenStatus._();

  static String of(SplashAdOrderView o, String today) {
    if (o.status == 'rejected') return 'rejected';
    if (o.status != 'approved') return 'pending';
    if (o.endDay.compareTo(today) < 0) return 'ended';
    if (o.startDay.compareTo(today) > 0) return 'scheduled';
    return 'active';
  }
}

/// «Менинг рекламаларим»: ҳолат, саналар, кўрсатишлар.
class MySplashAdsScreen extends StatefulWidget {
  const MySplashAdsScreen({super.key, this.service, this.now});

  final SplashAdPurchaseService? service;
  final DateTime Function()? now;

  @override
  State<MySplashAdsScreen> createState() => _MySplashAdsScreenState();
}

class _MySplashAdsScreenState extends State<MySplashAdsScreen> {
  late final SplashAdPurchaseService _svc = widget.service ?? SplashAdPurchaseService();
  late Future<List<SplashAdOrderView>> _f = _svc.myOrders();


  @override
  Widget build(BuildContext context) {
    final lang = context.contentLang;
    String t(String k, {Object? n}) => SplashBuyTexts.of(k, lang, n: n);
    final now = (widget.now ?? DateTime.now)();
    final today = now.toUtc().add(const Duration(hours: 5)).toIso8601String().substring(0, 10);
    return Scaffold(
      appBar: AppBar(title: Text(t('myAds'))),
      body: FutureBuilder<List<SplashAdOrderView>>(
        future: _f,
        builder: (context, s) {
          if (s.hasError) {
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(t('loadFailed')),
                TextButton(onPressed: () => setState(() => _f = _svc.myOrders()), child: Text(t('retry'))),
              ]),
            );
          }
          if (!s.hasData) return const Center(child: CircularProgressIndicator());
          final list = s.data!;
          if (list.isEmpty) return Center(child: Text(t('empty')));
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final o = list[i];
              final st = MySplashAdsScreenStatus.of(o, today);
              final area = o.areaLevel == 'district' ? t('districtsN', n: o.districtCount) : t(o.areaLevel == 'region' ? 'region' : 'republic');
              final color = switch (st) {
                'active' => Colors.green,
                'rejected' => Theme.of(context).colorScheme.error,
                'ended' => Colors.grey,
                _ => Colors.orange,
              };
              return Card(
                child: ListTile(
                  leading: o.imageUrl.isNotEmpty
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(o.imageUrl, width: 52, height: 52, fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Icon(Icons.campaign_outlined)),
                        )
                      : const Icon(Icons.campaign_outlined, size: 36),
                  title: Text(t(st), style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                  subtitle: Text([
                    '${o.startDay} → ${o.endDay} · ${t('days', n: o.days)} · $area',
                    '${formatMoney(o.amount)} · ${t('impressions')}: ${o.impressions}',
                    if (st == 'rejected') '${t('reason')}: ${o.rejectReason} · ${t('refunded')}: ${formatMoney(o.refundWallet)}',
                  ].join('\n')),
                  isThreeLine: true,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
