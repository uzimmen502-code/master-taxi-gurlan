import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/formatters.dart';
import '../../../core/theme/app_theme.dart';
import '../models/ad_model.dart';
import '../repositories/ads_repository.dart';
import '../widgets/ad_image_slider.dart';

/// Single ad detail with call action.
class AdDetailsScreen extends StatefulWidget {
  const AdDetailsScreen({super.key, required this.ad});

  final AdModel ad;

  @override
  State<AdDetailsScreen> createState() => _AdDetailsScreenState();
}

class _AdDetailsScreenState extends State<AdDetailsScreen> {
  // Rollout toggle: can be switched off quickly without touching repository logic.
  static const bool _enableSimilarAds = true;

  // Session metrics (debug): CTR / empty-rate / error-rate.
  static int _similarImpressions = 0;
  static int _similarClicks = 0;
  static int _similarEmpty = 0;
  static int _similarErrors = 0;

  late final Future<List<AdModel>> _similarAdsFuture;
  bool _similarOutcomeLogged = false;

  @override
  void initState() {
    super.initState();
    _similarAdsFuture = _enableSimilarAds
        ? context.read<AdsRepository>().getSimilarAds(current: widget.ad, limit: 6)
        : Future.value(const <AdModel>[]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdsRepository>().incrementViews(widget.ad.id);
    });
  }

  void _logSimilarAdsError(Object error, [StackTrace? stackTrace]) {
    if (!kDebugMode) return;
    debugPrint('Similar ads load error: $error');
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  void _logSimilarMetrics(String event, {int? shownCount}) {
    if (!kDebugMode) return;
    final requests = _similarImpressions + _similarEmpty + _similarErrors;
    final ctr = _similarImpressions == 0
        ? 0.0
        : (_similarClicks / _similarImpressions) * 100;
    final emptyRate = requests == 0 ? 0.0 : (_similarEmpty / requests) * 100;
    final errorRate = requests == 0 ? 0.0 : (_similarErrors / requests) * 100;
    debugPrint(
      'SimilarAds[$event] source=${widget.ad.id} shown=${shownCount ?? '-'} '
      'totals{impr=$_similarImpressions,click=$_similarClicks,empty=$_similarEmpty,error=$_similarErrors} '
      'rates{ctr=${ctr.toStringAsFixed(1)}%,empty=${emptyRate.toStringAsFixed(1)}%,error=${errorRate.toStringAsFixed(1)}%}',
    );
  }

  String get _callPhone {
    final p = widget.ad.phone;
    if (phoneDigits(p).length >= 9) return p;
    return widget.ad.ownerId;
  }

  Future<void> _callSeller() async {
    if (phoneDigits(_callPhone).length < 9) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Телефон рақами нотўғри'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    final uri = Uri.parse('tel:${phoneForCall(_callPhone)}');
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Қўнғироқ қилиб бўлмади'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _reportAd() async {
    const reasons = <String>[
      'Алдамчи эълон',
      'Телефон нотўғри',
      'Спам / Такрорий',
      'Ҳақоратли матн',
    ];
    final reason = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Шикоят',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            ...reasons.map(
              (r) => ListTile(
                title: Text(r),
                onTap: () => Navigator.pop(ctx, r),
              ),
            ),
          ],
        ),
      ),
    );
    if (reason == null || !mounted) return;
    try {
      await context.read<AdsRepository>().submitComplaint(
            adId: widget.ad.id,
            reason: reason,
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Шикоят юборилди')),
      );
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'resource-exhausted'
          ? 'Кунига шикоят лимити тугади'
          : (e.message ?? 'Хатолик');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Хатолик: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = widget.ad;
    final canCall = phoneDigits(_callPhone).length >= 9;

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: ElevatedButton.icon(
            onPressed: canCall ? _callSeller : null,
            icon: const Text('📞'),
            label: const Text('Қўнғироқ қилиш'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 300,
            pinned: true,
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                tooltip: 'Шикоят',
                icon: const Icon(Icons.flag_outlined),
                onPressed: _reportAd,
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: AdImageSlider(imageUrls: ad.imageUrls, height: 300),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          ad.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppText.titleLarge,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '${ad.price} so\'m',
                        style: const TextStyle(
                          fontSize: AppText.titleMedium,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          ad.sellerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppText.bodyMedium,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '👁 ${ad.views} кўрилди',
                        style: TextStyle(
                          fontSize: AppText.labelSmall,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    ad.description,
                    style: const TextStyle(fontSize: AppText.bodyMedium),
                  ),
                  const SizedBox(height: 20),
                  if (_enableSimilarAds) ...[
                    const Text(
                      'Ўхшаш эълонлар',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: AppText.bodyLarge,
                      ),
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<List<AdModel>>(
                      future: _similarAdsFuture,
                      builder: (context, snap) {
                        if (snap.connectionState == ConnectionState.waiting) {
                          return const SizedBox(
                            height: 190,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snap.hasError) {
                          _logSimilarAdsError(snap.error!, snap.stackTrace);
                          if (!_similarOutcomeLogged) {
                            _similarOutcomeLogged = true;
                            _similarErrors++;
                            _logSimilarMetrics('error');
                          }
                          return Text(
                            'Ўхшаш эълонларни юклаб бўлмади',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: AppText.bodySmall,
                            ),
                          );
                        }

                        final items = snap.data ?? const <AdModel>[];
                        if (items.isEmpty) {
                          if (!_similarOutcomeLogged) {
                            _similarOutcomeLogged = true;
                            _similarEmpty++;
                            _logSimilarMetrics('empty');
                          }
                          return Text(
                            'Ҳозирча ўхшаш эълонлар йўқ',
                            style: TextStyle(
                              color: Colors.grey.shade700,
                              fontSize: AppText.bodySmall,
                            ),
                          );
                        }

                        if (!_similarOutcomeLogged) {
                          _similarOutcomeLogged = true;
                          _similarImpressions++;
                          _logSimilarMetrics('impression', shownCount: items.length);
                        }
                        return SizedBox(
                          height: 190,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const SizedBox(width: 10),
                            itemBuilder: (_, i) {
                              final similar = items[i];
                              return _SimilarAdTile(
                                ad: similar,
                                onTap: () {
                                  _similarClicks++;
                                  _logSimilarMetrics('click');
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => AdDetailsScreen(ad: similar),
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        );
                      },
                    ),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SimilarAdTile extends StatelessWidget {
  const _SimilarAdTile({required this.ad, required this.onTap});

  final AdModel ad;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final imageUrl = ad.imageUrls.isNotEmpty ? ad.imageUrls.first : null;

    return SizedBox(
      width: 150,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 1.5,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: imageUrl == null
                    ? const ColoredBox(
                        color: AppColors.cardImageBg,
                        child: Center(child: Icon(Icons.image)),
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const ColoredBox(
                          color: AppColors.cardImageBg,
                          child: Center(child: Icon(Icons.broken_image)),
                        ),
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const ColoredBox(
                            color: AppColors.cardImageBg,
                            child: Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        },
                      ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ad.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: AppText.bodySmall,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${ad.price} so\'m',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: AppText.bodySmall,
                        ),
                      ),
                    ],
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
