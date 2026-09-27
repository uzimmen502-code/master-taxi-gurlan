import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/l10n/l10n_extension.dart';
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
    final isPending = ad.isPending;

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
              title: context.tr('my_ad_hide'),
              body: context.tr('my_ad_hide_body'),
              onConfirm: () => repo.deactivateAd(ad.id),
            );
            break;
          case 'republish':
            await _confirm(
              context,
              title: context.tr('my_ad_republish'),
              // Аввал бу ерда «Админ тасдиқлагач бозорда кўринади» деб
              // ёзилган эди — бу ЁЛҒОН: `settings/app.marketAutoApprove`
              // ёқиқ бўлса эълон дарҳол чиқади, админ аралашмайди.
              // Янги матн иккала режимда ҳам тўғри.
              body: context.tr('my_ad_republish_body'),
              onConfirm: () => repo.requestRepublish(ad.id),
            );
            break;
          case 'delete':
            await _confirm(
              context,
              title: context.tr('delete'),
              body: context.tr('my_ad_delete_body'),
              onConfirm: () => repo.deleteAd(ad.id),
              destructive: true,
            );
            break;
        }
      },
      itemBuilder: (ctx) {
        final edit = PopupMenuItem(
          value: 'edit',
          child: Text(ctx.tr('edit')),
        );
        final hide = PopupMenuItem(
          value: 'hide',
          child: Text(ctx.tr('my_ad_hide')),
        );
        final remove = PopupMenuItem(
          value: 'delete',
          child: Text(ctx.tr('delete')),
        );
        // Фаол ва текширувдаги эълонда бир хил амаллар.
        if (isActive || isPending) {
          return [edit, hide, remove];
        }
        // Яширилган / муддати тугаган — қайта жойлаштириш мумкин.
        return [
          PopupMenuItem(
            value: 'republish',
            child: Text(ctx.tr('my_ad_republish')),
          ),
          edit,
          remove,
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
            child: Text(ctx.tr('no')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              ctx.tr('yes'),
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
            SnackBar(
              content: Text(
                context.tr(destructive ? 'my_ad_deleted' : 'saved'),
              ),
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${context.tr('error')}: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}
