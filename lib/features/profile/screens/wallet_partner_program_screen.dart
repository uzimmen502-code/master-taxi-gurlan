import 'package:flutter/material.dart';

import '../../sell/screens/sell_offer_screen.dart';

/// Эски маршрут — бирлашган [SellOfferScreen] ga йўналтиради.
@Deprecated('SellOfferScreen ishlating')
class WalletPartnerProgramScreen extends StatelessWidget {
  const WalletPartnerProgramScreen({super.key, required this.phone});

  final String phone;

  @override
  Widget build(BuildContext context) {
    return SellOfferScreen(
      phone: phone,
      defaultToPlatform: true,
      defaultToPublic: false,
    );
  }
}
