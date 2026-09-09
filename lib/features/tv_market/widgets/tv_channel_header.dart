import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../models/tv_clip.dart';
import '../utils/tv_view_format.dart';
import 'tv_owner_avatar.dart';

/// Оммaviy kanal boshi — ism, tuman, roliklar va jami ko‘rish.
class TvChannelHeader extends StatelessWidget {
  const TvChannelHeader({
    super.key,
    required this.displayName,
    this.districtLabel = '',
    this.clipCount,
    this.totalViewCount,
    this.photoUrl = '',
    this.onEditPhoto,
    this.followerCount,
    this.isFollowing = false,
    this.onToggleFollow,
  });

  final String displayName;
  final String districtLabel;
  final int? clipCount;
  final int? totalViewCount;
  final String photoUrl;
  final VoidCallback? onEditPhoto;

  /// `null` = обуначилар сони кўрсатилмайди.
  final int? followerCount;
  final bool isFollowing;

  /// `null` = тугма кўринмайди (мас. эгасининг ўз экрани).
  final VoidCallback? onToggleFollow;

  @override
  Widget build(BuildContext context) {
    final name = tvOwnerDisplayName(displayName);
    if (name.isEmpty) return const SizedBox.shrink();
    final district = districtLabel.trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TvOwnerAvatar(
            name: name,
            photoUrl: photoUrl,
            radius: 26,
            onEdit: onEditPhoto,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                    height: 1.2,
                  ),
                ),
                if (district.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    district,
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                ],
                if (clipCount != null && clipCount! > 0) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.movie_outlined,
                          size: 15, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        context
                            .tr('tv_channel_clip_count')
                            .replaceAll('{n}', '$clipCount'),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
                if (totalViewCount != null && totalViewCount! > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.visibility_outlined,
                          size: 15, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        context
                            .tr('tv_channel_total_views')
                            .replaceAll('{n}', tvFormatViewCount(totalViewCount!)),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
                if (followerCount != null && followerCount! > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.people_alt_outlined,
                          size: 15, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        context
                            .tr('tv_channel_follower_count')
                            .replaceAll('{n}', tvFormatViewCount(followerCount!)),
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (onToggleFollow != null) ...[
            const SizedBox(width: 8),
            _FollowButton(
              following: isFollowing,
              onTap: onToggleFollow!,
            ),
          ],
        ],
      ),
    );
  }
}

class _FollowButton extends StatelessWidget {
  const _FollowButton({required this.following, required this.onTap});

  final bool following;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: following ? Colors.white : const Color(0xFF00E676),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: following ? Colors.grey.shade300 : Colors.transparent,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            context.tr(following ? 'tv_channel_following' : 'tv_channel_follow'),
            style: TextStyle(
              color: following ? Colors.black87 : Colors.black,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }
}
