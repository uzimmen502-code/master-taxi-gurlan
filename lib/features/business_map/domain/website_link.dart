/// «Ўз сайтингиз» майдони (эга қарори, 2026-10-23): фақат сайт манзили; Telegram/@ҳандл эмас. Форма текшируви ва
/// карточкада очиш — БИР функция (7-банд). Схемасиз ёзилса `https://` қўшилади; фақат http/https очилади.
Uri? websiteUri(String raw) {
  final s = raw.trim();
  if (s.isEmpty || s.contains(RegExp(r'\s')) || s.startsWith('@')) return null;
  final lower = s.toLowerCase();
  final String withScheme;
  if (lower.startsWith('http://') || lower.startsWith('https://')) {
    withScheme = s;
  } else if (s.contains(':')) {
    return null; // mailto:, javascript:, tel: ва ҳ.к.
  } else {
    withScheme = 'https://$s';
  }
  final uri = Uri.tryParse(withScheme);
  if (uri == null || uri.host.isEmpty || !uri.host.contains('.') || uri.host.startsWith('.') || uri.host.endsWith('.')) {
    return null;
  }
  return uri;
}

/// Бўш — тўғри (майдон ихтиёрий); тўлдирилган бўлса — очиладиган сайт манзили бўлиши шарт.
bool websiteFieldValid(String raw) => raw.trim().isEmpty || websiteUri(raw) != null;
