import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../data/account_deletion_repository.dart';

/// «Ҳисобни ўчириш»: нима ўчади/қолади, ҳамён ва пулли хизматлар огоҳлантириши, тугамаган ишлар (блок).
///
/// Қарор серверда (`requestAccountDeletion`): дарвоза ёпиқ бўлса ёки блок бўлса сўров қабул қилинмайди.
/// Сўров қабул қилинса [onRequested] чақирилади (чақирувчи сессияни тозалайди ва кириш экранига ўтади);
/// фаол сўров бўлса шу экран «N кун қолди — бекор қилиш»ни кўрсатади.
class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key, required this.onRequested, AccountDeletionRepository? repository})
      : _repo = repository;

  /// Сўров қабул қилингач: чиқиш + кириш экрани. `days` — кутиш кунлари.
  final Future<void> Function(BuildContext context, int days) onRequested;
  final AccountDeletionRepository? _repo;

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  late final AccountDeletionRepository _repo = widget._repo ?? AccountDeletionRepository();
  AccountDeletionPreview? _p;
  bool _loading = true;
  bool _failed = false;
  bool _busy = false;
  bool _confirmed = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final p = await _repo.preview();
      if (!mounted) return;
      setState(() {
        _p = p;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _request() async {
    final p = _p;
    if (p == null || _busy || !_confirmed) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _repo.request();
      if (!mounted) return;
      await widget.onRequested(context, p.waitDays);
    } on AccountDeletionFailure catch (e) {
      if (!mounted) return;
      if (e.code == 'ACCOUNT_DELETION_BLOCKED') {
        await _load(); // ҳолат ўзгарган: блокларни қайта кўрсатамиз
      } else {
        setState(() => _message = context.tr('acct_del_error'));
      }
    } catch (_) {
      if (mounted) setState(() => _message = context.tr('acct_del_error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await _repo.cancel();
      if (!mounted) return;
      setState(() => _message = context.tr('acct_del_cancelled'));
      await _load();
    } on AccountDeletionFailure catch (e) {
      if (!mounted) return;
      setState(() => _message =
          context.tr(e.code == 'ACCOUNT_DELETION_IN_PROGRESS' ? 'acct_del_in_progress' : 'acct_del_error'));
    } catch (_) {
      if (mounted) setState(() => _message = context.tr('acct_del_error'));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr('acct_del_screen_title')),
        backgroundColor: c.brand,
        foregroundColor: c.brandInk,
        elevation: 0,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _failed || _p == null
                ? _ErrorView(onRetry: _load)
                : _content(context, _p!),
      ),
    );
  }

  Widget _content(BuildContext context, AccountDeletionPreview p) {
    final children = <Widget>[];
    if (p.hasActiveRequest) {
      children.addAll(_pendingView(context, p));
    } else if (!p.enabled) {
      children.add(_InfoCard(title: null, body: context.tr('acct_del_off_body')));
    } else if (p.blockers.isNotEmpty) {
      children.addAll(_blockedView(context, p));
    } else {
      children.addAll(_requestView(context, p));
    }
    if (_message != null) {
      children.add(Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text(_message!, key: const ValueKey('acct-del-message'), style: TextStyle(color: context.ava.ink)),
      ));
    }
    return ListView(padding: const EdgeInsets.all(AvaSpace.screen), children: children);
  }

  List<Widget> _pendingView(BuildContext context, AccountDeletionPreview p) {
    final d = p.scheduledFor;
    final date = d == null ? '' : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
    return [
      _InfoCard(
        key: const ValueKey('acct-del-pending'),
        title: context.tr('acct_del_pending_title'),
        body: context.tr('acct_del_pending_body').replaceAll('{date}', date),
      ),
      const SizedBox(height: 16),
      if (p.canCancel)
        FilledButton(
          key: const ValueKey('acct-del-cancel'),
          onPressed: _busy ? null : _cancel,
          child: Text(context.tr('acct_del_cancel_btn')),
        )
      else
        Text(context.tr('acct_del_in_progress')),
    ];
  }

  String _blockerText(BuildContext context, String area) => context.tr(switch (area) {
        'orders' => 'acct_del_blk_orders',
        'trips' => 'acct_del_blk_trips',
        'courier' => 'acct_del_blk_courier',
        'money' => 'acct_del_blk_money',
        'staff' => 'acct_del_blk_staff',
        _ => 'acct_del_blk_other',
      });

  List<Widget> _blockedView(BuildContext context, AccountDeletionPreview p) {
    final areas = <String>[];
    for (final b in p.blockers) {
      if (!areas.contains(b.area)) areas.add(b.area);
    }
    return [
      _InfoCard(
        key: const ValueKey('acct-del-blocked'),
        title: context.tr('acct_del_blocked_title'),
        body: context.tr('acct_del_blocked_intro'),
        extra: [for (final a in areas) _Bullet(_blockerText(context, a))],
      ),
    ];
  }

  List<Widget> _requestView(BuildContext context, AccountDeletionPreview p) {
    final paid = <String>[
      for (final s in p.paidServices)
        context.tr(switch (s) {
          'realty_pro' => 'acct_del_paid_realty_pro',
          'realty_unlocks' => 'acct_del_paid_realty_unlocks',
          _ => 'acct_del_paid_assistant',
        }),
    ];
    return [
      _InfoCard(title: context.tr('acct_del_what_title'), body: context.tr('acct_del_what_body')),
      const SizedBox(height: 12),
      _InfoCard(title: context.tr('acct_del_keep_title'), body: context.tr('acct_del_keep_body')),
      const SizedBox(height: 12),
      _InfoCard(
        key: const ValueKey('acct-del-wallet'),
        title: context.tr('acct_del_wallet_title'),
        body: p.walletAmount > 0
            ? context.tr('acct_del_wallet_amount').replaceAll('{amount}', formatMoney(p.walletAmount))
            : context.tr('acct_del_wallet_zero'),
      ),
      if (paid.isNotEmpty) ...[
        const SizedBox(height: 12),
        _InfoCard(
          key: const ValueKey('acct-del-paid'),
          title: context.tr('acct_del_paid_title'),
          body: context.tr('acct_del_paid_body'),
          extra: [for (final t in paid) _Bullet(t)],
        ),
      ],
      const SizedBox(height: 12),
      Text(context.tr('acct_del_wait').replaceAll('{days}', '${p.waitDays}')),
      const SizedBox(height: 8),
      CheckboxListTile(
        key: const ValueKey('acct-del-check'),
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        value: _confirmed,
        onChanged: _busy ? null : (v) => setState(() => _confirmed = v == true),
        title: Text(context.tr('acct_del_confirm_check')),
      ),
      const SizedBox(height: 8),
      FilledButton(
        key: const ValueKey('acct-del-confirm'),
        style: FilledButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
        onPressed: (_confirmed && !_busy) ? _request : null,
        child: _busy
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
            : Text(context.tr('acct_del_confirm_btn')),
      ),
    ];
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({super.key, required this.title, required this.body, this.extra = const []});

  final String? title;
  final String body;
  final List<Widget> extra;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(AvaRadius.card)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(title!, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: c.ink)),
            const SizedBox(height: 6),
          ],
          Text(body, style: TextStyle(color: c.ink, height: 1.35)),
          ...extra,
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('•  '),
            Expanded(child: Text(text, style: TextStyle(color: context.ava.ink, height: 1.35))),
          ],
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(context.tr('acct_del_load_error'), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(
                key: const ValueKey('acct-del-retry'),
                onPressed: onRetry,
                child: Text(context.tr('acct_del_retry')),
              ),
            ],
          ),
        ),
      );
}
