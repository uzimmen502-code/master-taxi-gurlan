import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/news_read_state.dart';
import '../../../repositories/news_repository.dart';
import '../../../repositories/user_repository.dart';
import 'general_news_tab.dart';
import 'messages_tab.dart';
import 'order_news_tab.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/user_audience.dart';

/// Хабарлар — «Янгилик», «Хабарлар», «Буюртма».
class NewsHubScreen extends StatefulWidget {
  const NewsHubScreen({super.key, this.initialTabIndex = 0});

  /// 0 — Янгилик, 1 — Хабарлар, 2 — Буюртма.
  final int initialTabIndex;

  @override
  State<NewsHubScreen> createState() => _NewsHubScreenState();
}

class _NewsHubScreenState extends State<NewsHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabs;
  int _unreadBroadcast = 0;
  int _unreadMessages = 0;
  int _unreadOrders = 0;
  String _uid = '';
  String _role = 'user';
  NewsReadState _newsRead = NewsReadState.unknown;
  NewsReadState _messagesRead = NewsReadState.unknown;
  NewsReadState _ordersRead = NewsReadState.unknown;
  StreamSubscription<int>? _broadcastUnreadSub;
  StreamSubscription<int>? _messagesUnreadSub;
  StreamSubscription<int>? _orderUnreadSub;

  @override
  void initState() {
    super.initState();
    final startTab = widget.initialTabIndex.clamp(0, 2);
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: startTab,
    );
    _tabs.addListener(_onTabChanged);
    _bootstrap();
  }

  @override
  void dispose() {
    _broadcastUnreadSub?.cancel();
    _messagesUnreadSub?.cancel();
    _orderUnreadSub?.cancel();
    _tabs.removeListener(_onTabChanged);
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadContext();
    if (!mounted) return;
    await _captureReadState();
    if (!mounted) return;
    _startUnreadWatchers();
    _markReadForTab(_tabs.index);
  }

  /// Белгилашдан ОЛДИН: қайси хабарлар «янги» эканини рўйхатда кўрсатиш учун.
  Future<void> _captureReadState() async {
    if (_uid.length < 9) return;
    try {
      final r = await context.read<NewsRepository>().fetchLastReadAt(_uid);
      if (!mounted) return;
      setState(() {
        _newsRead = NewsReadState(known: true, readBefore: r.news);
        _messagesRead = NewsReadState(known: true, readBefore: r.messages);
        _ordersRead = NewsReadState(known: true, readBefore: r.orders);
      });
    } catch (_) {
      // Ҳолат номаълум — ҳамма хабар ўқилгандек кўринади, экран ишлайверади.
    }
  }

  void _onTabChanged() {
    if (!_tabs.indexIsChanging) {
      _markReadForTab(_tabs.index);
    }
  }

  Future<void> _loadContext() async {
    final prefs = await SharedPreferences.getInstance();
    _uid = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    _role = UserAudience.fromPrefs(prefs);
    if (_uid.length < 9 && mounted) {
      setState(() {
        _unreadBroadcast = 0;
        _unreadMessages = 0;
        _unreadOrders = 0;
      });
    }
  }

  void _startUnreadWatchers() {
    _broadcastUnreadSub?.cancel();
    _messagesUnreadSub?.cancel();
    _orderUnreadSub?.cancel();
    if (_uid.length < 9) return;

    final newsRepo = context.read<NewsRepository>();
    final audiences = ['all', _role];

    _broadcastUnreadSub = newsRepo
        .watchUnreadCount(
      userId: _uid,
      audiences: audiences,
      feed: NewsFeedKind.broadcast,
    )
        .listen((n) {
      if (mounted) setState(() => _unreadBroadcast = n);
    }, onError: (_) {});

    _messagesUnreadSub = newsRepo
        .watchUnreadCount(
      userId: _uid,
      audiences: audiences,
      feed: NewsFeedKind.dialog,
    )
        .listen((n) {
      if (mounted) setState(() => _unreadMessages = n);
    }, onError: (_) {});

    _orderUnreadSub = newsRepo
        .watchUnreadCount(
      userId: _uid,
      audiences: audiences,
      feed: NewsFeedKind.order,
    )
        .listen((n) {
      if (mounted) setState(() => _unreadOrders = n);
    }, onError: (_) {});
  }

  Future<void> _loadUnread() async {
    await _loadContext();
    _startUnreadWatchers();
  }

  Future<void> _markReadForTab(int index) async {
    if (_uid.length < 9) return;
    final userRepo = context.read<UserRepository>();
    switch (index) {
      case 0:
        await userRepo.markNewsRead(_uid);
      case 1:
        await userRepo.markMessagesRead(_uid);
      case 2:
        await userRepo.markOrderNewsRead(_uid);
    }
    await _loadUnread();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: const Text('Хабарлар'),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: AppColors.onPrimary,
          labelColor: AppColors.onPrimary,
          unselectedLabelColor: AppColors.onPrimary.withValues(alpha: 0.7),
          tabs: [
            Tab(
              child: _TabLabel(
                text: 'Янгилик',
                badge: _unreadBroadcast,
              ),
            ),
            Tab(
              child: _TabLabel(
                text: 'Хабарлар',
                badge: _unreadMessages,
              ),
            ),
            Tab(
              child: _TabLabel(
                text: 'Буюртма',
                badge: _unreadOrders,
              ),
            ),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          GeneralNewsTab(readState: _newsRead),
          MessagesTab(
            readState: _messagesRead,
            onMarkedRead: () => _markReadForTab(1),
          ),
          OrderNewsTab(
            readState: _ordersRead,
            onMarkedRead: () => _markReadForTab(2),
          ),
        ],
      ),
    );
  }
}

class _TabLabel extends StatelessWidget {
  const _TabLabel({required this.text, required this.badge});

  final String text;
  final int badge;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(text),
        if (badge > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              badge > 99 ? '99+' : '$badge',
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ],
    );
  }
}
