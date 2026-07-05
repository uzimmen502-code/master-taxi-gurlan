import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_theme.dart';
import '../../ads/models/ad_model.dart';
import '../services/admin_market_service.dart';

Future<void> showMarketAdEditDialog({
  required BuildContext context,
  required AdModel ad,
  required String adminPhone,
}) {
  return showDialog<void>(
    context: context,
    builder: (_) => _MarketAdEditDialog(ad: ad, adminPhone: adminPhone),
  );
}

class _MarketAdEditDialog extends StatefulWidget {
  const _MarketAdEditDialog({
    required this.ad,
    required this.adminPhone,
  });

  final AdModel ad;
  final String adminPhone;

  @override
  State<_MarketAdEditDialog> createState() => _MarketAdEditDialogState();
}

class _MarketAdEditDialogState extends State<_MarketAdEditDialog> {
  late final TextEditingController _title;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _phone;
  late final TextEditingController _sellerName;
  late final TextEditingController _adminNote;
  late String _status;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.ad.title);
    _description = TextEditingController(text: widget.ad.description);
    _price = TextEditingController(text: '${widget.ad.price}');
    _phone = TextEditingController(text: widget.ad.phone);
    _sellerName = TextEditingController(text: widget.ad.sellerName);
    _adminNote = TextEditingController(text: widget.ad.adminNote);
    _status = widget.ad.status;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _phone.dispose();
    _sellerName.dispose();
    _adminNote.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: Colors.red,
          content: Text('Sarlavha bo\'sh bo\'la olmaydi'),
        ),
      );
      return;
    }
    final price = int.tryParse(_price.text.replaceAll(RegExp(r'\D'), '')) ?? 0;
    setState(() => _saving = true);
    try {
      await context.read<AdminMarketService>().updateAd(
            adminPhone: widget.adminPhone,
            adId: widget.ad.id,
            title: _title.text.trim(),
            description: _description.text.trim(),
            price: price,
            phone: _phone.text.trim(),
            sellerName: _sellerName.text.trim(),
            status: _status,
            adminNote: _adminNote.text.trim(),
          );
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: AppColors.button,
          content: Text('E\'lon yangilandi'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: Colors.red, content: Text('Xatolik: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Onlayn BOZOR — tahrirlash'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _title,
                decoration: const InputDecoration(labelText: 'Sarlavha'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _description,
                minLines: 2,
                maxLines: 5,
                decoration: const InputDecoration(labelText: 'Tavsif'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Narx (so\'m)'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _sellerName,
                decoration: const InputDecoration(labelText: 'Sotuvchi ismi'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phone,
                decoration: const InputDecoration(labelText: 'Telefon'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Faol')),
                  DropdownMenuItem(value: 'inactive', child: Text('Nofaol')),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _status = v);
                },
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _adminNote,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'Admin izoh'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: const Text('Bekor'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Saqlash'),
        ),
      ],
    );
  }
}
