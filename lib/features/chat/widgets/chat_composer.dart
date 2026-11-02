import 'package:flutter/material.dart';

import '../../../core/l10n/l10n_extension.dart';
import '../../../core/theme/ava_tokens.dart';

/// Чат ёзиш майдони — support ва «Буюртма ёзиш» чатларида бир хил (аввал бирида
/// `ElevatedButton`, бошқасида `IconButton.filled` эди).
class ChatComposer extends StatelessWidget {
  const ChatComposer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.hintKey,
    this.sending = false,
    this.maxLength,
    this.inputKey,
    this.sendKey,
    this.sendTooltipKey = 'deal_chat_send',
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final String hintKey;
  final bool sending;
  final int? maxLength;
  final Key? inputKey;
  final Key? sendKey;
  final String sendTooltipKey;

  @override
  Widget build(BuildContext context) {
    final c = context.ava;
    return Material(
      color: c.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 6, 8, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: inputKey,
                  controller: controller,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: maxLength,
                  textCapitalization: TextCapitalization.sentences,
                  style: AvaText.body.copyWith(fontSize: 15, color: c.ink),
                  decoration: InputDecoration(
                    hintText: context.tr(hintKey),
                    counterText: '',
                    filled: true,
                    fillColor: c.surface2,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(22),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                key: sendKey,
                tooltip: context.tr(sendTooltipKey),
                style: IconButton.styleFrom(
                  backgroundColor: c.brand,
                  foregroundColor: c.brandInk,
                  minimumSize: const Size(46, 46),
                ),
                onPressed: sending ? null : onSend,
                icon: sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send_rounded),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
