import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/message_thread_group.dart';
import '../../../models/news_item.dart';
import '../../../models/order_news_group.dart';
import '../../../repositories/chat_repository.dart';
import '../../../repositories/driver_repository.dart';
import '../../../repositories/news_repository.dart';
import '../../../repositories/user_repository.dart';
import '../../../services/user_audience.dart';
import '../../chat/screens/chat_screen.dart';
import '../../deal_chat/data/deal_chat_repository.dart';
import '../../deal_chat/screens/deal_chat_screen.dart';
import '../inbox/inbox_entries.dart';
import '../inbox/inbox_read_store.dart';
import '../inbox/inbox_tile.dart';
import '../inbox/news_detail_screen.dart';
import '../inbox_hide_keys.dart';
import 'dialog_news_detail_screen.dart';
import 'order_news_detail_screen.dart';

/// «Хабарлар» — битта рўйхат ва тепада филтрлар (эга, 2026-11-02: бошқа
/// иловалар билан солиштириб такомиллаштириш, таклиф қабул қилинди).
///
/// Аввалги 3 таб («Янгилик / Хабарлар / Буюртма») ўрнига: «Барчаси · Чатлар ·
/// Буюртмалар · Янгиликлар». «AVA ёрдам» доим тепада; ҳар бир буюртма чати
/// алоҳида қатор; суриб ўчириш («Бекор қилиш» билан); қидирув; пастга тортиб
/// янгилаш; қатор очилгунча ўқилмаган ([InboxReadStore]).
class NewsHubScreen extends StatefulWidget {
  const NewsHubScreen({super.key, this.initialTabIndex, this.readStore});

  /// Push'дан (`push_navigation.dart` → `_newsHubTabIndex`): 0 — Янгиликлар,
  /// 1 — Чатлар, 2 — Буюртмалар. `null` (бош меню) — «Барчаси».
  final int? initialTabIndex;

  /// Тест учун (бўлмаса — SharedPreferences).
  final InboxReadStore? readStore;

  @override
  State<NewsHubScreen> createState() => _NewsHubScreenState();
}

class _NewsHubScreenState extends State<NewsHubScreen> {
  String _uid = '';
  String _role = 'user';
  bool _started = false;
  InboxReadStore _read = InboxReadStore.memory();

  late InboxFilter _filter = switch (widget.initialTabIndex) {
    0 => InboxFilter.news,
    1 => InboxFilter.chats,
    2 => InboxFilter.orders,
    _ => InboxFilter.all,
  };

  bool _searching = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  InboxNewsLists? _news;
  Object? _newsError;
  SupportChatMeta _support = SupportChatMeta.empty;
  Map<String, dynamic>? _driver;
  List<DealChat> _deals = const [];
  bool _dealsError = false;
  Set<String> _dismissed = <String>{};

  /// Суриб ўчирилган, лекин «Бекор қилиш» муддати ҳали тугамаган ID'лар.
  final Set<String> _pending = <String>{};

  final List<StreamSubscription<dynamic>> _subs = [];

