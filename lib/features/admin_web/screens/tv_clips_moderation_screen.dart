import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/services/tv_social.dart';
import '../services/admin_auth_service.dart';
import '../widgets/tv_social_settings_bar.dart';

/// Админ панел — TV Market клиплар модерацияси.
class TvClipsModerationScreen extends StatefulWidget {
  const TvClipsModerationScreen({super.key});

  @override
  State<TvClipsModerationScreen> createState() =>
      _TvClipsModerationScreenState();
}

class _TvClipsModerationScreenState extends State<TvClipsModerationScreen> {
  String _statusFilter = 'all';
  String _query = '';
  final _searchCtrl = TextEditingController();
  List<TvClip> _clips = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('tv_clips')
          .orderBy('createdAt', descending: true)
          .limit(500)
          .get();
      if (!mounted) return;
      setState(() {
        _clips = snap.docs.map(TvClip.fromFirestore).toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _setStatus(TvClip clip, String status) async {
    try {
      await FirebaseFirestore.instance
          .collection('tv_clips')
          .doc(clip.id)
          .update({'status': status});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: status == 'active' ? Colors.green : Colors.orange,
          content: Text(
            status == 'active'
                ? 'Фаоллаштирилди: ${clip.title}'
                : status == 'blocked'
                    ? 'Блокланди: ${clip.title}'
                    : 'Ҳолат ўзгарди: ${clip.title}',
          ),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Xatolik: $e')),
      );
    }
  }

  Future<void> _delete(TvClip clip) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Клипни ўчириш'),
        content: Text('«${clip.title}» бутунлай ўчирилади.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бекор'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Ўчириш', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await FirebaseFirestore.instance
          .collection('tv_clips')
          .doc(clip.id)
          .delete();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Клип ўчирилди')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Xatolik: $e')),
      );
    }
  }

  List<TvClip> _filtered() {
    final q = _query.trim().toLowerCase();
    return _clips.where((c) {
      if (_statusFilter != 'all' && c.status != _statusFilter) return false;
      if (q.isEmpty) return true;
      return c.title.toLowerCase().contains(q) ||
          c.ownerName.toLowerCase().contains(q) ||
          c.ownerPhone.contains(q) ||
          c.description.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filtered();
    return Column(
      children: [
        _header(),
        const _TvAutoApproveBar(),
        const TvSocialSettingsBar(),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Xatolik: $_error'),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _load,
                            child: const Text('Qayta urinish'),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: Column(
                        children: [
                          _summary(),
                          _filters(),
                          Expanded(
                            child: filtered.isEmpty
                                ? ListView(children: const [
                                    SizedBox(height: 120),
                                    Center(child: Text('Клип топилмади')),
                                  ])
                                : _ClipsTable(
                                    clips: filtered,
                                    onActivate: (c) =>
                                        _setStatus(c, 'active'),
                                    onBlock: (c) =>
                                        _setStatus(c, 'blocked'),
                                    onPending: (c) =>
                                        _setStatus(c, 'pending'),
                                    onDelete: _delete,
                                    onDetail: _showDetail,
                                  ),
                          ),
                        ],
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 14),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: Colors.deepPurple.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.play_circle_outline,
                color: Colors.deepPurple),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'TV Market — модерация',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
                SizedBox(height: 3),
                Text(
                  'Видео клипларни кўриш, фаоллаштириш ва AVA расмий саҳифаларига жойлаш',
                  style: TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Янгилаш',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _summary() {
    int count(String s) => _clips.where((c) => c.status == s).length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          _card('Жами', _clips.length, Colors.blueGrey),
          _card('Кутилмоқда', count('pending'), Colors.deepOrange),
          _card('Фаол', count('active'), Colors.green),
          _card('Блокланган', count('blocked'), Colors.red),
        ],
      ),
    );
  }

  Widget _card(String label, int value, Color color) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: color.withValues(alpha: 0.1),
            child: Text('$value',
                style:
                    TextStyle(color: color, fontWeight: FontWeight.bold)),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _filters() {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 4, 18, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(children: [
        TextField(
          controller: _searchCtrl,
          onChanged: (v) => setState(() => _query = v),
          decoration: InputDecoration(
            hintText: 'Сарлавҳа, эгаси, телефон бўйича қидириш...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _query.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      _searchCtrl.clear();
                      setState(() => _query = '');
                    },
                  ),
            border:
                OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            isDense: true,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 8, children: [
          for (final item in [
            ('all', 'Барчаси'),
            ('pending', 'Кутилмоқда'),
            ('active', 'Фаол'),
            ('blocked', 'Блокланган'),
          ])
            ChoiceChip(
              label: Text(item.$2),
              selected: _statusFilter == item.$1,
              onSelected: (_) =>
                  setState(() => _statusFilter = item.$1),
            ),
        ]),
      ]),
    );
  }

  Future<void> _publishSocial(TvClip clip) async {
    try {
      final fn = FirebaseFunctions.instance.httpsCallable(
        'adminPublishTvClipSocial',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 9)),
      );
      await fn.call({'clipId': clip.id});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.blue.shade700,
          content: Text('Соцсетга жойланди: ${clip.title}'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Xatolik: $e')),
      );
    }
  }

  Future<void> _boostShopItem(TvClip clip) async {
    if (clip.shopItemId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Бу роликка товар боғланмаган — реклама қўйилмайди'),
        ),
      );
      return;
    }
    try {
      final until = DateTime.now().add(const Duration(days: 7));
      await FirebaseFirestore.instance
          .collection('tv_shop_items')
          .doc(clip.shopItemId)
          .update({'boostUntil': Timestamp.fromDate(until)});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.deepOrange,
          content: Text('Реклама 7 кун: ${clip.title}'),
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Xatolik: $e')),
      );
    }
  }

  Future<void> _showDetail(TvClip clip) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _TvClipDetailDialog(
        clip: clip,
        onActivate: () {
          Navigator.pop(ctx);
          _setStatus(clip, 'active');
        },
        onBlock: () {
          Navigator.pop(ctx);
          _setStatus(clip, 'blocked');
        },
        onDelete: () {
          Navigator.pop(ctx);
          _delete(clip);
        },
        onSocialPosted: () {
          Navigator.pop(ctx);
          _publishSocial(clip);
        },
        onBoost: () {
          Navigator.pop(ctx);
          _boostShopItem(clip);
        },
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Table
// ---------------------------------------------------------------------------

String _statusLabel(String s) {
  switch (s) {
    case 'pending':
      return 'Кутилмоқда';
    case 'active':
      return 'Фаол';
    case 'blocked':
      return 'Блокланган';
    default:
      return s;
  }
}

Color _statusColor(String s) {
  switch (s) {
    case 'pending':
      return Colors.deepOrange;
    case 'active':
      return Colors.green;
    case 'blocked':
      return Colors.red;
    default:
      return Colors.blueGrey;
  }
}

Widget _statusChip(String status) {
  final c = _statusColor(status);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: c.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      _statusLabel(status),
      style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600),
    ),
  );
}

