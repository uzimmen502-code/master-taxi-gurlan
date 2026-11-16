/// `assistantGetStatus` / `assistantChat.status` жавоби.
class AssistantStatus {
  const AssistantStatus({
    required this.enabled,
    required this.pro,
    this.unlimited = false,
    required this.paidUntil,
    required this.usedToday,
    required this.dailyLimit,
    required this.freeDailyLimit,
    required this.webSearchesToday,
    required this.webSearchLimit,
    required this.balance,
    required this.packages,
    this.priceSearchEnabled = false,
    this.priceSearchDailyLimit = 0,
    this.priceSearchUsedToday = 0,
  });

  /// «Нарх қидириш» босқичи шу фойдаланувчига очиқ (`settings/assistant.priceSearchStage`).
  /// Plus алоҳида ([pro]) — Plus йўқ бўлса бўлим кўринади, лекин «Plus олинг» варақаси очилади.
  final bool priceSearchEnabled;
  final int priceSearchDailyLimit;
  final int priceSearchUsedToday;

  final bool enabled;
  final bool pro;

  /// Доимий Pro (`settings/assistant.freeProPhones`) — муддат кўрсатилмайди.
  final bool unlimited;
  final DateTime? paidUntil;
  final int usedToday;
  final int dailyLimit;
  final int freeDailyLimit;
  final int webSearchesToday;
  final int webSearchLimit;

  /// Ҳамён (`users.bonusBalance`) — пакет сотиб олиш экрани учун.
  final int balance;
  final List<AssistantPackage> packages;

  /// Бир марталик тўлов (10 йил) — муддат кўрсатилмайди, «чекловсиз».
  bool get lifetime =>
      paidUntil != null &&
      paidUntil!.difference(DateTime.now()).inDays > 5 * 365;

  int get remainingToday =>
      (dailyLimit - usedToday) < 0 ? 0 : dailyLimit - usedToday;

  /// Сотиладиган пакет (эга 2026-11-17: битта 24 соатлик пасс); бўлмаса биринчиси.
  AssistantPackage? get passPackage {
    for (final p in packages) {
      if (!p.oneTime) return p;
    }
    return packages.isNotEmpty ? packages.first : null;
  }

  factory AssistantStatus.fromMap(Map<String, dynamic> m) {
    final paidUntilMs = (m['paidUntil'] as num?)?.toInt();
    final rawPkgs = m['packages'];
    final ps = m['priceSearch'] is Map ? Map<String, dynamic>.from(m['priceSearch'] as Map) : const <String, dynamic>{};
    return AssistantStatus(
      priceSearchEnabled: ps['enabled'] == true,
      priceSearchDailyLimit: (ps['dailyLimit'] as num?)?.toInt() ?? 0,
      priceSearchUsedToday: (ps['usedToday'] as num?)?.toInt() ?? 0,
      enabled: m['enabled'] != false,
      pro: m['pro'] == true,
      unlimited: m['unlimited'] == true,
      paidUntil: paidUntilMs == null || paidUntilMs <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(paidUntilMs),
      usedToday: (m['usedToday'] as num?)?.toInt() ?? 0,
      dailyLimit: (m['dailyLimit'] as num?)?.toInt() ?? 0,
      freeDailyLimit: (m['freeDailyLimit'] as num?)?.toInt() ?? 0,
      webSearchesToday: (m['webSearchesToday'] as num?)?.toInt() ?? 0,
      webSearchLimit: (m['webSearchLimit'] as num?)?.toInt() ?? 0,
      balance: (m['balance'] as num?)?.toInt() ?? 0,
      packages: rawPkgs is List
          ? rawPkgs
              .whereType<Map>()
              .map((p) => AssistantPackage.fromMap(Map<String, dynamic>.from(p)))
              .toList()
          : const [],
    );
  }

  AssistantStatus copyWith({
    bool? pro,
    DateTime? paidUntil,
    int? balance,
  }) =>
      AssistantStatus(
        enabled: enabled,
        pro: pro ?? this.pro,
        unlimited: unlimited,
        paidUntil: paidUntil ?? this.paidUntil,
        usedToday: usedToday,
        dailyLimit: dailyLimit,
        freeDailyLimit: freeDailyLimit,
        webSearchesToday: webSearchesToday,
        webSearchLimit: webSearchLimit,
        balance: balance ?? this.balance,
        packages: packages,
        priceSearchEnabled: priceSearchEnabled,
        priceSearchDailyLimit: priceSearchDailyLimit,
        priceSearchUsedToday: priceSearchUsedToday,
      );
}

/// Pro пакет (`settings/assistant.packages` ёки сервер default).
class AssistantPackage {
  const AssistantPackage({
    required this.id,
    required this.days,
    required this.price,
    required this.promo,
    this.oneTime = false,
  });

  final String id;
  final int days;
  final int price;
  final bool promo;

  /// Эски «бир марталик» (доимий) пакет — 2026-11-17 дан сотилмайди; эски `settings` учун қолди.
  final bool oneTime;

  /// 24 соатлик пасс (`days == 1`, эга 2026-11-17).
  bool get isDayPass => !oneTime && days == 1;

  factory AssistantPackage.fromMap(Map<String, dynamic> m) => AssistantPackage(
        id: (m['id'] ?? '') as String,
        days: (m['days'] as num?)?.toInt() ?? 0,
        price: (m['price'] as num?)?.toInt() ?? 0,
        promo: m['promo'] == true,
        oneTime: m['oneTime'] == true,
      );
}
