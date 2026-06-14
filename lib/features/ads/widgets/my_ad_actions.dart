import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/ad_model.dart';
import '../repositories/ads_repository.dart';
import '../screens/edit_ad_screen.dart';

/// Popup actions for owner's ad row.
class MyAdActions extends StatelessWidget {
  const MyAdActions({super.key, required this.ad});

  final AdModel ad;

  @override
  Widget build(BuildContext context) {
    final repo = context.read<AdsRepository>();
    final isActive = ad.isActive;

    return PopupMenuButton<String>(
      onSelected: (value) async {
        switch (value) {
          case 'edit':
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EditAdScreen(ad: ad),
              ),
            );
            break;
          case 'hide':
            await _confirm(
              context,
              title: 'Яшириш',
              body: 'Эълон яширилади. Кейинчалик қайта жойлаштириш мумкин.',
              onConfirm: () => repo.deactivateAd(ad.id),
            );
            break;
          case 'republish':
            await repo.activateAd(ad.id);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Эълон қайта фаоллаштирилди')),
              );
            }
            break;
          case 'delete':
            await _confirm(
              context,
              title: 'Ўчириш',
              body: 'Эълон тўлиқ ўчирилади. Давом этасизми?',
              onConfirm: () => repo.deleteAd(ad.id),
              destructive: true,
            );
            break;
        }
      },
      itemBuilder: (ctx) {
        if (isActive) {
          return [
            const PopupMenuItem(value: 'edit', child: Text('Таҳрирлаш')),
            const PopupMenuItem(value: 'hide', child: Text('Яшириш')),
            const PopupMenuItem(value: 'delete', child: Text('Ўчириш')),
          ];
        }
        return [
          const PopupMenuItem(
            value: 'republish',
            child: Text('Қайта жойлаштириш'),
          ),
          const PopupMenuItem(value: 'edit', child: Text('Таҳрирлаш')),
          const PopupMenuItem(value: 'delete', child: Text('Ўчириш')),
        ];
      },
    );
  }

  static Future<void> _confirm(
    BuildContext context, {
    required String title,
    required String body,
    required Future<void> Function() onConfirm,
    bool destructive = false,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Йўқ'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Ҳа',
              style: TextStyle(
                color: destructive ? Colors.red : null,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await onConfirm();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(destructive ? 'Ўчирилди' : 'Сақланди')),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Хатолик: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
