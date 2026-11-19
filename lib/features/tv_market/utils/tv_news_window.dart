import '../models/tv_clip.dart';
import 'tv_clip_shuffle.dart';

/// «Кун янгиликлари» 24 соатлик ойнаси (эга қарори 2026-11-19).
///
/// AVAGram таблари: 0 «AVAGram», 1 «Кун янгиликлари», 2 «Реклама ва Эълонлар».
///   * Янгилик (`news`) 24 соат яшайди (сервер `expireTvContent`).
///   * Товар/хизмат клиплари (ресторан, таом, кўчмас мулк ва ҳ.к. боғланганлари ҳам — улар
///     `product`/`service`) фаоллашгандан кейинги 24 соат ФАҚАТ «Кун янгиликлари»да, кейин
///     фақат AVAGram'да. Пуллик реклама (`ad`) бу қоидага кирмайди.
///   * «Реклама ва Эълонлар» (пуллик режим) — янги органик товар/хизмат у ерда ҳам 24 соат йўқ
///     (эга 2026-11-19, 2-жавоб); 24 соатдан кейин аввалгидек.
///   * «Кун янгиликлари» ўқилмаганлик нуқтаси (қизил) янги товар/хизматда ҳам ёнади.
///   * Ҳисоб сервер ёзадиган `activatedAt`дан (модерация/авто-тасдиқ). У йўқ эски ҳужжат —
///     «эски»: AVAGram'да қолади (янгиликлар сўрови `activatedAt` бўйича, `createdAt`га
///     қайтиш клипни иккала табдан ҳам йўқотарди).
///
/// Сервер жуфти: `functions/tv_news_window.js` (CDN ҳовузлари ҳам шу қоида билан қурилади).
const Duration kTvNewsWindow = Duration(hours: 24);

/// «Янги» бўлиши мумкин бўлган категориялар (news ва ad эмас).
const List<String> kTvFreshCategories = ['product', 'service'];

const int kTvTabAll = 0;
const int kTvTabNews = 1;
const int kTvTabMarket = 2;

/// Лентада «чиққан вақт»: фаоллашув, бўлмаса яратилиш.
DateTime? tvClipShownAt(TvClip c) => c.activatedAt ?? c.createdAt;

/// Фаоллашгандан кейинги 24 соат ичидаги товар/хизмат клипи. Чегара: роппа-роса 24:00 — эски.
bool tvClipIsFreshNonNews(TvClip c, DateTime now) {
  if (!c.isActive || !kTvFreshCategories.contains(c.category)) return false;
  final at = c.activatedAt;
  if (at == null) return false;
  return now.difference(at) < kTvNewsWindow;
}

/// Клип шу табга тушадими.
bool tvClipInFeedTab(TvClip c, int tab, DateTime now) {
  switch (tab) {
    case kTvTabNews:
      return c.isNews || tvClipIsFreshNonNews(c, now);
    case kTvTabMarket:
      // Эга 2026-11-19 (2-жавоб): бу таб — ПУЛЛИК режим; янги органик товар/хизмат 24 соат
      // бу ерда ҳам йўқ. 24 соатдан кейинги ҳолат ўзгармаган.
      return c.category == 'ad' ||
          ((c.category == 'product' || c.category == 'service') && !tvClipIsFreshNonNews(c, now));
    default:
      return !tvClipIsFreshNonNews(c, now);
  }
}

/// Рўйхатни шу таб қоидасига кўра сузади (тартиб сақланади).
List<TvClip> tvFilterForFeedTab(Iterable<TvClip> clips, int tab, DateTime now) =>
    [for (final c in clips) if (tvClipInFeedTab(c, tab, now)) c];

/// «Кун янгиликлари» биринчи саҳифаси: янгиликлар + янги товар/хизмат, такрорсиз, эскирганлар
/// тушади; аралаштириш ва тариф устуворлиги аввалгидек (`tvShuffleClips` → `tvApplyAdTierPriority`).
List<TvClip> tvMergeNewsTab(List<TvClip> base, List<TvClip> fresh, DateTime now) {
  final byId = <String, TvClip>{};
  for (final c in [...base, ...fresh]) {
    if (tvClipInFeedTab(c, kTvTabNews, now)) byId.putIfAbsent(c.id, () => c);
  }
  return tvApplyAdTierPriority(tvShuffleClips(byId.values.toList()));
}
