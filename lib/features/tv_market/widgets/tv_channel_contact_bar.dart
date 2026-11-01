import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';

/// Pastki qism — qoʻngʻiroq CTA (kanal va vitrina).
class TvChannelContactBar extends StatelessWidget {
  const TvChannelContactBar({
    super.key,
    required this.onCall,
    this.labelKey = 'tv_shop_contact',
    this.onWrite,
    this.writeBusy = false,
  });

  final VoidCallback onCall;
  final String labelKey;

  /// «Ёзиш» (сотувчи билан чат, эга 2026-11-01) — берилса қўнғироқ ёнида; `null` — фақат қўнғироқ.
  final VoidCallback? onWrite;
  final bool writeBusy;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: SizedBox(
          height: 50,
          // «Ёзиш» қўнғироқдан қисқароқ (эга, 2026-11-01): 3 : 2.
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: ElevatedButton.icon(
                  onPressed: onCall,
                  icon: const Icon(Icons.call_rounded, size: 20),
                  label: Text(
                    context.tr(labelKey),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AvaLight.ok,
                    foregroundColor: Colors.black,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              if (onWrite != null) ...[
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: OutlinedButton.icon(
                    key: const ValueKey('contact_bar_write'),
                    onPressed: writeBusy ? null : onWrite,
                    icon: writeBusy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.chat_bubble_outline, size: 20),
                    label: Text(
                      context.tr('deal_chat_write'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.black,
                      side: const BorderSide(color: AvaLight.ok, width: 1.5),
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
