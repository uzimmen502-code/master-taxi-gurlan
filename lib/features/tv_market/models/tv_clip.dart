import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

import '../services/tv_social.dart';

/// Юкланадиган клипнинг максимал давомийлиги. Бу — клиент томондаги
/// нусха: ҳақиқий, авторитетли кесиш серверда (`TV_CLIP_MAX_SECONDS`,
/// functions/index.js) ffmpeg `-t` орқали бажарилади. Бу ердагиси фақат
/// фойдаланувчи узун видеони бекорга юклаб, кейин у кесилганини
/// билмаслиги учун. Икки қиймат мос туриши шарт.
const tvClipMaxUploadSeconds = 180;

/// Жойлаштирувчининг профил исми (тўлиқ). @nick / телефон / UI fallback — бўш.
String tvOwnerDisplayName(String raw) {
  final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty || s.startsWith('@')) return '';
  final compact = s.replaceAll(RegExp(r'[\s+\-()]'), '');
  if (RegExp(r'^\d{7,}$').hasMatch(compact)) return '';
  const fake = {
    'фойдаланувчи',
    'foydalanuvchi',
    'пользователь',
    'user',
  };
  if (fake.contains(s.toLowerCase())) return '';
  final first = s.split(' ').first.toLowerCase();
  if (fake.contains(first)) return '';
  return s;
}

/// Қидирув токени учун биринчи сўз.
String tvOwnerGivenName(String raw) {
  final d = tvOwnerDisplayName(raw);
  if (d.isEmpty) return '';
  return d.split(' ').first;
}

/// Bug fix (social-publish audit, 2026-09): ilgari faqat 3 ta t
/// (instagram/facebook/tiktok) tan olinardi — YouTube/Telegram tanlovi
/// Firestore'dan qayta o'qilganda jimgina o'chib qolardi, garchi yozish
/// tomoni (`tv_publish_screen.dart`, server) 5 tasini ham qo'llab-
/// quvvatlasa ham. Endi `TvSocial.ordered` — yagona manba.
List<String> _parseSocialNetworks(dynamic raw) {
  if (raw is! List) return const [];
  final out = <String>[];
  for (final e in raw) {
    final id = '$e'.trim().toLowerCase();
    if (TvSocial.ordered.contains(id) && !out.contains(id)) out.add(id);
  }
  return out;
}

class TvClip {
  const TvClip({
    required this.id,
    required this.videoUrl,
    required this.posterUrl,
    required this.title,
    required this.price,
    required this.districtId,
    required this.districtLabel,
    required this.ownerPhone,
    required this.ownerName,
    required this.category,
    this.ownerPhotoUrl = '',
    this.lat,
    this.lng,
    this.mfy,
    this.description = '',
    this.likeCount = 0,
    this.commentCount = 0,
    this.viewCount = 0,
    this.status = 'active',
    this.createdAt,
    this.shopItemId = '',
    this.socialConsent = false,
    this.socialNetworks = const [],
    this.socialPostedAt,
    this.socialPost = const {},
    this.searchTokens = const [],
    this.videoVariants = const {},
    this.hlsUrl = '',
    this.duration = 0,
    this.processingStatus = 'ready',
    this.expiresAt,
    this.adDurationDays = 0,
    this.adTier = '',
    this.adScope = 'district',
    this.regionId = '',
    this.showPhone = true,
    this.rejectReason = '',
  });

  final String id;
  final String videoUrl;
  final String posterUrl;
  final String title;
  final int price;
  final String districtId;
  final String districtLabel;
  final String ownerPhone;
  final String ownerName;
  final String ownerPhotoUrl;

  /// `product` | `service` | `news` | `ad`
  final String category;

  /// `news` (48 соат) ва `ad` (танланган муддат) учун тугаш вақти.
  /// `product`/`service` — доимий, бу майдон `null`.
  final DateTime? expiresAt;

  /// `category == 'ad'` бўлса — танланган муддат (7|15|30 кун). Бошқаларда 0.
  final int adDurationDays;

  /// `category == 'ad'` бўлса — тариф (`basic|visibility|home|premium|pro_max`).
  final String adTier;

  /// `category == 'ad'` бўлса — қамров: `district` (ўз тумани) | `region`
  /// (вилоят бўйлаб) | `national` (республика бўйлаб). Эски эълонларда
  /// майдон йўқ — default `district` (ҳозирги хатти-ҳаракат).
  final String adScope;

  /// Жойлаштирувчи вилояти (`ServiceConfigHolder.regionId` дан денормал.).
  /// `adScope == 'region'` эълонларини феддда бирлаштириш учун керак.
  final String regionId;

