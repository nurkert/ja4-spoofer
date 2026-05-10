import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/widgets/safe_network_icon.dart';
import '../../../app/widgets/section_card.dart';
import '../../../core/models/fingerprint_profile.dart';
import '../../configurator/configurator_controller.dart';
import '../quick_launch_controller.dart';

class ProfileSelectorCard extends StatelessWidget {
  const ProfileSelectorCard({
    super.key,
    required this.controller,
    required this.configuratorController,
    required this.onNavigateToConfigurator,
  });

  final QuickLaunchController controller;
  final ConfiguratorController configuratorController;
  final void Function([FingerprintProfile? profile]) onNavigateToConfigurator;

  @override
  Widget build(BuildContext context) {
    final ctrl = controller;
    final isSelectedSection =
        ctrl.selectedSection == QuickLaunchSection.profile;

    return SectionCard(
      title: 'Profile',
      subtitle:
          'Select a TLS fingerprint profile. Changes sync to Configurator.',
      isSelected: isSelectedSection,
      onTap: () => ctrl.selectSection(QuickLaunchSection.profile),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ctrl.profilesLoading)
            const Center(child: CircularProgressIndicator())
          else if (ctrl.profiles.isEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'No profiles saved yet.',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 8),
                ShadButton.outline(
                  onPressed: () => onNavigateToConfigurator(),
                  child: const Text('Create in Configurator'),
                ),
              ],
            )
          else ...[
            // Profile list
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 280),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: ctrl.profiles.length,
                itemBuilder: (context, index) {
                  final profile = ctrl.profiles[index];
                  final isSelected =
                      ctrl.selectedProfile?.profileId == profile.profileId;
                  return _ProfileListItem(
                    profile: profile,
                    isSelected: isSelected,
                    isDirty: isSelected && configuratorController.isDirty,
                    onTap: () => ctrl.selectProfile(profile),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            ShadButton.ghost(
              onPressed: () => onNavigateToConfigurator(),
              size: ShadButtonSize.sm,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.slidersHorizontal, size: 14),
                  SizedBox(width: 6),
                  Text('Edit in Configurator'),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ProfileListItem extends StatelessWidget {
  const _ProfileListItem({
    required this.profile,
    required this.isSelected,
    required this.onTap,
    this.isDirty = false,
  });

  final FingerprintProfile profile;
  final bool isSelected;
  final bool isDirty;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? theme.colorScheme.accent : null,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? theme.colorScheme.border : Colors.transparent,
          ),
        ),
        child: Row(
          children: [
            if (profile.metadata.iconUrl != null) ...[
              SafeNetworkIcon(url: profile.metadata.iconUrl, size: 24),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          profile.metadata.name,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isDirty) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (profile.metadata.version != null)
                    Text(
                      profile.metadata.version!,
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                ],
              ),
            ),
            if (profile.isBuiltIn)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Icon(
                  LucideIcons.lock,
                  size: 12,
                  color: theme.colorScheme.mutedForeground,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
