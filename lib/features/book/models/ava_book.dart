/// AVA Имкониятлар китоби — content-turi maʼlumot, `assets/book/ava_imkoniyatlar_kitobi.json`
/// dan yuklanadi (AppLocalizations kabi UI matn emas, uzun tarkib).
class AvaBookBlock {
  const AvaBookBlock({required this.type, this.text, this.label, this.items});

  final String type; // p, subhead, label, divider, quote, dialoguelist, rule, warning, exercise, bulletlist
  final String? text;
  final String? label;
  final List<String>? items;

  factory AvaBookBlock.fromJson(Map<String, dynamic> j) => AvaBookBlock(
        type: j['t'] as String,
        text: j['text'] as String?,
        label: j['label'] as String?,
        items: (j['items'] as List?)?.map((e) => e as String).toList(),
      );
}

class AvaBookChapter {
  const AvaBookChapter({required this.num, required this.title, required this.blocks});

  final int num;
  final String title;
  final List<AvaBookBlock> blocks;

  factory AvaBookChapter.fromJson(Map<String, dynamic> j) => AvaBookChapter(
        num: j['num'] as int,
        title: j['title'] as String,
        blocks: (j['blocks'] as List)
            .map((b) => AvaBookBlock.fromJson(b as Map<String, dynamic>))
            .toList(),
      );
}

class AvaBookPart {
  const AvaBookPart({
    required this.roman,
    required this.title,
    required this.epigraph,
    required this.chapters,
    required this.preamble,
  });

  final String roman;
  final String title;
  final String? epigraph;
  final List<AvaBookChapter> chapters;
  final List<AvaBookBlock> preamble;

  factory AvaBookPart.fromJson(Map<String, dynamic> j) => AvaBookPart(
        roman: j['roman'] as String,
        title: j['title'] as String,
        epigraph: j['epigraph'] as String?,
        chapters: (j['chapters'] as List)
            .map((c) => AvaBookChapter.fromJson(c as Map<String, dynamic>))
            .toList(),
        preamble: (j['preamble'] as List)
            .map((b) => AvaBookBlock.fromJson(b as Map<String, dynamic>))
            .toList(),
      );
}

class AvaBookCover {
  const AvaBookCover({
    required this.brand,
    required this.title,
    required this.taglines,
    required this.year,
  });

  final String brand;
  final String title;
  final List<String> taglines;
  final String year;

  factory AvaBookCover.fromJson(Map<String, dynamic> j) => AvaBookCover(
        brand: j['brand'] as String,
        title: j['title'] as String,
        taglines: (j['taglines'] as List).map((e) => e as String).toList(),
        year: j['year'] as String,
      );
}

class AvaBook {
  const AvaBook({
    required this.cover,
    required this.introTitle,
    required this.introBlocks,
    required this.parts,
  });

  final AvaBookCover cover;
  final String introTitle;
  final List<AvaBookBlock> introBlocks;
  final List<AvaBookPart> parts;

  factory AvaBook.fromJson(Map<String, dynamic> j) => AvaBook(
        cover: AvaBookCover.fromJson(j['cover'] as Map<String, dynamic>),
        introTitle: (j['intro'] as Map<String, dynamic>)['title'] as String,
        introBlocks: ((j['intro'] as Map<String, dynamic>)['blocks'] as List)
            .map((b) => AvaBookBlock.fromJson(b as Map<String, dynamic>))
            .toList(),
        parts: (j['parts'] as List)
            .map((p) => AvaBookPart.fromJson(p as Map<String, dynamic>))
            .toList(),
      );

  int get chapterCount => parts.fold(0, (sum, p) => sum + p.chapters.length);
}
