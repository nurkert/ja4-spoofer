import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/widgets/section_card.dart';
import '../../../core/models/registry_item.dart';

class RegistryEditorCard extends StatelessWidget {
  const RegistryEditorCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.registry,
    required this.selected,
    required this.filterController,
    required this.onToggle,
    required this.onReplaceSelection,
    required this.onReorder,
    required this.onRemove,
  });

  final String title;
  final String subtitle;
  final List<RegistryItem> registry;
  final List<int> selected;
  final TextEditingController filterController;
  final ValueChanged<int> onToggle;
  final ValueChanged<List<int>> onReplaceSelection;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final filter = filterController.text.trim().toLowerCase();
    final filtered = filter.isEmpty
        ? registry
        : registry
              .where((item) => item.label.toLowerCase().contains(filter))
              .toList(growable: false);
    final selectedSet = selected.toSet();
    final selectedById = {for (final item in registry) item.id: item};

    return SectionCard(
      title: title,
      subtitle: subtitle,
      trailing: ShadBadge.outline(
        child: Text('${selected.length} selected / ${registry.length} total'),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < 940;
          final allPane = _AllPane(
            filterController: filterController,
            filtered: filtered,
            selected: selected,
            selectedSet: selectedSet,
            registryHasEntries: registry.isNotEmpty,
            onToggle: onToggle,
            onAddFiltered: () {
              final merged = List<int>.from(selected);
              final mergedSet = merged.toSet();
              for (final item in filtered) {
                if (mergedSet.add(item.id)) merged.add(item.id);
              }
              onReplaceSelection(merged);
            },
            onClear: () => onReplaceSelection(const <int>[]),
          );

          final selectedPane = _SelectedPane(
            selected: selected,
            selectedById: selectedById,
            onReorder: onReorder,
            onRemove: onRemove,
          );

          if (stack) {
            return Column(
              children: [allPane, const SizedBox(height: 12), selectedPane],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: allPane),
              const SizedBox(width: 12),
              Expanded(child: selectedPane),
            ],
          );
        },
      ),
    );
  }
}

/// Available-entries pane.
///
/// Doubles as a "search the registry" widget AND a "type a raw ID directly"
/// widget. The latter is the only way to add entries when the IANA registry
/// is in `disabled` mode (registry is empty). When names are loaded the
/// behaviour is unchanged: type to filter, tick the checkbox to add, and the
/// inline `+` button is a shortcut that adds the typed ID even if it isn't
/// in the registry list.
class _AllPane extends StatefulWidget {
  const _AllPane({
    required this.filterController,
    required this.filtered,
    required this.selected,
    required this.selectedSet,
    required this.registryHasEntries,
    required this.onToggle,
    required this.onAddFiltered,
    required this.onClear,
  });

  final TextEditingController filterController;
  final List<RegistryItem> filtered;
  final List<int> selected;
  final Set<int> selectedSet;
  final bool registryHasEntries;
  final ValueChanged<int> onToggle;
  final VoidCallback onAddFiltered;
  final VoidCallback onClear;

  @override
  State<_AllPane> createState() => _AllPaneState();
}

class _AllPaneState extends State<_AllPane> {
  @override
  void initState() {
    super.initState();
    widget.filterController.addListener(_onFilterChanged);
  }

