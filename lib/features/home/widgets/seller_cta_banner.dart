import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';

/// «Siz ham soting» — sotish moduliga yo‘naltiruvchi banner.
class SellerCtaBanner extends StatelessWidget {
  const SellerCtaBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  static const _bg = Color(0xFFE8F5E4);
  static const _titleDark = Color(0xFF1A3A20);
  static const _brandGreen = Color(0xFF36A63A);

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Ink(
          decoration: BoxDecoration(
            color: _bg,
            borderRadius: BorderRadius.circular(13),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('home_seller_cta'),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _titleDark,
                  ),
                ),
              ),
              Icon(Icons.arrow_forward_rounded, color: _brandGreen, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
