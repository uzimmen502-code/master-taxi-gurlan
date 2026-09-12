import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../models/tv_clip.dart';
import '../utils/tv_view_format.dart';
import 'tv_owner_action_bar.dart';

/// Видео устидаги UI: ўнг тугмалар (лайм дўкон) + паст маълумот + Боғланиш / Таҳрир+Ўчириш.
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
    this.liked = false,
    this.saved = false,
    this.isOwner = false,
    this.onDelete,
    this.onEdit,
    this.onOpenShop,
    this.openChannelAsShop = true,
    this.filters,
  });

  final TvClip clip;
  final VoidCallback onContact;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final bool liked;
  final bool saved;
  final bool isOwner;
  final VoidCallback? onDelete;
  final VoidCallback? onEdit;
  final VoidCallback? onOpenShop;

  /// `false` → lime tugma «Канал».
  final bool openChannelAsShop;

  /// Пастки қаторнинг чап томонида, «Боғланиш» тугмасидан олдин
  /// турадиган ҳудуд фильтрлари (туман, вилоят). Экран даражасидаги
  /// ҳолатга боғлиқ бўлгани учун ташқаридан узатилади.
  final Widget? filters;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Stack(
      children: [
        Positioned(
          left: 12,
          // Пастки қатор экраннинг ўнг чеккасигача чўзилади. Ўнгдаги
          // тугмалар устуни ундан ЮҚОРИРОҚ (`bottom + 80`) тургани
          // учун бу қаторга халақит бермайди.
          right: 12,
          bottom: bottom + 16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Матн устуни эса ўнгдаги тугмалар устунига кириб
              // кетмаслиги керак — шунинг учун унга алоҳида чекинма
              // (12 + 60 = аввалги 72).
              Padding(
                padding: const EdgeInsets.only(right: 60),
                child: _InfoColumn(clip: clip),
              ),
              const SizedBox(height: 10),
              if (isOwner && onEdit != null && onDelete != null)
                TvOwnerActionBar(onEdit: onEdit!, onDelete: onDelete!),
              // Битта қатор: чапда [туман] [вилоят], ўнг чеккада
              // «Боғланиш». Фильтрлар эгасининг ўз клипида ҳам
              // кўринади — улар клипга эмас, лентага тегишли.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (filters != null) Flexible(child: filters!),
                  if (!isOwner && clip.showPhone) ...[
                    if (filters != null) const SizedBox(width: 6),
                    // Ихчам: матни қанча бўлса шунча жой олади ва
                    // қолганини фильтрларга бўшатади. `ElevatedButton`
                    // ўзидан 64px минимал КЕНГЛИК мажбурлайди —
                    // `minimumSize: Size.zero` уни олиб ташлайди
                    // (`tapTargetSize` фақат баландликка таъсир қилади).
                    // Иконка ва матн орасидаги оралиқни бошқариш учун
                    // `.icon` конструктори эмас, ўз `Row`имиз.
                    SizedBox(
                      height: 30,
                      child: ElevatedButton(
                        onPressed: onContact,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.28),
                          foregroundColor: const Color(0xFF00E676),
                          padding: const EdgeInsets.symmetric(horizontal: 9),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(9),
                          ),
                          elevation: 0,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.call_rounded, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              context.tr('tv_market_contact'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
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
            openChannelAsShop: openChannelAsShop,
            onLike: onLike,
            onComment: onComment,
            onShare: onShare,
            onSave: onSave,
            onOpenShop: onOpenShop,
          ),
        ),
      ],
    );
  }
}

/// Эга аватари ва исми бу ерда ЙЎҚ — улар экран юқорисига, AppBar'га
/// кўчирилди (`TvFeedOwnerTitle`).
class _InfoColumn extends StatelessWidget {
  const _InfoColumn({required this.clip});
  final TvClip clip;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
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
            if (clip.viewCount > 0) ...[
              const Icon(Icons.visibility_outlined,
                  color: Colors.white70, size: 14),
              const SizedBox(width: 2),
              Text(
                tvFormatViewCount(clip.viewCount),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
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
    required this.onComment,
    required this.onShare,
    required this.onSave,
    this.onOpenShop,
    this.openChannelAsShop = true,
    this.showShop = false,
  });

  final TvClip clip;
  final bool liked;
  final bool saved;
  final VoidCallback onLike;
  final VoidCallback onComment;
  final VoidCallback onShare;
  final VoidCallback onSave;
  final VoidCallback? onOpenShop;
  final bool openChannelAsShop;
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
          icon: Icons.mode_comment_outlined,
          label: clip.commentCount > 0 ? '${clip.commentCount}' : '',
          onTap: onComment,
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
            label: context.tr(
              openChannelAsShop ? 'tv_market_shop' : 'tv_market_channel',
            ),
            isShop: openChannelAsShop,
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
  const _ShopActionBtn({
    required this.label,
    required this.onTap,
    this.isShop = true,
  });

  final String label;
  final VoidCallback onTap;
  final bool isShop;

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
            child: Icon(
              isShop ? Icons.storefront_rounded : Icons.live_tv_rounded,
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
