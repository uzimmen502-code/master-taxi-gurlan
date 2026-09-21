import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../profile/screens/wallet_screen.dart';
import '../models/assistant_conversation.dart';
import '../models/assistant_message.dart';
import '../models/assistant_status.dart';
import '../services/assistant_service.dart';
import '../widgets/assistant_drawer.dart';
import '../widgets/assistant_gpt_colors.dart';
import '../widgets/assistant_pro_sheet.dart';
import 'assistant_memory_screen.dart';

/// «AVA ёрдамчиси» — илова ичидаги AI чат (В-1).
///
/// Кўриниш — расмий ChatGPT мобил иловаси услубида (эга талаби,
/// 2026-09-22): оқ/қора фон, фойдаланувчи хабари — кулранг думалоқ
/// пуфакча ўнгда, ёрдамчи жавоби — пуфакчасиз Markdown матн, pill input +
/// доира "юқорига стрелка" тугмаси, жавоб "ёзилаётгандек" очилади.
/// ChatGPT'нинг Söhne шрифти проприетар — энг яқин очиқ шрифт Inter.
///
/// Суҳбатлар ChatGPT каби алоҳида (`assistant_conversations`), чап панел
/// ([AssistantDrawer]); «Янги суҳбат» эскисини ўчирмайди. Охирги очиқ суҳбат
/// SharedPreferences'да. Юбориш — `assistantChat` callable. Лимит/Pro ҳолати серверда ([AssistantStatus]).
class AssistantChatScreen extends StatefulWidget {
  const AssistantChatScreen({super.key, required this.phone});

  final String phone;

  @override
  State<AssistantChatScreen> createState() => _AssistantChatScreenState();
}

class _AssistantChatScreenState extends State<AssistantChatScreen> {
  final _service = AssistantService();
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focus = FocusNode();
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  static const _prefLastConv = 'assistant_last_conversation';

  /// Фаол суҳбат; `null` — янги (бўш) суҳбат, биринчи хабарда сервер яратади.
  String? _convId;
  String _convTitle = '';
  bool _convLoaded = false;
  String? _titleSubId;
  StreamSubscription<List<AssistantConversation>>? _titleSub;

  AssistantStatus? _status;
  bool _sending = false;
  AssistantMessage? _pendingUser;

  /// Typewriter: серверда сақланган жавоб id → экранда очилаётган матн.
  String? _revealId;
  String _revealText = '';
  Timer? _revealTimer;

  /// Юбориш пайтида экранда бўлган хабар id'лари: сервердан келган ЯНГИ
  /// жавоб typewriter бошлангунча яширилади (акс ҳолда бутун матн бир зумда
  /// кўриниб, кейин қайта «ёзила» бошлайди).
  Set<String> _idsBeforeSend = const {};
  bool _awaitReveal = false;

  /// Охирги snapshot (улашиш/нусхалаш учун).
  List<AssistantMessage> _lastMessages = const [];

  String get _uid => phoneDigits(widget.phone);

  @override
  void initState() {
    super.initState();
    _inputCtrl.addListener(() => setState(() {}));
    _refreshStatus();
    _restoreLastConversation();
  }

