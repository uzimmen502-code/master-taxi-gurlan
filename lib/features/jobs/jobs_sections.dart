import '../../models/job_ad.dart';

/// `jobs` модули — иккита АЛОҲИДА бўлим: «Эълонлар» ва «Хизматлар».
///
/// Эга қарори (2026-10-06): аввал битта «ЭЪЛОН ва ХИЗМАТ» плиткаси ва
/// экран ичида 2 таб эди. Энди бош саҳифадаги «Хизматлар — танланг»
/// қаторида иккита плитка, ҳар бири ўз бўлимини табсиз очади ва ўз
/// рангига эга. Маълумот ўша-ўша: `ads` коллекцияси, `type` майдони
/// (`ad` | `service`); модерация ва сервер ўзгармаган. Админ панелда
/// иккаласи олдингидай битта `jobs` калити билан ёқилади.
///
/// Бу файл — бўлим ↔ тур ↔ плитка ↔ матн калити мослигининг ЯГОНА манбаи.
abstract final class JobsSections {
  /// Админ дарвозаси (кўриниш/очилиш) — иккала бўлим учун битта.
  static const String gateId = 'jobs';

  /// Плитка ранги/расми калити (`olxTintFor`, `serviceImageFor`).
  static const String adsTileId = 'jobs';
  static const String servicesTileId = 'jobs_services';

  /// Бўлимлар — экранда кўрсатиладиган турлар.
  ///
  /// Эски «Иш бор» (`work`) тури янги эълонда танланмайди (2026-07 дан)
  /// ва 3 кунда муддати тугайди — шунинг учун алоҳида бўлими йўқ.
  static const List<AdKind> kinds = [AdKind.ad, AdKind.service];

  /// Экран учун тур: `work` (эски) — «Эълонлар» бўлимига тушади.
  static AdKind sectionOf(AdKind kind) =>
      kind == AdKind.service ? AdKind.service : AdKind.ad;

  static String tileIdFor(AdKind kind) =>
      sectionOf(kind) == AdKind.service ? servicesTileId : adsTileId;

  /// Плитка ва экран сарлавҳаси.
  static String titleKeyFor(AdKind kind) =>
      sectionOf(kind) == AdKind.service
          ? 'home_module_jobs_services'
          : 'home_module_jobs_ads';

  /// AppBar'даги «қўшиш» тугмаси.
  static String addKeyFor(AdKind kind) =>
      sectionOf(kind) == AdKind.service ? 'jobs_add_service' : 'jobs_add_ad';

  /// Турнинг фойдаланувчи тилидаги номи (`AdKindX.label` — қотирилган кирилл,
  /// фақат админ учун).
  static String kindLabelKey(AdKind kind) {
    switch (kind) {
      case AdKind.service:
        return 'jobs_kind_service';
      case AdKind.work:
        return 'jobs_kind_work';
      case AdKind.ad:
        return 'jobs_kind_ad';
    }
  }

  /// Варақанинг юбориш тугмаси ёрлиғи ("ХИЗМАТ ҚЎШИШ" / "ЭЪЛОН ҚЎШИШ").
  static String submitKeyFor(AdKind kind) =>
      kind == AdKind.service ? 'jobs_submit_service' : 'jobs_submit_ad';

  /// Юборилгандан кейинги хабар: `жойланди` (active) ёки `текширувга юборилди`.
  static String postedKeyFor(AdKind kind, {required bool live}) {
    final service = kind == AdKind.service;
    if (live) return service ? 'jobs_posted_service' : 'jobs_posted_ad';
    return service ? 'jobs_review_service' : 'jobs_review_ad';
  }

  /// Эълон ҳолати ёрлиғи (Менинг эълонларим). Муддати ўтган — алоҳида.
  static String statusKeyFor(String status, {required bool expired}) {
    if (status == 'active' && expired) return 'jobs_status_expired';
    switch (status) {
      case 'pending':
        return 'jobs_status_pending';
      case 'completed':
        return 'jobs_status_completed';
      case 'blocked':
        return 'jobs_status_blocked';
      default:
        return 'jobs_status_active';
    }
  }
}
