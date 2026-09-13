import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../models/ava_book.dart';
import '../repositories/ava_book_repository.dart';

// ── "O'qish rejimi" — ilovaning umumiy neon-lime temasidan ataylab ajratilgan
// mustaqil rang palitrasi (qog'oz + tўq yashil siyoh), uzoq matnni o'qishga
// mos. Shuning uchun bu yerda AppColors ishlatilmaydi.
const _paper = Color(0xFFF2F0DE);
const _ink = Color(0xFF2B3420);
const _inkStrong = Color(0xFF20290F);
const _muted = Color(0xFF4A5738);
const _mutedSoft = Color(0xFF6E7A57);
const _accent = Color(0xFF6E9B00);
const _accentBright = Color(0xFFB7FF1A);

enum _UnitKind { cover, intro, partDivider, chapter, partOnly, finalPage }

class _ReadingUnit {
  const _ReadingUnit(this.kind, {this.part, this.chapter});
  final _UnitKind kind;
  final AvaBookPart? part;
  final AvaBookChapter? chapter;
}

final _dayRangeRe = RegExp(r'^\d+[–-]\d+-кун$');

class AvaBookScreen extends StatefulWidget {
  const AvaBookScreen({super.key});

  @override
  State<AvaBookScreen> createState() => _AvaBookScreenState();
}

class _AvaBookScreenState extends State<AvaBookScreen> {
  final _repo = AvaBookRepository();
  final _scrollCtrl = ScrollController();
  AvaBook? _book;
  List<_ReadingUnit> _units = const [];
  int _idx = 0;

  @override
  void initState() {
    super.initState();
    _repo.load().then((b) {
      if (!mounted) return;
      setState(() {
        _book = b;
        _units = _buildUnits(b);
      });
    });
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  List<_ReadingUnit> _buildUnits(AvaBook b) {
    final units = <_ReadingUnit>[const _ReadingUnit(_UnitKind.cover)];
    units.add(const _ReadingUnit(_UnitKind.intro));
    for (final p in b.parts) {
      units.add(_ReadingUnit(_UnitKind.partDivider, part: p));
      if (p.chapters.isNotEmpty) {
        for (final c in p.chapters) {
          units.add(_ReadingUnit(_UnitKind.chapter, part: p, chapter: c));
        }
      } else {
        units.add(_ReadingUnit(_UnitKind.partOnly, part: p));
      }
    }
    units.add(const _ReadingUnit(_UnitKind.finalPage));
    return units;
  }

  int _unitIndexForPart(String roman, int? chNum) {
    for (var i = 0; i < _units.length; i++) {
      final u = _units[i];
      if (chNum == null &&
          u.kind == _UnitKind.partDivider &&
          u.part?.roman == roman) {
        return i;
      }
      if (u.kind == _UnitKind.chapter &&
          u.part?.roman == roman &&
          u.chapter?.num == chNum) {
        return i;
      }
      if (u.kind == _UnitKind.partOnly &&
          u.part?.roman == roman &&
          chNum == null) {
        return i;
      }
    }
    return 0;
  }

  void _goTo(int i) {
    final clamped = i.clamp(0, _units.length - 1);
    setState(() => _idx = clamped);
    if (_scrollCtrl.hasClients) _scrollCtrl.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    if (book == null) {
      return const Scaffold(
        backgroundColor: _paper,
        body: Center(child: CircularProgressIndicator(color: _accent)),
      );
    }
    final u = _units[_idx];
    final totalReadable = _units.length - 2;
    final posInReadable = (_idx - 1).clamp(0, totalReadable - 1);
    final progress =
        totalReadable > 1 ? posInReadable / (totalReadable - 1) : 0.0;

    return Scaffold(
      backgroundColor: _paper,
      endDrawer: _ContentsDrawer(
        book: book,
        currentIndex: _idx,
        indexForPart: _unitIndexForPart,
        finalIndex: _units.length - 1,
        onJump: _goTo,
      ),
      body: SafeArea(
        child: Column(
          children: [
            _TopBar(breadcrumb: _breadcrumb(context, u)),
            LinearProgressIndicator(
              value: progress,
              minHeight: 2,
              backgroundColor: _inkStrong.withValues(alpha: 0.08),
              valueColor: const AlwaysStoppedAnimation(_accent),
            ),
            Expanded(
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(22, 14, 22, 26),
                child: _buildUnitContent(context, book, u),
              ),
            ),
            _NavRow(
              canPrev: _idx > 0,
              canNext: _idx < _units.length - 1,
              nextLabel: _idx == _units.length - 1
                  ? context.tr('book_finish')
                  : u.kind == _UnitKind.cover
                      ? context.tr('book_start_reading')
                      : context.tr('book_next'),
              onPrev: () => _goTo(_idx - 1),
              onNext: () => _goTo(_idx + 1),
            ),
          ],
        ),
      ),
    );
  }

