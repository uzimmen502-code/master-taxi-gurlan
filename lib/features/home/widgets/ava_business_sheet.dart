import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../models/driver_roles.dart';
import '../../../models/service_module_config.dart';
import '../../../repositories/courier_capability_repository.dart';
import '../../my_shop/widgets/shop_name_dialog.dart';

/// «＋» — «Менинг бизнесим»: фойдаланувчи ўз ишини шу ердан бошлайди.
///
/// Тартиб (эга, 2026-10-16 + харита банди 2026-10-23): харита · видео · эълон ·
/// хизмат · онлайн дўкон · ҳайдовчи · курьер · юк ташувчи · уй ошпази ·
/// кафе/ресторан · китоб · AI.
enum AvaCreateAction {
  video,
  ad,
  service,
  shopOnline,
  businessMap,
  driver,
  courier,
  homeCook,
  cafe,
  cargo,
  book,
  assistant,
}

/// «Онлайн Дўкон очиш» ичидаги танлов: маҳсулот қаерга қўшилади.
enum AvaShopTarget { retail, wholesale }

/// Банд кўринади, лекин очилмайди (эга, 2026-10-30, Q-1: «кўринсин-у босилмасин»).
enum AvaRowLock {
  /// Модул «Тез кунда» / «Ҳамкорлик» — хабари `HomeModuleGate.onTapBlocked`.
  soon,

  /// Вебда ишламайди (видео юклаш) — «фақат иловада» (эга, 2026-10-30, Q-2).
  appOnly,
}

/// Ҳар банднинг модул дарвозаси — хизматлар каталоги билан БИР манба
/// (`ServiceConfigHolder` ҳолати). Ҳайдовчи (турларни Иш панели ўзи текширади)
/// ва китоб (модули йўқ) — дарвозасиз. Дўкон: Аҳоли ёки Улгуржи бозоридан бири.
const Map<AvaCreateAction, List<String>> kAvaCreateModules = {
  AvaCreateAction.businessMap: ['business_map'],
  AvaCreateAction.video: ['tv_market'],
  AvaCreateAction.ad: ['jobs'],
  AvaCreateAction.service: ['jobs'],
  AvaCreateAction.shopOnline: ['cheap_products_home', 'wholesale_market'],
  AvaCreateAction.courier: ['courier'],
  AvaCreateAction.cargo: ['yuk_local'],
  AvaCreateAction.homeCook: ['restaurants'],
  AvaCreateAction.cafe: ['restaurants'],
  AvaCreateAction.assistant: ['chatgpt'],
};

/// «＋» бандларининг ҳолати: [hidden] — кўрсатилмайди; [locked] — кўринади,
/// босилса очилмайди; [blockedModule] — «Тез кунда» хабари учун модул ID.
class AvaCreateGates {
  const AvaCreateGates({
    this.hidden = const {},
    this.locked = const {},
    this.blockedModule = const {},
  });

  final Set<AvaCreateAction> hidden;
  final Map<AvaCreateAction, AvaRowLock> locked;
  final Map<AvaCreateAction, String> blockedModule;

  /// Соф ҳисоб (тест учун). [statusOf] — `ServiceConfigHolder.statusOf`.
  /// [hasShop] — эгаси бор дўкон доим очилади (ўз маҳсулотини бошқариши/ўчириши керак).
  factory AvaCreateGates.compute({
    required ModuleStatus Function(String moduleId) statusOf,
    required bool isWeb,
    bool hasShop = false,
  }) {
    final hidden = <AvaCreateAction>{};
    final locked = <AvaCreateAction, AvaRowLock>{};
    final blocked = <AvaCreateAction, String>{};
    kAvaCreateModules.forEach((action, ids) {
      if (action == AvaCreateAction.shopOnline && hasShop) return;
      final statuses = [for (final id in ids) statusOf(id)];
      if (statuses.any((s) => s.isOpenable)) return;
      final visibleAt = statuses.indexWhere((s) => s.isVisible);
      if (visibleAt < 0) {
        hidden.add(action);
      } else {
        locked[action] = AvaRowLock.soon;
        blocked[action] = ids[visibleAt];
      }
    });
    if (isWeb &&
        !hidden.contains(AvaCreateAction.video) &&
        !locked.containsKey(AvaCreateAction.video)) {
      locked[AvaCreateAction.video] = AvaRowLock.appOnly;
    }
    return AvaCreateGates(hidden: hidden, locked: locked, blockedModule: blocked);
  }
}