  Future<void> _restoreLastConversation() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString('${_prefLastConv}_$_uid');
      if (id != null && id.isNotEmpty && mounted) {
        setState(() => _convId = id);
      }
    } catch (_) {}
    if (mounted) setState(() => _convLoaded = true);
  }

  Future<void> _rememberConversation(String? id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (id == null || id.isEmpty) {
        await prefs.remove('${_prefLastConv}_$_uid');
      } else {
        await prefs.setString('${_prefLastConv}_$_uid', id);
      }
    } catch (_) {}
  }

  void _openConversation(AssistantConversation conv) {
    _revealTimer?.cancel();
    setState(() {
      _convId = conv.id;
      _convTitle = conv.title;
      _revealId = null;
    });
    _rememberConversation(conv.id);
    _scrollToEnd(animate: false);
  }

  @override
  void dispose() {
    _revealTimer?.cancel();
    _titleSub?.cancel();
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    try {
      final s = await _service.getStatus();
      if (mounted) setState(() => _status = s);
    } catch (_) {
      // Статус — фақат кўрсатиш учун; юбориш барибир серверда текширилади.
    }
  }

  void _scrollToEnd({bool animate = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollCtrl.hasClients) return;
      final target = _scrollCtrl.position.maxScrollExtent;
      if (animate) {
        _scrollCtrl.animateTo(
          target,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } else {
        _scrollCtrl.jumpTo(target);
      }
    });
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  /// ChatGPT каби жавобни бўлак-бўлак очиш (сервер бутун матнни қайтаради).
  void _startReveal(String id, String full) {
    _revealTimer?.cancel();
    _revealId = id;
    _revealText = '';
    // Машина босма эффекти: ~3–6 сонияда тўлиқ очилади (узунликка қараб).
    final step = (full.length / 220).ceil().clamp(1, 16);
    var i = 0;
    _revealTimer = Timer.periodic(const Duration(milliseconds: 22), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      i = (i + step).clamp(0, full.length);
      setState(() => _revealText = full.substring(0, i));
      _scrollToEnd(animate: false);
      if (i >= full.length) {
        t.cancel();
        setState(() => _revealId = null);
      }
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _inputCtrl.text).trim();
    if (text.isEmpty || _sending) return;

    final s = _status;
    if (s != null && !s.pro && s.remainingToday <= 0) {
      await _openProSheet(limitReached: true);
      return;
    }

    _inputCtrl.clear();
    setState(() {
      _sending = true;
      _awaitReveal = true;
      _idsBeforeSend = _lastMessages.map((m) => m.id).toSet();
      _pendingUser = AssistantMessage.localUser(text);
    });
    _scrollToEnd();

    try {
      final reply = await _service.send(text, conversationId: _convId);
      if (!mounted) return;
      setState(() {
        _status = reply.status;
        if (_convId != reply.conversationId) {
          _convId = reply.conversationId;
          _convTitle = '';
        }
      });
      _rememberConversation(reply.conversationId);
      _startReveal(reply.messageId, reply.reply);
      setState(() => _awaitReveal = false);
    } on AssistantException catch (e) {
      if (!mounted) return;
      _inputCtrl.text = text;
      if (e.isDailyLimit) {
        await _refreshStatus();
        await _openProSheet(limitReached: true);
      } else {
        _snack(_errorText(e));
      }
    } catch (_) {
      if (!mounted) return;
      _inputCtrl.text = text;
      _snack(context.tr('assistant_err_unavailable'));
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
          _awaitReveal = false;
          _pendingUser = null;
        });
      }
    }
  }

  String _errorText(AssistantException e) {
    switch (e.code) {
      case 'too_fast':
        return context.tr('assistant_err_too_fast');
      case 'assistant_disabled':
        return context.tr('assistant_err_disabled');
      case 'text_too_long':
        return context.tr('assistant_err_too_long');
      default:
        return context.tr('assistant_err_unavailable');
    }
  }

  Future<void> _openProSheet({bool limitReached = false}) async {
    AssistantStatus? status = _status;
    if (status == null) {
      try {
        status = await _service.getStatus();
      } catch (_) {
        if (!mounted) return;
        _snack(context.tr('assistant_err_unavailable'));
        return;
      }
    }
    if (!mounted) return;
    final sheetStatus = status;
    final result = await showModalBottomSheet<AssistantPurchaseResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AssistantProSheet(
        status: sheetStatus,
        service: _service,
        limitReached: limitReached,
        onTopUp: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => WalletScreen(phone: widget.phone)),
        ),
      ),
    );
    if (result != null && mounted) {
      _snack(context.trMsg('assistant_purchased',
          params: {'date': formatDateShort(result.paidUntil)}));
      await _refreshStatus();
    }
  }

  /// ChatGPT каби: эски суҳбат сақланади, янги бўш суҳбат очилади.
  void _newChat() {
    _revealTimer?.cancel();
    setState(() {
      _convId = null;
      _convTitle = '';
      _revealId = null;
      _pendingUser = null;
    });
    _rememberConversation(null);
  }

  /// Сарлавҳа — суҳбат ҳужжатидан (trigger 1–3 с кейин ёзади).
  void _syncTitle(AsyncSnapshot<List<AssistantMessage>> snap) {
    if (_convId == null || _titleSubId == _convId) return;
    _titleSubId = _convId;
    _titleSub?.cancel();
    _titleSub = _service.watchConversations(_uid).listen((list) {
      final conv = list.where((c) => c.id == _convId).firstOrNull;
      if (conv != null && mounted && conv.title != _convTitle) {
        setState(() => _convTitle = conv.title);
      }
    });
  }

  PopupMenuItem<String> _menuItem(
    BuildContext ctx,
    String value,
    IconData icon,
    String label, {
    Color? color,
  }) {
    final c = GptColors.of(ctx);
    return PopupMenuItem<String>(
      value: value,
      height: 44,
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? c.text),
          const SizedBox(width: 12),
          Text(label, style: GoogleFonts.inter(fontSize: 15, color: color ?? c.text)),
        ],
      ),
    );
  }

  /// Суҳбат матни (улашиш/нусхалаш учун) — ChatGPT экспорти услубида.
  String _transcript() {
    final b = StringBuffer();
    if (_convTitle.isNotEmpty) b.writeln('# $_convTitle\n');
    for (final m in _lastMessages) {
      b.writeln(m.isUser ? '**Сиз:**' : '**AVA ёрдамчиси:**');
      b.writeln(m.text.trim());
      b.writeln();
    }
    return b.toString().trim();
  }

  Future<void> _onMenu(String action) async {
    switch (action) {
      case 'share':
        final text = _transcript();
        if (text.isNotEmpty) await Share.share(text);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: _transcript()));
        if (mounted) _snack(context.tr('assistant_copied'));
      case 'rename':
        await _renameCurrent();
      case 'delete':
        await _deleteCurrent();
      case 'memory':
        _openMemory();
      case 'pro':
        await _openProSheet();
    }
  }

  Future<void> _renameCurrent() async {
    final id = _convId;
    if (id == null) return;
    final ctrl = TextEditingController(text: _convTitle);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('assistant_rename')),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 80,
          decoration: const InputDecoration(border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(ctx.tr('save')),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty || title == _convTitle) return;
    try {
      await _service.renameConversation(id, title);
      if (mounted) setState(() => _convTitle = title);
    } catch (_) {
      if (mounted) _snack(context.tr('assistant_err_unavailable'));
    }
  }

  Future<void> _deleteCurrent() async {
    final id = _convId;
    if (id == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.tr('assistant_delete')),
        content: Text(ctx.tr('assistant_delete_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.tr('cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFE53935)),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(ctx.tr('assistant_delete')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteConversation(id);
      if (mounted) _newChat();
    } catch (_) {
      if (mounted) _snack(context.tr('assistant_err_unavailable'));
    }
  }

  void _openMemory() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AssistantMemoryScreen(uid: _uid, service: _service),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = GptColors.of(context);
    final s = _status;
    final String? subtitle;
    if (s == null) {
      subtitle = null;
    } else if (s.unlimited || (s.pro && s.paidUntil == null)) {
      subtitle = context.tr('assistant_pro_unlimited');
    } else if (s.pro) {
      subtitle = context.trMsg('assistant_pro_until',
          params: {'date': formatDateShort(s.paidUntil)});
    } else {
      subtitle = context.trMsg('assistant_free_left',
          params: {'count': '${s.remainingToday}'});
    }

    return Theme(
      data: Theme.of(context).copyWith(
        textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme),
      ),
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: c.bg,
        drawer: AssistantDrawer(
          uid: _uid,
          service: _service,
          activeId: _convId,
          onNewChat: () {
            Navigator.pop(context);
            _newChat();
          },
          onOpen: (conv) {
            Navigator.pop(context);
            _openConversation(conv);
          },
          onOpenMemory: () {
            Navigator.pop(context);
            _openMemory();
          },
        ),
        appBar: AppBar(
          backgroundColor: c.bg,
          surfaceTintColor: Colors.transparent,
          foregroundColor: c.text,
          // Илова темаси AppBar иконкаларини оқ қилади (яшил AppBar учун) —
          // ChatGPT'нинг оқ фонида кўринмай қолади, шунинг учун аниқ берамиз.
          iconTheme: IconThemeData(color: c.text),
          actionsIconTheme: IconThemeData(color: c.text),
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleSpacing: 0,
          leading: IconButton(
            icon: Icon(Icons.menu_rounded, color: c.text),
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
          ),
          title: InkWell(
            onTap: () => _openProSheet(),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _convTitle.isNotEmpty
                        ? _convTitle
                        : context.tr('assistant_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: c.text,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: c.subtle,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            if (s != null && !s.pro)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: TextButton(
                  onPressed: () => _openProSheet(),
                  style: TextButton.styleFrom(
                    foregroundColor: c.text,
                    backgroundColor: c.bubble,
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    minimumSize: const Size(0, 34),
                  ),
                  child: Text(
                    context.tr('assistant_pro_button'),
                    style: GoogleFonts.inter(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            IconButton(
              tooltip: context.tr('assistant_new_chat'),
              icon: Icon(Icons.edit_square, size: 22, color: c.text),
              onPressed: _newChat,
            ),
            PopupMenuButton<String>(
              tooltip: '',
              icon: Icon(Icons.more_horiz_rounded, color: c.text),
              color: c.bg,
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: c.border),
              ),
              onSelected: _onMenu,
              itemBuilder: (ctx) => [
                if (_convId != null) ...[
                  _menuItem(ctx, 'share', Icons.ios_share_rounded,
                      ctx.tr('assistant_share')),
                  _menuItem(ctx, 'copy', Icons.copy_rounded,
                      ctx.tr('assistant_copy_chat')),
                  _menuItem(ctx, 'rename', Icons.drive_file_rename_outline,
                      ctx.tr('assistant_rename')),
                  const PopupMenuDivider(),
                ],
                _menuItem(ctx, 'memory', Icons.psychology_outlined,
                    ctx.tr('assistant_memory')),
                _menuItem(ctx, 'pro', Icons.workspace_premium_rounded,
                    ctx.tr('assistant_pro_sheet_title')),
                if (_convId != null) ...[
                  const PopupMenuDivider(),
                  _menuItem(ctx, 'delete', Icons.delete_outline,
                      ctx.tr('assistant_delete'),
                      color: const Color(0xFFE53935)),
                ],
              ],
            ),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: !_convLoaded
                  ? const SizedBox.shrink()
                  : _convId == null
                  ? (_sending
                      ? ListView(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                          children: [
                            if (_pendingUser != null)
                              _UserBubble(text: _pendingUser!.text),
                            const _ThinkingDot(),
                          ],
                        )
                      : _EmptyState(onTap: (q) => _send(q)))
                  : StreamBuilder<List<AssistantMessage>>(
                key: ValueKey(_convId),
                stream: _service.watchMessages(_uid, _convId!),
                builder: (context, snap) {
                  final server = snap.data ?? const <AssistantMessage>[];
                  if (snap.hasData) _lastMessages = server;
                  final list = <AssistantMessage>[];
                  var serverHasNewUser = false;
                  for (final m in server) {
                    final isNew = _awaitReveal && !_idsBeforeSend.contains(m.id);
                    if (isNew && !m.isUser) continue; // typewriter кутади
                    if (isNew && m.isUser) serverHasNewUser = true;
                    list.add(m);
                  }
                  if (_pendingUser != null && !serverHasNewUser) {
                    list.add(_pendingUser!);
                  }
                  if (snap.connectionState == ConnectionState.waiting &&
                      list.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  if (list.isEmpty && !_sending) {
                    return _EmptyState(onTap: (q) => _send(q));
                  }
                  if (snap.hasData && _revealId == null) _scrollToEnd();
                  // Сарлавҳа сервер (trigger) томонидан кейинроқ келади.
                  _syncTitle(snap);
                  return ListView.builder(
                    controller: _scrollCtrl,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: list.length + (_sending ? 1 : 0),
                    itemBuilder: (_, i) {
                      if (i >= list.length) return const _ThinkingDot();
                      final m = list[i];
                      if (m.isUser) return _UserBubble(text: m.text);
                      final text = m.id == _revealId ? _revealText : m.text;
                      return _AssistantMessageView(
                        text: text,
                        webSearches: m.webSearches,
                        revealing: m.id == _revealId,
                      );
                    },
                  );
                },
              ),
            ),
            _Composer(
              controller: _inputCtrl,
              focusNode: _focus,
              sending: _sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

/// Фойдаланувчи хабари — ChatGPT'дек кулранг думалоқ пуфакча ўнгда.
class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = GptColors.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(top: 8, bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.75,
        ),
        decoration: BoxDecoration(
          color: c.bubble,
          borderRadius: BorderRadius.circular(20),
        ),
        child: SelectableText(
          text,
          style: GoogleFonts.inter(fontSize: 16, height: 1.5, color: c.text),
        ),
      ),
    );
  }
}

