import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../core/controllers/profile_catalog_controller.dart';
import '../../../core/models/fingerprint_profile.dart';
import '../configurator_controller.dart';

/// Left-pane profile browser: search + grouped list + new-profile footer.
class ProfileBrowserPane extends StatefulWidget {
  const ProfileBrowserPane({
    super.key,
    required this.controller,
    required this.profileCatalogController,
    required this.onProfileSelected,
    required this.onDuplicate,
    required this.onDelete,
    required this.onNewProfile,
  });

  final ConfiguratorController controller;
  final ProfileCatalogController profileCatalogController;
  final void Function(FingerprintProfile profile) onProfileSelected;
  final void Function(FingerprintProfile profile) onDuplicate;
  final void Function(FingerprintProfile profile) onDelete;
  final VoidCallback onNewProfile;

  @override
  State<ProfileBrowserPane> createState() => _ProfileBrowserPaneState();
}

class _ProfileBrowserPaneState extends State<ProfileBrowserPane> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final all = widget.profileCatalogController.profiles;
    final query = _query.toLowerCase();
    final filtered = query.isEmpty
        ? all
        : all
              .where((p) => p.metadata.name.toLowerCase().contains(query))
              .toList(growable: false);

    final builtIns = filtered.where((p) => p.isBuiltIn).toList(growable: false);
    final custom = filtered.where((p) => !p.isBuiltIn).toList(growable: false);

    final activeId = widget.controller.editingProfileId;
    final isNew = activeId == null;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.card,
        border: Border.all(
          color: theme.colorScheme.border.withValues(alpha: 0.72),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Profiles',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.foreground,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${all.length}',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.mutedForeground,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ShadInput(
                  controller: _searchCtrl,
                  placeholder: const Text('Search'),
                  leading: const Padding(
                    padding: EdgeInsets.only(left: 6, right: 4),
                    child: Icon(LucideIcons.search, size: 14),
                  ),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: theme.colorScheme.border.withValues(alpha: 0.5),
          ),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(query: query)
                : ListView(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    children: [
                      if (builtIns.isNotEmpty) ...[
                        _SectionHeader(label: 'Built-in'),
                        for (final p in builtIns)
                          _ProfileRow(
                            profile: p,
                            isActive: !isNew && p.profileId == activeId,
                            isDirty:
                                !isNew &&
                                p.profileId == activeId &&
                                widget.controller.isDirty,
                            onTap: () => widget.onProfileSelected(p),
                            onDuplicate: () => widget.onDuplicate(p),
                            onDelete: null,
                          ),
                        const SizedBox(height: 6),
                      ],
                      if (custom.isNotEmpty) ...[
                        _SectionHeader(label: 'Custom'),
                        for (final p in custom)
                          _ProfileRow(
                            profile: p,
                            isActive: !isNew && p.profileId == activeId,
                            isDirty:
                                !isNew &&
                                p.profileId == activeId &&
                                widget.controller.isDirty,
                            onTap: () => widget.onProfileSelected(p),
                            onDuplicate: () => widget.onDuplicate(p),
                            onDelete: () => widget.onDelete(p),
                          ),
                      ],
                    ],
                  ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: theme.colorScheme.border.withValues(alpha: 0.5),
          ),
          Padding(
            padding: const EdgeInsets.all(10),
            child: SizedBox(
              width: double.infinity,
              child: ShadButton.outline(
                onPressed: widget.onNewProfile,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      LucideIcons.plus,
                      size: 14,
                      color: isNew
                          ? theme.colorScheme.primary
                          : theme.colorScheme.foreground,
                    ),
                    const SizedBox(width: 6),
                    Text(isNew ? 'New profile (active)' : 'New profile'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
          color: theme.colorScheme.mutedForeground,
        ),
      ),
    );
  }
}

class _ProfileRow extends StatefulWidget {
  const _ProfileRow({
    required this.profile,
    required this.isActive,
    required this.isDirty,
    required this.onTap,
    required this.onDuplicate,
    required this.onDelete,
  });

  final FingerprintProfile profile;
  final bool isActive;
  final bool isDirty;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback? onDelete;

  @override
  State<_ProfileRow> createState() => _ProfileRowState();
}

class _ProfileRowState extends State<_ProfileRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final p = widget.profile;
    final showActions = _hover || widget.isActive;

    final Color background;
    if (widget.isActive) {
      background = theme.colorScheme.accent.withValues(alpha: 0.18);
    } else if (_hover) {
      background = theme.colorScheme.accent.withValues(alpha: 0.08);
    } else {
      background = Colors.transparent;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(8),
            border: widget.isActive
                ? Border.all(
                    color: theme.colorScheme.ring.withValues(alpha: 0.45),
                  )
                : null,
          ),
          child: Row(
            children: [
              if (p.isBuiltIn) ...[
                Icon(
                  LucideIcons.lock,
                  size: 11,
                  color: theme.colorScheme.mutedForeground,
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            p.metadata.name,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: widget.isActive
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: theme.colorScheme.foreground,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (widget.isDirty) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: const BoxDecoration(
                              color: Colors.orange,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (p.metadata.version != null &&
                        p.metadata.version!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(
                          'v${p.metadata.version!}',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: theme.colorScheme.mutedForeground,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (showActions) ...[
                _RowAction(
                  icon: LucideIcons.copy,
                  tooltip: 'Duplicate',
                  onTap: widget.onDuplicate,
                ),
                if (widget.onDelete != null)
                  _RowAction(
                    icon: LucideIcons.trash2,
                    tooltip: 'Delete',
                    onTap: widget.onDelete!,
                    danger: true,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RowAction extends StatefulWidget {
  const _RowAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool danger;

  @override
  State<_RowAction> createState() => _RowActionState();
}

class _RowActionState extends State<_RowAction> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final base = widget.danger
        ? theme.colorScheme.destructive
        : theme.colorScheme.foreground;
    final color = _hover ? base : base.withValues(alpha: 0.65);

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 350),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Icon(widget.icon, size: 13, color: color),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.query});

  final String query;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(
          query.isEmpty ? 'No profiles yet.' : 'No matches for "$query".',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.mutedForeground,
          ),
        ),
      ),
    );
  }
}