  /// Эгаси телефон рақамини кўрсатишни хоҳлайдими — `false` бўлса
  /// «Боғланиш» тугмаси клип остида умуман кўринмайди. Эски клипларда
  /// майдон йўқ — шунинг учун default `true` (ҳозирги хатти-ҳаракат).
  final bool showPhone;

  final double? lat;
  final double? lng;
  final String? mfy;
  final String description;
  final int likeCount;
  final int commentCount;
  final int viewCount;

  /// `pending` | `active` | `blocked`
  final String status;
  final DateTime? createdAt;

  /// Боғланган витрина товар/хизмати. Бўш = фақат ролик.
  final String shopItemId;
  final bool socialConsent;
  /// `instagram` | `facebook` | `tiktok`
  final List<String> socialNetworks;
  final DateTime? socialPostedAt;
  /// CF жойлаш ҳолати: status posting|posted|partial|error + networks.{ig,fb,tt}.
  final Map<String, dynamic> socialPost;
  final List<String> searchTokens;

  /// Server-tomon transcode natijasi: `{'720p': url, '480p': url, '360p': url}`.
  /// Bo'sh = faqat `videoUrl` (eski klip yoki hali processing tugamagan).
  final Map<String, String> videoVariants;

  /// HLS master playlist (`master.m3u8`) URL'и — сервер уни MP4
  /// вариантларидан пакетлайди. Бўш бўлса клип HLS'сиз: эски клип,
  /// ёки пакетлаш йиқилган. Бундай ҳолда [urlForQuality] MP4'га
  /// қайтади, шунинг учун бўш қиймат ҳеч нарсани бузмайди.
  final String hlsUrl;

  /// Video davomiyligi (soniya). 0 = noma'lum (eski klip).
  final int duration;

  /// `uploading` | `processing` | `ready` | `error`. Eski kliplar uchun
  /// maydon Firestore'da yo'q — shuning uchun default `ready` (allaqachon
  /// playable, transcode pipeline'idan o'tmagan).
  final String processingStatus;

  /// Модерация рад этилганда admin ёзган сабаб. Фақат `status == 'blocked'`
  /// ва category `ad` бўлмаган клипларда маъноли (реклама модерациядан
  /// умуман ўтмайди — 🔴1/3 қарори).
  final String rejectReason;

  bool get isActive => status == 'active';
  bool get isExpired => status == 'expired';
  bool get isBlocked => status == 'blocked';
  bool get hasPrice => price > 0;
  bool get hasShopItem => shopItemId.trim().isNotEmpty;
  bool get socialPosted => socialPostedAt != null;
  bool get hasVariants => videoVariants.isNotEmpty;
  bool get isNews => category == 'news';
  bool get isAd => category == 'ad';

  /// Transcode йиқилган клип (`processingStatus == 'error'`) — варианти
  /// йўқ, шунинг учун [urlForQuality] кесилмаган, сиқилмаган асл файлга
  /// қайтади. Бундай клип томошабин лентасига чиқарилмайди; эгасининг ўз
  /// рўйхатида ва админ модерациясида эса кўринади.
  bool get isPlayable => processingStatus != 'error';

  static const _adTierWeight = {
    'basic': 0,
    'visibility': 1,
    'home': 2,
    'premium': 3,
    'pro_max': 4,
  };

  /// AVA TV тариф жадвали — «Кўриниш устуворлиги» устуни: тариф қанча
  /// юқори бўлса, feed'да шунча олдинроқ (`tv_clip_shuffle.dart`
  /// `tvApplyAdTierPriority`). Ad бўлмаса — 0.
  int get adBoostWeight => isAd ? (_adTierWeight[adTier] ?? 0) : 0;

  /// Тариф жадвали «Реклама жойлашуви» устуни: `home`/`premium`/`pro_max`
  /// Home экранида ҳам кўринади; `basic`/`visibility` — фақат AVAGram /
  /// Реклама лентасида. Ad бўлмаган клипларга тегишли эмас (ҳар доим true).
  bool get showsOnHome =>
      !isAd || const {'home', 'premium', 'pro_max'}.contains(adTier);

