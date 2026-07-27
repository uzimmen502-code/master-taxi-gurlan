import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';

/// Finance Center — Telegram ҳамён (топ-up / ечиш навбати + карта созламаси).
class WalletBotTab extends StatefulWidget {
  const WalletBotTab({super.key});

  @override
  State<WalletBotTab> createState() => _WalletBotTabState();
}

class _WalletBotTabState extends State<WalletBotTab>
    with SingleTickerProviderStateMixin {
  late final TabController _inner;
  final _cardCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _hintCtrl = TextEditingController();
  bool _enabled = true;
  /// `manual` | `auto`
  String _topUpApproveMode = 'manual';
  /// `manual` | `auto`
  String _withdrawApproveMode = 'manual';
  /// 20000 | 50000 | 100000
  int _withdrawAutoLimit = 20000;
  static const _withdrawAutoLimits = [20000, 50000, 100000];
  bool _loadingSettings = true;
  bool _saving = false;
  String? _botUsername;

  @override
  void initState() {
    super.initState();
    _inner = TabController(length: 3, vsync: this);
    _loadSettings();
  }

  @override
  void dispose() {
    _inner.dispose();
    _cardCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _hintCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _loadingSettings = true);
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('adminGetWalletBotSettings')
          .call();
      final data = Map<String, dynamic>.from(res.data as Map? ?? {});
      final s = Map<String, dynamic>.from(data['settings'] as Map? ?? {});
      _cardCtrl.text = '${s['depositCardNumber'] ?? ''}';
      final first = '${s['depositCardFirstName'] ?? ''}'.trim();
      final last = '${s['depositCardLastName'] ?? ''}'.trim();
      final legacy = '${s['depositCardHolder'] ?? ''}'.trim();
      if (first.isNotEmpty || last.isNotEmpty) {
        _firstNameCtrl.text = first;
        _lastNameCtrl.text = last;
      } else if (legacy.isNotEmpty) {
        final parts = legacy.split(RegExp(r'\s+'));
        _firstNameCtrl.text = parts.isNotEmpty ? parts.first : '';
        _lastNameCtrl.text =
            parts.length > 1 ? parts.sublist(1).join(' ') : '';
      } else {
        _firstNameCtrl.clear();
        _lastNameCtrl.clear();
      }
      _hintCtrl.text = '${s['depositInstructions'] ?? ''}';
      _enabled = s['enabled'] != false;
      _topUpApproveMode =
          '${s['topUpApproveMode'] ?? 'manual'}'.toLowerCase() == 'auto'
              ? 'auto'
              : 'manual';
      _withdrawApproveMode =
          '${s['withdrawApproveMode'] ?? 'manual'}'.toLowerCase() == 'auto'
              ? 'auto'
              : 'manual';
      final lim = (s['withdrawAutoLimit'] as num?)?.toInt() ?? 20000;
      _withdrawAutoLimit =
          _withdrawAutoLimits.contains(lim) ? lim : 20000;
      _botUsername = data['botUsername'] as String?;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingSettings = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _saving = true);
    try {
      await FirebaseFunctions.instance
          .httpsCallable('adminSetWalletBotSettings')
          .call({
        'enabled': _enabled,
        'topUpApproveMode': _topUpApproveMode,
        'withdrawApproveMode': _withdrawApproveMode,
        'withdrawAutoLimit': _withdrawAutoLimit,
        'depositCardNumber': _cardCtrl.text.trim(),
        'depositCardFirstName': _firstNameCtrl.text.trim(),
        'depositCardLastName': _lastNameCtrl.text.trim(),
        'depositInstructions': _hintCtrl.text.trim(),
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сақланди'),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _reviewTopUp(String id, bool accept, {String? reason}) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('adminReviewWalletTopUp')
          .call({
        'requestId': id,
        'accept': accept,
        if (reason != null) 'rejectReason': reason,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(accept ? 'Тасдиқланди → ҳамён' : 'Рад этилди'),
        backgroundColor: accept ? Colors.green : Colors.orange,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _reviewWithdraw(String id, bool accept,
      {bool markPaid = false, String? reason}) async {
    try {
      await FirebaseFunctions.instance
          .httpsCallable('adminReviewWalletWithdraw')
          .call({
        'requestId': id,
        'accept': accept,
        'markPaid': markPaid,
        if (reason != null) 'rejectReason': reason,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(accept ? 'Тасдиқланди' : 'Рад этилди'),
        backgroundColor: accept ? Colors.green : Colors.orange,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _openReceipt(String requestId) async {
    try {
      final res = await FirebaseFunctions.instance
          .httpsCallable('getWalletTopUpReceiptUrl')
          .call({'requestId': requestId});
      final url = (res.data as Map?)?['url'] as String?;
      if (url == null || !mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Чек'),
          content: SizedBox(
            width: 420,
            child: Image.network(url, fit: BoxFit.contain),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Ёпиш'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _inner,
          labelColor: AppColors.primaryDark,
          tabs: const [
            Tab(text: 'Тўлдириш навбати'),
            Tab(text: 'Ечиш навбати'),
            Tab(text: 'Созлама'),
          ],
        ),
        Expanded(
          child: TabBarView(
            controller: _inner,
            children: [
              _topUpQueue(),
              _withdrawQueue(),
              _settingsPane(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _topUpQueue() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('wallet_topup_requests')
          .where('status', isEqualTo: 'awaiting_review')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('Кутилаётган чек йўқ'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final d = docs[i];
            final m = d.data();
            final amount = (m['amount'] as num?)?.toInt() ?? 0;
            final uid = '${m['uid'] ?? ''}';
            final created = m['createdAt'] as Timestamp?;
            final when = created != null
                ? DateFormat('dd.MM.yyyy HH:mm').format(created.toDate())
                : '—';
            return Card(
              child: ListTile(
                title: Text('${formatMoney(amount)} · +$uid'),
                subtitle: Text('ID: ${d.id}\n$when'),
                isThreeLine: true,
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: 'Чек',
                      icon: const Icon(Icons.receipt_long),
                      onPressed: () => _openReceipt(d.id),
                    ),
                    IconButton(
                      tooltip: 'Тасдиқ',
                      icon: const Icon(Icons.check_circle, color: Colors.green),
                      onPressed: () => _reviewTopUp(d.id, true),
                    ),
                    IconButton(
                      tooltip: 'Рад',
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: () async {
                        final reason = await _askReason();
                        if (reason == null) return;
                        await _reviewTopUp(d.id, false, reason: reason);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _withdrawQueue() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('wallet_withdraw_requests')
          .where('status', isEqualTo: 'pending')
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return Center(child: Text('${snap.error}'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const Center(child: Text('Ечиш аризаси йўқ'));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            final d = docs[i];
            final m = d.data();
            final amount = (m['amount'] as num?)?.toInt() ?? 0;
            final uid = '${m['uid'] ?? ''}';
            final source = '${m['source'] ?? ''}';
            final card = '${m['payoutCardNumber'] ?? ''}';
            final holder = '${m['payoutCardHolder'] ?? ''}';
            final cardLine = card.isEmpty
                ? ''
                : 'Карта: $card${holder.isEmpty ? '' : ' · $holder'}';
            return Card(
              child: ListTile(
                title: Text('${formatMoney(amount)} · +$uid'),
                subtitle: Text(
                  [
                    'ID: ${d.id}',
                    if (source.isNotEmpty) source,
                    if (cardLine.isNotEmpty) cardLine,
                  ].join('\n'),
                ),
                isThreeLine: cardLine.isNotEmpty,
                trailing: Wrap(
                  spacing: 4,
                  children: [
                    TextButton(
                      onPressed: () =>
                          _reviewWithdraw(d.id, true, markPaid: true),
                      child: const Text('Тасдиқ+тўлов'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.check, color: Colors.green),
                      onPressed: () => _reviewWithdraw(d.id, true),
                    ),
                    IconButton(
                      icon: const Icon(Icons.cancel, color: Colors.red),
                      onPressed: () async {
                        final reason = await _askReason();
                        if (reason == null) return;
                        await _reviewWithdraw(d.id, false, reason: reason);
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _settingsPane() {
    if (_loadingSettings) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_botUsername != null && _botUsername!.isNotEmpty)
          Text('Бот: @$_botUsername',
              style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        SwitchListTile(
          title: const Text('Бот ёқилган'),
          value: _enabled,
          onChanged: (v) => setState(() => _enabled = v),
        ),
        const SizedBox(height: 8),
        const Text(
          'Тўлдириш тасдиғи',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'manual',
              label: Text('Қўлда'),
              icon: Icon(Icons.person_outline, size: 18),
            ),
            ButtonSegment(
              value: 'auto',
              label: Text('Авто'),
              icon: Icon(Icons.bolt, size: 18),
            ),
          ],
          selected: {_topUpApproveMode},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            setState(() => _topUpApproveMode = s.first);
          },
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 12),
          child: Text(
            _topUpApproveMode == 'auto'
                ? 'Авто: чек юклангач ҳамёнга дарҳол ёзилади (админ навбатисиз).'
                : 'Қўлда: чек «Тўлдириш навбати»да кутади, админ тасдиқлайди.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
        const Text(
          'Ечиш тасдиғи',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'manual',
              label: Text('Қўлда'),
              icon: Icon(Icons.person_outline, size: 18),
            ),
            ButtonSegment(
              value: 'auto',
              label: Text('Авто'),
              icon: Icon(Icons.bolt, size: 18),
            ),
          ],
          selected: {_withdrawApproveMode},
          onSelectionChanged: (s) {
            if (s.isEmpty) return;
            setState(() => _withdrawApproveMode = s.first);
          },
        ),
        if (_withdrawApproveMode == 'auto') ...[
          const SizedBox(height: 10),
          const Text(
            'Авто лимит (шу сумма ва ундан кичик — админсиз)',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SegmentedButton<int>(
            segments: [
              for (final lim in _withdrawAutoLimits)
                ButtonSegment(
                  value: lim,
                  label: Text(formatPrice(lim)),
                ),
            ],
            selected: {_withdrawAutoLimit},
            onSelectionChanged: (s) {
              if (s.isEmpty) return;
              setState(() => _withdrawAutoLimit = s.first);
            },
          ),
        ],
        Padding(
          padding: const EdgeInsets.only(top: 6, bottom: 12),
          child: Text(
            _withdrawApproveMode == 'auto'
                ? 'Авто: ≤ ${formatMoney(_withdrawAutoLimit)} дарҳол ҳамёндан ечилади; '
                    'каттареси «Ечиш навбати»да кутади. Картага тўлов ҳали қўлда.'
                : 'Қўлда: барча ечиш аризалари админ тасдиғини кутади.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
        TextField(
          controller: _cardCtrl,
          decoration: const InputDecoration(
            labelText: 'Депозит карта рақами',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _firstNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Карта эгаси — исм',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: _lastNameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Карта эгаси — фамилия',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _hintCtrl,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Қўшимча кўрсатма',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: _saving ? null : _saveSettings,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Сақлаш'),
        ),
      ],
    );
  }

  Future<String?> _askReason() async {
    final ctrl = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Рад сабаби'),
        content: TextField(controller: ctrl, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Бекор'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Рад'),
          ),
        ],
      ),
    );
  }
}
