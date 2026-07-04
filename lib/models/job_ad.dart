import 'package:cloud_firestore/cloud_firestore.dart';

/// Эълон тури — иш, хизмат, оддий эълон, сотаман (P2P).
enum AdKind { work, service, ad, sell }

extension AdKindX on AdKind {
  String get key {
    switch (this) {
      case AdKind.work:
        return 'work';
      case AdKind.service:
        return 'service';
      case AdKind.ad:
        return 'ad';
      case AdKind.sell:
        return 'sell';
    }
  }

  String get emoji {
    switch (this) {
      case AdKind.work:
        return '🔨';
      case AdKind.service:
        return '🛠️';
      case AdKind.ad:
        return '📢';
      case AdKind.sell:
        return '🛒';
    }
  }

  String get label {
    switch (this) {
      case AdKind.work:
        return 'Иш бор';
      case AdKind.service:
        return 'Хизмат';
      case AdKind.ad:
        return 'Эълон';
      case AdKind.sell:
        return 'Сотаман';
    }
  }

  /// Шошилинч эълонлар учун кўриниш муддати (кун).
  static const int urgentExpiryDays = 2;

  /// Кўриниш муддати — кунда.
  int get expiresInDays {
    switch (this) {
      case AdKind.work:
        return 3;
      case AdKind.service:
        return 30;
      case AdKind.ad:
        return 14;
      case AdKind.sell:
        return 14;
    }
  }

  /// Фойдаланувчи панелида яратish mumkin bo'lgan turlar (Иш йўқ).
  static const List<AdKind> userPanelKinds = [
    AdKind.ad,
    AdKind.service,
    AdKind.sell,
  ];

  /// Шошилинч белгиси қўйиш мумкин бўлган турлар (эski «Иш» эълонлари учун ham).
  bool get supportsUrgent => this == AdKind.work || this == AdKind.ad;

  /// Янги эълон формасида шошилинч — фақат «Эълон» учун.
  bool get userCanMarkUrgent => this == AdKind.ad;

  static AdKind parse(String? key) {
    switch (key) {
      case 'service':
        return AdKind.service;
      case 'ad':
      case 'announcement':
        return AdKind.ad;
      case 'sell':
        return AdKind.sell;
      case 'work':
        return AdKind.work;
      default:
        return AdKind.work;
    }
  }

  /// `cheap_product` va boshqa turlar doskaga kirmaydi.
  static bool isJobsBoardType(String? type) {
    switch (type) {
      case 'work':
      case 'service':
      case 'ad':
      case 'sell':
        return true;
      default:
        return false;
    }
  }
}

/// `ads` collection — иш / хизмат / эълон (mini-OLX).
///
/// Эски `type` (`work` | `service`) сақланди, янги `ad` тур қўшилди.
class JobAd {
  const JobAd({
    required this.id,
    required this.type,
    required this.text,
    required this.authorName,
    required this.authorPhone,
    required this.address,
    required this.isUrgent,
    required this.status,
    this.title = '',
    this.priceText = '',
    this.expiresAt,
    this.createdAt,
    this.editedAt,
    this.moderatedAt,
    this.adminNote = '',
    this.moderatedBy = '',
  });

  final String id;

  /// `work` | `service` | `ad`.
  final String type;
  final String text;

  /// Қисқа сарлавҳа (ихтиёрий) — янги эълонлар учун.
  final String title;

  /// Нарх кўриниши (ихтиёрий) — "200 000 сўм", "Шартномавий".
  final String priceText;

  final String authorName;
  final String authorPhone;
  final String address;
  final bool isUrgent;

  /// `pending` | `active` | `completed` | `blocked`.
  final String status;
  final DateTime? expiresAt;
  final DateTime? createdAt;
  final DateTime? editedAt;
  final DateTime? moderatedAt;
  final String adminNote;
  final String moderatedBy;

  static bool isJobsBoardType(String? type) => AdKindX.isJobsBoardType(type);

  AdKind get kind => AdKindX.parse(type);

  bool get isWork => kind == AdKind.work;
  bool get isService => kind == AdKind.service;
  bool get isAnnouncement => kind == AdKind.ad;
  bool get isSell => kind == AdKind.sell;

  bool get supportsUrgent => kind.supportsUrgent;

  bool get isExpired {
    final exp = expiresAt;
    if (exp == null) return false;
    return exp.isBefore(DateTime.now());
  }

  String get titleOrText =>
      title.trim().isEmpty ? text : title.trim();

  /// Эълон joylangan sana — `кун/ой/йил`.
  String get postedDateLabel {
    final ts = createdAt;
    if (ts == null) return '';
    final d = ts.day.toString().padLeft(2, '0');
    final m = ts.month.toString().padLeft(2, '0');
    return '$d/$m/${ts.year}';
  }

  /// «Сотаман» рўйхати учун: префикс ва (Бир марта|Доимий) олиб ташланган матн.
  String get displayText {
    if (!isSell) return text;
    var t = text.trim();
    const prefix = '🛒 Сотиш таклифи:';
    if (t.startsWith(prefix)) {
      t = t.substring(prefix.length).trim();
    }
    return t.replaceAll(RegExp(r'\s*\((Бир марта|Доимий)\)'), '');
  }

  /// "5 дақ. олдин" / "2 соат олдин" / "3 кун олдин".
  String get timeAgo {
    final ts = createdAt;
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 1) return 'ҳозиргина';
    if (diff.inMinutes < 60) return '${diff.inMinutes} дақ.';
    if (diff.inHours < 24) return '${diff.inHours} соат';
    return '${diff.inDays} кун';
  }

  /// Admin kartochka: muddat qoldi.
  String get expiresLabel {
    final exp = expiresAt;
    if (exp == null) return 'Муддатсiz';
    if (isExpired) return 'Муддати tugagan';
    final days = exp.difference(DateTime.now()).inDays;
    if (days <= 0) {
      final hours = exp.difference(DateTime.now()).inHours;
      return hours <= 0 ? 'Бугун tugaydi' : '$hours soat qoldi';
    }
    return '$days kun qoldi';
  }

  factory JobAd.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const <String, dynamic>{};
    return JobAd(
      id: doc.id,
      type: (d['type'] ?? 'work') as String,
      text: (d['text'] ?? '') as String,
      title: (d['title'] ?? '') as String,
      priceText: (d['priceText'] ?? '') as String,
      authorName: (d['authorName'] ?? '') as String,
      authorPhone: (d['authorPhone'] ?? '') as String,
      address: (d['address'] ?? '') as String,
      isUrgent: d['isUrgent'] == true,
      status: (d['status'] ?? 'active') as String,
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      editedAt: (d['editedAt'] as Timestamp?)?.toDate(),
      moderatedAt: (d['moderatedAt'] as Timestamp?)?.toDate(),
      adminNote: (d['adminNote'] ?? '') as String,
      moderatedBy: (d['moderatedBy'] ?? '') as String,
    );
  }
}
