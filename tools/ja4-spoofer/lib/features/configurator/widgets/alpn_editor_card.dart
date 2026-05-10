import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/widgets/labeled_fields.dart';
import '../../../app/widgets/section_card.dart';

class AlpnEditorCard extends StatelessWidget {
  const AlpnEditorCard({
    super.key,
    required this.available,
    required this.selected,
    required this.filterController,
    required this.onToggle,
    required this.onReplaceSelection,
    required this.onReorder,
    required this.onRemove,
  });

  final List<String> available;
  final List<String> selected;
  final TextEditingController filterController;
  final ValueChanged<String> onToggle;
  final ValueChanged<List<String>> onReplaceSelection;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final filter = filterController.text.trim().toLowerCase();
    final filtered = filter.isEmpty
        ? available
        : available
              .where((value) => value.toLowerCase().contains(filter))
              .toList(growable: false);
    final selectedSet = selected.toSet();

    return SectionCard(
      title: 'ALPN Order',
      subtitle: 'Select and reorder ALPN protocol IDs used by NSS.',
      trailing: ShadBadge.outline(
        child: Text('${selected.length} selected / ${available.length} total'),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stack = constraints.maxWidth < 780;
          final left = _AllPane(
            filterController: filterController,
            filtered: filtered,
            selectedSet: selectedSet,
            onToggle: onToggle,
            onAddFiltered: () {
              final merged = List<String>.from(selected);
              final mergedSet = merged.toSet();
              for (final item in filtered) {
                if (mergedSet.add(item)) merged.add(item);
              }
              onReplaceSelection(merged);
            },
            onClear: () => onReplaceSelection(const <String>[]),
          );

          final right = _SelectedPane(
            selected: selected,
            onReorder: onReorder,
            onRemove: onRemove,
          );

          if (stack) {
            return Column(children: [left, const SizedBox(height: 12), right]);
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 12),
              Expanded(child: right),
            ],
          );
        },
      ),
    );
  }
}

class _AllPane extends StatelessWidget {
  const _AllPane({
    required this.filterController,
    required this.filtered,
    required this.selectedSet,
    required this.onToggle,
    required this.onAddFiltered,
    required this.onClear,
  });

  final TextEditingController filterController;
  final List<String> filtered;
  final Set<String> selectedSet;
  final ValueChanged<String> onToggle;
  final VoidCallback onAddFiltered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return _PaneFrame(
      title: 'Available protocols',
      actions: Row(
        children: [
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: filtered.isEmpty ? null : onAddFiltered,
            child: const Text('Add filtered'),
          ),
          const SizedBox(width: 8),
          ShadButton.outline(
            size: ShadButtonSize.sm,
            onPressed: selectedSet.isEmpty ? null : onClear,
            child: const Text('Clear'),
          ),
        ],
      ),
      child: Column(
        children: [
          LabeledInputField(
            label: 'Filter',
            controller: filterController,
            hint: 'h2, http/1.1, ...',
          ),
          const SizedBox(height: 10),
          Expanded(
            child: ListView.builder(
              itemCount: filtered.length,
              itemBuilder: (context, index) {
                final item = filtered[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: ShadCheckbox(
                    value: selectedSet.contains(item),
                    onChanged: (_) => onToggle(item),
                    label: Text(item),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedPane extends StatelessWidget {
  const _SelectedPane({
    required this.selected,
    required this.onReorder,
    required this.onRemove,
  });

  final List<String> selected;
  final void Function(int oldIndex, int newIndex) onReorder;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    return _PaneFrame(
      title: 'Selected order',
      child: selected.isEmpty
          ? const Center(
              child: Text(
                'No ALPN values selected yet.',
                style: TextStyle(fontSize: 12),
              ),
            )
          : ReorderableListView.builder(
              buildDefaultDragHandles: false,
              onReorder: onReorder,
              itemCount: selected.length,
              itemBuilder: (context, index) {
                final value = selected[index];
                return Padding(
                  key: ValueKey(value),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ShadCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        ReorderableDragStartListener(
                          index: index,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              LucideIcons.gripVertical,
                              size: 14,
                              color: theme.colorScheme.mutedForeground,
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
                        Expanded(child: Text(value)),
                        const SizedBox(width: 8),
                        ShadButton.destructive(
                          size: ShadButtonSize.sm,
                          onPressed: () => onRemove(index),
                          child: const Text('Remove'),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
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
      height: 360,
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
