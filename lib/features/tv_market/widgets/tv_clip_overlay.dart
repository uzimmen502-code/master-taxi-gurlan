import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_clip.dart';
import 'tv_owner_action_bar.dart';

/// Видео устидаги UI: ўнг тугмалар + паст маълумот + Боғланиш / Таҳрир+Ўчириш.
/// Фақат ўз виджетлари hit-test қилади — вертикал скролл бўш жойдан ўтади.
class TvClipOverlay extends StatelessWidget {
  const TvClipOverlay({
    super.key,
    required this.clip,
    required this.onContact,
    required this.onLike,
    required this.onShare,
    required this.onSave,
    required this.onProfile,
    this.liked = false,
    this.saved = false,
    this.isOwner = false,
    this.onDelete,
    this.onEdit,
    this.onOpenShop,
    this.ownerLabel,
  });

  final TvClip clip;
  final VoidCallback onContact;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onProfile;
  final bool liked;
  final bool saved;
  final bool isOwner;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onOpenShop;

  /// Берилса, клипдаги `ownerName` ўрнига шу матн кўринади.
  final String? ownerLabel;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        Positioned(
          left: 12,
          right: 72,
          bottom: bottom + 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _InfoColumn(
                clip: clip,
                ownerLabel: ownerLabel,
              ),
              const SizedBox(height: 10),
              if (onOpenShop != null && !isOwner) ...[
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: onOpenShop,
                    icon: const Icon(Icons.storefront_rounded, size: 18),
                    label: Text(
                      context.tr('tv_market_go_shop'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white70, width: 1.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (isOwner && onEdit != null && onDelete != null)
                TvOwnerActionBar(onEdit: onEdit!, onDelete: onDelete!)
              else
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: ElevatedButton.icon(
                    onPressed: onContact,
                    icon: const Icon(Icons.call_rounded, size: 18),
                    label: Text(
                      context.tr('tv_market_contact'),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00E676),
                      foregroundColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          right: 8,
          bottom: bottom + 80,
          child: _ActionButtons(
            clip: clip,
            liked: liked,
            saved: saved,
            ownerLabel: ownerLabel,
            onLike: onLike,
            onShare: onShare,
            onProfile: onProfile,
            onSave: onSave,
          ),
        ),
      ],
    );
  }
}

class _InfoColumn extends StatelessWidget {
  const _InfoColumn({required this.clip, this.ownerLabel});
  final TvClip clip;
  final String? ownerLabel;

  String get _name {
    final labeled = ownerLabel == null ? '' : tvOwnerDisplayName(ownerLabel!);
    if (labeled.isNotEmpty) return labeled;
    return tvOwnerDisplayName(clip.ownerName);
  }

  @override
  Widget build(BuildContext context) {
    final name = _name;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (name.isNotEmpty) ...[
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 15,
              shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
            ),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 6),
        ],
        Text(
          clip.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 15,
            shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
          ),
        ),
        if (clip.description.trim().isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            clip.description.trim(),
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFFFFFFFF),
              fontWeight: FontWeight.w500,
              fontSize: 13,
              height: 1.25,
              backgroundColor: Colors.transparent,
              shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
            ),
          ),
        ],
        const SizedBox(height: 4),
        Row(
          children: [
            if (clip.hasPrice) ...[
              Text(
                formatMoney(clip.price),
                style: const TextStyle(
                  color: Color(0xFF00E676),
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
              const SizedBox(width: 10),
            ],
            const Icon(Icons.location_on, color: Colors.white70, size: 14),
            const SizedBox(width: 2),
            Flexible(
              child: Text(
                clip.districtLabel,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  const _ActionButtons({
    required this.clip,
    required this.liked,
    required this.saved,
    required this.onLike,
    required this.onShare,
    required this.onProfile,
    required this.onSave,
    this.ownerLabel,
  });

  final TvClip clip;
  final bool liked;
  final bool saved;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback onProfile;
  final VoidCallback onSave;
  final String? ownerLabel;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionBtn(
          icon: liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: liked ? const Color(0xFFFF1744) : Colors.white,
          label: clip.likeCount > 0 ? '${clip.likeCount}' : '',
          onTap: onLike,
        ),
        const SizedBox(height: 16),
        _ActionBtn(
          icon: Icons.send_rounded,
          label: '',
          onTap: onShare,
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onProfile,
          child: CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white24,
            child: Text(
              _initial(
                tvOwnerDisplayName(
                  (ownerLabel != null && ownerLabel!.trim().isNotEmpty)
                      ? ownerLabel!
                      : clip.ownerName,
                ),
              ),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        _ActionBtn(
          icon: saved
              ? Icons.bookmark_rounded
              : Icons.bookmark_border_rounded,
          color: saved ? const Color(0xFFFFD54F) : Colors.white,
          label: '',
          onTap: onSave,
        ),
      ],
    );
  }

  String _initial(String name) {
    final t = name.trim();
    if (t.isEmpty) return '?';
    return t.substring(0, 1).toUpperCase();
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = Colors.white,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: color,
            size: 28,
            shadows: const [Shadow(blurRadius: 6, color: Colors.black54)],
          ),
          if (label.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
