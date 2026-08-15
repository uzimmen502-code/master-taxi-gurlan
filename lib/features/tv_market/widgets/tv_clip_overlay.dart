import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_clip.dart';

/// Видео устидаги UI: ўнг тугмалар + паст маълумот + Боғланиш.
/// Фақат ўз виджетлари hit-test қилади — вертикал скролл бўш жойдан ўтади.
class TvClipOverlay extends StatelessWidget {
  const TvClipOverlay({
    super.key,
    required this.clip,
    required this.onContact,
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSave,
    required this.onProfile,
    this.isOwner = false,
    this.onDelete,
  });

  final TvClip clip;
  final VoidCallback onContact;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onProfile;
  final bool isOwner;
  final VoidCallback? onDelete;

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
              _InfoColumn(clip: clip),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: ElevatedButton.icon(
                  onPressed: isOwner ? onDelete : onContact,
                  icon: Icon(
                    isOwner
                        ? Icons.delete_outline_rounded
                        : Icons.chat_bubble_outline_rounded,
                    size: 18,
                  ),
                  label: Text(
                    context.tr(
                      isOwner ? 'tv_market_delete' : 'tv_market_contact',
                    ),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isOwner
                        ? const Color(0xFFFF1744)
                        : const Color(0xFF00E676),
                    foregroundColor: isOwner ? Colors.white : Colors.black,
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
            onLike: onLike,
            onComment: onComment,
            onShare: onShare,
            onSave: onSave,
            onProfile: onProfile,
          ),
        ),
      ],
    );
  }
}

class _InfoColumn extends StatelessWidget {
  const _InfoColumn({required this.clip});
  final TvClip clip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.white24,
              child: Icon(Icons.person, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                '@${clip.ownerName}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  shadows: [Shadow(blurRadius: 4, color: Colors.black54)],
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
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
    required this.onLike,
    required this.onComment,
    required this.onShare,
    required this.onSave,
    required this.onProfile,
  });

  final TvClip clip;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback onProfile;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ActionBtn(
          icon: Icons.favorite_border_rounded,
          label: clip.likeCount > 0 ? '${clip.likeCount}' : '',
          onTap: onLike,
        ),
        const SizedBox(height: 16),
        _ActionBtn(
          icon: Icons.chat_bubble_outline_rounded,
          label: clip.commentCount > 0 ? '${clip.commentCount}' : '',
          onTap: onComment,
        ),
        const SizedBox(height: 16),
        _ActionBtn(
          icon: Icons.send_rounded,
          label: '',
          onTap: onShare,
        ),
        const SizedBox(height: 16),
        _ActionBtn(
          icon: Icons.bookmark_border_rounded,
          label: '',
          onTap: onSave,
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: onProfile,
          child: const CircleAvatar(
            radius: 18,
            backgroundColor: Colors.white24,
            child: Icon(Icons.person, color: Colors.white, size: 20),
          ),
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
  });

  final IconData icon;
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
          Icon(
            icon,
            color: Colors.white,
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
