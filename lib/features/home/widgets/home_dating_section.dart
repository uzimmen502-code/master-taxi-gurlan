import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/dating_public_profile.dart';
import '../../../repositories/dating_repository.dart';
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

    final c = context.ava;
    return AvaSection(
      title: context.tr('dating_short_label'),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      skeletonRows: 1,
      child: Container(
        decoration: BoxDecoration(
          color: c.surface,
          borderRadius: BorderRadius.circular(AvaRadius.card),
          border: Border.all(color: c.line),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Column(
          children: [
            for (final profile in _items)
              _ProfileRow(
                // Карточка босилса АЙНАН ШУ профил эмас, танишув модули
                // очилади: бегона профилни фақат ўзининг тасдиқланган
                // профили бор фойдаланувчи кўриши керак, бу текширув
                // эса `DatingHomeScreen` ичида.
                profile: profile,
                onTap: widget.onOpenAll,
              ),
          ],
        ),
      ),
    );
  }
}

/// Битта профил — қора нуқта (●) + бош ҳарф доираси + исм, ёш.
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.profile, required this.onTap});

  final DatingPublicProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    final age = profile.age;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: c.ink, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            // Расм ЎРНИГА бош ҳарф — профил фотоси чизилмайди.
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.brandSoft,
                shape: BoxShape.circle,
              ),
              child: Text(
                datingInitial(profile.displayName),
                style: AvaText.caption.copyWith(
                  color: c.brand,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                age != null
                    ? '${profile.displayName}, $age'
                    : profile.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AvaText.body.copyWith(color: c.ink),
              ),
            ),
            // Шаҳар / жойлашув АТАЙЛАБ кўрсатилмайди.
          ],
        ),
      ),
    );
  }
}
