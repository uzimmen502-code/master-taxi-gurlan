import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../ads/screens/cheap_products_screen.dart';
import '../../ads/screens/create_ad_screen.dart';
import '../../ads/screens/my_ads_screen.dart';

/// «Сиз ҳам сотинг» — фақат Онлайн бозорга сотиш тавсияси.
class SellerCtaBanner extends StatelessWidget {
  const SellerCtaBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  static const _ink = Color(0xFF102418);
  static const _muted = Color(0xFF3D5C28);
  static const _chipBg = Color(0xFF1B3D12);
  static const _chipFg = Color(0xFFD9FF3F);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFFFFFF),
                Color(0xFFF4FBE6),
                Color(0xFFE8F6C8),
              ],
            ),
            border: Border.all(color: const Color(0xFF8BC34A), width: 1.1),
            boxShadow: [
              BoxShadow(
                color: AppColors.limeDeep.withValues(alpha: 0.18),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 12, 14),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: _chipBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: const Icon(
                    Icons.storefront_rounded,
                    color: _chipFg,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _chipBg,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          context.tr('home_seller_cta_badge'),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.3,
                            color: _chipFg,
                            height: 1.1,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        context.tr('home_seller_cta'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _ink,
                          height: 1.15,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.tr('home_seller_cta_subtitle'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: _muted,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 36,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: AppColors.limeDeep,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Онлайн бозор сотув оқими (платформа таклифи йўқ).
  static Future<void> openOnlineMarketSellFlow(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _OnlineMarketSellSheet(),
    );
  }
}

class _OnlineMarketSellSheet extends StatelessWidget {
  const _OnlineMarketSellSheet();

  static const _ink = Color(0xFF102418);
  static const _muted = Color(0xFF4A6740);
  static const _sheetBg = Color(0xFFF7FBF0);

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: _sheetBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFC5D9A8),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B3D12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.shopping_bag_rounded,
                      color: Color(0xFFD9FF3F),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('online_market_sell_title'),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: _ink,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.tr('home_seller_cta_badge'),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppColors.limeDeep,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                context.tr('online_market_sell_lead'),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: _muted,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 18),
              _SellActionTile(
                icon: Icons.add_circle_outline_rounded,
                title: context.tr('online_market_sell_new'),
                subtitle: context.tr('online_market_sell_new_hint'),
                emphasized: true,
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CreateAdScreen()),
                  );
                },
              ),
              const SizedBox(height: 8),
              _SellActionTile(
                icon: Icons.inventory_2_outlined,
                title: context.tr('online_market_sell_mine'),
                subtitle: context.tr('online_market_sell_mine_hint'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const MyAdsScreen()),
                  );
                },
              ),
              const SizedBox(height: 8),
              _SellActionTile(
                icon: Icons.storefront_outlined,
                title: context.tr('online_market_sell_browse'),
                subtitle: context.tr('online_market_sell_browse_hint'),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const CheapProductsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SellActionTile extends StatelessWidget {
  const _SellActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.emphasized = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final bg = emphasized ? const Color(0xFF1B3D12) : Colors.white;
    final titleColor = emphasized ? const Color(0xFFD9FF3F) : const Color(0xFF102418);
    final subColor = emphasized
        ? const Color(0xFFB8D98A)
        : const Color(0xFF5A7A40);
    final iconColor = emphasized ? const Color(0xFFD9FF3F) : AppColors.limeDeep;

    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: emphasized
                ? null
                : Border.all(color: const Color(0xFFC8E09A)),
          ),
          child: Row(
            children: [
              Icon(icon, color: iconColor, size: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: titleColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: subColor,
                        height: 1.25,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: emphasized
                    ? const Color(0xFFD9FF3F)
                    : const Color(0xFF9AB870),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