String _fmtDate(DateTime? d) {
  if (d == null) return '—';
  String two(int x) => x.toString().padLeft(2, '0');
  return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

class _ClipsTable extends StatelessWidget {
  const _ClipsTable({
    required this.clips,
    required this.onActivate,
    required this.onBlock,
    required this.onPending,
    required this.onDelete,
    required this.onDetail,
  });

  final List<TvClip> clips;
  final ValueChanged<TvClip> onActivate;
  final ValueChanged<TvClip> onBlock;
  final ValueChanged<TvClip> onPending;
  final ValueChanged<TvClip> onDelete;
  final ValueChanged<TvClip> onDetail;

  static const _headerBg = Color(0xFFF3E5F5);
  static const _border = Color(0xFFE0E0E0);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _border),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: LayoutBuilder(builder: (context, constraints) {
            return SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: constraints.maxWidth < 900
                        ? 900
                        : constraints.maxWidth,
                  ),
                  child: Table(
                    columnWidths: const {
                      0: FlexColumnWidth(2),
                      1: FixedColumnWidth(120),
                      2: FixedColumnWidth(100),
                      3: FlexColumnWidth(1.4),
                      4: FixedColumnWidth(80),
                      5: FixedColumnWidth(90),
                      6: FixedColumnWidth(90),
                      7: FixedColumnWidth(160),
                    },
                    defaultVerticalAlignment:
                        TableCellVerticalAlignment.middle,
                    border: TableBorder(
                      horizontalInside:
                          BorderSide(color: _border.withValues(alpha: 0.7)),
                      verticalInside: const BorderSide(color: _border),
                    ),
                    children: [
                      TableRow(
                        decoration: const BoxDecoration(color: _headerBg),
                        children: _headers(),
                      ),
                      for (final c in clips) _row(c),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  List<Widget> _headers() {
    const s = TextStyle(fontWeight: FontWeight.w800, fontSize: 12);
    Widget h(String t, {TextAlign a = TextAlign.left}) => Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
          child: Text(t, style: s, textAlign: a),
        );
    return [
      h('Сарлавҳа'),
      h('Нарх', a: TextAlign.right),
      h('Ҳолат'),
      h('Эгаси'),
      h('Тури'),
      h('Кўришлар'),
      h('Сана'),
      h('Амал', a: TextAlign.center),
    ];
  }

  TableRow _row(TvClip c) {
    return TableRow(children: [
      InkWell(
        onTap: () => onDetail(c),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 13)),
              if (c.description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(c.description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 11, color: Colors.grey.shade600)),
              ],
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Text(c.hasPrice ? formatMoney(c.price) : '—',
            textAlign: TextAlign.right,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.primary)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Align(
            alignment: Alignment.centerLeft, child: _statusChip(c.status)),
      ),
      InkWell(
        onTap: () => onDetail(c),
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c.ownerName.isEmpty ? '—' : c.ownerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600)),
              Text(c.ownerPhone,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      TextStyle(fontSize: 11, color: Colors.grey.shade600)),
            ],
          ),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(
          c.category == 'service' ? 'Хизмат' : 'Маҳсулот',
          style: const TextStyle(fontSize: 12),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text('${c.viewCount}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 12)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Text(_fmtDate(c.createdAt),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700)),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (c.status != 'active')
              IconButton(
                tooltip: 'Фаоллаштириш',
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                onPressed: () => onActivate(c),
                icon: const Icon(Icons.check_circle_outline,
                    color: Colors.green),
              ),
            if (c.status == 'active')
              IconButton(
                tooltip: 'Блоклаш',
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                onPressed: () => onBlock(c),
                icon: const Icon(Icons.block, color: Colors.orange),
              ),
            IconButton(
              tooltip: 'Ўчириш',
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              onPressed: () => onDelete(c),
              icon: const Icon(Icons.delete_outline, color: Colors.red),
            ),
          ],
        ),
      ),
    ]);
  }
}

