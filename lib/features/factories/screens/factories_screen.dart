import 'package:flutter/material.dart';

import '../../../core/geo/geo_context.dart';
import '../../../core/geo/geo_names.dart';
import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../business_map/domain/business.dart';
import '../../business_map/screens/my_businesses_screen.dart';
import '../data/factories_repository.dart';
import '../domain/factory_profile.dart';
import 'factory_page_screen.dart';

/// «Ишлаб чиқарувчи завод/фабрикалар» (эга 2026-11-28): бизнес харитасидаги `manufacturing` объектлари —
/// ҳудуд ҳалқалари бўйича (туман → вилоят → Республика), тасдиқланганлар ҳар ҳалқада олдинда.
/// Заводни қўшиш — мавжуд «Менинг бизнесим» (тури «Ишлаб чиқариш»).
class FactoriesScreen extends StatefulWidget {
  const FactoriesScreen({super.key, this.load});

  @visibleForTesting
  final Future<List<Business>> Function()? load;

  @override
  State<FactoriesScreen> createState() => _FactoriesScreenState();
}

class _FactoriesScreenState extends State<FactoriesScreen> {
  late Future<List<Business>> _future = _open();

  Future<List<Business>> _open() {
    final a = GeoContext.active;
    return widget.load?.call() ?? FactoriesRepository().fetchRings(districtId: a.districtId, regionId: a.regionId);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(context.tr('factory_title')),
        actions: [
          IconButton(
            key: const ValueKey('factory_add_mine'),
            tooltip: context.tr('factory_add_mine'),
            icon: const Icon(Icons.add_business_rounded),
            onPressed: () => Navigator.of(context)
                .push<void>(MaterialPageRoute(builder: (_) => const MyBusinessesScreen())),
          ),
        ],
      ),
      body: FutureBuilder<List<Business>>(
        future: _future,
        builder: (ctx, snap) {
          if (snap.hasError) {
            debugPrint('[Factories] FACTORIES_LOAD_FAILED: ${snap.error}');
            return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(ctx.tr('factory_load_error'), key: const ValueKey('factory_error')),
                TextButton(
                  onPressed: () => setState(() => _future = _open()),
                  child: Text(ctx.tr('home_section_retry')),
                ),
              ]),
            );
          }
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Text(ctx.tr('factory_empty'), key: const ValueKey('factory_empty'), textAlign: TextAlign.center),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final b = list[i];
              final district = GeoNames.district(b.districtId, ctx.contentLang);
              return Card(
                key: ValueKey('factory_card_${b.id}'),
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: Icon(b.category.icon, color: b.category.color),
                  title: Row(children: [
                    Flexible(child: Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                    if (showsVerifiedProducerBadge(b)) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.verified_rounded, size: 18, color: c.ok, key: ValueKey('factory_verified_${b.id}')),
                    ],
                  ]),
                  subtitle: Text(
                    [if (b.subtype.isNotEmpty) b.subtype, if (district.isNotEmpty) district].join(' · '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.of(context)
                      .push<void>(MaterialPageRoute(builder: (_) => FactoryPageScreen(business: b))),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
