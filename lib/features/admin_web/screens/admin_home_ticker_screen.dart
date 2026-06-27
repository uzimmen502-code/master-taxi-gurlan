import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../models/home_ticker_ad.dart';
import '../../../models/home_ticker_animation_style.dart';
import '../../../repositories/home_ticker_repository.dart';
import '../../../services/admin_service.dart';
import '../../../core/theme/app_theme.dart';

/// Admin — bosh ekran begushchaya qator (`home_ticker_ads`).
class AdminHomeTickerScreen extends StatefulWidget {
  const AdminHomeTickerScreen({super.key});

  @override
  State<AdminHomeTickerScreen> createState() => _AdminHomeTickerScreenState();
}

class _AdminHomeTickerScreenState extends State<AdminHomeTickerScreen> {
  static const _blue = AppColors.primary;

  bool _adminChecked = false;
  bool _isAdmin = false;
  String _query = '';

  static const _audiences = [
    ('all', 'Барча'),
    ('user', 'Фойдаланувчилар'),
    ('driver', 'Ҳайдовчилар'),
    ('courier', 'Курьерлар'),
    ('admin', 'Админлар'),
  ];

  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  Future<void> _checkAdmin() async {
    var ok = false;
    try {
      ok = await context.read<AdminService>().isCurrentUserAdmin();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    setState(() {
      _isAdmin = ok;
      _adminChecked = true;
    });
  }

  String _audienceLabel(String code) {
    for (final a in _audiences) {
      if (a.$1 == code) return a.$2;
    }
    return code;
  }

  Future<void> _openBulkAnimation() async {
    String value = HomeTickerAnimationStyle.auto;
    final repo = context.read<HomeTickerRepository>();
    final applied = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Барча матнлар анимацияси'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Бош экран маълумот майдони (home_search) барча '
                'матнлари учун анимация услуби:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: value,
                isExpanded: true,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: [
                  for (final s in HomeTickerAnimationStyle.all)
                    DropdownMenuItem(
                      value: s,
                      child: Text(
                        HomeTickerAnimationStyle.label(s),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) =>
                    setLocal(() => value = v ?? HomeTickerAnimationStyle.auto),
              ),
              const SizedBox(height: 8),
              Text(
                HomeTickerAnimationStyle.description(value),
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Бекор'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ҳаммасига қўллаш'),
            ),
          ],
        ),
      ),
    );

    if (applied != true || !mounted) return;
    try {
      final count =
          await repo.setAnimationStyleForModule('home_search', value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.button,
          content: Text(
              '✅ $count та матн "${HomeTickerAnimationStyle.label(value)}" услубига ўрнатилди'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Хатолик: $e')),
      );
    }
  }

  Future<void> _openBulkDuration() async {
    int value = 4;
    final repo = context.read<HomeTickerRepository>();
    final applied = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Барча матнлар давомийлиги'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Бош экран маълумот майдони (home_search) барча '
                'матнлари учун кўрсатилиш вақти (сония):',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: value > 3
                        ? () => setLocal(() => value--)
                        : null,
                  ),
                  Container(
                    width: 56,
                    alignment: Alignment.center,
                    child: Text(
                      '$value',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline),
                    onPressed: value < 12
                        ? () => setLocal(() => value++)
                        : null,
                  ),
                ],
              ),
              const Text('(3–12 сония)',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Бекор'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Ҳаммасига қўллаш'),
            ),
          ],
        ),
      ),
    );

    if (applied != true || !mounted) return;
    try {
      final count = await repo.setDurationForModule('home_search', value);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.button,
          content: Text('✅ $count та матн $value сонияга ўрнатилди'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Хатолик: $e')),
      );
    }
  }

  Future<void> _openEditor({HomeTickerAd? existing}) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => _TickerEditorDialog(
        existing: existing,
        audiences: _audiences,
      ),
    );
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: AppColors.button,
          content: Text(
            existing == null ? '✅ Матн қўшилди' : '✅ Созламалар сақланди',
          ),
        ),
      );
    }
  }

  Future<void> _delete(HomeTickerAd ad) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Ўчириш?'),
        content: Text(
          '«${ad.text.length > 80 ? '${ad.text.substring(0, 80)}…' : ad.text}» '
          'бегущая строкadan olib tashlanadi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Бекор'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Ўчириш', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await context.read<HomeTickerRepository>().delete(ad.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.button,
          content: Text('🗑 Ўчирилди'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатолик: $e')),
      );
    }
  }

  Future<void> _toggleActive(HomeTickerAd ad, bool value) async {
    try {
      await context.read<HomeTickerRepository>().setActive(ad.id, value);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Хатолик: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_adminChecked) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_isAdmin) {
      return const Center(
        child: Text('⛔ Бу бўлим учун админ ҳуқуқи керак'),
      );
    }

    final repo = context.read<HomeTickerRepository>();
    final df = DateFormat('dd.MM.yyyy HH:mm');

    return Scaffold(
      backgroundColor: AppColors.scaffold,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: _blue,
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Бегущая строка',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Бош экран — маълумот майдони (сариқ панел)',
                        style: TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _openEditor(),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _blue,
                  ),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Янги матн'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _openBulkDuration,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                  icon: const Icon(Icons.timer_outlined, size: 18),
                  label: const Text('Давомийлик'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: _openBulkAnimation,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white70),
                  ),
                  icon: const Icon(Icons.animation, size: 18),
                  label: const Text('Анимация'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Матн бўйича қидириш...',
                prefixIcon: const Icon(Icons.search, size: 20),
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => setState(() => _query = ''),
                      ),
              ),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<HomeTickerAd>>(
              stream: repo.watchForAdmin(limit: 300),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Хатолик: ${snap.error}'));
                }
                final allItems = snap.data ?? const <HomeTickerAd>[];
                final items = _query.isEmpty
                    ? allItems
                    : allItems
                        .where((a) => a.text.toLowerCase().contains(_query))
                        .toList(growable: false);
                if (allItems.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.view_stream_outlined,
                            size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 12),
                        Text(
                          'Ҳали матн йўқ',
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          onPressed: () => _openEditor(),
                          icon: const Icon(Icons.add),
                          label: const Text('Биринчи матнни қўшиш'),
                        ),
                      ],
                    ),
                  );
                }

                if (items.isEmpty) {
                  return Center(
                    child: Text(
                      '"$_query" бўйича ҳеч нарса топилмади',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final ad = items[i];
                    final schedule = <String>[];
                    if (ad.activeFrom != null) {
                      schedule.add('дан ${df.format(ad.activeFrom!)}');
                    }
                    if (ad.activeTo != null) {
                      schedule.add('гача ${df.format(ad.activeTo!)}');
                    }

                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: ad.active
                              ? AppColors.primary.withValues(alpha: 0.25)
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Text(
                                    ad.text,
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Switch(
                                  value: ad.active,
                                  onChanged: (v) => _toggleActive(ad, v),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                Chip(
                                  label: Text(_audienceLabel(ad.audience),
                                      style: const TextStyle(fontSize: 11)),
                                  visualDensity: VisualDensity.compact,
                                ),
                                Chip(
                                  label: Text(
                                    'Устуворлик: ${ad.priority}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                Chip(
                                  label: Text(
                                    'Давомийлик: ${ad.durationSec} с',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                Chip(
                                  label: Text(
                                    HomeTickerAnimationStyle.label(
                                      ad.animationStyle,
                                    ),
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                Chip(
                                  label: Text(
                                    'Шрифт: ${ad.fontSize}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                Chip(
                                  label: Text(
                                    HomeTickerAnimationStyle.usesScrollPxPerSec(
                                      ad.animationStyle,
                                    )
                                        ? 'Тезлик: ${ad.scrollSpeed} px/с'
                                        : 'Тезлик: ${ad.scrollSpeed}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ],
                            ),
                            if (schedule.isNotEmpty) ...[
                              const SizedBox(height: 6),
                              Text(
                                schedule.join(' · '),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                            const SizedBox(height: 10),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                TextButton.icon(
                                  onPressed: () => _openEditor(existing: ad),
                                  icon: const Icon(Icons.edit_outlined,
                                      size: 18),
                                  label: const Text('Таҳрир'),
                                ),
                                TextButton.icon(
                                  onPressed: () => _delete(ad),
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18, color: Colors.red),
                                  label: const Text('Ўчириш',
                                      style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TickerEditorDialog extends StatefulWidget {
  const _TickerEditorDialog({
    required this.existing,
    required this.audiences,
  });

  final HomeTickerAd? existing;
  final List<(String, String)> audiences;

  @override
  State<_TickerEditorDialog> createState() => _TickerEditorDialogState();
}

class _TickerEditorDialogState extends State<_TickerEditorDialog> {
  static const _maxText = 500;

  late final TextEditingController _textCtrl;
  late String _audience;
  late String _module;
  late int _priority;
  late int _durationSec;
  late int _scrollSpeed;
  late int _fontSize;
  late String _animationStyle;
  late bool _active;
  DateTime? _activeFrom;
  DateTime? _activeTo;
  bool _useSchedule = false;
  bool _saving = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _textCtrl = TextEditingController(text: e?.text ?? '');
    _audience = e?.audience ?? 'all';
    _module = 'home_search';
    _priority = e?.priority ?? 0;
    _durationSec = e?.durationSec ?? HomeTickerAd.defaultDurationSec;
    _scrollSpeed = e?.scrollSpeed ?? HomeTickerAd.defaultScrollSpeed;
    _fontSize = e?.fontSize ?? HomeTickerAd.defaultFontSize;
    _animationStyle = e?.animationStyle ?? HomeTickerAnimationStyle.auto;
    _active = e?.active ?? true;
    _activeFrom = e?.activeFrom;
    _activeTo = e?.activeTo;
    _useSchedule = _activeFrom != null || _activeTo != null;
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime(bool isFrom) async {
    final initial = isFrom
        ? (_activeFrom ?? DateTime.now())
        : (_activeTo ?? DateTime.now().add(const Duration(days: 7)));
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2024),
      lastDate: DateTime(2030),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    final dt = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    setState(() {
      if (isFrom) {
        _activeFrom = dt;
      } else {
        _activeTo = dt;
      }
    });
  }

  Future<void> _save() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty) {
      setState(() => _err = 'Матн мажбурий');
      return;
    }
    if (text.length > _maxText) {
      setState(() => _err = 'Матн $_maxText белгидан ошмасин');
      return;
    }
    if (_useSchedule &&
        _activeFrom != null &&
        _activeTo != null &&
        !_activeTo!.isAfter(_activeFrom!)) {
      setState(() => _err = 'Тугаш вақти бошланишдан кейин бўлиши керак');
      return;
    }

    setState(() {
      _saving = true;
      _err = null;
    });

    final ad = HomeTickerAd(
      id: widget.existing?.id ?? '',
      text: text,
      audience: _audience,
      module: _module,
      durationSec: _durationSec,
      scrollSpeed: _scrollSpeed,
      animationStyle: _animationStyle,
      fontSize: _fontSize,
      priority: _priority,
      active: _active,
      activeFrom: _useSchedule ? _activeFrom : null,
      activeTo: _useSchedule ? _activeTo : null,
    );

    try {
      final repo = context.read<HomeTickerRepository>();
      if (widget.existing == null) {
        await repo.create(ad);
      } else {
        await repo.update(ad);
      }
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      setState(() => _err = 'Хатолик: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final df = DateFormat('dd.MM.yyyy HH:mm');

    return AlertDialog(
      title: Text(isEdit ? 'Матнни таҳрирлаш' : 'Янги бегущая строка'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _textCtrl,
                maxLines: 3,
                maxLength: _maxText,
                decoration: const InputDecoration(
                  labelText: 'Матн *',
                  hintText: 'Масалан: Маршрут такси — янги маршрутлар!',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _audience,
                decoration: const InputDecoration(
                  labelText: 'Кимлар кўради',
                  border: OutlineInputBorder(),
                ),
                items: widget.audiences
                    .map(
                      (a) => DropdownMenuItem(
                        value: a.$1,
                        child: Text(a.$2),
                      ),
                    )
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _audience = v);
                },
              ),
              const SizedBox(height: 16),
              const Text(
                'Анимация услуби',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              ...HomeTickerAnimationStyle.all.map((style) {
                final selected = _animationStyle == style;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: InkWell(
                    onTap: () => setState(() => _animationStyle = style),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: selected
                            ? const Color(0xFFE3F2FD)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: selected
                              ? AppColors.primary
                              : Colors.grey.shade300,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 18,
                            color: selected
                                ? AppColors.primary
                                : Colors.grey,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  HomeTickerAnimationStyle.label(style),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: selected
                                        ? AppColors.primary
                                        : Colors.black87,
                                  ),
                                ),
                                Text(
                                  HomeTickerAnimationStyle.description(style),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
              const Text(
                'Созламалар',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 8),
              _sliderRow(
                label: 'Шрифт ўлчами',
                value: _fontSize.toDouble(),
                min: 10,
                max: 24,
                divisions: 14,
                suffix: '$_fontSize',
                onChanged: (v) => setState(() => _fontSize = v.round()),
              ),
              _sliderRow(
                label: 'Давомийлик (бир матн)',
                value: _durationSec.toDouble(),
                min: 5,
                max: 120,
                divisions: 23,
                suffix: '$_durationSec с',
                onChanged: (v) => setState(() => _durationSec = v.round()),
              ),
              _sliderRow(
                label: HomeTickerAnimationStyle.usesScrollPxPerSec(
                  _animationStyle,
                )
                    ? 'Югуриш тезлиги (px/с)'
                    : 'Ҳарф / анимация тезлиги',
                value: _scrollSpeed.toDouble(),
                min: 15,
                max: 120,
                divisions: 21,
                suffix: HomeTickerAnimationStyle.usesScrollPxPerSec(
                  _animationStyle,
                )
                    ? '$_scrollSpeed px/с'
                    : '$_scrollSpeed',
                onChanged: (v) => setState(() => _scrollSpeed = v.round()),
              ),
              _sliderRow(
                label: 'Устуворлик',
                value: _priority.toDouble().clamp(0, 100),
                min: 0,
                max: 100,
                divisions: 20,
                suffix: '$_priority',
                onChanged: (v) => setState(() => _priority = v.round()),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Фаол'),
                subtitle: const Text('Ўчирилса иловада кўринмайди'),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Вақт бўйича'),
                subtitle: const Text('Фақат белгиланган оралиқда кўрсатиш'),
                value: _useSchedule,
                onChanged: (v) => setState(() {
                  _useSchedule = v;
                  if (!v) {
                    _activeFrom = null;
                    _activeTo = null;
                  }
                }),
              ),
              if (_useSchedule) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Бошланиш'),
                  subtitle: Text(
                    _activeFrom != null
                        ? df.format(_activeFrom!)
                        : 'Танланмаган',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () => _pickDateTime(true),
                  ),
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Тугаш'),
                  subtitle: Text(
                    _activeTo != null ? df.format(_activeTo!) : 'Танланмаган',
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.calendar_today),
                    onPressed: () => _pickDateTime(false),
                  ),
                ),
              ],
              if (_err != null) ...[
                const SizedBox(height: 8),
                Text(_err!, style: const TextStyle(color: Colors.red)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Бекор'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(isEdit ? 'Сақлаш' : 'Қўшиш'),
        ),
      ],
    );
  }

  Widget _sliderRow({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String suffix,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(fontSize: 12)),
            ),
            Text(suffix,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: suffix,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
