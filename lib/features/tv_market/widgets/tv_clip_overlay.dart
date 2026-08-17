import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_clip.dart';
import 'tv_owner_action_bar.dart';

/// Видео устидаги UI: ўнг тугмалар (лайм дўкон) + паст маълумот + Боғланиш / Таҳрир+Ўчириш.
/// Фақат ўз виджетлари hit-test қилади — вертикал скролл бўш жойдан ўтади.
class TvClipOverlay extends StatelessWidget {
  const TvClipOverlay({
    super.key,
    required this.clip,
    required this.onContact,
    required this.onLike,
    required this.onShare,
    required this.onSave,
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
            showShop: onOpenShop != null,
            onLike: onLike,
            onShare: onShare,
            onSave: onSave,
            onOpenShop: onOpenShop,
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
    required this.onSave,
    this.onOpenShop,
    this.showShop = false,
  });

  final TvClip clip;
  final bool liked;
  final bool saved;
  final VoidCallback onLike;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback? onOpenShop;
  final bool showShop;

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
        if (showShop && onOpenShop != null) ...[
          const SizedBox(height: 16),
          _ShopActionBtn(
            label: context.tr('tv_market_shop'),
            onTap: onOpenShop!,
          ),
        ],
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

class _ShopActionBtn extends StatelessWidget {
  const _ShopActionBtn({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF00E676),
              shape: BoxShape.circle,
              boxShadow: const [
                BoxShadow(color: Colors.black54, blurRadius: 6),
              ],
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.black,
              size: 22,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
