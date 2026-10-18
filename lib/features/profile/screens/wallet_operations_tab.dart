import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/utils/formatters.dart';
import '../widgets/wallet_ledger_list.dart';

/// Хабарлар — кошелёк operatsiyalari (oxirgi 1 oy).
class WalletOperationsTab extends StatefulWidget {
  const WalletOperationsTab({super.key});

  @override
  State<WalletOperationsTab> createState() => _WalletOperationsTabState();
}

class _WalletOperationsTabState extends State<WalletOperationsTab> {
  String _uid = '';

  @override
  void initState() {
    super.initState();
    _loadUid();
  }

  Future<void> _loadUid() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = phoneDigits(prefs.getString('user_phone') ?? '');
    if (mounted) setState(() => _uid = uid);
  }

  @override
  Widget build(BuildContext context) {
    final since = DateTime.now().subtract(const Duration(days: 30));

    if (_uid.length < 9) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            context.tr('wlt_phone_needed'),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadUid,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blue.shade100),
            ),
            child: Text(
              context.tr('wlt_ops_intro'),
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
                height: 1.35,
              ),
            ),
          ),
          const SizedBox(height: 12),
          WalletLedgerList(
            uid: _uid,
            since: since,
            emptyMessage: context.tr('wlt_ops_empty_month'),
          ),
        ],
      ),
    );
  }
}
