import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';

/// Жойлаштирувчи аватари: расм бор бўлса network image, бўлмаса исм бош ҳарфи.
/// [onEdit] берилса, тагида таҳрирлаш белгиси кўринади (эгаси экрани учун).
class TvOwnerAvatar extends StatelessWidget {
  const TvOwnerAvatar({
    super.key,
    required this.name,
    this.photoUrl = '',
    this.radius = 16,
    this.onEdit,
  });

  final String name;
  final String photoUrl;
  final double radius;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final trimmedName = name.trim();
    final initial = trimmedName.isNotEmpty
        ? trimmedName.substring(0, 1).toUpperCase()
        : '?';
    final url = photoUrl.trim();
    final avatar = CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFF00E676).withValues(alpha: 0.18),
      backgroundImage: url.isNotEmpty ? NetworkImage(url) : null,
      child: url.isEmpty
          ? Text(
              initial,
              style: TextStyle(
                color: const Color(0xFF007A3D),
                fontWeight: FontWeight.w900,
                fontSize: radius * 0.8,
              ),
            )
          : null,
    );
    if (onEdit == null) return avatar;
    return Tooltip(
      message: context.tr('tv_channel_edit_photo'),
      child: GestureDetector(
        onTap: onEdit,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            avatar,
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(
                  color: Colors.black87,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.edit_rounded,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