/// Танланган амални қайтаради; бекор қилинса `null`.
///
/// [driverRoles] — ҳайдовчи/курьер бўлса «…бўлиш» ўрнига «…панели» ва фаол
/// турда «Фаол» белгиси чиқади. [hidden] — модули яширин бўлган бандлар
/// (масалан, кафе-ресторан `hidden` бўлса «Уй ошпази» ва «Кафе» кўринмайди).
/// [locked] — кўринади, хира ва белгили; танланса ҳам амал қайтади —
/// чақирувчи очмайди, сабабини айтади ([AvaCreateGates]).
Future<AvaCreateAction?> showAvaCreateSheet(
  BuildContext context, {
  DriverRoles driverRoles = DriverRoles.none,
  Set<AvaCreateAction> hidden = const {},
  Map<AvaCreateAction, AvaRowLock> locked = const {},
  bool hasShop = false,
}) {
  return showModalBottomSheet<AvaCreateAction>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.ava.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _Scaled(
      child: _BusinessSheet(
        driverRoles: driverRoles,
        hidden: hidden,
        locked: locked,
        hasShop: hasShop,
      ),
    ),
  );
}

/// Тизим шрифти катта қилинган қурилмада (1.3–1.5×) варақа «тўлиб» кетмасин:
/// изоҳлар кесилмасин, бир экранга кўпроқ гуруҳ сиғсин. Ассистент варағидаги
/// каби чегара (`assistant_entry.dart`); матн ҳамон бироз катталашади.
class _Scaled extends StatelessWidget {
  const _Scaled({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.15)),
      child: child,
    );
  }
}

/// Биринчи киришда («Онлайн Дўкон очиш»): дўкон номи (ихтиёрий) ва маҳсулот
/// қаерга қўшилиши. Ном бўш қолса сақланмайди — кейин ҳам қўйиш мумкин.
class AvaFirstShop {
  const AvaFirstShop({required this.name, required this.target});

  /// Тозаланган ном; бўш — ном қўйилмади.
  final String name;
  final AvaShopTarget target;
}

Future<AvaFirstShop?> showAvaFirstShopSheet(BuildContext context) {
  return showModalBottomSheet<AvaFirstShop>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    backgroundColor: context.ava.bg,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _Scaled(child: const _FirstShopSheet()),
  );
}

class _FirstShopSheet extends StatefulWidget {
  const _FirstShopSheet();

  @override
  State<_FirstShopSheet> createState() => _FirstShopSheetState();
}

