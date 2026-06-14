import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../models/ad_model.dart';
import '../repositories/ads_repository.dart';
import '../widgets/my_ad_actions.dart';

/// Owner's active and hidden ads.
class MyAdsScreen extends StatefulWidget {
  const MyAdsScreen({super.key});

  @override
  State<MyAdsScreen> createState() => _MyAdsScreenState();
}

class _MyAdsScreenState extends State<MyAdsScreen>
    with SingleTickerProviderStateMixin {
  String _uid = '';

  @override
  void initState() {
    super.initState();
    _loadUid();
  }

  Future<void> _loadUid() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _uid = phoneDigits(prefs.getString('user_phone') ?? '');
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Менинг эълонларим'),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            tabs: [
              Tab(text: 'Фаол'),
              Tab(text: 'Яширилган'),
            ],
          ),
        ),
        body: _uid.length < 9
            ? const Center(child: Text('Телефон тасдиқланмаган'))
            : TabBarView(
                children: [
                  _AdsList(uid: _uid, status: 'active'),
                  _AdsList(uid: _uid, status: 'inactive'),
                ],
              ),
      ),
    );
  }
}

class _AdsList extends StatelessWidget {
  const _AdsList({required this.uid, required this.status});

  final String uid;
  final String status;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AdsRepository>();
    final dateFmt = DateFormat('dd.MM.yyyy');

    return StreamBuilder<List<AdModel>>(
      stream: repo.getMyAds(uid, status: status),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting &&
            !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Center(child: Text('Хатолик: ${snap.error}'));
        }
        final ads = snap.data ?? const [];
        if (ads.isEmpty) {
          return const Center(child: Text('Эълонлар йўқ'));
        }
        return ListView.separated(
          itemCount: ads.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (_, i) {
            final ad = ads[i];
            final thumb = ad.imageUrls.isNotEmpty ? ad.imageUrls.first : null;
            final date = ad.publishedAt ?? ad.createdAt;

            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: thumb != null
                    ? CachedNetworkImage(
                        imageUrl: thumb,
                        width: 60,
                        height: 60,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 60,
                        height: 60,
                        color: AppColors.cardImageBg,
                        child: const Icon(Icons.image),
                      ),
              ),
              title: Text(
                ad.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${ad.price} so\'m'
                '${date != null ? ' · ${dateFmt.format(date)}' : ''}',
              ),
              trailing: MyAdActions(ad: ad),
            );
          },
        );
      },
    );
  }
}
