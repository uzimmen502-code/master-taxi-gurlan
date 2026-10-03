// УМУМИЙ ФОРМА ХОСТИ (13.4.5).
//
// Битта экран — барча модуллар учун. Модулга хос қисм adapter'дан
// келади (`buildForm`, `validate`, `buildConfirmRows`). Янги модул
// қўшилганда бу файл ЎЗГАРМАЙДИ.
//
// Оқим:
//   1) Форма тўлдирилади (adapter чизади)
//   2) «Юбориш» → валидация (клиент) → «Шундай тушундик» варақаси
//   3) Тасдиқлангач `createDemand` callable
//   4) Натижа: «N мос устага юборилди» ёки «Ҳозирча мос уста йўқ»
//
// МУҲИМ — Т-12: `clientRequestId` форма ОЧИЛГАНДА бир марта яратилади.
// Фойдаланувчи «Юбориш»ни икки марта боссa ҳам сервер иккинчи талабни
// яратмайди, аввалгисининг `demandId`сини қайтаради.

import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/ava_tokens.dart';
import '../../data/demand_repository.dart';
import '../../domain/demand.dart';
import '../../ui_adapters/demand_ui_adapter.dart';
import '../demand_confirm/demand_confirm_sheet.dart';

class DemandComposerScreen extends StatefulWidget {
  const DemandComposerScreen({
    super.key,
    required this.adapter,
    required this.repository,
    this.intent,
    this.initialLocation,
    this.onCreated,
  });

  final DemandUiAdapter adapter;
  final DemandRepository repository;

  /// Universal Search'дан келган бўлса — форма олдиндан тўлдирилади.
  final IntentResult? intent;

  /// Жорий жойлашув (модул экранидан).
  final DemandPoint? initialLocation;

  /// Муваффақиятли яратилгандан кейин.
  final void Function(CreateDemandResult result)? onCreated;

  @override
  State<DemandComposerScreen> createState() => _DemandComposerScreenState();
}

class _DemandComposerScreenState extends State<DemandComposerScreen> {
  late DemandDraft _draft;
  DraftValidation _validation = const DraftValidation.valid();
  bool _sending = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    // Т-12: ID ФОРМА ОЧИЛГАНДА бир марта.
    _draft = widget.adapter.newDraft(
      clientRequestId: widget.repository.newRequestId(),
      source: widget.intent != null ? 'intent_card' : 'module',
    );
    if (widget.intent != null) {
      widget.adapter.prefillFromIntent(_draft, widget.intent!);
    }
    if (widget.initialLocation != null) {
      _draft.location = widget.initialLocation;
    }
  }

  void _onChanged() {
    setState(() {
      // Хато матнлари фақат «Юбориш» босилгандан кейин кўрсатилади,
      // ҳар белги ёзилганда эмас — акс ҳолда форма қизил бўлиб туради.
      if (_validation.errors.isNotEmpty) {
        _validation = widget.adapter.validate(_draft);
      }
      _errorMessage = null;
    });
  }

  Future<void> _submit() async {
    final v = widget.adapter.validate(_draft);
    setState(() => _validation = v);
    if (!v.isValid) return;

    final rows = widget.adapter.buildConfirmRows(context, _draft);
    final confirmed = await showDemandConfirmSheet(
      context,
      rows: rows,
      isSending: false,
      onEditField: (field) {
        // Тузатишга қайтилди — хато белгиси қўйилади, фокус шу майдонга.
        setState(() => _validation = DraftValidation({field: ''}));
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _sending = true;
      _errorMessage = null;
    });

    try {
      final result = await widget.repository.createDemand(
        module: _draft.module,
        clientRequestId: _draft.clientRequestId,
        categoryId: _draft.categoryId,
        source: _draft.source,
        input: _draft.inputPayload,
        title: _draft.title,
        description: _draft.description,
        location: _draft.location,
        destination: _draft.destination,
        timeWindow: _draft.timeWindowPayload,
        budget: _draft.budget,
        quantity: _draft.quantity,
        images: _draft.images,
        recipientName: _draft.recipientName,
        recipientPhone: _draft.recipientPhone,
        attributes: _draft.attributes,
      );

      if (!mounted) return;
      widget.onCreated?.call(result);
      await _showResult(result);
      if (mounted) Navigator.of(context).pop(result);
    } on DemandException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _errorMessage = _messageFor(context, e);
      });
    } finally {
      if (mounted && _sending) setState(() => _sending = false);
    }
  }

  /// Сервер хатосини фойдаланувчи тилига ўгиради.
  ///
  /// Сервер матни ҳам ўзбекча, лекин лимит ва ҳудуд хатолари учун
  /// иловада аниқроқ матн бор (учала локал файлда).
  String _messageFor(BuildContext context, DemandException e) {
    switch (e.code) {
      case 'resource-exhausted':
        return e.message.contains('ochiq')
            ? context.tr('demand_error_limit_active')
            : context.tr('demand_error_limit_daily');
      case 'failed-precondition':
        return context.tr('demand_error_region');
      case 'unavailable':
        return context.tr('demand_error_unavailable');
      case 'invalid-argument':
        return context.tr('demand_error_moderation');
      default:
        return e.message;
    }
  }

  Future<void> _showResult(CreateDemandResult result) async {
    final c = context.ava;

    // Дубликат — янги талаб яратилмади (икки марта тап).
    if (result.duplicate) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.tr('request_duplicate'))),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: Text(
          ctx.tr('request_sent_title'),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: c.ink,
          ),
        ),
        content: Text(
          // «Ҳозирча мос уста йўқ. Пайдо бўлса, хабар берамиз» —
          // бўш экран ЭМАС (концепция талаби).
          result.noProviders
              ? ctx.tr('request_no_providers')
              // Т-8: АНИҚ РАҚАМ ЭМАС, панжара («30+»).
              : '${result.matchedBucket} ${ctx.tr('request_sent_to')}',
          style: TextStyle(fontSize: 13, color: c.ink2),
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: FilledButton.styleFrom(
              backgroundColor: c.brand,
              foregroundColor: c.brandInk,
            ),
            child: Text(ctx.tr('confirm_ok')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;

    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: c.surface,
        elevation: 0,
        title: Text(
          context.tr(widget.adapter.primaryActionL10nKey),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: c.ink,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            widget.adapter.buildForm(context, _draft, _onChanged),

            // Валидация хатолари — калит бўйича, учала локал файлдан.
            if (!_validation.isValid) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.warnSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final key in _validation.errors.values)
                      if (key.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            context.tr(key),
                            style: TextStyle(fontSize: 12, color: c.warn),
                          ),
                        ),
                  ],
                ),
              ),
            ],

            if (_errorMessage != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.dangerSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(fontSize: 12, color: c.danger),
                ),
              ),
            ],

            const SizedBox(height: 20),
            FilledButton(
              onPressed: _sending ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: c.brandInk,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _sending
                    ? context.tr('request_sending')
                    : context.tr('request_send'),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