class _FirstShopSheetState extends State<_FirstShopSheet> {
  final _name = TextEditingController();
  AvaShopTarget _target = AvaShopTarget.retail;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _continue() {
    final raw = _name.text.trim();
    final clean = validShopName(raw);
    // Ном ихтиёрий: бўш — ўтказиб юборилади; тўлдирилган, лекин яроқсиз — хато.
    if (raw.isNotEmpty && clean == null) {
      setState(() => _error = context.tr('my_shop_name_err'));
      return;
    }
    Navigator.of(context).pop(AvaFirstShop(name: clean ?? '', target: _target));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.fromLTRB(AvaSpace.screen, 0, AvaSpace.screen,
            AvaSpace.screen + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
                child: Text(
                  context.tr('my_shop_name_title'),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: c.ink,
                  ),
                ),
              ),
              TextField(
                controller: _name,
                maxLength: kShopNameMaxLength,
                textInputAction: TextInputAction.done,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  hintText: context.tr('my_shop_name_hint'),
                  helperText: context.tr('my_shop_name_note'),
                  helperMaxLines: 2,
                  errorText: _error,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  context.tr('home_create_shop_where'),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: c.ink,
                  ),
                ),
              ),
              SegmentedButton<AvaShopTarget>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: AvaShopTarget.retail,
                    label: Text(context.tr('tv_shop_to_market')),
                  ),
                  ButtonSegment(
                    value: AvaShopTarget.wholesale,
                    label: Text(context.tr('home_module_wholesale')),
                  ),
                ],
                selected: {_target},
                onSelectionChanged: (s) => setState(() => _target = s.first),
              ),
              const SizedBox(height: 16),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _continue,
                child: Text(context.tr('my_shop_continue')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
/// Бир қатор бандининг маълумоти (матн калитлари — 3 тилда).
class _Item {
  const _Item(this.action, this.icon, this.labelKey, this.subKey,
      {this.active = false});

  final AvaCreateAction action;
  final IconData icon;
  final String labelKey;
  final String subKey;

  /// Ҳозир иш бораётган (яшил «Фаол» белгиси).
  final bool active;
}

class _BusinessSheet extends StatelessWidget {
  const _BusinessSheet({
    this.driverRoles = DriverRoles.none,
    this.hidden = const {},
    this.locked = const {},
    this.hasShop = false,
  });

  final DriverRoles driverRoles;
  final Set<AvaCreateAction> hidden;
  final Map<AvaCreateAction, AvaRowLock> locked;

  /// Эгада Аҳоли/Улгуржи маҳсулоти бор: «Онлайн Дўкон очиш» ўрнига «Менинг дўконим».
  final bool hasShop;

  /// Курьер панели бор (ёки тўхтатилган, лекин қўлдаги ишни тугатиши керак).
  bool get _courierHasPanel =>
      driverRoles.courierOnline ||
      CourierCapabilityRepository.panelStatuses
          .contains(driverRoles.courierStatus);

  List<_Item> _visible(List<_Item> items) =>
      items.where((e) => !hidden.contains(e.action)).toList(growable: false);

  @override
  Widget build(BuildContext context) {
    final groups = <(String, List<_Item>)>[
      // «Менинг бизнесим» (эга, 2026-10-23): сарлавҳасиз, энг юқорида ЯГОНА қатор — бир босишда «Менинг
      // бизнесларим» очилади (дўкон, кафе, мойка, цех, хизмат — барча жисмоний объектлар харитага).
      // Аввал «Сотиш» гуруҳи ичида эди, лекин кафе ёки мойка «сотиш» эмас.
      (
        '',
        _visible(const [
          _Item(AvaCreateAction.businessMap, Icons.add_business_rounded,
              'home_create_business_map', 'home_create_business_map_sub'),
        ]),
      ),
      (
        'home_create_group_quick',
        _visible(const [
          _Item(AvaCreateAction.video, Icons.videocam_rounded,
              'home_create_video', 'home_create_video_sub'),
          _Item(AvaCreateAction.ad, Icons.campaign_rounded, 'home_create_ad',
              'home_create_ad_sub'),
          _Item(AvaCreateAction.service, Icons.handyman_rounded,
              'home_create_service', 'home_create_service_sub'),
        ]),
      ),
      (
        'home_create_group_sell',
        _visible([
          _Item(
            AvaCreateAction.shopOnline,
            Icons.storefront_rounded,
            // «Менинг онлайн дўконим» (эга, 2026-10-26) — фақат «＋» да; дўкон экрани сарлавҳаси `my_shop_title`.
            hasShop ? 'home_my_shop_online' : 'home_create_shop_online',
            hasShop ? 'my_shop_row_sub' : 'home_create_shop_online_hint',
          ),
        ]),
      ),
      (
        'home_create_group_work',
        _visible([
          _Item(
            AvaCreateAction.driver,
            Icons.local_taxi_rounded,
            driverRoles.isDriver
                ? 'home_create_driver_open'
                : 'home_create_driver',
            'home_create_driver_sub',
            active: driverRoles.hasActive,
          ),
          _Item(
            AvaCreateAction.courier,
            Icons.delivery_dining_rounded,
            _courierHasPanel
                ? 'home_create_courier_open'
                : 'home_create_courier',
            'home_create_courier_sub',
            active: driverRoles.courierOnline,
          ),
          const _Item(AvaCreateAction.cargo, Icons.local_shipping_rounded,
              'home_create_cargo', 'home_create_cargo_sub'),
        ]),
      ),
      (
        'home_create_group_food',
        _visible(const [
          _Item(AvaCreateAction.homeCook, Icons.soup_kitchen_rounded,
              'home_create_home_cook', 'home_create_home_cook_sub'),
          _Item(AvaCreateAction.cafe, Icons.restaurant_rounded,
              'restaurants_m_open_cafe', 'home_create_cafe_sub'),
        ]),
      ),
      (
        'home_create_group_help',
        _visible(const [
          _Item(AvaCreateAction.book, Icons.menu_book_rounded,
              'book_menu_title', 'book_menu_subtitle'),
          _Item(AvaCreateAction.assistant, Icons.auto_awesome_rounded,
              'home_module_chatgpt', 'home_create_assistant_sub'),
        ]),
      ),
    ].where((g) => g.$2.isNotEmpty).toList(growable: false);

    void pick(AvaCreateAction a) => Navigator.of(context).pop(a);

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        // Кичик экранда ҳам сиғади: сарлавҳа туради, рўйхат айланади.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Header(
              title: context.tr('home_create_title'),
              subtitle: context.tr('home_create_subtitle'),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(
                    AvaSpace.screen, 4, AvaSpace.screen, 20),
                children: [
                  for (final g in groups) ...[
                    if (g.$1.isNotEmpty) _GroupTitle(context.tr(g.$1)),
                    _Card(
                      children: [
                        for (final it in g.$2)
                          _RowTile(
                            icon: it.icon,
                            label: context.tr(it.labelKey),
                            subtitle: context.tr(it.subKey),
                            active: it.active,
                            lock: locked[it.action],
                            onTap: () => pick(it.action),
                          ),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Сарлавҳа: бренд белгиси + «Менинг бизнесим» + қисқа таъриф.
class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AvaSpace.screen + 4, 0, AvaSpace.screen, 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: c.brand,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: c.brand.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Icon(Icons.rocket_launch_rounded, color: c.brandInk, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    height: 1.15,
                    letterSpacing: -0.2,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, height: 1.3, color: c.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupTitle extends StatelessWidget {
  const _GroupTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: context.ava.ink2,
        ),
      ),
    );
  }
}

/// Оқ юмалоқ карта: ичидаги қаторлар ингичка чизиқ билан ажралган.
class _Card extends StatelessWidget {
  const _Card({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: c.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: c.line),
        ),
        child: Column(
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                Divider(height: 1, thickness: 1, indent: 74, color: c.line),
              children[i],
            ],
          ],
        ),
      ),
    );
  }
}

