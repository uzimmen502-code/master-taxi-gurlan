import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/dating_public_profile.dart';
import '../../../repositories/dating_repository.dart';
import 'ava_card.dart';
import 'ava_section.dart';

/// 18 ёш — бўлим кўриниши учун энг кичик ёш.
const int kDatingMinViewerAge = 18;

/// Кўрувчига бўлим кўрсатиладими.
///
/// Эга қарори: туғилган сана тўлдирилмаган бўлса ҳам КЎРСАТИЛМАЙДИ —
/// ёши номаълум фойдаланувчига 18+ мазмун чиқармаймиз.
bool datingSectionVisibleFor(String birthDate) {
  final age = ageFromBirthDate(birthDate);
  if (age == null) return false;
  return age >= kDatingMinViewerAge;
}

/// Исмнинг бош ҳарфи — расм ўрнига.
///
/// Тавсиф талаби: «Расм ўрнида бош ҳарфни тизимнинг ўзи қўяди».
String datingInitial(String displayName) {
  final s = displayName.trim();
  if (s.isEmpty) return '?';
  return s.characters.first.toUpperCase();
}

/// 9-бўлим: танишув.
///
/// ФАҚАТ исм ва ёш кўрсатилади. Расм, шаҳар, «ҳақида» ва бошқа
/// майдонлар КЎРСАТИЛМАЙДИ (тавсиф талаби) — устига улар умуман
/// ЮКЛАНМАЙДИ ҳам: бўлим `dating_profiles_public` очиқ кўчирмасини
/// ўқийди, унда бу майдонларнинг ўзи йўқ.
class HomeDatingSection extends StatefulWidget {
  const HomeDatingSection({
    super.key,
    required this.viewerUid,
    required this.viewerBirthDate,
    required this.viewerGender,
    required this.onOpenAll,
  });

  /// Ўз профилини рўйхатда кўрсатмаслик учун.
  final String viewerUid;

  /// `users.birthDate` — 18+ текшируви учун.
  final String viewerBirthDate;

  /// Танишувда қарама-қарши жинс кўрсатилади.
  final String viewerGender;

  final VoidCallback onOpenAll;

  static const limit = 5;

  @override
  State<HomeDatingSection> createState() => _HomeDatingSectionState();
}

class _HomeDatingSectionState extends State<HomeDatingSection> {
  final _repo = DatingRepository();
  StreamSubscription<List<DatingPublicProfile>>? _sub;

  AvaSectionStatus _status = AvaSectionStatus.loading;
  List<DatingPublicProfile> _items = const [];

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(covariant HomeDatingSection old) {
    super.didUpdateWidget(old);
    if (old.viewerGender != widget.viewerGender) _listen();
  }

  void _listen() {
    _sub?.cancel();
    if (mounted) setState(() => _status = AvaSectionStatus.loading);
    _sub = _repo
        .watchPublicDiscovery(
          myUid: widget.viewerUid,
          myGender: widget.viewerGender,
        )
        .listen(
      (list) {
        if (!mounted) return;
        setState(() {
          _items = list.take(HomeDatingSection.limit).toList();
          _status = _items.isEmpty
              ? AvaSectionStatus.empty
              : AvaSectionStatus.ready;
        });
      },
      onError: (Object e) {
        debugPrint('[HomeDating] $e');
        if (mounted) setState(() => _status = AvaSectionStatus.error);
      },
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 18 ёшдан кичик ёки ёши номаълум — бўлим БУТУНЛАЙ йўқ.
    if (!datingSectionVisibleFor(widget.viewerBirthDate)) {
      return const SizedBox.shrink();
    }

    return AvaSection(
      title: context.tr('dating_short_label'),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      skeletonRows: 1,
      child: SizedBox(
        // Ички чет (10×2) + бош ҳарф доираси (44) + оралиқ (6) + исм ва
        // ёш қаторлари. Қатъий баландлик шрифт 130% бўлганда тошарди.
        height: 70 +
            MediaQuery.textScalerOf(context)
                    .scale(AvaText.productName.fontSize ?? 13) *
                1.5 +
            MediaQuery.textScalerOf(context)
                    .scale(AvaText.caption.fontSize ?? 12) *
                1.5,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          physics: const BouncingScrollPhysics(),
          itemCount: _items.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          // Карточка босилса АЙНАН ШУ профил эмас, танишув модули
          // очилади: бегона профилни фақат ўзининг тасдиқланган профили
          // бор фойдаланувчи кўриши керак, бу текширув эса
          // `DatingHomeScreen` ичида.
          itemBuilder: (context, i) => _ProfileTile(
            profile: _items[i],
            onTap: widget.onOpenAll,
          ),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({required this.profile, required this.onTap});

  final DatingPublicProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final age = profile.age;

    return AvaCard(
      width: 92,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Расм ЎРНИГА бош ҳарф — профил фотоси чизилмайди.
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.brandSoft,
              shape: BoxShape.circle,
            ),
            child: Text(
              datingInitial(profile.displayName),
              style: AvaText.sectionTitle.copyWith(color: c.brand),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            profile.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AvaText.productName.copyWith(color: c.ink),
          ),
          if (age != null)
            Text(
              '$age',
              style: AvaText.caption.copyWith(color: c.ink3),
            ),
          // Шаҳар / жойлашув АТАЙЛАБ кўрсатилмайди.
        ],
      ),
    );
  }
}
