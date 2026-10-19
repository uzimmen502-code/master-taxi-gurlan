import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../tv_market/models/tv_clip.dart';
import '../../tv_market/screens/tv_market_feed_screen.dart';
import 'realty_feedback.dart';

/// Объектга боғланган ЭСКИ видеони (`avagramClipId` / `adClipId`) очиш.
///
/// Мавжуд AVAGram плеери қайта ишлатилади — кўчмас мулк учун алоҳида видео ўйнатгич қурилмайди. Янги видео
/// умумий қатлам орқали ([TvClipLink], `realty_listing`) жойланади; эски «мавжуд клипни боғлаш» ойнаси олиб
/// ташланди (дубликат, эга 2026-10-20) — бу ерда фақат аввал боғланганларни кўриш қолди.
Future<void> openRealtyVideo(
  BuildContext context, {
  required String clipId,
}) async {
  final snap =
      await FirebaseFirestore.instance.collection('tv_clips').doc(clipId).get();
  if (!context.mounted) return;
  if (!snap.exists) {
    showRealtyInfo(
      ScaffoldMessenger.of(context),
      context.tr('realty_video_missing'),
    );
    return;
  }
  final clip = TvClip.fromFirestore(snap);
  await Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => TvMarketFeedScreen(initialClip: clip)),
  );
}