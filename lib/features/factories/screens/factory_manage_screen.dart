import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../business_map/domain/business.dart';
import '../../vacancies/screens/vacancy_form_screen.dart';
import '../../wholesale/open_wholesale_seller.dart';
import '../data/factories_repository.dart';
import '../domain/factory_profile.dart';

/// Заводни бошқариш (эга 2026-11-28): тизим уланишларни ТАКЛИФ ҚИЛАДИ, завод ЎЗИ ёқади — Улгуржида сотиш,
/// AVAGram видеолари, вакансиялар, «AVA'га таъминотчи бўлишга тайёрман»; «Тасдиқланган ишлаб чиқарувчи» сўрови.
/// Сақлаш — `setMyFactoryOptions` (сервер эгаликни ва `manufacturing` турини текширади).
/// Натижа (pop) — янгиланган [Business] ёки `null` (ўзгармади).
class FactoryManageScreen extends StatefulWidget {
  const FactoryManageScreen({super.key, required this.business, this.save});

  final Business business;

  /// Тест учун: сервер чақируви ўрнига → ҳолат (`producerStatus`).
  @visibleForTesting
  final Future<String> Function(FactoryOptions options, bool requestVerification)? save;

  @override
  State<FactoryManageScreen> createState() => _FactoryManageScreenState();
}

class _FactoryManageScreenState extends State<FactoryManageScreen> {
  late FactoryOptions _o = widget.business.factoryOptions;
  late String _status = widget.business.producerStatus;
  bool _busy = false;

  Future<void> _save({bool requestVerification = false}) async {
    setState(() => _busy = true);
    try {
      final st = await (widget.save?.call(_o, requestVerification) ??
          FactoriesRepository().setOptions(widget.business.id, _o, requestVerification: requestVerification));
      if (!mounted) return;
      setState(() => _status = st.isEmpty ? _status : st);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr('factory_saved'))));
      Navigator.of(context).pop(_updated());
    } catch (e) {
      debugPrint('[FactoryManage] save: $e');
      final code = e is FirebaseFunctionsException && e.details is Map ? (e.details as Map)['code']?.toString() : null;
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
        content: Text(context.tr(code == 'BUSINESS_BLOCKED' ? 'bizmap_delete_blocked' : 'factory_err_generic')),
      ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Business _updated() => widget.business.withFactory(options: _o, producer: _status);

  Widget _option({
    required String key,
    required bool value,
    required ValueChanged<bool> onChanged,
    required String titleKey,
    required String hintKey,
    Widget? action,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SwitchListTile(
          key: ValueKey('factory_opt_$key'),
          contentPadding: EdgeInsets.zero,
          value: value,
          onChanged: _busy ? null : onChanged,
          title: Text(context.tr(titleKey), style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(context.tr(hintKey)),
        ),
        if (value && action != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: action),
        const Divider(height: 1),
      ]);

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final b = widget.business;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(title: Text(context.tr('factory_manage_title'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        children: [
          Text(b.name, style: AvaText.homeCardTitle.copyWith(color: c.ink)),
          const SizedBox(height: 4),
          Text(context.tr('factory_manage_hint'), style: TextStyle(color: c.ink2)),
          const SizedBox(height: 8),
          _option(
            key: 'wholesale',
            value: _o.sellWholesale,
            onChanged: (v) => setState(() => _o = _o.copyWith(sellWholesale: v)),
            titleKey: 'factory_opt_wholesale',
            hintKey: 'factory_opt_wholesale_hint',
            action: TextButton.icon(
              key: const ValueKey('factory_open_wholesale_seller'),
              onPressed: () => openWholesaleSeller(context, phone: b.ownerId),
              icon: const Icon(Icons.storefront_rounded),
              label: Text(context.tr('factory_wholesale_profile')),
            ),
          ),
          _option(
            key: 'videos',
            value: _o.showVideos,
            onChanged: (v) => setState(() => _o = _o.copyWith(showVideos: v)),
            titleKey: 'factory_opt_videos',
            hintKey: 'factory_opt_videos_hint',
          ),
          _option(
            key: 'vacancies',
            value: _o.publishVacancies,
            onChanged: (v) => setState(() => _o = _o.copyWith(publishVacancies: v)),
            titleKey: 'factory_opt_vacancies',
            hintKey: 'factory_opt_vacancies_hint',
            action: TextButton.icon(
              key: const ValueKey('factory_add_vacancy'),
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => VacancyFormScreen(employerBusinessId: b.id)),
              ),
              icon: const Icon(Icons.work_outline_rounded),
              label: Text(context.tr('vac_add')),
            ),
          ),
          _option(
            key: 'supplier',
            value: _o.avaSupplierReady,
            onChanged: (v) => setState(() => _o = _o.copyWith(avaSupplierReady: v)),
            titleKey: 'factory_opt_supplier',
            hintKey: 'factory_opt_supplier_hint',
          ),
          const SizedBox(height: 16),
          Text(context.tr('factory_verified'), style: AvaText.homeCardTitle.copyWith(color: c.ink)),
          const SizedBox(height: 4),
          Text(context.tr('factory_verify_status_${_status.isEmpty ? 'none' : _status}'),
              key: const ValueKey('factory_verify_status')),
          if (_status == ProducerStatus.none || _status == ProducerStatus.rejected) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const ValueKey('factory_request_verify'),
              onPressed: _busy ? null : () => _save(requestVerification: true),
              icon: const Icon(Icons.verified_outlined),
              label: Text(context.tr('factory_request_verify')),
            ),
          ],
          const SizedBox(height: 24),
          FilledButton(
            key: const ValueKey('factory_save'),
            onPressed: _busy ? null : () => _save(),
            child: Text(context.tr('factory_save')),
          ),
        ],
      ),
    );
  }
}