  T? _maybe<T>() {
    try {
      return context.read<T>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  DealChatRepository _dealRepo() => _maybe<DealChatRepository>() ?? DealChatRepository();

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    final role = UserAudience.fromPrefs(prefs);
    final read = widget.readStore ?? await InboxReadStore.load();
    if (!mounted) return;
    _uid = uid;
    _role = role;
    _read = read;
    if (uid.length >= 9) {
      await _ensureBaselines();
      if (!mounted) return;
      _subscribe();
      // Бош менюдаги белги: экран очилди — бўлимлар «кўрилди» (аввал фақат очиқ таб).
      // Қаторларнинг ўзи эса очилгунча жирний қолади ([InboxReadStore]).
      unawaited(_markServerSeen());
    }
    setState(() => _started = true);
  }

  /// Биринчи очилишда: сервердаги «ўқилди» вақтлари — ўқилмаганлар жирний бўлиб
  /// қолиши учун ([InboxReadStore.ensureBaseline]). Сервер жавоб бермаса — «ҳозир».
  Future<void> _ensureBaselines() async {
    if (InboxFeed.all.every(_read.hasBaseline)) return;
    final now = DateTime.now();
    ({DateTime? news, DateTime? messages, DateTime? orders})? r;
    try {
      r = await context.read<NewsRepository>().fetchLastReadAt(_uid);
    } catch (e) {
      debugPrint('[Inbox] fetchLastReadAt: $e');
    }
    // Ҳеч қачон ўқимаган — 30 кун: эски хабарлар бирданига «янги» бўлиб кетмасин.
    final never = now.subtract(const Duration(days: 30));
    await _read.ensureBaseline(InboxFeed.news, r == null ? now : (r.news ?? never), fallback: now);
    await _read.ensureBaseline(InboxFeed.messages, r == null ? now : (r.messages ?? never), fallback: now);
    await _read.ensureBaseline(InboxFeed.orders, r == null ? now : (r.orders ?? never), fallback: now);
  }

  Future<void> _markServerSeen() async {
    final users = _maybe<UserRepository>();
    if (users == null) return;
    try {
      await users.markNewsRead(_uid);
      await users.markMessagesRead(_uid);
      await users.markOrderNewsRead(_uid);
    } catch (e) {
      debugPrint('[Inbox] mark seen: $e');
    }
  }

  void _subscribe() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    final news = context.read<NewsRepository>();
    _subs.add(news.watchInboxNews(userId: _uid, role: _role).listen((v) {
      if (!mounted) return;
      setState(() {
        _news = v;
        _newsError = null;
      });
    }, onError: (Object e) {
      debugPrint('[Inbox] news: $e');
      if (mounted) setState(() => _newsError = e);
    }));
    _subs.add(news.watchDismissedIds(_uid).listen((ids) {
      // Тўплам фақат ўсади (янги ўчириш дарров кўринади).
      if (mounted) setState(() => _dismissed = {..._dismissed, ...ids});
    }, onError: (Object e) => debugPrint('[Inbox] dismissed: $e')));
    final chat = _maybe<ChatRepository>();
    if (chat != null) {
      _subs.add(chat.watchSupportMeta(_uid).listen((m) {
        if (mounted) setState(() => _support = m);
      }, onError: (Object e) => debugPrint('[Inbox] support: $e')));
    }
    final driver = _maybe<DriverRepository>();
    if (driver != null) {
      _subs.add(driver.watchMyDriverRequest(_uid).listen((d) {
        if (mounted) setState(() => _driver = d);
      }, onError: (Object e) => debugPrint('[Inbox] driver: $e')));
    }
    _subs.add(_dealRepo().watchMyChats(_uid).listen((list) {
      if (!mounted) return;
      setState(() {
        _deals = list;
        _dealsError = false;
      });
    }, onError: (Object e) {
      debugPrint('[Inbox] deal chats: $e');
      if (mounted) setState(() => _dealsError = true);
    }));
  }

  Future<void> _refresh() async {
    setState(() {
      _newsError = null;
      _dealsError = false;
    });
    _subscribe();
    await Future<void>.delayed(const Duration(milliseconds: 600));
  }

  List<InboxEntry> _entries() {
    final n = _news ?? const InboxNewsLists();
    return buildInboxEntries(
      InboxData(
        broadcast: n.broadcast,
        dialog: n.dialog,
        orders: n.orders,
        support: _support,
        driver: _driver,
        deals: _deals,
        hidden: {..._dismissed, ..._pending},
      ),
      uid: _uid,
      read: _read,
      tr: context.tr,
    );
  }

  // ─── Ҳаракатлар ───