  /// Ижро учун URL. Тартиб: HLS → сўралган MP4 варианти → асл файл.
  ///
  /// HLS бор бўлса [quality] эътиборга олинмайди — сифатни плеернинг
  /// ўзи, ҳақиқий тармоқ тезлигига қараб танлайди (ABR). Бу
  /// [TvNetworkQualityService]нинг «Wi-Fi → 720p» тахминидан аниқроқ.
  ///
  /// Web'да HLS ишлатилмайди: Chrome m3u8'ни нативда ўқимайди
  /// (қаранг: [mp4Url]).
  String urlForQuality(String quality) {
    if (!kIsWeb && hlsUrl.isNotEmpty) return hlsUrl;
    return videoVariants[quality] ?? videoUrl;
  }

  /// Ҳар доим оддий, прогрессив MP4 — ҳеч қачон HLS playlist эмас.
  ///
  /// HLS'ни ўзи қўллаб-қувватламайдиган контекстлар учун: Flutter web
  /// админ панели (Chrome нативда m3u8 ўқимайди) ва ижтимоий тармоқларга
  /// кросс-постинг (`tv_social_publish.js` — Instagram/TikTok/YouTube
  /// playlist эмас, файл кутади). Лента HLS'га ўтганда ҳам бу контекстлар
  /// шу ерда ишлашда давом этади.
  ///
  /// Кичикроқ вариант афзал: модерацияда сифат эмас, очилиш тезлиги муҳим.
  String get mp4Url =>
      videoVariants['480p'] ?? videoVariants['720p'] ?? videoUrl;

  String get socialPostStatus => '${socialPost['status'] ?? ''}'.trim();

  String socialPostSummary() {
    if (socialPosted) return 'Чоп этилган';
    switch (socialPostStatus) {
      case 'posting':
        return 'Жойланмоқда';
      case 'partial':
        return 'Қисман';
      case 'error':
        return 'Хато';
      default:
        if (socialConsent || socialNetworks.isNotEmpty) return 'Навбатда';
        return '—';
    }
  }

  String displayOwnerName(String fallback) {
    final n = tvOwnerDisplayName(ownerName);
    return n.isEmpty ? fallback : n;
  }

  TvClip copyWith({
    int? likeCount,
    int? commentCount,
    int? viewCount,
    String? shopItemId,
    bool? socialConsent,
    List<String>? socialNetworks,
    DateTime? socialPostedAt,
    Map<String, dynamic>? socialPost,
    String? ownerName,
    String? ownerPhotoUrl,
    String? districtId,
    String? districtLabel,
    String? title,
    int? price,
    String? description,
    String? category,
    String? videoUrl,
    String? posterUrl,
    List<String>? searchTokens,
    Map<String, String>? videoVariants,
    String? hlsUrl,
    int? duration,
    String? processingStatus,
    DateTime? expiresAt,
    int? adDurationDays,
    String? adTier,
    String? adScope,
    String? regionId,
    bool? showPhone,
    String? rejectReason,
  }) {
    return TvClip(
      id: id,
      videoUrl: videoUrl ?? this.videoUrl,
      posterUrl: posterUrl ?? this.posterUrl,
      title: title ?? this.title,
      price: price ?? this.price,
      districtId: districtId ?? this.districtId,
      districtLabel: districtLabel ?? this.districtLabel,
      ownerPhone: ownerPhone,
      ownerName: ownerName ?? this.ownerName,
      ownerPhotoUrl: ownerPhotoUrl ?? this.ownerPhotoUrl,
      category: category ?? this.category,
      lat: lat,
      lng: lng,
      mfy: mfy,
      description: description ?? this.description,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      viewCount: viewCount ?? this.viewCount,
      status: status,
      createdAt: createdAt,
      shopItemId: shopItemId ?? this.shopItemId,
      socialConsent: socialConsent ?? this.socialConsent,
      socialNetworks: socialNetworks ?? this.socialNetworks,
      socialPostedAt: socialPostedAt ?? this.socialPostedAt,
      socialPost: socialPost ?? this.socialPost,
      searchTokens: searchTokens ?? this.searchTokens,
      videoVariants: videoVariants ?? this.videoVariants,
      hlsUrl: hlsUrl ?? this.hlsUrl,
      duration: duration ?? this.duration,
      processingStatus: processingStatus ?? this.processingStatus,
      expiresAt: expiresAt ?? this.expiresAt,
      adDurationDays: adDurationDays ?? this.adDurationDays,
      adTier: adTier ?? this.adTier,
      adScope: adScope ?? this.adScope,
      regionId: regionId ?? this.regionId,
      showPhone: showPhone ?? this.showPhone,
      rejectReason: rejectReason ?? this.rejectReason,
    );
  }