// ---------------------------------------------------------------------------
// Detail dialog
// ---------------------------------------------------------------------------

class _TvClipDetailDialog extends StatelessWidget {
  const _TvClipDetailDialog({
    required this.clip,
    required this.onActivate,
    required this.onBlock,
    required this.onDelete,
    required this.onSocialPosted,
    required this.onBoost,
  });

  final TvClip clip;
  final VoidCallback onActivate;
  final VoidCallback onBlock;
  final VoidCallback onDelete;
  final VoidCallback onSocialPosted;
  final VoidCallback onBoost;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 640),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(children: [
                Expanded(
                  child: Text(clip.title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ]),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView(padding: const EdgeInsets.all(16), children: [
                _row('Нарх', clip.hasPrice ? formatMoney(clip.price) : '—'),
                _row('Ҳолат', _statusLabel(clip.status)),
                _row('Тури',
                    clip.category == 'service' ? 'Хизмат' : 'Маҳсулот'),
                _row('Эгаси', '${clip.ownerName} · ${clip.ownerPhone}'),
                _row('Худуд', clip.districtLabel),
                _row('Кўришлар', '${clip.viewCount}'),
                _row('Лайклар', '${clip.likeCount}'),
                _row('Соцсет розилиги', clip.socialConsent
                    ? (clip.socialNetworks.isEmpty
                        ? 'Ҳа'
                        : clip.socialNetworks.join(', '))
                    : 'Йўқ'),
                _row('Соцсетда', _socialLine(clip)),
                if ('${clip.socialPost['error'] ?? ''}'.trim().isNotEmpty)
                  _row('Соцсет хато', '${clip.socialPost['error']}'),
                _row('Товар', clip.hasShopItem ? clip.shopItemId : '—'),
                _row('Изоҳлар', '${clip.commentCount}'),
                _row('Сана', _fmtDate(clip.createdAt)),
                if (clip.description.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('Тавсиф',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(clip.description,
                      style: const TextStyle(height: 1.35)),
                ],
                if (clip.videoUrl.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  const Text('Видео URL',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  SelectableText(
                    clip.videoUrl,
                    style: TextStyle(
                        fontSize: 12, color: Colors.blue.shade700),
                  ),
                ],
              ]),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
              child: Wrap(spacing: 8, runSpacing: 8, children: [
                if (clip.status != 'active')
                  FilledButton.icon(
                    onPressed: onActivate,
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: const Text('Фаоллаштириш'),
                  ),
                if (clip.status != 'blocked')
                  OutlinedButton.icon(
                    onPressed: onBlock,
                    icon: const Icon(Icons.block, size: 18),
                    label: const Text('Блоклаш'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.orange),
                  ),
                OutlinedButton.icon(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Ўчириш'),
                  style:
                      OutlinedButton.styleFrom(foregroundColor: Colors.red),
                ),
                if ((clip.socialConsent || clip.socialNetworks.isNotEmpty) &&
                    !clip.socialPosted)
                  FilledButton.icon(
                    onPressed: clip.status == 'active' &&
                            clip.socialPostStatus != 'posting'
                        ? onSocialPosted
                        : null,
                    icon: const Icon(Icons.public, size: 18),
                    label: Text(
                      clip.socialPostStatus == 'posting'
                          ? 'Жойланмоқда…'
                          : (clip.socialPostStatus == 'error' ||
                                  clip.socialPostStatus == 'partial'
                              ? 'Қайта жойлаш'
                              : 'Соцсетга жойлаш'),
                    ),
                  ),
                if (clip.hasShopItem)
                  OutlinedButton.icon(
                    onPressed: onBoost,
                    icon: const Icon(Icons.campaign_outlined, size: 18),
                    label: const Text('Реклама 7 кун'),
                  ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  String _socialLine(TvClip clip) {
    final nets = clip.socialPost['networks'];
    if (nets is! Map) return clip.socialPostSummary();
    final parts = <String>[];
    for (final id in TvSocial.ordered) {
      final row = nets[id];
      if (row is Map && '${row['status'] ?? ''}'.isNotEmpty) {
        parts.add('$id: ${row['status']}');
      }
    }
    if (parts.isEmpty) return clip.socialPostSummary();
    return '${clip.socialPostSummary()} (${parts.join(', ')})';
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        SizedBox(
          width: 120,
          child: Text(label,
              style: TextStyle(
                  color: Colors.grey.shade600,
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w500)),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------------------
// Auto/Manual toggle bar
// ---------------------------------------------------------------------------

class _TvAutoApproveBar extends StatefulWidget {
  const _TvAutoApproveBar();

  @override
  State<_TvAutoApproveBar> createState() => _TvAutoApproveBarState();
}

class _TvAutoApproveBarState extends State<_TvAutoApproveBar> {
  bool _busy = false;

  Future<void> _setAuto(bool enabled) async {
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .set({'tvAutoApprove': enabled}, SetOptions(merge: true));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('settings')
          .doc('app')
          .snapshots(),
      builder: (context, snap) {
        final auto = snap.data?.data()?['tvAutoApprove'] == true;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(18, 10, 18, 0),
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: auto ? Colors.green.shade50 : Colors.orange.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color:
                  auto ? Colors.green.shade200 : Colors.orange.shade200,
            ),
          ),
          child: Row(children: [
            Icon(
              auto ? Icons.flash_on : Icons.admin_panel_settings,
              color:
                  auto ? Colors.green.shade700 : Colors.orange.shade800,
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                auto
                    ? 'АВТО — янги видеолар дарҳол фийдда; соцсет чипи бўлса AVA расмий саҳифасига тизим ўзи жойлайди'
                    : 'ҚЎЛДА — тасдиқдан кейин фийдда чиқади; танланган Instagram / Facebook / TikTok’га ҳам тизим жойлайди',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: auto
                      ? Colors.green.shade900
                      : Colors.orange.shade900,
                ),
              ),
            ),
            if (_busy)
              const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else ...[
              OutlinedButton(
                onPressed: auto ? () => _setAuto(false) : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.orange.shade800,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                ),
                child:
                    const Text('ҚЎЛДА', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: auto ? null : () => _setAuto(true),
                icon: const Icon(Icons.flash_on, size: 16),
                label:
                    const Text('АВТО', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.button,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  minimumSize: const Size(0, 36),
                ),
              ),
            ],
          ]),
        );
      },
    );
  }
}