  String _breadcrumb(BuildContext context, _ReadingUnit u) {
    switch (u.kind) {
      case _UnitKind.cover:
        return context.tr('book_cover');
      case _UnitKind.intro:
        return _book!.introTitle;
      case _UnitKind.partDivider:
      case _UnitKind.partOnly:
        return 'ҚИСМ ${u.part!.roman}';
      case _UnitKind.chapter:
        return 'ҚИСМ ${u.part!.roman} · ${u.chapter!.num}-БОБ';
      case _UnitKind.finalPage:
        return context.tr('book_final_page');
    }
  }

  Widget _buildUnitContent(BuildContext context, AvaBook book, _ReadingUnit u) {
    switch (u.kind) {
      case _UnitKind.cover:
        return _CoverPage(cover: book.cover);
      case _UnitKind.finalPage:
        return _FinalPage(onDone: () => Navigator.of(context).maybePop());
      case _UnitKind.partDivider:
        return _PartDividerPage(part: u.part!);
      case _UnitKind.intro:
        return _ProsePage(
          eyebrow: book.introTitle,
          title: book.introTitle,
          blocks: book.introBlocks,
        );
      case _UnitKind.chapter:
        return _ProsePage(
          eyebrow: u.part!.title,
          title: '${u.chapter!.num}-боб. ${u.chapter!.title}',
          blocks: u.chapter!.blocks,
        );
      case _UnitKind.partOnly:
        return _ProsePage(
          eyebrow: 'ҚИСМ ${u.part!.roman}',
          title: u.part!.title,
          blocks: u.part!.preamble,
          timeline: u.part!.roman == 'XVII',
        );
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.breadcrumb});
  final String breadcrumb;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 6, 6, 2),
      child: Row(
        children: [
          Builder(
            builder: (ctx) => IconButton(
              icon: const Icon(Icons.menu_rounded, color: _inkStrong),
              tooltip: context.tr('book_toc'),
              onPressed: () => Scaffold.of(ctx).openEndDrawer(),
            ),
          ),
          Expanded(
            child: Text(
              breadcrumb,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w700,
                fontSize: 11,
                letterSpacing: 0.6,
                color: _mutedSoft,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, color: _inkStrong),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ],
      ),
    );
  }
}

class _NavRow extends StatelessWidget {
  const _NavRow({
    required this.canPrev,
    required this.canNext,
    required this.nextLabel,
    required this.onPrev,
    required this.onNext,
  });

  final bool canPrev;
  final bool canNext;
  final String nextLabel;
  final VoidCallback onPrev;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: _inkStrong.withValues(alpha: 0.08))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: canPrev ? onPrev : null,
            child: Text(
              '← ${context.tr('book_prev')}',
              style: const TextStyle(fontWeight: FontWeight.w700, color: _inkStrong),
            ),
          ),
          FilledButton(
            onPressed: canNext ? onNext : null,
            style: FilledButton.styleFrom(
              backgroundColor: _inkStrong,
              foregroundColor: _paper,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
            ),
            child: Text(nextLabel, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class _CoverPage extends StatelessWidget {
  const _CoverPage({required this.cover});
  final AvaBookCover cover;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Text(
            cover.brand,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 40,
              letterSpacing: 2,
              color: _inkStrong,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            cover.title.replaceAll(RegExp(r'\s+'), ' ').trim(),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 4,
              color: _accent,
            ),
          ),
          const SizedBox(height: 22),
          ...cover.taglines.map(
            (t) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                t,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontStyle: FontStyle.italic,
                  fontSize: 13.5,
                  height: 1.5,
                  color: _muted,
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '${cover.year} · AVA нашри',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              color: _mutedSoft,
            ),
          ),
        ],
      ),
    );
  }
}

