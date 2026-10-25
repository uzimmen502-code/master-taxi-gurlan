import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../seller_tg_channel.dart';

/// «Менинг Telegram каналим» (2026-10-25): сотувчи ўз ошкора каналини улайди — товар/хизмат видеоси AVA'да
/// фаол бўлгач, ўша каналга ҳам чиқади. Қадамлар: 1) AVA ботини каналда администратор қилиш («Хабар жойлаш»
/// ҳуқуқи билан); 2) канал номи → «Код олиш»; 3) кодни канал тавсифига ёзиш → «Текшириш» (эгалик исботи).
/// Бот ҳуқуқини йўқотса — огоҳлантириш ва «Қайта текшириш».
class SellerTgChannelCard extends StatefulWidget {
  const SellerTgChannelCard({super.key, this.api});

  /// Тест учун; бўлмаса ҳақиқий callable'лар.
  final SellerTgChannelApi? api;

  @override
  State<SellerTgChannelCard> createState() => _SellerTgChannelCardState();
}

class _SellerTgChannelCardState extends State<SellerTgChannelCard> {
  late final SellerTgChannelApi _api = widget.api ?? CallableSellerTgChannelApi();
  final _username = TextEditingController();

  SellerTgChannelState? _state;
  bool _loading = true;
  bool _loadFailed = false;
  bool _busy = false;
  bool _expanded = false;
  String _errorKey = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _username.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadFailed = false;
    });
    try {
      final s = await _api.status();
      if (!mounted) return;
      setState(() {
        _state = s;
        _loading = false;
        if (s.channel.isPending) {
          _expanded = true;
          if (_username.text.isEmpty) _username.text = s.channel.handle;
        }
      });
    } catch (e) {
      debugPrint('[SellerTgChannelCard] status: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
    }
  }

  void _setChannel(SellerTgChannel c) {
    final s = _state;
    if (s == null) return;
    _state = SellerTgChannelState(available: s.available, botUsername: s.botUsername, channel: c);
  }

  Future<void> _run(Future<SellerTgChannel> Function() op, {String doneKey = ''}) async {
    setState(() {
      _busy = true;
      _errorKey = '';
    });
    try {
      final c = await op();
      if (!mounted) return;
      setState(() {
        _setChannel(c);
        if (!c.isPending) _expanded = false;
      });
      if (doneKey.isNotEmpty) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr(doneKey))));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorKey = sellerTgErrorKey(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepare([String? username]) => _run(() => _api.prepare(username ?? _username.text));

  Future<void> _verify() => _run(_api.connect, doneKey: 'seller_tg_connected_done');

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        content: Text(ctx.tr('seller_tg_disconnect_confirm')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('cancel'))),
          FilledButton(
            key: const ValueKey('seller_tg_disconnect_yes'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('seller_tg_disconnect')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      await _api.disconnect();
      return SellerTgChannel.none;
    }, doneKey: 'seller_tg_disconnected');
  }

  Future<void> _copy(String text, String doneKey) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(context.tr(doneKey))));
  }

  @override
  Widget build(BuildContext context) {
    final channel = _state?.channel ?? SellerTgChannel.none;
    final subtitle = channel.isConnected
        ? context.tr('seller_tg_connected').replaceAll('{channel}', channel.handle)
        : context.tr('seller_tg_sub_none');
    return Card(
      key: const ValueKey('seller_tg_card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.send_rounded, color: AppColors.primaryDark),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(context.tr('seller_tg_title'), style: const TextStyle(fontWeight: FontWeight.w700)),
                      if (!_loading && !_loadFailed)
                        Text(subtitle, style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ..._body(context, channel),
          ],
        ),
      ),
    );
  }

  List<Widget> _body(BuildContext context, SellerTgChannel channel) {
    if (_loading) {
      return const [Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)))];
    }
    if (_loadFailed) {
      return [
        Text(context.tr('seller_tg_load_err'), key: const ValueKey('seller_tg_load_err')),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            key: const ValueKey('seller_tg_retry'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _load,
            child: Text(context.tr('home_section_retry')),
          ),
        ),
      ];
    }
    final s = _state!;
    if (!s.available && !channel.isConnected && !channel.needsReconnect) {
      return [Text(context.tr('seller_tg_unavailable'), key: const ValueKey('seller_tg_unavailable'))];
    }
    final error = _errorKey.isEmpty
        ? null
        : Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              context.tr(_errorKey),
              key: const ValueKey('seller_tg_error'),
              style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 13),
            ),
          );
    if (channel.isConnected || channel.needsReconnect) {
      return [
        if (channel.title.isNotEmpty) Text(channel.title, style: const TextStyle(fontSize: 13)),
        if (channel.needsReconnect)
          Container(
            key: const ValueKey('seller_tg_needs_reconnect'),
            margin: const EdgeInsets.only(top: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Text(
              context.tr('seller_tg_needs_reconnect').replaceAll('{bot}', '@${s.botUsername}'),
              style: const TextStyle(fontSize: 13),
            ),
          )
        else
          Text(context.tr('seller_tg_connected_hint'), style: TextStyle(fontSize: 13, color: Colors.grey.shade700)),
        if (error != null) error,
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (channel.needsReconnect)
              FilledButton(
                key: const ValueKey('seller_tg_recheck'),
                style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: _busy ? null : () => _prepare(channel.handle),
                child: Text(context.tr('seller_tg_recheck')),
              ),
            OutlinedButton(
              key: const ValueKey('seller_tg_disconnect'),
              style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: _busy ? null : _disconnect,
              child: Text(context.tr('seller_tg_disconnect')),
            ),
          ],
        ),
      ];
    }
    if (!_expanded) {
      return [
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            key: const ValueKey('seller_tg_start'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: () => setState(() => _expanded = true),
            icon: const Icon(Icons.link_rounded, size: 18),
            label: Text(context.tr('seller_tg_connect')),
          ),
        ),
      ];
    }
    final bot = '@${s.botUsername}';
    final minutes = channel.expiresAt == null
        ? 0
        : (channel.expiresAt!.difference(DateTime.now()).inSeconds / 60).ceil().clamp(0, 999);
    return [
      Text(context.tr('seller_tg_step1').replaceAll('{bot}', bot)),
      Row(
        children: [
          Expanded(
            child: SelectableText(bot,
                key: const ValueKey('seller_tg_bot'), style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
          IconButton(
            key: const ValueKey('seller_tg_copy_bot'),
            tooltip: context.tr('shop_link_copy'),
            icon: const Icon(Icons.copy_rounded, size: 20),
            onPressed: () => _copy(bot, 'seller_tg_bot_copied'),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text(context.tr('seller_tg_step2')),
      const SizedBox(height: 6),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('seller_tg_username'),
              controller: _username,
              enabled: !_busy,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _busy ? null : _prepare(),
              decoration: InputDecoration(
                isDense: true,
                hintText: context.tr('seller_tg_username_hint'),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(
            key: const ValueKey('seller_tg_get_code'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _busy ? null : () => _prepare(),
            child: Text(context.tr('seller_tg_get_code')),
          ),
        ],
      ),
      if (channel.isPending) ...[
        const SizedBox(height: 10),
        Text(context.tr('seller_tg_step3')),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: SelectableText(
                channel.code,
                key: const ValueKey('seller_tg_code'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: 1),
              ),
            ),
            IconButton(
              key: const ValueKey('seller_tg_copy_code'),
              tooltip: context.tr('seller_tg_copy_code'),
              icon: const Icon(Icons.copy_rounded, size: 20),
              onPressed: () => _copy(channel.code, 'seller_tg_code_copied'),
            ),
          ],
        ),
        if (minutes > 0)
          Text(
            context.tr('seller_tg_code_expires').replaceAll('{minutes}', '$minutes'),
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton(
            key: const ValueKey('seller_tg_verify'),
            style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _busy ? null : _verify,
            child: Text(context.tr('seller_tg_verify')),
          ),
        ),
      ],
      if (error != null) error,
    ];
  }
}
