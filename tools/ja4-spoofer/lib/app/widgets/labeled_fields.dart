import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class LabeledInputField extends StatelessWidget {
  const LabeledInputField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.labelWidget,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final Widget? labelWidget;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        labelWidget ??
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
        const SizedBox(height: 6),
        ShadInput(
          controller: controller,
          placeholder: hint == null ? null : Text(hint!),
        ),
      ],
    );
  }
}

class LabeledTextareaField extends StatelessWidget {
  const LabeledTextareaField({
    super.key,
    required this.label,
    required this.controller,
    this.hint,
    this.minHeight = 110,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        ShadTextarea(
          controller: controller,
          minHeight: minHeight,
          maxHeight: minHeight,
          resizable: false,
          placeholder: hint == null ? null : Text(hint!),
        ),
      ],
    );
  }
}

class LabeledSelectField extends StatelessWidget {
  const LabeledSelectField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.optionLabels = const {},
    this.includeUnset = false,
    this.unsetLabel = '(unset)',
    this.labelWidget,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final Map<String, String> optionLabels;
  final bool includeUnset;
  final String unsetLabel;
  final Widget? labelWidget;

  @override
  Widget build(BuildContext context) {
    final entries = <MapEntry<String, String>>[
      if (includeUnset && !options.contains('')) MapEntry('', unsetLabel),
      ...options.map((option) => MapEntry(option, _labelFor(option))),
    ];
    final fallbackValue = entries.isEmpty ? '' : entries.first.key;
    final currentValue = entries.any((e) => e.key == value)
        ? value
        : fallbackValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        labelWidget ??
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
        const SizedBox(height: 6),
        ShadSelect<String>(
          key: ValueKey('$label/$currentValue/${entries.length}'),
          initialValue: currentValue,
          onChanged: (next) => onChanged(next ?? ''),
          selectedOptionBuilder: (context, selected) =>
              Text(_labelFor(selected)),
          options: entries
              .map(
                (entry) => ShadOption<String>(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
              .toList(growable: false),
        ),
      ],
    );
  }

  String _labelFor(String option) {
    if (option.isEmpty) return unsetLabel;
    return optionLabels[option] ?? option;
  }
}
