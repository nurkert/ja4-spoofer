import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import '../../../app/widgets/section_card.dart';
import '../../../app/widgets/terminal_box.dart';

class CommandConsoleCard extends StatefulWidget {
  const CommandConsoleCard({
    super.key,
    required this.commandPreview,
    required this.status,
    required this.onCopyCommand,
    required this.onNavigateToQuickLaunch,
  });

  final String commandPreview;
  final String status;
  final VoidCallback onCopyCommand;
  final VoidCallback onNavigateToQuickLaunch;

  @override
  State<CommandConsoleCard> createState() => _CommandConsoleCardState();
}

class _CommandConsoleCardState extends State<CommandConsoleCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return SectionCard(
      title: 'Command Preview',
      subtitle: 'Generated launch command based on Settings + Configurator.',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ShadBadge.secondary(child: Text(widget.status)),
          const SizedBox(width: 8),
          ShadButton.ghost(
            size: ShadButtonSize.sm,
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Icon(
              _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
              size: 16,
            ),
          ),
        ],
      ),
      child: AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: _expanded ? _buildContent() : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            ShadButton(
              onPressed: widget.onNavigateToQuickLaunch,
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(LucideIcons.zap, size: 14),
                  SizedBox(width: 6),
                  Text('Go to Launch'),
                ],
              ),
            ),
            ShadButton.outline(
              onPressed: () {
                widget.onCopyCommand();
                ShadSonner.of(context).show(
                  const ShadToast(
                    description: Text('Command copied to clipboard'),
                  ),
                );
              },
              child: const Text('Copy Command'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TerminalBox(text: widget.commandPreview, height: 200),
      ],
    );
  }
}
