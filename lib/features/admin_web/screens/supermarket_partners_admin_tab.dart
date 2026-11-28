// «AVA Супермаркет» — Ҳамкорлар (эга 2026-11-28, а-вариант; матнлар — Кирилл, админ конвенцияси):
// модерация навбати (тасдиқлаш / рад + сабаб), автоматик тасдиқ, эски «AVA» таклифларини «Намуна» қилиш.
// Ҳаммаси сервер callable'лари орқали (supermarket.js); админ тўлиқ назоратда.
import 'package:flutter/material.dart';

import '../../../core/utils/formatters.dart';
import '../services/admin_supermarket_service.dart';

class SmPartnersAdminTab extends StatefulWidget {
  const SmPartnersAdminTab({super.key, required this.service});
  final AdminSupermarketService service;

  @override
  State<SmPartnersAdminTab> createState() => _SmPartnersAdminTabState();
}

class _SmPartnersAdminTabState extends State<SmPartnersAdminTab> {
  List<SmPartnerQueueItem> _queue = const [];
  List<String> _samples = const [];
  bool _auto = false;
  bool _busy = false;
  bool _loaded = false;
  String? _msg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await Future.wait([
        widget.service.partnerModerationQueue(),
        widget.service.partnerAutoApprove(),
        widget.service.sampleCandidates(),
      ]);
      if (!mounted) return;
      setState(() {
        _queue = r[0] as List<SmPartnerQueueItem>;
        _auto = r[1] as bool;
        _samples = r[2] as List<String>;
        _loaded = true;
      });
    } catch (e) {
      if (mounted) setState(() => _msg = 'Юклаб бўлмади: $e');
    }
  }

  Future<void> _do(Future<void> Function() job, String ok) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _msg = null;
    });
    try {
      await job();
      if (mounted) setState(() => _msg = ok);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _msg = 'Хато: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reject(SmPartnerQueueItem o) async {
    final ctl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Рад этиш сабаби'),
        content: TextField(key: const ValueKey('sm_partner_reject_reason'), controller: ctl, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Бекор')),
          FilledButton(key: const ValueKey('sm_partner_reject_ok'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Рад этиш')),
        ],
      ),
    );
    if (ok != true) return;
    if (ctl.text.trim().length < 3) return setState(() => _msg = 'Сабаб ёзинг (камида 3 белги)');
    await _do(() => widget.service.moderateOffer(o.productId, approve: false, reason: ctl.text.trim()), 'Рад этилди');
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded && _msg == null) return const Center(child: CircularProgressIndicator());
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const Text(
          'AVA\'нинг ўз маҳсулоти йўқ: ҳар таклиф ҳамкорники (тасдиқланган Улгуржи сотувчиси). Харидор «AVA Супермаркет»ни кўради. '
          'Ҳамкорга тўлов ҳисоби — «Ҳамкорларга тўлов» табида (сукут ўчиқ; пул тизимдан ташқарида, қўлда белгиланади).',
          style: TextStyle(color: Colors.black54),
        ),
        SwitchListTile(
          key: const ValueKey('sm_partner_auto'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Ҳамкор таклифларини автоматик тасдиқлаш'),
          subtitle: const Text('Ўчиқ — ҳар янги таклиф текширувдан кейин сотувга чиқади'),
          value: _auto,
          onChanged: _busy ? null : (v) => _do(() => widget.service.setPartnerAutoApprove(v), v ? 'Автоматик тасдиқ ёқилди' : 'Қўлда тасдиқлаш'),
        ),
        const Divider(),
        Text('Модерация навбати (${_queue.length})', key: const ValueKey('sm_partner_queue_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
        if (_queue.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('Навбат бўш')),
        for (final o in _queue)
          Card(
            key: ValueKey('sm_partner_q_${o.productId}'),
            child: ListTile(
              title: Text(o.name),
              subtitle: Text('${o.groupId} · ${formatMoney(o.price)} · қолдиқ ${o.stock ?? 0} · ҳамкор ${o.partnerKey}'),
              trailing: Wrap(spacing: 4, children: [
                IconButton(
                  key: ValueKey('sm_partner_approve_${o.productId}'),
                  tooltip: 'Тасдиқлаш',
                  icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                  onPressed: _busy ? null : () => _do(() => widget.service.moderateOffer(o.productId, approve: true), 'Тасдиқланди'),
                ),
                IconButton(
                  key: ValueKey('sm_partner_reject_${o.productId}'),
                  tooltip: 'Рад этиш',
                  icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                  onPressed: _busy ? null : () => _reject(o),
                ),
              ]),
            ),
          ),
        const Divider(height: 28),
        const Text('Намуналар', style: TextStyle(fontWeight: FontWeight.w700)),
        Text(
          'Ҳамкорсиз эски «AVA» таклифлари: ${_samples.length}. Намуна — харидорга кўринади («Намуна»), сотилмайди.',
          key: const ValueKey('sm_partner_samples_count'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.tonal(
            key: const ValueKey('sm_partner_mark_samples'),
            onPressed: _busy || _samples.isEmpty
                ? null
                : () => _do(() async {
                      await widget.service.setSample(_samples, sample: true);
                    }, 'Намуна қилинди'),
            child: const Text('Ҳаммасини «Намуна» қилиш'),
          ),
        ),
        if (_msg != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_msg!, key: const ValueKey('sm_partner_msg'))),
      ],
    );
  }
}