class _FinalPage extends StatelessWidget {
  const _FinalPage({required this.onDone});
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50),
      child: Column(
        children: [
          const Text('✨', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 10),
          const Text(
            'AVA — платформа сиз учун',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, color: _inkStrong),
          ),
          const SizedBox(height: 10),
          const Text(
            'Касбингиз, маҳсулотингиз, ғоянгиз бор — уларни фақат ўзингизда сақлаб қўйманг.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, height: 1.5, color: _muted),
          ),
          const SizedBox(height: 26),
          FilledButton(
            onPressed: onDone,
            style: FilledButton.styleFrom(
              backgroundColor: _inkStrong,
              foregroundColor: _paper,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            ),
            child: const Text('Бошлаш', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

class _PartDividerPage extends StatelessWidget {
  const _PartDividerPage({required this.part});
  final AvaBookPart part;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 50),
      child: Column(
        children: [
          Text(
            'ҚИСМ ${part.roman}',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 2,
              color: _accent,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            part.title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20, color: _inkStrong),
          ),
          if (part.epigraph != null) ...[
            const SizedBox(height: 16),
            Text(
              part.epigraph!,
              textAlign: TextAlign.center,
              style: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w600, fontSize: 14.5, color: _inkStrong),
            ),
          ],
          const SizedBox(height: 22),
          const Text('❖   ❖   ❖', style: TextStyle(color: _mutedSoft, letterSpacing: 4)),
        ],
      ),
    );
  }
}

class _ProsePage extends StatelessWidget {
  const _ProsePage({
    required this.eyebrow,
    required this.title,
    required this.blocks,
    this.timeline = false,
  });

  final String eyebrow;
  final String title;
  final List<AvaBookBlock> blocks;
  final bool timeline;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          eyebrow,
          style: const TextStyle(
            fontFamily: 'monospace',
            fontWeight: FontWeight.w700,
            fontSize: 10.5,
            letterSpacing: 1.2,
            color: _accent,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 19, height: 1.28, color: _inkStrong),
        ),
        const SizedBox(height: 16),
        ..._renderBlocks(blocks, timeline: timeline),
      ],
    );
  }

  List<Widget> _renderBlocks(List<AvaBookBlock> blocks, {required bool timeline}) {
    final out = <Widget>[];
    final tsteps = <Widget>[];

    void flushTimeline() {
      if (tsteps.isEmpty) return;
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Column(children: List.of(tsteps)),
      ));
      tsteps.clear();
    }

    for (var k = 0; k < blocks.length; k++) {
      final b = blocks[k];
      if (timeline && b.type == 'subhead' && _dayRangeRe.hasMatch(b.text ?? '')) {
        String body = '';
        if (k + 1 < blocks.length && blocks[k + 1].type == 'p') {
          body = blocks[++k].text ?? '';
        }
        final isLast = !blocks
            .skip(k + 1)
            .any((bb) => bb.type == 'subhead' && _dayRangeRe.hasMatch(bb.text ?? ''));
        tsteps.add(_TimelineStep(range: b.text ?? '', body: body, isLast: isLast));
        continue;
      }
      flushTimeline();
      out.add(_blockWidget(b));
    }
    flushTimeline();
    return out;
  }

  Widget _blockWidget(AvaBookBlock b) {
    switch (b.type) {
      case 'p':
        return Padding(
          padding: const EdgeInsets.only(bottom: 13),
          child: Text(b.text ?? '', style: const TextStyle(fontSize: 14.5, height: 1.62, color: _ink)),
        );
      case 'subhead':
        return Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 8),
          child: Text(
            b.text ?? '',
            style: const TextStyle(fontWeight: FontWeight.w700, fontStyle: FontStyle.italic, fontSize: 15.5, color: _inkStrong),
          ),
        );
      case 'label':
        return Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(
            b.text ?? '',
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
              letterSpacing: 1.4,
              color: _accent,
            ),
          ),
        );
      case 'divider':
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: Text('❖   ❖   ❖', style: TextStyle(color: _mutedSoft, letterSpacing: 4)),
          ),
        );
      case 'quote':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 16),
          padding: const EdgeInsets.only(left: 14),
          decoration: const BoxDecoration(
            border: Border(left: BorderSide(color: _accent, width: 3)),
          ),
          child: Text(
            b.text ?? '',
            style: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w700, fontSize: 15, height: 1.45, color: _inkStrong),
          ),
        );
      case 'dialoguelist':
        return Container(
          margin: const EdgeInsets.only(bottom: 13),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _inkStrong.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: (b.items ?? const [])
                .map((it) => Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Text(it, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 14, height: 1.5, color: _ink)),
                    ))
                .toList(),
          ),
        );
      case 'rule':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 14),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(color: _inkStrong, borderRadius: BorderRadius.circular(14)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ҚОИДА', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 10, letterSpacing: 1.6, color: _accentBright)),
              const SizedBox(height: 6),
              Text(b.text ?? '', style: const TextStyle(fontStyle: FontStyle.italic, fontWeight: FontWeight.w600, fontSize: 14.5, height: 1.45, color: _paper)),
            ],
          ),
        );
      case 'warning':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 14),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _accent.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _accent.withValues(alpha: 0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Муҳим чегара', style: TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 10.5, letterSpacing: 0.8, color: Color(0xFF5C7A1E))),
              const SizedBox(height: 6),
              Text(b.text ?? '', style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF3A4429))),
            ],
          ),
        );
      case 'exercise':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 14),
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _inkStrong.withValues(alpha: 0.12)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text((b.label ?? '').replaceAll('✎', '').trim(),
                  style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 10.5, letterSpacing: 0.8, color: _accent)),
              const SizedBox(height: 8),
              ...(b.items ?? const []).map(
                (it) => Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('✓', style: TextStyle(color: _accent, fontWeight: FontWeight.w800)),
                      const SizedBox(width: 8),
                      Expanded(child: Text(it, style: const TextStyle(fontSize: 13, height: 1.5, color: _ink))),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      case 'bulletlist':
        return Padding(
          padding: const EdgeInsets.only(bottom: 13),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: (b.items ?? const [])
                .map((it) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: const BoxDecoration(color: _inkStrong, shape: BoxShape.circle),
                            alignment: Alignment.center,
                            child: const Text('?', style: TextStyle(fontFamily: 'monospace', fontSize: 9, fontWeight: FontWeight.w700, color: _accentBright)),
                          ),
                          const SizedBox(width: 8),
                          Expanded(child: Text(it, style: const TextStyle(fontStyle: FontStyle.italic, fontSize: 13.5, height: 1.5, color: Color(0xFF3A4429)))),
                        ],
                      ),
                    ))
                .toList(),
          ),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

