import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/widgets/section_card.dart';
import '../configurator_controller.dart';

/// Header card for the active profile in the editor (replaces the old
/// ProfileEditorToolbar). Shows identity + Save action; the
/// "Edit identity" disclosure exposes name/version/icon URL inputs.
class ProfileEditorHeader extends StatefulWidget {
  const ProfileEditorHeader({
    super.key,
    required this.controller,
    required this.onSave,
    required this.onSaveAs,
    required this.onReloadRegistries,
  });

  final ConfiguratorController controller;
  final VoidCallback onSave;
  final VoidCallback onSaveAs;
  final VoidCallback onReloadRegistries;

  @override
  State<ProfileEditorHeader> createState() => _ProfileEditorHeaderState();
}

class _ProfileEditorHeaderState extends State<ProfileEditorHeader> {
  bool _identityExpanded = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final isBuiltIn = c.editingIsBuiltIn;
    final hasProfile = c.editingProfileId != null;
    final name = c.editingMetadata.name;
    final version = c.editingMetadata.version;

    final subtitleParts = <String>[];
    if (version != null && version.isNotEmpty) subtitleParts.add('v$version');
    if (isBuiltIn) {
      subtitleParts.add('Built-in (read-only)');
    } else if (!hasProfile) {
      subtitleParts.add('Unsaved');
    }
    final subtitle = subtitleParts.isEmpty ? null : subtitleParts.join('  •  ');

    return SectionCard(
      title: name,
      subtitle: subtitle,
      trailing: _SaveAction(
        controller: c,
        onSave: widget.onSave,
        onSaveAs: widget.onSaveAs,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Identity disclosure
          _IdentityDisclosure(
            expanded: _identityExpanded,
            isBuiltIn: isBuiltIn,
            controller: c,
            onToggle: () =>
                setState(() => _identityExpanded = !_identityExpanded),
          ),
          const SizedBox(height: 12),
          // Footer: utility actions + status
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ShadButton.outline(
                onPressed: c.randomizeAll,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.dices, size: 14),
                    SizedBox(width: 6),
                    Text('Randomize all'),
                  ],
                ),
              ),
              ShadButton.outline(
                onPressed: widget.onReloadRegistries,
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.refreshCw, size: 14),
                    SizedBox(width: 6),
                    Text('Reload IANA'),
                  ],
                ),
              ),
              if (c.registryLoading)
                const ShadBadge.secondary(child: Text('Registry loading'))
              else
                ShadBadge.secondary(child: Text(c.status)),
            ],
          ),
        ],
      ),
    );
  }
}

class _SaveAction extends StatelessWidget {
  const _SaveAction({
    required this.controller,
    required this.onSave,
    required this.onSaveAs,
  });

  final ConfiguratorController controller;
  final VoidCallback onSave;
  final VoidCallback onSaveAs;

  @override
  Widget build(BuildContext context) {
    final isBuiltIn = controller.editingIsBuiltIn;
    final hasProfile = controller.editingProfileId != null;
    final dirty = controller.isDirty;

    if (isBuiltIn) {
      return ShadButton(
        onPressed: onSaveAs,
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(LucideIcons.copy, size: 14),
            SizedBox(width: 6),
            Text('Save as Copy'),
          ],
        ),
      );
    }

    final canSave = dirty || !hasProfile;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ShadButton(
          onPressed: canSave ? onSave : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(LucideIcons.save, size: 14),
              const SizedBox(width: 6),
              Text(hasProfile ? 'Save' : 'Save profile'),
            ],
          ),
        ),
        const SizedBox(width: 6),
        ShadButton.outline(
          onPressed: onSaveAs,
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(LucideIcons.filePlus, size: 14),
              SizedBox(width: 6),
              Text('Save As'),
            ],
          ),
        ),
      ],
    );
  }
}

class _IdentityDisclosure extends StatelessWidget {
  const _IdentityDisclosure({
    required this.expanded,
    required this.isBuiltIn,
    required this.controller,
    required this.onToggle,
  });

  final bool expanded;
  final bool isBuiltIn;
  final ConfiguratorController controller;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.5),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggle,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    AnimatedRotation(
                      duration: const Duration(milliseconds: 160),
                      turns: expanded ? 0.25 : 0,
                      child: Icon(
                        LucideIcons.chevronRight,
                        size: 14,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Edit identity',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                    if (isBuiltIn) ...[
                      const SizedBox(width: 8),
                      Icon(
                        LucideIcons.lock,
                        size: 11,
                        color: theme.colorScheme.mutedForeground,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Read-only',
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.mutedForeground,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: _IdentityFields(
                controller: controller,
                enabled: !isBuiltIn,
              ),
            ),
        ],
      ),
    );
  }
}

class _IdentityFields extends StatelessWidget {
  const _IdentityFields({required this.controller, required this.enabled});

  final ConfiguratorController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: _Field(
            label: 'Name',
            child: ShadInput(
              key: ValueKey('name-${controller.editingProfileId ?? "new"}'),
              initialValue: controller.editingMetadata.name,
              placeholder: const Text('Profile name'),
              onChanged: controller.setEditingName,
              enabled: enabled,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 1,
          child: _Field(
            label: 'Version',
            child: ShadInput(
              key: ValueKey('ver-${controller.editingProfileId ?? "new"}'),
              initialValue: controller.editingMetadata.version ?? '',
              placeholder: const Text('e.g. 133.0'),
              onChanged: (v) =>
                  controller.setEditingVersion(v.isEmpty ? null : v),
              enabled: enabled,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _Field(
            label: 'Icon URL',
            child: ShadInput(
              key: ValueKey('icon-${controller.editingProfileId ?? "new"}'),
              initialValue: controller.editingMetadata.iconUrl ?? '',
              placeholder: const Text('https://...'),
              onChanged: (v) =>
                  controller.setEditingIconUrl(v.isEmpty ? null : v),
              enabled: enabled,
            ),
          ),
        ),
      ],
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        child,
      ],
    );
  }
}
