// TAXI SERVICE AGREEMENT — D-TAXI-24 / D-TAXI-24.1.
//
// Ҳайдовчи таксини ёққанда ЭМАС — 4 ойлик starter тугаб
// `verification_required` бўлганда (ва келишув версияси янгиланганда)
// тизим шу варақни ўзи тақдим қилади (D-TAXI-24.1, эга қарори
// 2026-10-06). Қабул қилиш СЕРВЕРДА қайд этилади
// (`acceptServiceAgreement` → `service_agreements/{accountId}`), илова
// фақат чақиради. Версияни сервер айтади (`requestCapability` /
// `quoteTaxiFee` → `agreementVersion`), илова ўзича рақам ўйлаб
// топмайди — эски матнни «қабул қилдим» деб юбориш рад этилади.
//
// Матн уч тилда (`taxi_agreement_p1…p8`) — uz_Cyrl, uz_Latn, ru.

import 'package:flutter/material.dart';

import '../../core/l10n/l10n_extension.dart';
import '../../core/theme/app_theme.dart';
import '../../repositories/taxi_billing_repository.dart';

/// `true` — қабул қилинди ва серверга ёзилди.
Future<bool> showTaxiAgreementSheet(
  BuildContext context, {
  required int version,
  required Color primaryColor,
  TaxiBillingRepository? repository,
}) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _TaxiAgreementSheet(
      version: version,
      primaryColor: primaryColor,
      repository: repository ?? TaxiBillingRepository(),
    ),
  );
  return ok == true;
}

/// D-TAXI-1 + D-TAXI-24.1: таксини ёқиш — дарҳол `starter`, келишувсиз.
///
/// `requestCapability` чақирилади. Сервер `agreementRequired: true` деса
/// (starter тугаган: `verification_required`/`verified`, келишув ҳали
/// қабул қилинмаган) варақ АВТОМАТИК тақдим қилинади. Рад этилса ҳам
/// ҳайдовчи ишлашда давом этади (D-TAXI-5) — фақат янги пуллик рейс
/// олдидан сервер яна сўрайди. `true` — capability бор, ҳайдовчи
/// ишлаши мумкин. Админ тасдиғи КУТИЛМАЙДИ.
Future<bool> ensureTaxiCapability(
  BuildContext context, {
  required Future<Map<String, dynamic>> Function() requestCapability,
  required Color primaryColor,
  TaxiBillingRepository? repository,
}) async {
  final res = await requestCapability();
  final hasCapability = (res['accountId'] ?? '').toString().isNotEmpty;
  if (hasCapability && res['agreementRequired'] == true && context.mounted) {
    await showTaxiAgreementSheet(
      context,
      version: (res['agreementVersion'] as int?) ?? 1,
      primaryColor: primaryColor,
      repository: repository,
    );
  }
  return hasCapability;
}

class _TaxiAgreementSheet extends StatefulWidget {
  const _TaxiAgreementSheet({
    required this.version,
    required this.primaryColor,
    required this.repository,
  });

  final int version;
  final Color primaryColor;
  final TaxiBillingRepository repository;

  @override
  State<_TaxiAgreementSheet> createState() => _TaxiAgreementSheetState();
}

class _TaxiAgreementSheetState extends State<_TaxiAgreementSheet> {
  bool _checked = false;
  bool _saving = false;
  String? _error;

  Future<void> _accept() async {
    if (!_checked || _saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repository.acceptAgreement(version: widget.version);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.sizeOf(context).height * 0.9;
    final points = List.generate(8, (i) => context.tr('taxi_agreement_p${i + 1}'));

    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxH),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                context.tr('taxi_agreement_title'),
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text('v${widget.version}',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(height: 12),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: points.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${i + 1}. ',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: AppColors.primaryText)),
                      Expanded(
                          child: Text(points[i],
                              style: const TextStyle(fontSize: 14, height: 1.35))),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                value: _checked,
                onChanged: _saving ? null : (v) => setState(() => _checked = v == true),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                activeColor: widget.primaryColor,
                title: Text(context.tr('taxi_agreement_accept'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!,
                      style: TextStyle(color: Colors.red.shade700, fontSize: 12)),
                ),
              SizedBox(
                height: 48,
                child: FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: widget.primaryColor),
                  onPressed: _checked && !_saving ? _accept : null,
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: AppColors.onPrimary))
                      : Text(context.tr('taxi_agreement_accept')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
