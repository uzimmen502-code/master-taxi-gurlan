import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../models/ad_model.dart';
import 'ad_details_screen.dart';

/// Аҳоли бозори эълонлари — АВА дўконидаги каби СУРИБ кўриш
/// (эга қарори, 2026-09-29: «экранларни свайп қилиш»).
///
/// Аввал лентадаги эълон босилганда фақат ўша биттаси очилар, кейингисини
/// кўриш учун орқага қайтиш керак эди. АВА дўконида эса
/// `PlatformProductDetailScreen` аллақачон вертикал `PageView` билан
/// ишлайди. Шу хулқ Аҳоли бозорига ҳам кўчирилди: йўналиш ҳам, `reverse`
/// ҳам ўша — иккала бўлимда бармоқ ҳаракати бир хил бўлсин.
///
/// `AdDetailsScreen` ЎЗГАРТИРИЛМАДИ: у мураккаб экран (кўришлар ҳисоби,
/// «ўхшаш эълонлар», метрика) ва ҳар саҳифа ўз ҳолича, ўз `Scaffold`и
/// билан қурилади. Шунинг учун бу экран — устидаги юпқа қобиқ.
class AdSwipeScreen extends StatefulWidget {
  const AdSwipeScreen({
    super.key,
    required this.ads,
    required this.initialIndex,
  });

  /// Лентадаги эълонлар — сурилиш шулар орасида боради.
  final List<AdModel> ads;

  /// Босилган эълоннинг рўйхатдаги ўрни.
  final int initialIndex;

  @override
  State<AdSwipeScreen> createState() => _AdSwipeScreenState();
}

class _AdSwipeScreenState extends State<AdSwipeScreen> {
  late final PageController _pageCtrl;
  late int _index;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.ads.length - 1);
    _pageCtrl = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ads = widget.ads;
    // Битта эълон бўлса сурилишнинг маъноси йўқ — одатдаги экран.
    if (ads.length <= 1) {
      return AdDetailsScreen(ad: ads.isEmpty ? widget.ads.first : ads.first);
    }
    return Stack(
      children: [
        PageView.builder(
          controller: _pageCtrl,
          scrollDirection: Axis.vertical,
          reverse: true,
          itemCount: ads.length,
          onPageChanged: (i) {
            HapticFeedback.lightImpact();
            setState(() => _index = i);
          },
          itemBuilder: (_, i) => AdDetailsScreen(
            // Калит бўлмаса Flutter саҳифа ҳолатини қайта ишлатиб
            // юборади — бир эълоннинг «ўхшашлари» бошқасида кўриниб
            // қолар эди.
            key: ValueKey(ads[i].id),
            ad: ads[i],
          ),
        ),
        // Нечанчи эълон эканини кўрсатиб туради — фойдаланувчи
        // лентанинг ичида эканини билсин.
        Positioned(
          top: MediaQuery.of(context).padding.top + 8,
          right: 12,
          child: IgnorePointer(
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_index + 1} / ${ads.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: AppText.labelTiny,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ),
        // Сурса бўлишини биринчи эълондагина айтамиз — кейин халақит
        // бермасин.
        if (_index == 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).padding.bottom + 16,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.keyboard_double_arrow_down_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        context.tr('platform_store_swipe_next'),
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
