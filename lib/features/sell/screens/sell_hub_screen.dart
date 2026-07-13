import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/sell_offers_repository.dart';
import '../../ads/screens/cheap_products_screen.dart';
import '../../ads/screens/create_ad_screen.dart';
import '../../ads/screens/my_ads_screen.dart';
import '../../jobs/jobs_tabs.dart';
import '../../jobs/screens/jobs_screen.dart';
import '../widgets/sell_submission_tile.dart';
import 'sell_offer_screen.dart';

/// Ягона сотув кабинети — 3 йўл + тариx + forwarded.
class SellHubScreen extends StatefulWidget {
  const SellHubScreen({
    super.key,
    required this.phone,
    this.initialTab = 0,
  });

  final String phone;

  /// 0 — Менинг таклифларим, 1 — Менга юборилган.
  final int initialTab;

  @override
  State<SellHubScreen> createState() => _SellHubScreenState();
}

class _SellHubScreenState extends State<SellHubScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: 2,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String get _uid => phoneDigits(widget.phone);

  @override
  Widget build(BuildContext context) {
    final phoneOk = _uid.length >= 9;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      appBar: AppBar(
        title: const Text(
          'Сотув маркази',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabs,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(text: 'Менинг таклифларим'),
            Tab(text: 'Менга юборилган'),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              children: [
                _PathCard(
                  icon: Icons.storefront_outlined,
                  title: 'Платформага сотаман',
                  subtitle: 'Оператор қабул қилади, курьер йиғиб олади',
                  onTap: phoneOk
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => SellOfferScreen(
                                phone: widget.phone,
                                defaultToPlatform: true,
                                defaultToPublic: false,
                              ),
                            ),
                          )
                      : null,
                ),
                const SizedBox(height: 8),
                _PathCard(
                  icon: Icons.shopping_bag_outlined,
                  title: 'Онлайн бозор',
                  subtitle: 'Эълон жойлаштириш · Менинг эълонларим',
                  onTap: phoneOk
                      ? () => _openMarketSheet(context)
                      : null,
                ),
                const SizedBox(height: 8),
                _PathCard(
                  icon: Icons.campaign_outlined,
                  title: 'P2P Сотаман',
                  subtitle: 'Иш топда бошқаларга эълон',
                  onTap: phoneOk
                      ? () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const JobsScreen(
                                initialTabIndex: JobsTabs.sell,
                              ),
                            ),
                          )
                      : null,
                ),
              ],
            ),
          ),
          if (!phoneOk)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Телефон тасдиқланмаган — профилда тўлдиринг',
                style: TextStyle(color: Colors.orange.shade800),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: _tabs,
              children: [
                _MySubmissionsTab(uid: _uid),
                _ForwardedTab(uid: _uid),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openMarketSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: const Text('Янги эълон'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const CreateAdScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined),
              title: const Text('Менинг эълонларим'),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const MyAdsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.storefront),
              title: const Text('Бозор лентаси'),
              onTap: () {
                Navigator.pop(ctx);
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
    );
  }
}

class _PathCard extends StatelessWidget {
  const _PathCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.cardBorderMuted),
          ),
          child: Row(
            children: [
              Icon(icon, color: AppColors.primary, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}

class _MySubmissionsTab extends StatelessWidget {
  const _MySubmissionsTab({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    if (uid.length < 9) {
      return const Center(child: Text('Телефон йўқ'));
    }
    return StreamBuilder(
      stream: context.read<SellOffersRepository>().watchByUser(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return Center(
            child: Text(
              'Ҳали платформа таклифи йўқ',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          itemCount: list.length,
          itemBuilder: (_, i) => SellSubmissionTile(submission: list[i]),
        );
      },
    );
  }
}

class _ForwardedTab extends StatelessWidget {
  const _ForwardedTab({required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context) {
    if (uid.length < 9) {
      return const Center(child: Text('Телефон йўқ'));
    }
    final repo = context.read<SellOffersRepository>();
    return StreamBuilder(
      stream: repo.watchForwardedForUser(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Юклаш хатоси: ${snap.error}',
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return Center(
            child: Text(
              'Ҳозирча сизга юборилган таклиф йўқ',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          itemCount: list.length,
          itemBuilder: (_, i) => SellSubmissionTile(
            submission: list[i],
            showOwnerExtras: false,
          ),
        );
      },
    );
  }
}
