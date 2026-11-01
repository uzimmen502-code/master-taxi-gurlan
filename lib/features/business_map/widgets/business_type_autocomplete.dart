import 'package:flutter/material.dart';

import '../domain/business_subtypes.dart';

/// «Фаолият тури» ва «Аниқроқ тури» майдонлари учун умумий автокомплит (эга, 2026-11-01).
/// Таклифлар рўйхати майдон остида, майдон энида; ҳар бир қатор калити `<keyPrefix>_opt_<i>` (тест учун).
class BusinessTypeAutocomplete extends StatelessWidget {
  const BusinessTypeAutocomplete({
    super.key,
    required this.keyPrefix,
    required this.controller,
    required this.focusNode,
    required this.decoration,
    required this.options,
    required this.displayString,
    required this.onSelected,
    required this.itemBuilder,
    this.enabled = true,
    this.maxLength,
    this.onChanged,
  });

  final String keyPrefix;
  final TextEditingController controller;
  final FocusNode focusNode;
  final InputDecoration decoration;
  final Iterable<BusinessTypeOption> Function(String text) options;

  /// Танланганда майдонга ёзиладиган матн.
  final String Function(BusinessTypeOption o) displayString;
  final ValueChanged<BusinessTypeOption> onSelected;
  final Widget Function(BuildContext context, BusinessTypeOption o) itemBuilder;
  final bool enabled;
  final int? maxLength;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => RawAutocomplete<BusinessTypeOption>(
        textEditingController: controller,
        focusNode: focusNode,
        displayStringForOption: displayString,
        optionsBuilder: (value) => options(value.text),
        onSelected: onSelected,
        fieldViewBuilder: (context, ctrl, node, onSubmit) => TextField(
          key: ValueKey('${keyPrefix}_field'),
          controller: ctrl,
          focusNode: node,
          enabled: enabled,
          maxLength: maxLength,
          decoration: decoration,
          onChanged: onChanged,
          onSubmitted: (_) => onSubmit(),
        ),
        optionsViewBuilder: (context, select, opts) => Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: 300, maxWidth: constraints.maxWidth),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: opts.length,
                itemBuilder: (context, i) {
                  final o = opts.elementAt(i);
                  return InkWell(
                    key: ValueKey('${keyPrefix}_opt_$i'),
                    onTap: () => select(o),
                    child: itemBuilder(context, o),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
