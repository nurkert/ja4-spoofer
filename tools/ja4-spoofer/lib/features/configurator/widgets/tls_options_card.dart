import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/widgets/labeled_fields.dart';
import '../../../app/widgets/section_card.dart';
import '../configurator_controller.dart';

/// ClientHello-shaping options: TLS version range and SNI mode.
///
/// GREASE and CH-extension-permutation toggles are intentionally hidden
/// from the GUI \u2014 JA4 is GREASE-stable per spec and sorts extensions
/// before hashing, so neither toggle affects the JA4 hash this tool
/// targets. The underlying profile fields are still parsed/persisted
/// for backwards compatibility and for power users editing JSON / shell
/// scripts directly.
class TlsOptionsCard extends StatelessWidget {
  const TlsOptionsCard({super.key, required this.controller});

  final ConfiguratorController controller;

  @override
  Widget build(BuildContext context) {
    const unsetLabels = <String, String>{'': '(unset)'};

    return SectionCard(
      title: 'ClientHello Options',
      subtitle:
          'TLS version range and SNI behavior. Hover any label\u2019s '
          'info icon for details.',
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          SizedBox(
            width: 180,
            child: LabeledSelectField(
              label: 'TLS Min',
              labelWidget: const _LabelWithInfo(
                label: 'TLS Min',
                message:
                    'Lowest TLS version the client advertises support for. '
                    'Combined with TLS Max it determines the supported_versions '
                    'extension and feeds the JA4_a TLS-version digit.',
              ),
              value: controller.tlsMin,
              options: ConfiguratorController.tlsVersionOptions,
              onChanged: controller.setTlsMin,
              optionLabels: unsetLabels,
            ),
          ),
          SizedBox(
            width: 180,
            child: LabeledSelectField(
              label: 'TLS Max',
              labelWidget: const _LabelWithInfo(
                label: 'TLS Max',
                message:
                    'Highest TLS version the client advertises support for. '
                    'JA4_a encodes the highest negotiable version (e.g. 1.3 -> "13").',
              ),
              value: controller.tlsMax,
              options: ConfiguratorController.tlsVersionOptions,
              onChanged: controller.setTlsMax,
              optionLabels: unsetLabels,
            ),
          ),
          SizedBox(
            width: 200,
            child: LabeledSelectField(
              label: 'SNI Mode',
              labelWidget: const _LabelWithInfo(
                label: 'SNI Mode',
                message:
                    'Server Name Indication.\n'
                    '\u2022 present \u2014 always send the SNI extension (JA4_a marker "d" for domain).\n'
                    '\u2022 none \u2014 never send SNI (JA4_a marker "i").\n'
                    '\u2022 ip \u2014 omit SNI only when the target is an IP literal.',
              ),
              value: controller.sniMode,
              options: ConfiguratorController.sniModeOptions,
              onChanged: controller.setSniMode,
              optionLabels: unsetLabels,
            ),
          ),
        ],
      ),
    );
  }
}

/// Label + info icon with a hover tooltip. Uses Flutter's built-in
/// [Tooltip] (rather than ShadTooltip) because the trigger here is a
/// non-interactive Row, and Material's Tooltip reliably handles hover
/// + long-press across desktop and touch.
class _LabelWithInfo extends StatelessWidget {
  const _LabelWithInfo({required this.label, required this.message});

  final String label;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: message,
      waitDuration: const Duration(milliseconds: 200),
      preferBelow: true,
      verticalOffset: 18,
      textStyle: const TextStyle(
        fontSize: 12,
        color: Colors.white,
        height: 1.35,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(6),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: MouseRegion(
        cursor: SystemMouseCursors.help,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 4),
            const Icon(LucideIcons.info, size: 12),
          ],
        ),
      ),
    );
  }
}