  factory TvClip.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data()!;
    return TvClip(
      id: doc.id,
      videoUrl: (d['videoUrl'] ?? '') as String,
      posterUrl: (d['posterUrl'] ?? '') as String,
      title: (d['title'] ?? '') as String,
      price: (d['price'] ?? 0) as int,
      districtId: (d['districtId'] ?? '') as String,
      districtLabel: (d['districtLabel'] ?? '') as String,
      ownerPhone: (d['ownerPhone'] ?? '') as String,
      ownerName: (d['ownerName'] ?? '') as String,
      ownerPhotoUrl: (d['ownerPhotoUrl'] ?? '') as String,
      category: (d['category'] ?? 'product') as String,
      lat: (d['lat'] as num?)?.toDouble(),
      lng: (d['lng'] as num?)?.toDouble(),
      mfy: d['mfy'] as String?,
      description: (d['description'] ?? '') as String,
      likeCount: (d['likeCount'] ?? 0) as int,
      commentCount: (d['commentCount'] ?? 0) as int,
      viewCount: (d['viewCount'] ?? 0) as int,
      status: (d['status'] ?? 'active') as String,
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
      shopItemId: (d['shopItemId'] ?? '') as String,
      socialConsent: d['socialConsent'] == true,
      socialNetworks: _parseSocialNetworks(d['socialNetworks']),
      socialPostedAt: (d['socialPostedAt'] as Timestamp?)?.toDate(),
      socialPost: d['socialPost'] is Map
          ? Map<String, dynamic>.from(d['socialPost'] as Map)
          : const {},
      searchTokens: (d['searchTokens'] is List)
          ? (d['searchTokens'] as List)
              .map((e) => '$e')
              .where((e) => e.isNotEmpty)
              .toList()
          : const [],
      videoVariants: d['videoVariants'] is Map
          ? Map<String, String>.from(
              (d['videoVariants'] as Map).map(
                (k, v) => MapEntry('$k', '$v'),
              ),
            )
          : const {},
      hlsUrl: (d['hlsUrl'] ?? '') as String,
      duration: (d['duration'] ?? 0) as int,
      processingStatus: (d['processingStatus'] ?? 'ready') as String,
      expiresAt: (d['expiresAt'] as Timestamp?)?.toDate(),
      adDurationDays: (d['adDurationDays'] ?? 0) as int,
      adTier: (d['adTier'] ?? '') as String,
      adScope: (d['adScope'] as String?)?.trim().isNotEmpty == true
          ? d['adScope'] as String
          : 'district',
      regionId: (d['regionId'] ?? '') as String,
      showPhone: (d['showPhone'] as bool?) ?? true,
      rejectReason: (d['rejectReason'] ?? '') as String,
    );
  }

  Map<String, dynamic> toMap() => {
        'videoUrl': videoUrl,
        'posterUrl': posterUrl,
        'title': title,
        'price': price,
        'districtId': districtId,
        'districtLabel': districtLabel,
        'ownerPhone': ownerPhone,
        'ownerName': ownerName,
        if (ownerPhotoUrl.isNotEmpty) 'ownerPhotoUrl': ownerPhotoUrl,
        'category': category,
        if (lat != null) 'lat': lat,
        if (lng != null) 'lng': lng,
        if (mfy != null) 'mfy': mfy,
        'description': description,
        'likeCount': likeCount,
        'commentCount': commentCount,
        'viewCount': viewCount,
        'status': status,
        'createdAt': createdAt != null
            ? Timestamp.fromDate(createdAt!)
            : FieldValue.serverTimestamp(),
        if (shopItemId.isNotEmpty) 'shopItemId': shopItemId,
        'socialConsent': socialConsent,
        if (socialNetworks.isNotEmpty) 'socialNetworks': socialNetworks,
        if (socialPostedAt != null)
          'socialPostedAt': Timestamp.fromDate(socialPostedAt!),
        if (socialPost.isNotEmpty) 'socialPost': socialPost,
        if (searchTokens.isNotEmpty) 'searchTokens': searchTokens,
        if (videoVariants.isNotEmpty) 'videoVariants': videoVariants,
        if (hlsUrl.isNotEmpty) 'hlsUrl': hlsUrl,
        if (duration > 0) 'duration': duration,
        'processingStatus': processingStatus,
        if (expiresAt != null) 'expiresAt': Timestamp.fromDate(expiresAt!),
        if (adDurationDays > 0) 'adDurationDays': adDurationDays,
        if (adTier.isNotEmpty) 'adTier': adTier,
        if (isAd) 'adScope': adScope,
        if (regionId.isNotEmpty) 'regionId': regionId,
        'showPhone': showPhone,
        if (rejectReason.isNotEmpty) 'rejectReason': rejectReason,
      };
}
