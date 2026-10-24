import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/load_error_view.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/formatters.dart';
import '../../../models/news_item.dart';
import '../../../models/news_read_state.dart';
import '../widgets/news_delete_button.dart';
import '../../../repositories/news_repository.dart';
import '../../../services/user_audience.dart';

/// Умумий админ янгиликлари (буюртма хабарларисиз).
class GeneralNewsTab extends StatefulWidget {
  const GeneralNewsTab({super.key, this.readState = NewsReadState.unknown});

  /// Экранга кирилгандаги ўқилганлик ҳолати — «янги» карталарни ажратади.
  final NewsReadState readState;

  @override
  State<GeneralNewsTab> createState() => _GeneralNewsTabState();
}

class _GeneralNewsTabState extends State<GeneralNewsTab>
    with AutomaticKeepAliveClientMixin {
  static const _green = AppColors.primaryText;

  // Оқим БИР марта очилади (қаранг: OrderNewsTab) — қайта чизилганда
  // рўйхат spinner билан «милтилламасин».
  Stream<List<NewsItem>>? _stream;
  String _uid = '';
  String _role = 'all';
  Set<String> _hidden = <String>{};
  StreamSubscription<Set<String>>? _dismissedSub;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final prefs = await SharedPreferences.getInstance();
    final role = UserAudience.fromPrefs(prefs);
    final uid = phoneDigits(prefs.getString('user_phone') ?? '');
    if (!mounted) return;
    final repo = context.read<NewsRepository>();
    final stream =
        repo.watchBroadcastNews(audiences: ['all', role], userId: uid, limit: 50);
    // Ўчирилган хабарлар сервердан (барча қурилмада бир хил); янги ўчириш дарров, тўплам фақат ўсади.
    _dismissedSub = repo.watchDismissedIds(canonicalPhoneId(uid)).listen((ids) {
      if (mounted) setState(() => _hidden = {..._hidden, ...ids});
    });
    setState(() {
      _uid = uid;
      _role = role;
      _stream = stream;
    });
  }

  /// Хато бўлса — фақат янгиликлар оқимини қайта очади.
  void _retry() {
    final repo = context.read<NewsRepository>();
    setState(() {
      _stream = repo.watchBroadcastNews(
          audiences: ['all', _role], userId: _uid, limit: 50);
    });
  }

  @override
  void dispose() {
    _dismissedSub?.cancel();
    super.dispose();
  }

  Future<void> _delete(NewsItem n) async {
    setState(() => _hidden = {..._hidden, n.id});
    await context.read<NewsRepository>().dismissNews(canonicalPhoneId(_uid), [n.id]);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final stream = _stream;
    if (stream == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return StreamBuilder<List<NewsItem>>(
      stream: stream,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError && !snap.hasData) {
          return LoadErrorView(error: snap.error!, onRetry: _retry);
        }
        final items = (snap.data ?? const <NewsItem>[])
            .where((n) => !_hidden.contains(n.id))
            .toList();
        if (items.isEmpty) return _emptyState();
        final sorted = [...items]..sort((a, b) {
            if (a.priority != b.priority) {
              return b.priority.compareTo(a.priority);
            }
            return b.createdAt.compareTo(a.createdAt);
          });
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: sorted.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _newsCard(sorted[i]),
        );
      },
    );
  }

  Widget _emptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.campaign_outlined, color: Colors.grey.shade400, size: 48),
          const SizedBox(height: 12),
          Text(context.tr('news_general_empty'),
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700)),
        ],
      ),
    );
  }

  Widget _newsCard(NewsItem n) {
    final accent = _accentFor(n.category);
    final unread = widget.readState.isUnread(n.createdAt);
    return Container(
      key: ValueKey('general-news-${n.id}'),
      padding: const EdgeInsets.all(14),
      // Ўқилмаган — жирний (қалин) ёзув, ўқилган — оддий ёзув (эга, 2026-10-19).
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(_labelFor(n.category),
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: accent)),
            ),
            const Spacer(),
            Text(_ago(n.createdAt),
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
            NewsDeleteButton(onDelete: () => _delete(n)),
          ]),
          const SizedBox(height: 6),
          Text(n.title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: unread ? FontWeight.bold : FontWeight.normal,
                  height: 1.3)),
          const SizedBox(height: 6),
          Text(n.body,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  fontWeight: unread ? FontWeight.bold : FontWeight.normal)),
          if (n.ctaLabel.isNotEmpty && n.ctaUrl.isNotEmpty) ...[
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: () => _openUrl(n.ctaUrl),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: Text(n.ctaLabel),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Color _accentFor(String cat) {
    switch (cat) {
      case 'emergency':
        return Colors.red.shade700;
      case 'warning':
        return Colors.orange.shade700;
      case 'promo':
        return Colors.purple.shade700;
      case 'update':
        return Colors.blue.shade700;
      default:
        return _green;
    }
  }

  String _labelFor(String cat) {
    switch (cat) {
      case 'emergency':
        return context.tr('news_cat_urgent');
      case 'warning':
        return context.tr('news_cat_warning');
      case 'promo':
        return context.tr('news_cat_promo');
      case 'update':
        return context.tr('news_cat_update');
      default:
        return context.tr('restaurants_info');
    }
  }

  String _ago(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return context.tr('addr_time_just_now');
    if (diff.inMinutes < 60) {
      return context.trMsg('news_ago_min', params: {'n': '${diff.inMinutes}'});
    }
    if (diff.inHours < 24) {
      return context.trMsg('news_ago_hour', params: {'n': '${diff.inHours}'});
    }
    return '${t.day}.${t.month.toString().padLeft(2, '0')}.${t.year}';
  }
}