/// Карта ичидаги қатор: иконка белгиси · ном + изоҳ · («Фаол») · ›.
class _RowTile extends StatelessWidget {
  const _RowTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.subtitle,
    this.active = false,
    this.lock,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final VoidCallback onTap;
  final bool active;

  /// Кўринади, лекин очилмайди: хира иконка ва «Тез кунда» / «Иловада» белгиси.
  final AvaRowLock? lock;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final sub = subtitle;
    final lockText = switch (lock) {
      AvaRowLock.soon => context.tr('home_create_pill_soon'),
      AvaRowLock.appOnly => context.tr('home_create_pill_app_only'),
      null => null,
    };
    // Изоҳ ҳам экран ўқувчига ўқилади (аввал фақат ном эди); ёпиқ бандда — сабаби ҳам.
    final base = (sub == null || sub.isEmpty) ? label : '$label. $sub';
    return Semantics(
      button: true,
      label: lockText == null ? base : '$base. $lockText',
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: lock == null ? c.brandSoft : c.bg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, size: 24, color: lock == null ? c.brandText : c.ink3),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          height: 1.25,
                          color: lock == null ? c.ink : c.ink2,
                        ),
                      ),
                      if (sub != null && sub.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          sub,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.3,
                            color: c.ink2,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (active && lockText == null) ...[
                  const SizedBox(width: 8),
                  _ActivePill(text: context.tr('driver_chip_active')),
                ],
                if (lockText != null) ...[
                  const SizedBox(width: 8),
                  _LockPill(text: lockText),
                ] else ...[
                  const SizedBox(width: 4),
                  Icon(Icons.chevron_right_rounded, size: 22, color: c.ink3),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Ёпиқ банд белгиси: кулранг, «›» ўрнида — бу банд ҳозир очилмаслигини кўрсатади.
class _LockPill extends StatelessWidget {
  const _LockPill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    // Кенглик чегараланган: узун таржима ёки катта шрифтда қатор тошиб кетмасин.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 112),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: c.bg,
          borderRadius: BorderRadius.circular(AvaRadius.chip),
          border: Border.all(color: c.line),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: c.ink2),
        ),
      ),
    );
  }
}

class _ActivePill extends StatelessWidget {
  const _ActivePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: c.okSoft,
        borderRadius: BorderRadius.circular(AvaRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: c.ok, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            text,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: c.ok,
            ),
          ),
        ],
      ),
    );
  }
}
