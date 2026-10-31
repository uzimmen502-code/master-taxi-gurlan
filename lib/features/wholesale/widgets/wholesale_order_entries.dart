// Улгуржи буюртмаларга кириш нуқталари (4-босқич).
//
//   харидор — бозор экрани AppBar'идаги «Менинг буюртмаларим» тугмаси;
//   сотувчи — «Мен сотувчиман» / «Менинг дўконим» панелидаги «Келган
//             буюртмалар» ва «Тўлов қабул қилиш картаси» (3b) қаторлари.
//
// Ҳаммаси `module_config/wholesale_orders_all` дарвозаси очиқ бўлсагина
// кўринади (42-банд); ҳал қилувчи — сервер.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/app_theme.dart';
import '../models/wholesale_order.dart';
import '../repositories/wholesale_orders_repository.dart';
import '../screens/wholesale_orders_screen.dart';
import '../utils/wholesale_order_errors.dart';

class WholesaleBuyerOrdersAction extends StatelessWidget {
  const WholesaleBuyerOrdersAction({super.key, required this.userPhone, this.repository});

  final String userPhone;
  final WholesaleOrdersRepository? repository;

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? WholesaleOrdersRepository();
    return FutureBuilder<WholesaleOrdersGate>(
      future: repo.gate(),
      builder: (context, snap) {
        if (!(snap.data?.allows(userPhone) ?? false)) return const SizedBox.shrink();
        return IconButton(
          key: const ValueKey('wholesale-my-orders'),
          tooltip: context.tr('wholesale_my_orders'),
          icon: const Icon(Icons.receipt_long_outlined),
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => WholesaleOrdersScreen(
                role: WholesaleOrdersRole.buyer,
                userId: userPhone,
                repository: repo,
              ),
            ),
          ),
        );
      },
    );
  }
}

class WholesaleSellerOrdersPanel extends StatelessWidget {
  const WholesaleSellerOrdersPanel({super.key, required this.sellerPhone, this.cardLast4 = '', this.repository});

  final String sellerPhone;

  /// Жорий тўлов картасининг охирги 4 рақами (`wholesale_sellers.cardLast4`); бўш — йўқ.
  final String cardLast4;
  final WholesaleOrdersRepository? repository;

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? WholesaleOrdersRepository();
    return FutureBuilder<WholesaleOrdersGate>(
      future: repo.gate(),
      builder: (context, snap) {
        // Сотувчига буюртма ҲАР ҚАНДАЙ харидордан (синовчидан ҳам) келиши
        // мумкин — шунинг учун босқичдан қатъи назар, дарвоза ёқилган бўлса.
        if (snap.data?.enabled != true) return const SizedBox.shrink();
        return Material(
          color: Colors.white,
          child: Column(
            children: [
              ListTile(
                key: const ValueKey('wholesale-incoming-orders'),
                leading: const Icon(Icons.inbox_outlined),
                title: Text(context.tr('wholesale_incoming_orders'),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => WholesaleOrdersScreen(
                      role: WholesaleOrdersRole.seller,
                      userId: sellerPhone,
                      repository: repo,
                    ),
                  ),
                ),
              ),
              ListTile(
                key: const ValueKey('wholesale-seller-card'),
                leading: const Icon(Icons.credit_card),
                title: Text(context.tr('wholesale_seller_card_title')),
                subtitle: Text(
                  cardLast4.isEmpty
                      ? context.tr('wholesale_seller_card_none')
                      : context.trMsg('wholesale_seller_card_current', params: {'last4': cardLast4}),
                  key: const ValueKey('wholesale-seller-card-current'),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => showWholesaleSellerCardSheet(context, repository: repo),
              ),
              Divider(height: 1, color: AppColors.cardBorderMuted),
            ],
          ),
        );
      },
    );
  }
}

/// 3b: сотувчининг тўлов қабул қилиш картаси (`setWholesaleSellerCard`).
Future<void> showWholesaleSellerCardSheet(
  BuildContext context, {
  WholesaleOrdersRepository? repository,
}) async {
  final last4 = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => WholesaleSellerCardSheet(repository: repository ?? WholesaleOrdersRepository()),
  );
  if (last4 != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(last4.isEmpty
            ? context.tr('wholesale_seller_card_saved')
            : context.trMsg('wholesale_seller_card_saved_last4', params: {'last4': last4})),
      ),
    );
  }
}

class WholesaleSellerCardSheet extends StatefulWidget {
  const WholesaleSellerCardSheet({super.key, required this.repository});

  final WholesaleOrdersRepository repository;

  /// Локал текширув (соф, сервер қоидаси билан бир хил): 16 рақам + Luhn, исм 2–60.
  /// Ҳал қилувчи — сервер (`card_number_invalid` / `holder_name_invalid`).
  static String? validate(String number, String holder) {
    final d = number.replaceAll(RegExp(r'\D'), '');
    if (d.length != 16) return 'wholesale_seller_card_err_number';
    if (!luhnOk(d)) return 'wholesale_order_err_card_luhn';
    final h = holder.trim();
    if (h.length < 2 || h.length > 60) return 'wholesale_seller_card_err_holder';
    return null;
  }

  static bool luhnOk(String digits) {
    var sum = 0;
    var dbl = false;
    for (var i = digits.length - 1; i >= 0; i--) {
      var n = digits.codeUnitAt(i) - 48;
      if (n < 0 || n > 9) return false;
      if (dbl) {
        n *= 2;
        if (n > 9) n -= 9;
      }
      sum += n;
      dbl = !dbl;
    }
    return sum % 10 == 0;
  }

  @override
  State<WholesaleSellerCardSheet> createState() => _WholesaleSellerCardSheetState();
}

class _WholesaleSellerCardSheetState extends State<WholesaleSellerCardSheet> {
  final _number = TextEditingController();
  final _holder = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _number.dispose();
    _holder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final err = WholesaleSellerCardSheet.validate(_number.text, _holder.text);
    if (err != null) {
      setState(() => _error = context.tr(err));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final last4 = await widget.repository.setSellerCard(cardNumber: _number.text, holderName: _holder.text);
      if (mounted) Navigator.of(context).pop(last4);
    } catch (e) {
      if (mounted) setState(() => _error = wholesaleOrderErrorText(context, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(context.tr('wholesale_seller_card_title'),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text(context.tr('wholesale_seller_card_help'),
                style: TextStyle(fontSize: 12, color: AppColors.sectionMuted)),
            const SizedBox(height: 12),
            TextField(
              controller: _number,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(16)],
              decoration: InputDecoration(
                labelText: context.tr('wholesale_seller_card_number'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _holder,
              textCapitalization: TextCapitalization.characters,
              maxLength: 60,
              buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              decoration: InputDecoration(
                labelText: context.tr('wholesale_seller_card_holder'),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 6),
              Text(_error!, style: TextStyle(fontSize: 12, color: AppColors.error)),
            ],
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(context.tr('save')),
            ),
          ],
        ),
      ),
    );
  }
}
