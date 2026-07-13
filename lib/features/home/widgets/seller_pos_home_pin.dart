import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../seller/screens/seller_pos_screen.dart';

/// Seller / admin uchun bosh ekranda «Sotuv paneli» tezkor kirish.
class SellerPosHomePin extends StatelessWidget {
  const SellerPosHomePin({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SellerPosScreen()),
          );
        },
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          decoration: BoxDecoration(
            color: AppColors.primaryDark,
            borderRadius: BorderRadius.circular(13),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: const Row(
            children: [
              Icon(Icons.point_of_sale, color: Colors.white, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sotuv paneli',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
