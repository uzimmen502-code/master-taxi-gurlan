import 'dart:typed_data';

/// Қайта кодлаш поғоналари (энг катта томон, JPEG сифати) — биринчиси ҳажмга сиққани олинади.
const kImageFitLadder = <(int, double)>[
  (1600, 0.82),
  (1440, 0.78),
  (1280, 0.72),
  (1080, 0.66),
  (960, 0.6),
  (720, 0.55),
];

/// Расмни [maxBytes] гача сиғдириш (соф; кодловчи — DI, web'да canvas). Эга 2026-11-28: splash креативи клиент
/// кеши чегараси (1500 КБ) дан катта бўлса, қурилма уни умуман кўрсатмайди — шунинг учун юклашда шу чегарага келтирилади.
///  * Аслиси сиғса ва [keepOriginalIfFits] — аслиси (формати сақланади).
///  * Акс ҳолда поғоналар бўйича JPEG; биринчи сиққани.
///  * Ҳеч бири сиғмаса — `null` (чақирувчи рад этади, хато матни).
Future<({Uint8List bytes, String mime})?> fitImageToMaxBytes(
  Uint8List input, {
  required int maxBytes,
  required Future<Uint8List?> Function(int maxEdge, double quality) encode,
  String mimeHint = 'image/jpeg',
  bool keepOriginalIfFits = true,
}) async {
  if (input.isEmpty) return null;
  if (keepOriginalIfFits && input.length <= maxBytes) {
    return (bytes: input, mime: mimeHint.startsWith('image/') ? mimeHint : 'image/jpeg');
  }
  for (final (edge, q) in kImageFitLadder) {
    Uint8List? out;
    try {
      out = await encode(edge, q);
    } catch (_) {
      out = null;
    }
    if (out != null && out.isNotEmpty && out.length <= maxBytes) return (bytes: out, mime: 'image/jpeg');
  }
  return null;
}
