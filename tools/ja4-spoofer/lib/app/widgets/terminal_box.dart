import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// A themed, read-only terminal/code output box.
///
/// Adapts to light and dark mode using the shadcn_ui color scheme.
/// Use this everywhere CLI output, command previews, or code snippets
/// are displayed so the style stays consistent across the app.
class TerminalBox extends StatelessWidget {
  const TerminalBox({
    super.key,
    required this.text,
    this.height = 180,
    this.dimTaggedLines = true,
  });

  final String text;
  final double height;
  final bool dimTaggedLines;

  static final RegExp _tagPrefix = RegExp(r'^\[[A-Za-z0-9_-]+\]');

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Subtle surface tint that blends with shadcn stone palette.
    final bgColor = isDark
        ? theme.colorScheme.card.withValues(alpha: 0.6)
        : theme.colorScheme.muted.withValues(alpha: 0.5);

    final textColor = isDark
        ? theme.colorScheme.cardForeground
        : theme.colorScheme.foreground;
    final metaColor = theme.colorScheme.mutedForeground.withValues(alpha: 0.86);

    final borderColor = theme.colorScheme.border;
    final baseStyle = TextStyle(
      fontSize: 12,
      height: 1.35,
      fontFamily: 'Geist Mono',
      color: textColor,
    );
    final metaStyle = baseStyle.copyWith(color: metaColor);

    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: bgColor,
        border: Border.all(color: borderColor, width: 0.5),
      ),
      child: SingleChildScrollView(
        child: SelectableText.rich(
          TextSpan(
            style: baseStyle,
            children: _styledSpans(
              text: text,
              baseStyle: baseStyle,
              metaStyle: metaStyle,
              dimTaggedLines: dimTaggedLines,
            ),
          ),
        ),
      ),
    );
  }

  static List<InlineSpan> _styledSpans({
    required String text,
    required TextStyle baseStyle,
    required TextStyle metaStyle,
    required bool dimTaggedLines,
  }) {
    final lines = text.split('\n');
    final spans = <InlineSpan>[];
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final style = dimTaggedLines && _tagPrefix.hasMatch(line)
          ? metaStyle
          : baseStyle;

      spans.add(TextSpan(text: line, style: style));
      if (i != lines.length - 1) {
        spans.add(TextSpan(text: '\n', style: baseStyle));
      }
    }
    return spans;
  }
}
