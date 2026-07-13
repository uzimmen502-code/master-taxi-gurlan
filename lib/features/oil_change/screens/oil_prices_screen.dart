import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/oil_vehicle.dart';
import '../../../repositories/oil_change_repository.dart';

class OilPricesScreen extends StatefulWidget {
  const OilPricesScreen({super.key});

  @override
  State<OilPricesScreen> createState() => _OilPricesScreenState();
}

class _OilPricesScreenState extends State<OilPricesScreen> {
  late Future<List<OilPricePackage>> _future;

  @override
  void initState() {
    super.initState();
    _future = OilChangeRepository().loadPricePackages();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('oil_prices')),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: FutureBuilder<List<OilPricePackage>>(
        future: _future,
        builder: (context, snap) {
          final packages = snap.data ?? OilPricePackage.defaults;
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                context.tr('oil_prices_hint'),
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              ...packages.map(
                (p) => Card(
                  elevation: 0,
                  margin: const EdgeInsets.only(bottom: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: ListTile(
                    title: Text(
                      p.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(p.description),
                    trailing: Text(
                      context.tr('oil_price_from').replaceAll(
                            '{price}',
                            formatPrice(p.priceFrom),
                          ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
