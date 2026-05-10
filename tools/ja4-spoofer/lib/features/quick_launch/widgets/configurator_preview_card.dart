import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/widgets/section_card.dart';
import '../../configurator/configurator_controller.dart';
import '../quick_launch_controller.dart';

/// Read-only summary of the current Configurator TLS state.
class ConfiguratorPreviewCard extends StatelessWidget {
  const ConfiguratorPreviewCard({
    super.key,
    required this.controller,
    required this.quickLaunchController,
    required this.onOpenConfigurator,
  });

  final ConfiguratorController controller;
  final QuickLaunchController quickLaunchController;
  final VoidCallback onOpenConfigurator;

  @override
  Widget build(BuildContext context) {
    final isSelected =
        quickLaunchController.selectedSection ==
        QuickLaunchSection.tlsConfiguration;

    return SectionCard(
      title: 'TLS Configuration',
      subtitle: 'Live preview of the current Configurator state.',
      isSelected: isSelected,
      onTap: () => quickLaunchController.selectSection(
        QuickLaunchSection.tlsConfiguration,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Row(
            'TLS Version',
            '${controller.tlsMin} \u2013 ${controller.tlsMax}',
          ),
          _Row(
            'SNI Mode',
            controller.sniMode.isEmpty ? '(unset)' : controller.sniMode,
          ),
          _Row('Ciphers', '${controller.selectedCiphers.length} selected'),
          _Row(
            'Extensions',
            '${controller.selectedExtensions.length} selected',
          ),
          _Row(
            'Signatures',
            '${controller.selectedSignatures.length} selected',
          ),
          _Row(
            'ALPN',
            controller.selectedAlpn.isEmpty
                ? '(none)'
                : controller.selectedAlpn.join(', '),
          ),
          if (controller.isDirty)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: ShadBadge.secondary(child: Text('Unsaved changes')),
            ),
          const SizedBox(height: 10),
          ShadButton.outline(
            onPressed: () {
              quickLaunchController.selectSection(
                QuickLaunchSection.tlsConfiguration,
              );
              onOpenConfigurator();
            },
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.slidersHorizontal, size: 14),
                SizedBox(width: 6),
                Text('Open Configurator'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 12, fontFamily: 'Geist Mono'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
