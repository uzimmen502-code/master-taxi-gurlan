import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/utils/formatters.dart';
import '../../../repositories/news_repository.dart';
import '../../chat/screens/chat_screen.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../profile/screens/news_hub_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../profile/screens/wallet_screen.dart';
import '../../../core/theme/app_theme.dart';
import '../controllers/home_controller.dart';

/// Пастки bar — Хабарлар · Чат · Кошелёк · Профиль.
class HomeBottomBar extends StatefulWidget {
  const HomeBottomBar({super.key});

  @override
  State<HomeBottomBar> createState() => _HomeBottomBarState();
}

class _HomeBottomBarState extends State<HomeBottomBar> {
  int _unreadTotal = 0;
  int _boldIndex = 0;
  Timer? _boldCycleTimer;
  HomeController? _home;
  StreamSubscription<int>? _unreadSub;

  static const _labelCount = 4;

  @override
  void initState() {
    super.initState();
    _boldCycleTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted) return;
      setState(() => _boldIndex = (_boldIndex + 1) % _labelCount);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _home = context.read<HomeController>();
      _home!.addListener(_restartUnreadWatch);
      _restartUnreadWatch();
    });
  }

  @override
  void dispose() {
    _boldCycleTimer?.cancel();
    _unreadSub?.cancel();
    _home?.removeListener(_restartUnreadWatch);
    super.dispose();
  }

  void _restartUnreadWatch() {
    _unreadSub?.cancel();
    final home = context.read<HomeController>();
    final phone = phoneDigits(home.phone);
    if (phone.length < 9) {
      if (mounted) setState(() => _unreadTotal = 0);
      return;
    }
    final audiences = ['all', home.role.isEmpty ? 'user' : home.role];
    _unreadSub = context
        .read<NewsRepository>()
        .watchUnreadTotal(userId: phone, audiences: audiences)
        .listen(
      (n) {
        if (mounted) setState(() => _unreadTotal = n);
      },
      onError: (_) {},
    );
  }

  String _phoneDigits() => phoneDigits(context.read<HomeController>().phone);

  Future<void> _openProfile() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const ProfileScreen()),
    );
    if (!mounted) return;
    await context.read<HomeController>().refreshUser();
    _restartUnreadWatch();
  }

  void _needPhone() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.tr('need_phone_profile')),
        duration: const Duration(seconds: 3),
      ),
    );
    _openProfile();
  }

  Future<void> _openNews() async {
    if (_phoneDigits().length < 9) {
      _needPhone();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const NewsHubScreen()),
    );
  }

  void _openChat() {
    final phone = _phoneDigits();
    if (phone.length < 9) {
      _needPhone();
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(targetPhone: phone),
      ),
    );
  }

  Future<void> _openWallet() async {
    final phone = _phoneDigits();
    if (phone.length < 9) {
      _needPhone();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => WalletScreen(phone: phone)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final home = context.watch<HomeController>();
    final initial = home.name.isNotEmpty ? home.name[0].toUpperCase() : '?';

    return Container(
      color: AppColors.scaffold,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: SafeArea(
        top: false,
        child: Material(
          elevation: 8,
          shadowColor: const Color(0x1A0E7A38),
          color: AppColors.bottomBarCapsule,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: 64,
            child: Row(
            children: [
              _BarItem(
                icon: Icons.newspaper_rounded,
                iconColor: const Color(0xFF1565C0),
                iconBackground: const Color(0xFFE3F2FD),
                label: context.tr('bottom_news'),
                labelBold: _boldIndex == 0,
                badge: _unreadTotal > 0 ? _unreadTotal : null,
                onTap: _openNews,
              ),
              _BarItem(
                icon: Icons.forum_rounded,
                iconColor: AppColors.primary,
                iconBackground: const Color(0xFFE8F5E9),
                label: context.tr('bottom_chat'),
                labelBold: _boldIndex == 1,
                onTap: _openChat,
              ),
              _BarItem(
                icon: Icons.account_balance_wallet_rounded,
                iconColor: AppColors.accentGold,
                iconBackground: const Color(0xFFFFF8E1),
                label: context.tr('bottom_wallet'),
                labelBold: _boldIndex == 2,
                onTap: _openWallet,
              ),
              _BarItem(
                label: context.tr('bottom_profile'),
                labelBold: _boldIndex == 3,
                onTap: _openProfile,
                avatarLetter: initial,
              ),
            ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.label,
    required this.onTap,
    this.labelBold = false,
    this.icon,
    this.iconColor,
    this.iconBackground,
    this.badge,
    this.avatarLetter,
  });

  final IconData? icon;
  final Color? iconColor;
  final Color? iconBackground;
  final String label;
  final bool labelBold;
  final VoidCallback onTap;
  final int? badge;
  final String? avatarLetter;

  static const _active = AppColors.primary;
  static const _inactive = Color(0xFF9CA3AF);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              height: 32,
              width: 40,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  if (avatarLetter != null)
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: _active,
                      child: Text(
                        avatarLetter!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    )
                  else if (icon != null)
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: iconBackground ?? _active.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        color: iconColor ?? _active,
                        size: 22,
                      ),
                    ),
                  if (badge != null)
                    Positioned(
                      right: -2,
                      top: -4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 2,
                        ),
                        constraints: const BoxConstraints(minWidth: 16),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: Text(
                          badge! > 99 ? '99+' : '$badge',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            height: 1.1,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeInOut,
              style: TextStyle(
                fontSize: labelBold ? 11 : 9.5,
                fontWeight: labelBold ? FontWeight.w900 : FontWeight.w500,
                color: labelBold
                    ? (iconColor ?? _active)
                    : _inactive,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
