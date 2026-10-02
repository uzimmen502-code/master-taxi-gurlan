import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/realty_listing.dart';
import '../../../repositories/realty_repository.dart';
import '../realty_tabs.dart';
import '../widgets/realty_feedback.dart';

/// 🏢 Риэлторлик компанияси учун (концепция, 5-бўлим).
///
/// Объектлар биттадан киритилади ва ҳар бири харитага боғланади — бу
/// қоида бу ерда ҳам ЎЗГАРМАЙДИ. Бу экран фақат шу ишни тезлаштиради:
/// профессионал пакет, стандарт матн шаблони ва жамоа аккаунти.
class RealtyProScreen extends StatefulWidget {
  const RealtyProScreen({super.key});

  @override
  State<RealtyProScreen> createState() => _RealtyProScreenState();
}

class _RealtyProScreenState extends State<RealtyProScreen> {
  final _repo = RealtyRepository();
  final _templateCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();

  List<RealtyProPlan> _plans = const [];
  RealtyQuota _quota = RealtyQuota.empty;
  bool _loading = true;
  String? _busyPlanId;
  bool _savingTemplate = false;
  bool _addingMember = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _templateCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final plans = await _repo.loadProPlans();
    final quota = await _repo.fetchQuota();
    final template = await _repo.loadTemplateText();
    if (!mounted) return;
    setState(() {
      _plans = plans;
      _quota = quota;
      _templateCtrl.text = template;
      _loading = false;
    });
  }

  Future<void> _buy(RealtyProPlan plan) async {
    setState(() => _busyPlanId = plan.id);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await _repo.purchaseProPackage(plan.id);
      await _load();
      if (!mounted) return;
      setState(() => _busyPlanId = null);
      showRealtyInfo(
        messenger,
        context.tr('realty_pro_bought'),
        background: RealtyTabs.colorFor(RealtyTier.plain),
      );
    } on RealtyException catch (e) {
      if (!mounted) return;
      setState(() => _busyPlanId = null);
      showRealtyError(messenger, realtyErrorText(context, e));
    }
  }

  Future<void> _saveTemplate() async {
    setState(() => _savingTemplate = true);
    await _repo.saveTemplateText(_templateCtrl.text);
    if (!mounted) return;
    setState(() => _savingTemplate = false);
    showRealtyInfo(ScaffoldMessenger.of(context), context.tr('realty_saved'));
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
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('realty_pro_title'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                RealtyQuotaBar(quota: _quota),
                const SizedBox(height: 20),

                _sectionTitle(context, 'realty_pro_plans'),
                for (final plan in _plans) ...[
                  _PlanTile(
                    plan: plan,
                    busy: _busyPlanId == plan.id,
                    onBuy: _busyPlanId == null ? () => _buy(plan) : null,
                  ),
                  const SizedBox(height: 8),
                ],
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

class _PlanTile extends StatelessWidget {
  const _PlanTile({
    required this.plan,
    required this.busy,
    required this.onBuy,
  });

  final RealtyProPlan plan;
  final bool busy;
  final VoidCallback? onBuy;

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
                    color: c.ink2,
                  ),
                ),
              ],
            ),
          ),
          ElevatedButton(
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
