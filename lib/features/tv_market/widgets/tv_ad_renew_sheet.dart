import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../../../repositories/user_repository.dart';
import '../models/tv_clip.dart';
import '../services/tv_ad_service.dart';
import 'tv_ad_tier_picker.dart';

/// Эълонни узайтириш — тариф + муддат танлаб, wallet'дан тўлаш.
/// Видеони қайта юклаш шарт эмас (CF `renewTvAd` фақат муддатни узайтиради).
/// `true` қайтарса — узайтирилди.
Future<bool> showTvAdRenewSheet(BuildContext context, TvClip clip) async {
  final ok = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
    ),
    builder: (_) => _TvAdRenewSheet(clip: clip),
  );
  return ok ?? false;
}

class _TvAdRenewSheet extends StatefulWidget {
  const _TvAdRenewSheet({required this.clip});

  final TvClip clip;

  @override
  State<_TvAdRenewSheet> createState() => _TvAdRenewSheetState();
}

class _TvAdRenewSheetState extends State<_TvAdRenewSheet> {
  late String _tier = tvAdTiers.contains(widget.clip.adTier)
      ? widget.clip.adTier
      : tvAdTiers.first;
  late int _days = tvAdDurationOptions.contains(widget.clip.adDurationDays)
      ? widget.clip.adDurationDays
      : tvAdDurationOptions.first;

  Map<String, Map<int, int>> _pricing = {
    for (final e in tvAdTierPricingDefault.entries) e.key: Map.of(e.value),
  };
  Map<String, num> _scopeMultiplier = Map.of(tvAdScopeMultiplierDefault);
  // Қамров узайтиришда ўзгармайди (сервер ҳам мавжуд клипдан ўқийди —
  // арзонроқ scope юбориб нархни пасайтиришнинг олдини олиш учун).
  String get _scope =>
      tvAdScopes.contains(widget.clip.adScope) ? widget.clip.adScope : 'district';
  int _balance = 0;
  StreamSubscription<int>? _balanceSub;
  final String _idempotencyKey = const Uuid().v4();
  bool _busy = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_balanceSub?.cancel());
    super.dispose();
  }

  Future<void> _load() async {
    final results = await Future.wait([
      TvAdService.loadPricing(),
      TvAdService.loadScopeMultiplier(),
    ]);
    if (mounted) {
      setState(() {
        _pricing = results[0] as Map<String, Map<int, int>>;
        _scopeMultiplier = results[1] as Map<String, num>;
      });
    }

    final prefs = await SharedPreferences.getInstance();
    final phone = canonicalPhoneId(prefs.getString('user_phone') ?? '');
    if (phone.isEmpty) return;
    _balanceSub = UserRepository().watchBonusBalance(phone).listen((b) {
      if (mounted) setState(() => _balance = b);
    });
  }

  int get _price {
    final base =
        _pricing[_tier]?[_days] ?? tvAdTierPricingDefault[_tier]?[_days] ?? 0;
    final mult =
        _scopeMultiplier[_scope] ?? tvAdScopeMultiplierDefault[_scope] ?? 1;
    return (base * mult).round();
  }

  bool get _insufficient => _price > 0 && _balance < _price;

  Future<void> _renew() async {
    if (_busy || _insufficient) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await TvAdService.renewTvAd(
        idempotencyKey: _idempotencyKey,
        clipId: widget.clip.id,
        durationDays: _days,
        tier: _tier,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.code == 'failed-precondition' &&
              e.message == 'insufficient_balance'
          ? context.tr('tv_ad_insufficient_balance')
          : (e.message ?? e.code));
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                context.tr('tv_ad_renew_title'),
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                widget.clip.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 14),
              // Қамров кўрсатилади, лекин таҳрирланмайди — `onScopeChanged`
              // берилмагани учун селектор яширин, фақат жорий scope
              // нархга киритилади (сервер ҳам шу scope'дан ҳисоблайди).
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${context.tr('tv_ad_scope_title')}: '
                  '${context.tr('tv_ad_scope_$_scope')}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.grey.shade600,
                  ),
                ),
              ),
              TvAdTierPicker(
                selectedTier: _tier,
                selectedDays: _days,
                pricing: _pricing,
                walletBalance: _balance,
                enabled: !_busy,
                onTierChanged: (t) => setState(() => _tier = t),
                onDaysChanged: (d) => setState(() => _days = d),
                selectedScope: _scope,
                scopeMultiplier: _scopeMultiplier,
              ),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(_error,
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
              const SizedBox(height: 14),
              SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: _busy || _insufficient ? null : _renew,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.autorenew_rounded, size: 18),
                  label: Text(
                    context
                        .tr('tv_ad_renew_pay')
                        .replaceAll('{price}', formatMoney(_price)),
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 15),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
