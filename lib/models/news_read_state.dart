/// «Хабарлар» экранига кирилган пайтдаги ўқилганлик ҳолати.
///
/// Экран очилганда бўлим «ўқилди» деб белгиланади (badge тозаланади), шунинг
/// учун ўқилмаганларни рўйхатда ажратиш учун белгидан ОЛДИНГИ вақт сақланади.
/// Ҳолат номаълум (юкланмади) бўлса — ҳеч бир хабар «янги» деб белгиланмайди.
class NewsReadState {
  const NewsReadState({this.known = false, this.readBefore});

  /// Ҳолат номаълум: ҳамма хабар ўқилгандек кўринади.
  static const unknown = NewsReadState();

  final bool known;

  /// Охирги ўқиш вақти (`null` + [known] — ҳали ҳеч қачон ўқилмаган).
  final DateTime? readBefore;

  bool isUnread(DateTime createdAt) {
    if (!known) return false;
    final r = readBefore;
    return r == null || createdAt.isAfter(r);
  }
}