  Future<void> _open(InboxEntry e) async {
    if (e.feed.isNotEmpty) {
      await _read.markOpened(e.key);
      if (mounted) setState(() {});
    }
    if (!mounted) return;
    final Widget? screen = switch (e.kind) {
      InboxKind.support => ChatScreen(targetPhone: _uid),
      InboxKind.deal => DealChatScreen(
          chatId: (e.payload as DealChat).id, myUid: _uid, repository: _maybe<DealChatRepository>()),
      InboxKind.dialog => DialogNewsDetailScreen(group: e.payload as MessageThreadGroup),
      InboxKind.order => OrderNewsDetailScreen(group: e.payload as OrderNewsGroup),
      InboxKind.news => NewsDetailScreen(item: e.payload as NewsItem),
      // Ариза ҳолати қаторнинг ўзида тўлиқ ёзилган — очиладиган экран йўқ.
      InboxKind.driver => null,
    };
    if (screen == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  /// Суриб ўчириш: дарров йўқолади, 4 сония «Бекор қилиш» мумкин, кейин серверга
  /// (`users/{uid}/dismissed_news` — аввалги ўчириш механизми, барча қурилмада).
  void _dismiss(InboxEntry e) {
    final support = e.kind == InboxKind.support;
    final ids = support ? [InboxHideKeys.supportChatCleared(DateTime.now())] : e.dismissIds;
    if (ids.isEmpty) return;
    final repo = context.read<NewsRepository>();
    final uid = _uid;
    setState(() => _pending.addAll(ids));
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    var undone = false;
    final ctrl = messenger.showSnackBar(SnackBar(
      key: const ValueKey('inbox-undo-snack'),
      content: Text(context.tr(support ? 'inbox_history_cleared' : 'inbox_deleted')),
      duration: const Duration(seconds: 4),
      // Flutter 3.41: тугмали SnackBar ўз-ўзидан ЁПИЛМАЙДИ (`persist ?? action != null`) —
      // ўшанда ўчириш серверга ҳеч қачон ёзилмас эди.
      persist: false,
      action: SnackBarAction(
        label: context.tr('inbox_undo'),
        onPressed: () {
          undone = true;
          if (mounted) setState(() => _pending.removeAll(ids));
        },
      ),
    ));
    ctrl.closed.then((_) async {
      if (undone) return;
      try {
        await repo.dismissNews(uid, ids);
        if (mounted) setState(() => _dismissed = {..._dismissed, ...ids});
      } catch (err) {
        debugPrint('[Inbox] dismiss: $err');
        // Ёзилмади — қатор қайтади (жимгина йўқолиб, кейин пайдо бўлмасин).
        if (mounted) setState(() => _pending.removeAll(ids));
      }
    });
  }

  Future<void> _markAllRead(List<InboxEntry> all) async {
    await _read.markAllRead(InboxFeed.all);
    if (!mounted) return;
    setState(() {});
    final deals = _dealRepo();
    for (final e in all) {
      if (e.kind == InboxKind.deal && e.unreadCount > 0) {
        unawaited(deals.markRead((e.payload as DealChat).id).catchError((Object err) {
          debugPrint('[Inbox] deal markRead: $err');
        }));
      }
      if (e.kind == InboxKind.support && e.unreadCount > 0) {
        unawaited(_maybe<ChatRepository>()?.markUserRead(_uid).catchError((Object err) {
          debugPrint('[Inbox] support markRead: $err');
        }));
      }
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(context.tr('inbox_marked_all'))));
  }

  Future<void> _rowMenu(InboxEntry e) async {
    final c = context.ava;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: c.surface,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (e.feed.isNotEmpty && e.unread)
              ListTile(
                leading: const Icon(Icons.done_all),
                title: Text(ctx.tr('inbox_mark_read')),
                onTap: () => Navigator.pop(ctx, 'read'),
              ),
            if (e.canDismiss)
              ListTile(
                leading: Icon(Icons.delete_outline, color: c.danger),
                title: Text(
                  ctx.tr(e.kind == InboxKind.support ? 'inbox_clear_history' : 'inbox_delete'),
                  style: TextStyle(color: c.danger),
                ),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );
    if (!mounted) return;
    if (action == 'read') {
      await _read.markOpened(e.key);
      if (mounted) setState(() {});
    } else if (action == 'delete') {
      _dismiss(e);
    }
  }

  // ─── Кўриниш ───

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final all = _uid.length >= 9 ? _entries() : const <InboxEntry>[];
    return Scaffold(
      backgroundColor: c.bg,
      appBar: _appBar(c, all),
      body: !_started
          ? const Center(child: CircularProgressIndicator())
          : _uid.length < 9
              ? _Empty(icon: Icons.lock_outline, title: context.tr('msgs_phone_required'))
              : Column(
                  children: [
                    _filters(c, all),
                    if (_newsError != null || _dealsError) _errorBanner(c),
                    Expanded(child: _list(c, all)),
                  ],
                ),
    );
  }

