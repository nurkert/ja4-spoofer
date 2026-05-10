import 'package:flutter/material.dart';

import '../../../app/widgets/section_card.dart';
import '../../../app/widgets/terminal_box.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

class LaunchConsoleCard extends StatelessWidget {
  const LaunchConsoleCard({super.key, required this.output, this.onClear});

  final String output;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    if (output.isEmpty) return const SizedBox.shrink();

    return SectionCard(
      title: 'Output',
      trailing: ShadButton.ghost(
        onPressed: onClear,
        size: ShadButtonSize.sm,
        child: const Text('Clear'),
      ),
      child: TerminalBox(text: output, height: 180),
    );
  }
}
