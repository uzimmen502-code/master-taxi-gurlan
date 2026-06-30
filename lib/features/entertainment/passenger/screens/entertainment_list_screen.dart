import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
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
  String? _error;
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
      _error = null;
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
    } on EntertainmentAccessException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
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
          const SnackBar(content: Text('Юклаб бўлмади. Wi‑Fi ни текширинг.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Хато: $e')),
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
        title: const Text('🎬 Сафар кинотеатри'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : _videos.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          '${widget.driverName} бу рейс учун фильм танламаган.\n'
                          'Кейинроқ уриниб кўринг ёки ҳайдовчига мурожаат қилинг.',
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
                          child: const Text(
                            'Wi‑Fi да фильмни юклаб олинг, сафарда интернетсиз томоша қилинг.',
                            style: TextStyle(fontSize: 12, height: 1.35),
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
                                  color: widget.primaryColor,
                                ),
                              ),
                              title: Text(v.title,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600)),
                              subtitle: Text(
                                [
                                  if (v.durationLabel.isNotEmpty)
                                    v.durationLabel,
                                  cached ? 'Офлайн тайёр' : 'Онлайн кўрилади',
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
                                            tooltip: 'Wi‑Fi да юклаб олиш',
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
