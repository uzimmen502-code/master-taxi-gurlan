import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/user_error.dart';
import '../../../models/chat_message.dart';
import '../../chat/widgets/chat_composer.dart';
import '../../chat/widgets/message_bubble.dart';
import '../../wholesale/models/wholesale_product.dart';
import '../../wholesale/utils/wholesale_labels.dart';
import '../data/deal_chat_repository.dart';
import '../deal_chat_support.dart';

/// «Буюртма ёзиш» чати: харидор ↔ эълон эгаси (эга қарори 2026-11-01).
///
/// Тепада маҳсулот (расм, ном, нарх), пастда хабарлар ва ёзиш майдони. Хабар фақат сервер
/// орқали (`sendDealMessage`); ўқилди белгиси — `markDealChatRead` (ўқилмаган бўлсагина).
class DealChatScreen extends StatefulWidget {
  const DealChatScreen({
    super.key,
    required this.chatId,
    required this.myUid,
    this.initialProduct,
    this.repository,
    this.initialDraft,
  });

  /// Ёзиш майдонига олдиндан қўйиладиган матн (эга, 2026-11-02: Улгуржи
  /// тафсилотида танланган миқдор чатга борсин). Ўзи ЮБОРИЛМАЙДИ — харидор
  /// кўриб, ўзгартириб, ўзи юборади.
  final String? initialDraft;

  final String chatId;

  /// Жорий фойдаланувчининг канон рақами (998…).
  final String myUid;

  /// Тафсилот экранидан очилганда — нарх қайта ўқилмайди.
  final WholesaleProduct? initialProduct;

  /// Тест учун; бўлмаса — [DealChatRepository] (Firebase).
  final DealChatRepository? repository;

  @override
  State<DealChatScreen> createState() => _DealChatScreenState();
}

class _DealChatScreenState extends State<DealChatScreen> {
  late final DealChatRepository _repo = widget.repository ?? DealChatRepository();
  late final Stream<List<DealMessage>> _msgStream = _repo.watchMessages(widget.chatId);
  final _ctrl = TextEditingController();
  StreamSubscription<DealChat?>? _chatSub;

  /// Чат ҳужжати — БИТТА обуна (сарлавҳа, роль ва ўқилди белгиси шундан).
  DealChat? _chat;
  WholesaleProduct? _product;
  bool _productRequested = false;
  bool _sending = false;
  bool _marking = false;

  /// Муваффақиятсиз юборилган матн ва унинг clientId'си: шу матн қайта юборилса —
  /// АЙНАН шу ID (сервер дубликат қилмайди, 21-банд).
  String? _pendingText;
  String? _pendingClientId;

  @override
  void initState() {
    super.initState();
    _product = widget.initialProduct;
    final draft = widget.initialDraft?.trim() ?? '';
    if (draft.isNotEmpty) _ctrl.text = draft;
    DealChatPresence.enter(widget.chatId);
    _chatSub = _repo.watchChat(widget.chatId).listen(_onChat, onError: (Object e) {
      debugPrint('[DealChat] watchChat: $e');
    });
  }