  PreferredSizeWidget _appBar(AvaColors c, List<InboxEntry> all) {
    return AppBar(
      backgroundColor: c.surface,
      foregroundColor: c.ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: _searching ? 0 : AvaSpace.screen,
      leading: _searching
          ? IconButton(
              tooltip: context.tr('inbox_search_close'),
              icon: const Icon(Icons.arrow_back),
              onPressed: () => setState(() {
                _searching = false;
                _searchCtrl.clear();
                _query = '';
              }),
            )
          : null,
      automaticallyImplyLeading: !_searching && Navigator.of(context).canPop(),
      title: _searching
          ? TextField(
              key: const ValueKey('inbox-search-field'),
              controller: _searchCtrl,
              autofocus: true,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: context.tr('inbox_search_hint'),
                border: InputBorder.none,
              ),
              onChanged: (v) => setState(() => _query = v),
            )
          // `home_nav_messages` — пастки менюдаги ном билан бир хил (`bottom_news` русчада «Новости» эди).
          : Text(context.tr('home_nav_messages'), style: AvaText.sectionTitle.copyWith(fontSize: 20, color: c.ink)),
      actions: [
        if (!_searching && _uid.length >= 9) ...[
          IconButton(
            key: const ValueKey('inbox-search'),
            tooltip: context.tr('inbox_search'),
            icon: const Icon(Icons.search),
            onPressed: () => setState(() => _searching = true),
          ),
          IconButton(
            key: const ValueKey('inbox-mark-all'),
            tooltip: context.tr('inbox_mark_all'),
            icon: const Icon(Icons.done_all),
            onPressed: () => _markAllRead(all),
          ),
        ],
      ],
    );
  }

  Widget _filters(AvaColors c, List<InboxEntry> all) {
    const order = [InboxFilter.all, InboxFilter.chats, InboxFilter.orders, InboxFilter.news];
    String label(InboxFilter f) => context.tr(switch (f) {
          InboxFilter.all => 'inbox_filter_all',
          InboxFilter.chats => 'inbox_filter_chats',
          InboxFilter.orders => 'inbox_filter_orders',
          InboxFilter.news => 'inbox_filter_news',
        });
    return Container(
      color: c.surface,
      height: 48,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 6, AvaSpace.screen, 10),
        itemCount: order.length,
        separatorBuilder: (_, __) => const SizedBox(width: AvaSpace.gap),
        itemBuilder: (_, i) {
          final f = order[i];
          final selected = f == _filter;
          final n = inboxFilterCount(all, f);
          return Semantics(
            selected: selected,
            button: true,
            child: InkWell(
              key: ValueKey('inbox-filter-${f.name}'),
              borderRadius: BorderRadius.circular(AvaRadius.chip),
              onTap: () => setState(() => _filter = f),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? c.ink : c.chip,
                  borderRadius: BorderRadius.circular(AvaRadius.chip),
                  border: Border.all(color: selected ? c.ink : c.line),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      label(f),
                      style: AvaText.body.copyWith(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: selected ? c.surface : c.inkRow,
                      ),
                    ),
                    if (n > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        n > 99 ? '99+' : '$n',
                        key: ValueKey('inbox-filter-count-${f.name}'),
                        style: AvaText.caption.copyWith(
                          fontWeight: FontWeight.w700,
                          color: selected ? c.brand : c.brandText,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _errorBanner(AvaColors c) {
    return Material(
      key: const ValueKey('inbox-error-banner'),
      color: c.warnSoft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AvaSpace.screen, 6, 6, 6),
        child: Row(
          children: [
            Icon(Icons.cloud_off_outlined, size: 18, color: c.warn),
            const SizedBox(width: 8),
            Expanded(
              child: Text(context.tr('inbox_partial_error'), style: AvaText.caption.copyWith(color: c.inkRow)),
            ),
            TextButton(onPressed: _refresh, child: Text(context.tr('inbox_retry'))),
          ],
        ),
      ),
    );
  }

  Widget _list(AvaColors c, List<InboxEntry> all) {
    final loading = _news == null && _newsError == null;
    final shown = filterInbox(all, _filter, _query);
    // «AVA ёрдам» доим бор — ундан бошқа ҳеч нарса бўлмаса ҳам рўйхат кўринади,
    // лекин бўш ҳолат матни остида (фақат «Барчаси»/«Чатлар»да).
    final onlySupport = shown.length == 1 && shown.first.kind == InboxKind.support;
    final now = DateTime.now();
    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        key: const ValueKey('inbox-list'),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: shown.length + (loading || shown.isEmpty || onlySupport ? 1 : 0),
        itemBuilder: (_, i) {
          if (i >= shown.length) {
            if (loading) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return _query.trim().isNotEmpty
                ? _Empty(icon: Icons.search_off, title: context.tr('inbox_search_empty'))
                : _Empty(
                    icon: Icons.inbox_outlined,
                    title: context.tr(_filter == InboxFilter.all ? 'inbox_empty_all_title' : 'inbox_empty_filter'),
                    hint: _filter == InboxFilter.all ? context.tr('inbox_empty_all_hint') : null,
                  );
          }
          final e = shown[i];
          final tile = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InboxTile(entry: e, now: now, onTap: () => _open(e), onLongPress: () => _rowMenu(e)),
              Divider(height: 1, thickness: 0.5, indent: AvaSpace.screen + InboxTile.avatar + 12, color: c.line),
            ],
          );
          if (!e.canDismiss) return KeyedSubtree(key: ValueKey(e.key), child: tile);
          return Dismissible(
            key: ValueKey('dismiss-${e.key}'),
            direction: DismissDirection.endToStart,
            background: Container(
              color: c.danger,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 24),
              child: Icon(e.kind == InboxKind.support ? Icons.cleaning_services_outlined : Icons.delete_outline,
                  color: Colors.white),
            ),
            // «AVA ёрдам» қатори ЎЗИ қолади (админга ёзишнинг йўли) — фақат тарих тозаланади.
            confirmDismiss: (_) async {
              if (e.kind == InboxKind.support) {
                _dismiss(e);
                return false;
              }
              return true;
            },
            onDismissed: (_) => _dismiss(e),
            child: tile,
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.icon, required this.title, this.hint});

  final IconData icon;
  final String title;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 48, 32, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: c.ink3),
          const SizedBox(height: 12),
          Text(title,
              textAlign: TextAlign.center,
              style: AvaText.sectionTitle.copyWith(color: c.inkRow)),
          if (hint != null) ...[
            const SizedBox(height: 6),
            Text(hint!, textAlign: TextAlign.center, style: AvaText.body.copyWith(color: c.ink2)),
          ],
        ],
      ),
    );
  }
}
