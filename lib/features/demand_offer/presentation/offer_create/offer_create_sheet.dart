// ТАКЛИФЧИ ТОМОНИ — таклиф бериш варақаси (13.4.8).
//
// МАНБА: `demand_matches` проекцияси. Таклифчи `demands` ҳужжатини
// ЎҚИМАЙДИ — бу экрандаги ҳамма маълумот проекциядан келади.
//
// Т-19.4: таклифни максимум 3 марта ўзгартириш мумкин. Чегарага
// етилганда тугма ўчади ва сабаб кўрсатилади — акс ҳолда фойдаланувчи
// «нега ишламайди?» деб ўйлайди.

import 'package:flutter/material.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/ava_tokens.dart';
import '../../data/demand_repository.dart' show DemandException;
import '../../data/match_repository.dart';
import '../../domain/demand_match.dart';

/// Таклиф варақасини кўрсатади. `true` — таклиф юборилди.
Future<bool?> showOfferCreateSheet(
  BuildContext context, {
  required DemandMatch match,
  required MatchRepository repository,
  int maxRevisions = 3,
  int currentRevision = 0,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
      child: OfferCreateSheet(
        match: match,
        repository: repository,
        maxRevisions: maxRevisions,
        currentRevision: currentRevision,
      ),
    ),
  );
}

class OfferCreateSheet extends StatefulWidget {
  const OfferCreateSheet({
    super.key,
    required this.match,
    required this.repository,
    this.maxRevisions = 3,
    this.currentRevision = 0,
  });

  final DemandMatch match;
  final MatchRepository repository;
  final int maxRevisions;
  final int currentRevision;

  @override
  State<OfferCreateSheet> createState() => _OfferCreateSheetState();
}

class _OfferCreateSheetState extends State<OfferCreateSheet> {
  late final String _clientRequestId;
  final _priceCtrl = TextEditingController();
  final _messageCtrl = TextEditingController();
  final _etaCtrl = TextEditingController();
  bool _delivery = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // Т-12: ID варақа ОЧИЛГАНДА бир марта.
    _clientRequestId = widget.repository.newRequestId();
  }

  @override
  void dispose() {
    _priceCtrl.dispose();
    _messageCtrl.dispose();
    _etaCtrl.dispose();
    super.dispose();
  }

  bool get _limitReached => widget.currentRevision >= widget.maxRevisions;

  Future<void> _submit() async {
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.repository.submitOffer(
        demandId: widget.match.demandId,
        clientRequestId: _clientRequestId,
        price: num.tryParse(_priceCtrl.text.replaceAll(RegExp(r'\s'), '')),
        message: _messageCtrl.text.trim(),
        etaMinutes: int.tryParse(_etaCtrl.text.trim()),
        delivery: _delivery,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on DemandException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        // Т-19.4 чегараси ва «буюртма олинди» холатлари учун иловадаги
        // аниқроқ матн, қолганида сервер матни (у ҳам ўзбекча).
        _error = switch (e.code) {
          'resource-exhausted' => context.tr('match_revise_limit'),
          'failed-precondition' => context.tr('demand_error_taken'),
          'permission-denied' => context.tr('demand_error_expired'),
          _ => e.message,
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final p = widget.match.projection;

    return Container(
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: c.line,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),

            Text(
              p.title.isNotEmpty ? p.title : context.tr('match_make_offer'),
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: c.ink,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (p.description.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                p.description,
                style: TextStyle(fontSize: 12, color: c.ink2),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            const SizedBox(height: 14),

            if (_limitReached) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.warnSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  context.tr('match_revise_limit'),
                  style: TextStyle(fontSize: 12, color: c.warn),
                ),
              ),
              const SizedBox(height: 12),
            ],

            TextField(
              controller: _priceCtrl,
              enabled: !_limitReached,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.tr('request_budget'),
                suffixText: context.tr('sum'),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.line),
                ),
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _etaCtrl,
              enabled: !_limitReached,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: context.tr('offer_eta_minutes'),
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.line),
                ),
              ),
            ),
            const SizedBox(height: 10),

            TextField(
              controller: _messageCtrl,
              enabled: !_limitReached,
              minLines: 2,
              maxLines: 4,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: context.tr('request_describe'),
                counterText: '',
                filled: true,
                fillColor: c.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: c.line),
                ),
              ),
            ),
            const SizedBox(height: 6),

            SwitchListTile(
              value: _delivery,
              onChanged: _limitReached
                  ? null
                  : (v) => setState(() => _delivery = v),
              title: Text(
                context.tr('offer_with_delivery'),
                style: TextStyle(fontSize: 13, color: c.ink),
              ),
              contentPadding: EdgeInsets.zero,
              activeThumbColor: c.brand,
            ),

            if (_error != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: c.dangerSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  _error!,
                  style: TextStyle(fontSize: 12, color: c.danger),
                ),
              ),
            ],

            const SizedBox(height: 12),
            FilledButton(
              onPressed: (_sending || _limitReached) ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: c.brand,
                foregroundColor: c.brandInk,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                _sending
                    ? context.tr('request_sending')
                    : context.tr('match_make_offer'),
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
