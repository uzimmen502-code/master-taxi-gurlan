import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/idempotency_keys.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../realty_tabs.dart';
import '../widgets/realty_feedback.dart';
import '../widgets/realty_wallet.dart';
import '../../../shared/widgets/wallet_topup_ui.dart';

/// 🏢 Риэлторлик компанияси учун (концепция, 5-бўлим).
///
/// Объектлар биттадан киритилади ва ҳар бири харитага боғланади — бу
/// қоида бу ерда ҳам ЎЗГАРМАЙДИ. Бу экран фақат шу ишни тезлаштиради:
/// профессионал пакет, стандарт матн шаблони ва жамоа аккаунти.
///
/// ТЕЗ ОЧИЛИШИ (2026-10-18): аввал экран учта сўровни КЕТМА-КЕТ кутарди
/// (режалар → квота → шаблон — иккита Cloud Function + Firestore) ва ҳаммаси
/// тугамагунча тўлиқ экран айлантирувчи кўрсатарди. Энди:
///   * учаласи ПАРАЛЛЕЛ юкланади;
///   * экран дарҳол очилади, ҳар бўлим тайёр бўлгани ҳамон кўринади;
///   * чақирувчи билган квота ([initialQuota]) ва олдиндан бошланган режалар
///     ([plansFuture]) бўлса — улар кутилмайди.
class RealtyProScreen extends StatefulWidget {
  const RealtyProScreen({
    super.key,
    this.initialQuota,
    this.plansFuture,
    this.repository,
    this.balance,
    this.openWallet,
  });

  /// Тест учун: баланс оқими ва «ҳамённи тўлдириш» ҳаракати.
  final Stream<int>? balance;
  final VoidCallback? openWallet;

  /// Чақирувчи аллақачон ўқиган квота (маълум бўлса дарҳол кўрсатилади,
  /// орқа фонда янгиланади).
  final RealtyQuota? initialQuota;

  /// Чақирувчи олдиндан бошлаб қўйган режалар сўрови.
  final Future<List<RealtyProPlan>>? plansFuture;

  /// Тест учун алмаштириладиган репозиторий.
  final RealtyRepository? repository;

  @override
  State<RealtyProScreen> createState() => _RealtyProScreenState();
}

class _RealtyProScreenState extends State<RealtyProScreen> {
  late final RealtyRepository _repo = widget.repository ?? RealtyRepository();
  final _templateCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  /// Ҳар режа — ўз ИДЕМПОТЕНТЛИК калити (қайта уриниш пулни яна емайди).
  final _keys = IdempotencyKeys();

  /// Эганинг баланси — етмайдиган режалар сотиб олишдан ОЛДИН кўринсин.
  late final Stream<int> _balance = widget.balance ?? walletBalanceStream();

  void _topUp([int? amount]) => (widget.openWallet ??
      () => openWalletTopUp(Navigator.of(context), suggestedAmount: amount))();

  List<RealtyProPlan> _plans = const [];
  bool _plansLoading = true;
  late RealtyQuota _quota = widget.initialQuota ?? RealtyQuota.empty;
  late bool _quotaLoading = !(widget.initialQuota?.isKnown ?? false);
  String? _busyPlanId;
  bool _savingTemplate = false;
  bool _addingMember = false;

  @override
  void initState() {
    super.initState();
    _loadPlans(widget.plansFuture);
    _refreshQuota();
    _loadTemplate();
  }