/// Ёрдамчи жавоби — пуфакчасиз, Markdown, тўлиқ кенглик (ChatGPT каби).
class _AssistantMessageView extends StatelessWidget {
  const _AssistantMessageView({
    required this.text,
    required this.webSearches,
    required this.revealing,
  });

  final String text;
  final int webSearches;
  final bool revealing;

  @override
  Widget build(BuildContext context) {
    final c = GptColors.of(context);
    final base = GoogleFonts.inter(fontSize: 16, height: 1.55, color: c.text);
    final mono = GoogleFonts.jetBrainsMono(
      fontSize: 13.5,
      height: 1.5,
      color: const Color(0xFFECECEC),
    );
    final sheet = MarkdownStyleSheet(
      p: base,
      pPadding: const EdgeInsets.only(bottom: 10),
      h1: base.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
      h2: base.copyWith(fontSize: 19, fontWeight: FontWeight.w700),
      h3: base.copyWith(fontSize: 17, fontWeight: FontWeight.w600),
      h1Padding: const EdgeInsets.only(top: 10, bottom: 4),
      h2Padding: const EdgeInsets.only(top: 10, bottom: 4),
      h3Padding: const EdgeInsets.only(top: 8, bottom: 2),
      strong: base.copyWith(fontWeight: FontWeight.w600),
      em: base.copyWith(fontStyle: FontStyle.italic),
      a: base.copyWith(
        color: const Color(0xFF2D6CDF),
        decoration: TextDecoration.underline,
      ),
      listBullet: base,
      listIndent: 22,
      blockSpacing: 10,
      blockquote: base.copyWith(color: c.subtle),
      blockquoteDecoration: BoxDecoration(
        border: Border(left: BorderSide(color: c.border, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.only(left: 12),
      code: GoogleFonts.jetBrainsMono(
        fontSize: 14,
        color: c.text,
        backgroundColor: c.bubble,
      ),
      codeblockDecoration: BoxDecoration(
        color: c.codeBg,
        borderRadius: BorderRadius.circular(12),
      ),
      codeblockPadding: const EdgeInsets.all(14),
      tableHead: base.copyWith(fontWeight: FontWeight.w600),
      tableBody: base.copyWith(fontSize: 15),
      tableBorder: TableBorder.all(color: c.border, width: 1),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      tableColumnWidth: const IntrinsicColumnWidth(),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(top: BorderSide(color: c.border)),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownBody(
            data: text,
            selectable: !revealing,
            styleSheet: sheet,
            // Код блоклари: ChatGPT каби қора фон, оқ моно шрифт.
            styleSheetTheme: MarkdownStyleSheetBaseTheme.material,
            onTapLink: (_, href, __) {
              if (href == null) return;
              launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
            },
            builders: {'pre': _CodeBlockBuilder(mono, c)},
          ),
          if (!revealing)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  _IconAction(
                    icon: Icons.copy_rounded,
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: text));
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(
                          content: Text(context.tr('assistant_copied')),
                          duration: const Duration(seconds: 1),
                        ));
                    },
                  ),
                  if (webSearches > 0) ...[
                    const SizedBox(width: 10),
                    Icon(Icons.public, size: 14, color: c.subtle),
                    const SizedBox(width: 4),
                    Text(
                      context.tr('assistant_web_search_used'),
                      style: GoogleFonts.inter(fontSize: 12, color: c.subtle),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Код блоки — ChatGPT'дек: устида тил ёрлиғи + «Нусхалаш», қора фон.
class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder(this.mono, this.c);

  final TextStyle mono;
  final GptColors c;

  @override
  Widget? visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    var lang = '';
    final children = element.children;
    var code = element.textContent;
    if (children != null && children.isNotEmpty) {
      final first = children.first;
      if (first is md.Element) {
        final cls = first.attributes['class'] ?? '';
        if (cls.startsWith('language-')) lang = cls.substring(9);
        code = first.textContent;
      }
    }
    if (code.endsWith('\n')) code = code.substring(0, code.length - 1);
    return Builder(
      builder: (context) => Container(
        margin: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: c.codeBg,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 6, 6, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      lang,
                      style: GoogleFonts.inter(
                          fontSize: 12, color: const Color(0xFFB4B4B4)),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: code));
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(SnackBar(
                          content: Text(context.tr('assistant_copied')),
                          duration: const Duration(seconds: 1),
                        ));
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: const Color(0xFFB4B4B4),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 30),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    label: Text(
                      context.tr('assistant_copy'),
                      style: GoogleFonts.inter(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: SelectableText(code, style: mono),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  const _IconAction({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = GptColors.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: c.subtle),
      ),
    );
  }
}

/// ChatGPT'нинг "ўйлаяпти" белгиси — пульсланувчи доира.
class _ThinkingDot extends StatefulWidget {
  const _ThinkingDot();

  @override
  State<_ThinkingDot> createState() => _ThinkingDotState();
}

class _ThinkingDotState extends State<_ThinkingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = GptColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: ScaleTransition(
          scale: Tween(begin: 0.7, end: 1.0).animate(
            CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
          ),
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(color: c.text, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}

/// Pill input + доира "юқорига стрелка" тугмаси (ChatGPT композитори).
class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.focusNode,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final c = GptColors.of(context);
    final canSend = controller.text.trim().isNotEmpty && !sending;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
        child: Container(
          decoration: BoxDecoration(
            color: c.inputBg,
            borderRadius: BorderRadius.circular(26),
          ),
          padding: const EdgeInsets.fromLTRB(18, 6, 6, 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  minLines: 1,
                  maxLines: 6,
                  enabled: !sending,
                  textInputAction: TextInputAction.newline,
                  style: GoogleFonts.inter(
                      fontSize: 16, height: 1.4, color: c.text),
                  decoration: InputDecoration(
                    hintText: context.tr('assistant_hint'),
                    hintStyle: GoogleFonts.inter(
                        fontSize: 16, color: c.subtle),
                    border: InputBorder.none,
                    isCollapsed: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 150),
                opacity: canSend ? 1 : 0.35,
                child: Material(
                  color: c.sendBg,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: canSend ? onSend : null,
                    child: SizedBox(
                      width: 36,
                      height: 36,
                      child: sending
                          ? Padding(
                              padding: const EdgeInsets.all(10),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: c.sendFg,
                              ),
                            )
                          : Icon(Icons.arrow_upward_rounded,
                              color: c.sendFg, size: 22),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Бўш ҳолат — ChatGPT'дек марказда сарлавҳа + таклиф чиплари.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onTap});

  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final c = GptColors.of(context);
    final starters = [
      context.tr('assistant_starter_1'),
      context.tr('assistant_starter_2'),
      context.tr('assistant_starter_3'),
      context.tr('assistant_starter_4'),
    ];
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              context.tr('assistant_empty_title'),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 24,
                fontWeight: FontWeight.w600,
                color: c.text,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr('assistant_empty_body'),
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(fontSize: 14, color: c.subtle),
            ),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final q in starters)
                  ActionChip(
                    label: Text(q,
                        style: GoogleFonts.inter(fontSize: 13, color: c.text)),
                    onPressed: () => onTap(q),
                    backgroundColor: c.bg,
                    side: BorderSide(color: c.border),
                    shape: const StadiumBorder(),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
