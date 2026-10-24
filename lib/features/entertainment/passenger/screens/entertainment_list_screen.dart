import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/l10n/l10n_extension.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/user_error.dart';
import '../../../../models/entertainment_video.dart';
import '../../../../repositories/entertainment_repository.dart';
import '../../../../repositories/intercity_bookings_repository.dart';
import '../../services/entertainment_cache_service.dart';
import 'entertainment_player_screen.dart';

/// Йўловчи — ҳайдовчи танлаган фильмлар рўйхати (B variant).
class EntertainmentListScreen extends StatefulWidget {
  const EntertainmentListScreen({
    super.key,
    required this.driverId,
    required this.driverName,
    required this.userPhone,
    this.bookingId,
    this.primaryColor = AppColors.primary,
  });

  final String driverId;
  final String driverName;
  final String userPhone;
  final String? bookingId;
  final Color primaryColor;

  @override
  State<EntertainmentListScreen> createState() =>
      _EntertainmentListScreenState();
}

class _EntertainmentListScreenState extends State<EntertainmentListScreen> {
  final _cache = EntertainmentCacheService();
  List<EntertainmentVideo> _videos = const [];
  bool _loading = true;

  /// Xato matni emas — l10n kaliti (ekranda `context.trMsg(_errorKey!)`).
  String? _errorKey;
  final Set<String> _cached = {};
  final Set<String> _downloading = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _errorKey = null;
    });
    try {
      final repo = context.read<EntertainmentRepository>();
      final bookingsRepo = context.read<IntercityBookingsRepository>();
      final list = await repo.videosForPassenger(
        bookingsRepo: bookingsRepo,
        userPhone: widget.userPhone,
        driverId: widget.driverId,
        bookingId: widget.bookingId,
      );
      final cached = <String>{};
      for (final v in list) {
        if (await _cache.isCached(v.id)) cached.add(v.id);
      }
      if (!mounted) return;
      setState(() {
        _videos = list;
        _cached.addAll(cached);
        _loading = false;
      });
    } on EntertainmentAccessException {
      if (!mounted) return;
      setState(() {
        _errorKey = 'ent_access_denied';
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorKey = userErrorKey(e, fallbackKey: 'err_load_failed');
        _loading = false;
      });
    }
  }

  /// Wi‑Fi'da oldindan yuklab olish → safarda internetsiz tomosha.
  Future<void> _downloadVideo(EntertainmentVideo video) async {
    if (_downloading.contains(video.id)) return;
    setState(() => _downloading.add(video.id));
    try {
      final f = await _cache.download(
        videoId: video.id,
        storagePath: video.storagePath,
      );
      if (!mounted) return;
      if (f != null) {
        setState(() => _cached.add(video.id));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.tr('ent_download_failed'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(userErrorMessage(context, e,
                  fallbackKey: 'ent_download_failed'))),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading.remove(video.id));
    }
  }

  Future<void> _openVideo(EntertainmentVideo video) async {
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => EntertainmentPlayerScreen(
          video: video,
          primaryColor: widget.primaryColor,
        ),
      ),
    );
    if (mounted) {
      if (await _cache.isCached(video.id)) {
        setState(() => _cached.add(video.id));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.moduleBg,
      appBar: AppBar(
        title: Text(context.tr('ent_list_title')),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _errorKey != null
              ? Center(child: Text(context.trMsg(_errorKey!)))
              : _videos.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          context.trMsg('ent_list_empty',
                              params: {'driver': widget.driverName}),
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            context.tr('ent_wifi_hint'),
                            style: const TextStyle(fontSize: 12, height: 1.35),
                          ),
                        ),
                        const SizedBox(height: 12),
                        ..._videos.map((v) {
                          final cached = _cached.contains(v.id);
                          return Card(
                            margin: const EdgeInsets.only(bottom: 10),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    widget.primaryColor.withValues(alpha: 0.15),
                                child: Icon(
                                  cached
                                      ? Icons.download_done
                                      : Icons.movie_outlined,
                                  color: AppColors.primaryText,
                                ),
                              ),
                              title: Text(v.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                [
                                  if (v.durationLabel.isNotEmpty)
                                    v.durationLabel,
                                  cached
                                      ? context.tr('ent_offline_ready')
                                      : context.tr('ent_online_only'),
                                ].join(' · '),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (!cached)
                                    _downloading.contains(v.id)
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          )
                                        : IconButton(
                                            icon: const Icon(
                                                Icons.download_outlined),
                                            tooltip:
                                                context.tr('ent_wifi_download'),
                                            onPressed: () => _downloadVideo(v),
                                          ),
                                  const Icon(Icons.play_circle_fill),
                                ],
                              ),
                              onTap: () => _openVideo(v),
                            ),
                          );
                        }),
                      ],
                    ),
    );
  }
}