  @override
  void dispose() {
    _templateCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPlans([Future<List<RealtyProPlan>>? prepared]) async {
    if (!_plansLoading) setState(() => _plansLoading = true);
    List<RealtyProPlan> plans;
    try {
      plans = await (prepared ?? _repo.loadProPlans());
    } catch (_) {
      plans = const [];
    }
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _plansLoading = false;
    });
  }

  Future<void> _refreshQuota() async {
    RealtyQuota q;
    try {
      q = await _repo.fetchQuota();
    } catch (_) {
      q = RealtyQuota.empty;
    }
    if (!mounted) return;
    setState(() {
      // Хатода (маълумот йўқ) аввалги маълум қиймат сақланади.
      if (q.isKnown) _quota = q;
      _quotaLoading = false;
    });
  }

  Future<void> _loadTemplate() async {
    String template;
    try {
      template = await _repo.loadTemplateText();
    } catch (_) {
      template = '';
    }
    if (!mounted) return;
    // Фойдаланувчи юкланишни кутмай ёза бошлаган бўлса — унинг матни
    // устидан ёзилмайди.
    if (_templateCtrl.text.isEmpty) _templateCtrl.text = template;
    setState(() {});
  }

  Future<void> _buy(RealtyProPlan plan) async {
    setState(() => _busyPlanId = plan.id);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final scope = 'pro:${plan.id}';
    try {
      await _repo.purchaseProPackage(plan.id, idempotencyKey: _keys.keyFor(scope));
      _keys.settled(scope);
      await _refreshQuota();
      if (!mounted) return;
      setState(() => _busyPlanId = null);
      showRealtyInfo(
        messenger,
        context.tr('realty_pro_bought'),
        background: RealtyTabs.colorFor(RealtyTier.plain),
      );
    } on RealtyException catch (e) {
      // Сервер АНИҚ рад этди — пул ечилмаган.
      _keys.settled(scope);
      if (!mounted) return;
      setState(() => _busyPlanId = null);
      showRealtyPurchaseError(
        context: context,
        messenger: messenger,
        navigator: navigator,
        error: e,
        openWallet: widget.openWallet,
      );
    } catch (_) {
      // Натижа НОМАЪЛУМ (тармоқ узилди): калит сақланади — қайта уриниш
      // пулни яна емайди; тугма қотиб қолмайди.
      if (!mounted) return;
      setState(() => _busyPlanId = null);
      showRealtyError(messenger, context.tr('realty_error_generic'));
    }
  }

  Future<void> _saveTemplate() async {
    setState(() => _savingTemplate = true);
    try {
      await _repo.saveTemplateText(_templateCtrl.text);
      if (!mounted) return;
      setState(() => _savingTemplate = false);
      showRealtyInfo(ScaffoldMessenger.of(context), context.tr('realty_saved'));
    } catch (_) {
      if (!mounted) return;
      setState(() => _savingTemplate = false);
      showRealtyError(ScaffoldMessenger.of(context), context.tr('realty_error_generic'));
    }
  }

  Future<void> _addMember() async {
    final phone = _phoneCtrl.text.trim();
    if (phone.isEmpty) return;
    setState(() => _addingMember = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.addTeamMember(phone);
      if (!mounted) return;
      _phoneCtrl.clear();
      setState(() => _addingMember = false);
      showRealtyInfo(messenger, context.tr('realty_team_added'));
    } on RealtyException catch (e) {
      if (!mounted) return;
      setState(() => _addingMember = false);
      showRealtyError(messenger, realtyErrorText(context, e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _addingMember = false);
      showRealtyError(messenger, context.tr('realty_error_generic'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('realty_pro_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          if (_quotaLoading)
            const _InlineLoader(key: ValueKey('pro-quota-loading'))
          else
            RealtyQuotaBar(quota: _quota),
          const SizedBox(height: 20),

          _sectionTitle(context, 'realty_pro_plans'),
          if (_plansLoading)
            const _InlineLoader(key: ValueKey('pro-plans-loading'))
          else if (_plans.isEmpty)
            Row(
              key: const ValueKey('pro-plans-failed'),
              children: [
                Expanded(
                  child: Text(
                    context.tr('realty_pro_plans_failed'),
                    style: TextStyle(fontSize: AppText.bodySmall, color: c.ink2),
                  ),
                ),
                TextButton(
                  key: const ValueKey('pro-plans-retry'),
                  onPressed: _loadPlans,
                  child: Text(context.tr('realty_pricing_retry')),
                ),
              ],
            )
          else
            // Битта оқим: баланс қатори ҳам, ҳар режанинг «етмайди» белгиси ҳам.
            StreamBuilder<int>(
              stream: _balance,
              builder: (context, snap) {
                final bal = snap.data;
                final cheapest = _plans.map((p) => p.price).reduce((a, b) => a < b ? a : b);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Энг арзон режага ҳам етмаса — огоҳлантириш ва «тўлдириш»;
                    // етса — кичик «Ҳамёнда: X».
                    WalletBalanceBar(balance: bal, price: cheapest, onTopUp: _topUp, onTopUpAmount: _topUp),
                    for (final plan in _plans) ...[
                      _PlanTile(
                        plan: plan,
                        busy: _busyPlanId == plan.id,
                        short: bal != null && bal < plan.price,
                        onBuy: _busyPlanId == null ? () => _buy(plan) : null,
                      ),
                      const SizedBox(height: 8),
                    ],
                  ],
                );
              },
            ),
          const SizedBox(height: 20),

          _sectionTitle(context, 'realty_template_title'),
          Text(
            context.tr('realty_template_body'),
            style: TextStyle(
              fontSize: AppText.bodySmall,
              color: c.ink2,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _templateCtrl,
            maxLines: 4,
            maxLength: 1000,
            decoration: InputDecoration(
              filled: true,
              fillColor: c.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _savingTemplate ? null : _saveTemplate,
              child: Text(context.tr('save')),
            ),
          ),
          const SizedBox(height: 20),

          _sectionTitle(context, 'realty_team_title'),
          Text(
            context.tr('realty_team_body'),
            style: TextStyle(
              fontSize: AppText.bodySmall,
              color: c.ink2,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: '998901234567',
                    filled: true,
                    fillColor: c.surface,
                    isDense: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: _addingMember ? null : _addMember,
                child: Text(context.tr('realty_team_add')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String key) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        context.tr(key),
        style: TextStyle(
          fontSize: AppText.titleMedium,
          fontWeight: FontWeight.w800,
          color: c.ink,
        ),
      ),
    );
  }
}

/// Бўлим юкланаётганда кичик айлантирувчи (тўлиқ экран эмас).
class _InlineLoader extends StatelessWidget {
  const _InlineLoader({super.key});

  @override
  Widget build(BuildContext context) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
}

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.busy,
    required this.onBuy,
    this.short = false,
  });

  final RealtyProPlan plan;
  final bool busy;
  final VoidCallback? onBuy;

  /// Баланс шу режага етмайди (тугма ўчирилмайди — ҳал қилувчи сервер).
  final bool short;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: c.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${plan.objects} ${context.tr('realty_package_objects')} · '
                  '${plan.days} ${context.tr('realty_days_short')}',
                  style: TextStyle(
                    fontSize: AppText.bodyMedium,
                    fontWeight: FontWeight.w700,
                    color: c.ink,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  formatMoney(plan.price),
                  style: TextStyle(
                    fontSize: AppText.bodySmall,
                    color: short ? c.warn : c.ink2,
                    fontWeight: short ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (short)
                  Text(
                    context.tr('realty_wallet_short_tile'),
                    key: ValueKey('pro-short-${plan.id}'),
                    style: TextStyle(fontSize: AppText.labelTiny, color: c.warn),
                  ),
              ],
            ),
          ),
          ElevatedButton(
            key: ValueKey('pro-buy-${plan.id}'),
            onPressed: onBuy,
            style: ElevatedButton.styleFrom(
              backgroundColor: c.brand,
              foregroundColor: c.brandInk,
            ),
            child: busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(context.tr('realty_tier_buy')),
          ),
        ],
      ),
    );
  }
}
