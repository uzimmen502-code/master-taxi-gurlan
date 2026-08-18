import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';

/// Pastki qism — qoʻngʻiroq CTA (kanal va vitrina).
class TvChannelContactBar extends StatelessWidget {
  const TvChannelContactBar({
    super.key,
    required this.onCall,
    this.labelKey = 'tv_shop_contact',
  });

  final VoidCallback onCall;
  final String labelKey;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 50,
          child: ElevatedButton.icon(
            onPressed: onCall,
            icon: const Icon(Icons.call_rounded, size: 20),
            label: Text(
              context.tr(labelKey),
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00E676),
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