  @override
  void dispose() {
    DealChatPresence.leave(widget.chatId);
    _chatSub?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChat(DealChat? chat) {
    if (chat == null || !mounted) return;
    setState(() => _chat = chat);
    // Нарх ва бирлик фақат Улгуржи/Хитой маҳсулотидан; Аралаш бозор чатида — чатдаги нарх.
    if (!_productRequested && _product == null && chat.productId.isNotEmpty && chat.source == 'wholesale') {
      _productRequested = true;
      _repo.fetchProduct(chat.productId).then((p) {
        if (mounted && p != null) setState(() => _product = p);
      });
    }
    // Экран очиқ — янги хабар кўринди: ўқилмаганни нолга (фақат керак бўлса, ёзув тежалади).
    if (chat.unreadFor(widget.myUid) > 0 && !_marking) {
      _marking = true;
      _repo.markRead(widget.chatId).catchError((Object e) {
        debugPrint('[DealChat] markRead: $e');
      }).whenComplete(() => _marking = false);
    }
  }

  Future<void> _send() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty || _sending) return;
    final clientId = (_pendingText == text && _pendingClientId != null)
        ? _pendingClientId!
        : DealChatRepository.newClientId();
    setState(() => _sending = true);
    _ctrl.clear();
    try {
      await _repo.send(chatId: widget.chatId, text: text, clientId: clientId);
      _pendingText = null;
      _pendingClientId = null;
    } catch (e) {
      _pendingText = text;
      _pendingClientId = clientId;
      if (mounted) {
        // Матн йўқолмасин — қайта юбориш учун майдонга қайтади.
        if (_ctrl.text.isEmpty) _ctrl.text = text;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(userErrorMessage(context, e,
              fallbackKey: 'deal_chat_send_failed', byServerMessage: kDealChatServerErrors)),
        ));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = _chat;
    final iAmSeller = chat?.isSeller(widget.myUid) ?? false;
    return Scaffold(
      backgroundColor: context.ava.bg,
      appBar: AppBar(
        title: Text(context.tr(iAmSeller ? 'deal_chat_with_buyer' : 'deal_chat_with_seller')),
        backgroundColor: context.ava.surface,
        foregroundColor: context.ava.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          _ProductHeader(chat: chat, product: _product),
          const Divider(height: 1),
          Expanded(child: _messages()),
          _composer(),
        ],
      ),
    );
  }

  Widget _messages() {
    return StreamBuilder<List<DealMessage>>(
      stream: _msgStream,
      builder: (context, snap) {
        final c = context.ava;
        if (snap.hasError && !snap.hasData) {
          return Center(
              child: Text(context.tr('deal_chat_load_failed'), style: AvaText.body.copyWith(color: c.inkRow)));
        }
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final msgs = snap.data!;
        if (msgs.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                context.tr('deal_chat_empty'),
                key: const ValueKey('deal-chat-empty'),
                textAlign: TextAlign.center,
                style: AvaText.body.copyWith(color: c.ink2),
              ),
            ),
          );
        }
        final readIds = dealReadMessageIds(msgs, myUid: widget.myUid, chat: _chat);
        final rows = withDaySeparators<DealMessage>(msgs, (m) => m.at);
        return ListView.builder(
          key: const ValueKey('deal-chat-messages'),
          reverse: true,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          itemCount: rows.length,
          itemBuilder: (_, i) {
            final r = rows[rows.length - 1 - i];
            if (r is ChatDay) return ChatDaySeparator(day: r.day);
            final m = r as DealMessage;
            final mine = m.from == widget.myUid;
            // Умумий пуфакча (support чат) — `fromPhone` бўш: «Админ» ёрлиғи чиқмайди.
            return MessageBubble(
              key: ValueKey('deal-msg-${m.id}'),
              message: ChatMessage(id: m.id, text: m.text, createdAt: m.at),
              isMine: mine,
              read: mine && readIds != null ? readIds.contains(m.id) : null,
            );
          },
        );
      },
    );
  }

  Widget _composer() {
    return ChatComposer(
      controller: _ctrl,
      onSend: _send,
      sending: _sending,
      hintKey: 'deal_chat_hint',
      maxLength: kDealChatTextMax,
      inputKey: const ValueKey('deal-chat-input'),
      sendKey: const ValueKey('deal-chat-send'),
    );
  }
}

/// Меники хабарлардан қайсилари ҚАРШИ ТОМОН томонидан ўқилган (✓✓). Сервер
/// `unread[қарши томон]` = у ҳали ўқимаган МЕНИКИ хабарлар сони (`sendDealMessage`
/// ошириб, `markDealChatRead` нолга туширади) — шунинг учун меники охирги шунча
/// хабар ўқилмаган, олдингилари ўқилган. Чат ҳужжати ҳали келмаган бўлса — `null`
/// (белги кўрсатилмайди).
Set<String>? dealReadMessageIds(List<DealMessage> msgs, {required String myUid, required DealChat? chat}) {
  if (chat == null) return null;
  final other = chat.isSeller(myUid) ? chat.buyerId : chat.sellerId;
  if (other.isEmpty) return null;
  final mine = msgs.where((m) => m.from == myUid).toList();
  final unread = chat.unreadFor(other).clamp(0, mine.length);
  return {for (final m in mine.take(mine.length - unread)) m.id};
}

/// Маҳсулот: расм, ном, нарх (нарх — маҳсулот ўқилса; ёпиқ/ўчирилган бўлса фақат ном).
class _ProductHeader extends StatelessWidget {
  const _ProductHeader({required this.chat, required this.product});

  final DealChat? chat;
  final WholesaleProduct? product;

  @override
  Widget build(BuildContext context) {
    final p = product;
    final title = (chat?.productTitle.isNotEmpty ?? false) ? chat!.productTitle : (p?.title ?? '');
    final photo = (chat?.productPhoto.isNotEmpty ?? false)
        ? chat!.productPhoto
        : ((p?.imageUrls.isNotEmpty ?? false) ? p!.imageUrls.first : '');
    String? price;
    if (p != null) {
      final pack = p.effectivePacks.first;
      final from = pack.priceTiers.length > 1 ? '${context.tr('home_price_from')} ' : '';
      price = '$from${formatPrice(pack.priceForQty(pack.moq))} ${p.currencyLabel} / '
          '${wholesaleUnitLabel(context, p.unit)}';
    } else if ((chat?.productPrice ?? 0) > 0) {
      price = '${formatPrice(chat!.productPrice!)} ${context.tr('currency_sum')}';
    }
    return Container(
      key: const ValueKey('deal-chat-product'),
      color: AppColors.primary.withValues(alpha: 0.06),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 52,
              height: 52,
              child: photo.isEmpty
                  ? ColoredBox(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.inventory_2_outlined, color: Colors.grey))
                  : Image.network(photo,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => ColoredBox(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.inventory_2_outlined, color: Colors.grey))),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.2)),
                if (price != null) ...[
                  const SizedBox(height: 2),
                  Text(price,
                      key: const ValueKey('deal-chat-price'),
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.primaryText)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