class _TimelineStep extends StatelessWidget {
  const _TimelineStep({required this.range, required this.body, required this.isLast});
  final String range;
  final String body;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.only(top: 5),
                decoration: const BoxDecoration(color: _accent, shape: BoxShape.circle),
              ),
              if (!isLast)
                Expanded(child: Container(width: 1, color: _accent.withValues(alpha: 0.35))),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(range, style: const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w700, fontSize: 11, color: _accent)),
                  const SizedBox(height: 3),
                  Text(body, style: const TextStyle(fontSize: 14, height: 1.5, color: _ink)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContentsDrawer extends StatelessWidget {
  const _ContentsDrawer({
    required this.book,
    required this.currentIndex,
    required this.indexForPart,
    required this.finalIndex,
    required this.onJump,
  });

  final AvaBook book;
  final int currentIndex;
  final int Function(String roman, int? chNum) indexForPart;
  final int finalIndex;
  final void Function(int) onJump;

  @override
  Widget build(BuildContext context) {
    return Drawer(
      backgroundColor: _inkStrong,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
              child: Text(context.tr('book_toc'),
                  style: const TextStyle(color: _paper, fontWeight: FontWeight.w800, fontSize: 18)),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 20),
                children: [
                  _drawerItem(context, context.tr('book_cover'), 0),
                  _drawerItem(context, book.introTitle, 1),
                  ...book.parts.map((p) => _partTile(context, p)),
                  _drawerItem(context, context.tr('book_final_page'), finalIndex),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _partTile(BuildContext context, AvaBookPart p) {
    final headIndex = indexForPart(p.roman, null);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        collapsedIconColor: _accentBright,
        iconColor: _accentBright,
        title: Text('${p.roman}. ${p.title}',
            style: const TextStyle(color: _paper, fontWeight: FontWeight.w700, fontSize: 13.5)),
        childrenPadding: const EdgeInsets.only(left: 10),
        children: [
          _drawerItem(context, '— ${context.tr('book_section_start')} —', headIndex, dense: true),
          ...p.chapters.map((c) =>
              _drawerItem(context, '${c.num}-боб. ${c.title}', indexForPart(p.roman, c.num), dense: true)),
        ],
      ),
    );
  }

  Widget _drawerItem(BuildContext context, String label, int i, {bool dense = false}) {
    final active = i == currentIndex;
    return ListTile(
      dense: dense,
      title: Text(
        label,
        style: TextStyle(
          color: active ? _accentBright : const Color(0xFFD8E0C8),
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          fontSize: dense ? 13 : 14.5,
        ),
      ),
      onTap: () {
        onJump(i);
        Navigator.of(context).maybePop();
      },
    );
  }
}