  @override
  void didUpdateWidget(covariant _AllPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filterController != widget.filterController) {
      oldWidget.filterController.removeListener(_onFilterChanged);
      widget.filterController.addListener(_onFilterChanged);
    }
  }

  @override
  void dispose() {
    widget.filterController.removeListener(_onFilterChanged);
    super.dispose();
  }

  void _onFilterChanged() {
    if (mounted) setState(() {});
  }

  /// Parses the filter text as a 16-bit TLS codepoint. Accepts decimal
  /// (`4865`) and `0xHEX` (`0x1301`). Returns `null` for free-text searches
  /// or out-of-range values.
  int? _parseCodepoint(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return null;
    int? parsed;
    if (t.toLowerCase().startsWith('0x')) {
      parsed = int.tryParse(t.substring(2), radix: 16);
    } else {
      parsed = int.tryParse(t);
    }
    if (parsed == null || parsed < 0 || parsed > 0xFFFF) return null;
    return parsed;
  }

  String _hexOf(int id) =>
      '0x${id.toRadixString(16).padLeft(4, '0').toUpperCase()}';

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final filterText = widget.filterController.text.trim();
    final parsedId = _parseCodepoint(filterText);
    final alreadySelected =
        parsedId != null && widget.selectedSet.contains(parsedId);
    final canAddById = parsedId != null && !alreadySelected;

    final addTooltip = parsedId == null
        ? 'Type a decimal ID or 0xHEX to add directly'
        : alreadySelected
        ? 'ID ${_hexOf(parsedId)} is already selected'
        : 'Add ${_hexOf(parsedId)} directly';

    final filterHint = widget.registryHasEntries
        ? 'Filter — name, decimal or 0xHEX'
        : 'Type ID (e.g. 4865) or 0x1301 and click +';

    return _PaneFrame(
      title: 'Available entries',
      actions: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: widget.filtered.isEmpty || !widget.registryHasEntries
                ? null
                : widget.onAddFiltered,
            child: const Text('Add filtered'),
          ),
          const SizedBox(width: 8),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: widget.selected.isEmpty ? null : widget.onClear,
            child: const Text('Clear'),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Filter / Add',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: ShadInput(
                  controller: widget.filterController,
                  placeholder: Text(filterHint),
                  onSubmitted: canAddById
                      ? (_) => widget.onToggle(parsedId)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: addTooltip,
                child: ShadButton(
                  size: ShadButtonSize.sm,
                  onPressed: canAddById
                      ? () => widget.onToggle(parsedId)
                      : null,
                  leading: const Icon(LucideIcons.plus, size: 12),
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: widget.filtered.isEmpty
                ? _emptyState(theme, filterText)
                : ListView.builder(
                    itemCount: widget.filtered.length,
                    itemBuilder: (context, index) {
                      final item = widget.filtered[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: ShadCheckbox(
                          value: widget.selectedSet.contains(item.id),
                          onChanged: (_) => widget.onToggle(item.id),
                          label: Text(item.label),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState(ShadThemeData theme, String filterText) {
    final String message;
    if (!widget.registryHasEntries) {
      message =
          'IANA name resolution is disabled in Settings.\n'
          'Type a decimal ID (e.g. 4865) or 0xHEX (e.g. 0x1301) above '
          'and click + to add it directly.';
    } else if (filterText.isEmpty) {
      message = 'Loading registry…';
    } else {
      message =
          'No registry entries match "$filterText".\n'
          'If it is a valid TLS codepoint, click + to add it directly.';
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
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

class _SelectedPane extends StatefulWidget {
  const _SelectedPane({
    required this.selected,
    required this.selectedById,
    required this.onReorder,
    required this.onRemove,
  });

  final List<int> selected;
  final Map<int, RegistryItem> selectedById;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<int> onRemove;

  @override
  State<_SelectedPane> createState() => _SelectedPaneState();
}

class _SelectedPaneState extends State<_SelectedPane> {
  // Reordering is mostly relevant for JA4_r and `extension_mode=exact`
  // wire authenticity, not for the JA4 hash itself (which sorts before
  // hashing). Hide it behind a toggle so the standard view stays calm.
  bool _reorderEnabled = false;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return _PaneFrame(
      title: 'Selected',
      actions: ShadButton.outline(
        size: ShadButtonSize.sm,
        onPressed: widget.selected.isEmpty
            ? null
            : () => setState(() => _reorderEnabled = !_reorderEnabled),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _reorderEnabled ? LucideIcons.check : LucideIcons.arrowUpDown,
              size: 12,
            ),
            const SizedBox(width: 6),
            Text(_reorderEnabled ? 'Done reordering' : 'Reorder'),
          ],
        ),
      ),
      child: widget.selected.isEmpty
          ? const Center(
              child: Text(
                'No entries selected yet.',
                style: TextStyle(fontSize: 12),
              ),
            )
          : _reorderEnabled
          ? ReorderableListView.builder(
              buildDefaultDragHandles: false,
              onReorder: widget.onReorder,
              itemCount: widget.selected.length,
              itemBuilder: (context, index) {
                return _SelectedRow(
                  key: ValueKey(widget.selected[index]),
                  index: index,
                  id: widget.selected[index],
                  item: widget.selectedById[widget.selected[index]],
                  reorderable: true,
                  onRemove: () => widget.onRemove(index),
                  mutedColor: theme.colorScheme.mutedForeground,
                );
              },
            )
          : ListView.builder(
              itemCount: widget.selected.length,
              itemBuilder: (context, index) {
                return _SelectedRow(
                  index: index,
                  id: widget.selected[index],
                  item: widget.selectedById[widget.selected[index]],
                  reorderable: false,
                  onRemove: () => widget.onRemove(index),
                  mutedColor: theme.colorScheme.mutedForeground,
                );
              },
            ),
    );
  }
}

class _SelectedRow extends StatelessWidget {
  const _SelectedRow({
    super.key,
    required this.index,
    required this.id,
    required this.item,
    required this.reorderable,
    required this.onRemove,
    required this.mutedColor,
  });

  final int index;
  final int id;
  final RegistryItem? item;
  final bool reorderable;
  final VoidCallback onRemove;
  final Color mutedColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ShadCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            if (reorderable)
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    LucideIcons.gripVertical,
                    size: 14,
                    color: mutedColor,
                  ),
                ),
              ),
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item?.label ?? _hexLabel(id),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            ShadButton.destructive(
              size: ShadButtonSize.sm,
              onPressed: onRemove,
              child: const Text('Remove'),
            ),
          ],
        ),
      ),
    );
  }

  String _hexLabel(int id) {
    final hex = '0x${id.toRadixString(16).padLeft(4, '0').toUpperCase()}';
    return '$id  $hex';
  }
}

class _PaneFrame extends StatelessWidget {
  const _PaneFrame({required this.title, required this.child, this.actions});

  final String title;
  final Widget child;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    return ShadCard(
      height: 390,
      padding: const EdgeInsets.all(12),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
          ?actions,
        ],
      ),
      child: Padding(padding: const EdgeInsets.only(top: 10), child: child),
    );
  }
}
