import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/utils/session_shuffle.dart';
import '../../../models/dating_public_profile.dart';
import '../../../repositories/dating_repository.dart';
import '../home_demo_feed.dart';
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

  /// Реал профиллар шунчагача; қолган жой намунавий қаторларга берилади.
  /// Ойнада 5 таси кўринади, қолгани скролл ([AvaRowViewport]).
  static const limit = HomeDemoFeed.capacity;

  @override
  State<HomeDatingSection> createState() => _HomeDatingSectionState();
}

class _HomeDatingSectionState extends State<HomeDatingSection> {
  final _repo = DatingRepository();
  final Random _rnd = sessionRandom();
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
          // Ҳар очилишда бошқа тартиб; кўрилиб турганлар ўрнида қолади.
          _items = mergeShuffled(
            current: _items,
            incoming: list.take(HomeDatingSection.limit).toList(),
            idOf: (p) => p.userId,
            random: _rnd,
          );
          // Намунавий қаторлар доим бор, шунинг учун «бўш» ҳолат йўқ.
          _status = AvaSectionStatus.ready;
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

    // Реал профиллардан кейин қолган жой намунавий қаторларга берилади;
    // реал профил 10 тага етганда улар ўз-ўзидан йўқолади.
    final demo = HomeDemoFeed.fill(
      context,
      keys: HomeDemoFeed.profileKeysFor(widget.viewerGender),
      realCount: _items.length,
      random: _rnd,
    );
    return AvaSection(
      moduleId: 'dating',
      title: context.tr('dating_short_label'),
      status: _status,
      onSeeAll: widget.onOpenAll,
      onRetry: _listen,
      skeletonRows: 1,
      // Ботиқ майдон — қаторлар унинг ичида (қаранг: [AvaInsetPanel]).
      child: AvaInsetPanel(
        child: AvaRowPager(
          // Бошқа бўлимлар билан АЙНАН бир хил қатор баландлиги — бош
          // ҳарф доираси шу баландликка мослашади (эга қарори,
          // 2026-09-27).
          rowHeight: AvaRowPager.textRowHeight(context),
          onOpenModule: widget.onOpenAll,
          rows: [
            for (final p in _items)
              _ProfileRow(
                // Қатор босилса АЙНАН ШУ профил эмас, танишув модули
                // очилади: бегона профилни фақат ўзининг тасдиқланган
                // профили бор фойдаланувчи кўриши керак, бу текширув
                // эса `DatingHomeScreen` ичида.
                label: p.age != null
                    ? '${p.displayName}, ${p.age}'
                    : p.displayName,
                onTap: widget.onOpenAll,
              ),
            for (final label in demo)
              _ProfileRow(label: label, onTap: widget.onOpenAll),
          ],
        ),
      ),
    );
  }
}

/// Битта қатор — қора нуқта (●) + бош ҳарф доираси + «исм, ёш».
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({required this.label, required this.onTap});

  /// Тайёр ёзув: «Дилноза, 24».
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {

    final c = context.ava;
    // Бош ҳарф доираси қатор баландлигига тенг — шунда танишув қатори
    // бошқа бўлимлардаги матн қаторидан баланд бўлиб кетмайди. Олдин у
    // қатъий 28px эди ва қаторлар икки баробар сийрак кўринарди.
    final avatar = AvaRowPager.textRowHeight(context);
    // Қаторлар ораси айнан 1px: ички вертикал чет йўқ.
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.zero,
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
              width: avatar,
              height: avatar,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.brandSoft,
                shape: BoxShape.circle,
              ),
              // Ҳарф доира билан бирга кичраяди. `height: 1` — акс ҳолда
              // шрифтнинг ўз қатор оралиғи доирадан ошиб, ҳарф пастга
              // сурилиб қоларди.
              child: Text(
                datingInitial(label),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: avatar * 0.6,
                  height: 1,
                  color: c.brand,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AvaText.feedRow.copyWith(color: c.inkRow),
              ),
            ),
            // Шаҳар / жойлашув АТАЙЛАБ кўрсатилмайди.
          ],
        ),
      ),
    );
  }
}
