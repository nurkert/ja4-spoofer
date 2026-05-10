import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// Shared section wrapper to keep card styling and layout consistent.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding,
    this.isSelected = false,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry? padding;
  final bool isSelected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final borderRadius = BorderRadius.circular(14);
    final cardPadding = padding ?? const EdgeInsets.all(20);
    final borderColor = isSelected
        ? theme.colorScheme.ring.withValues(alpha: 0.32)
        : theme.colorScheme.border.withValues(alpha: 0.72);
    final backgroundColor = isSelected
        ? theme.colorScheme.accent.withValues(alpha: 0.1)
        : theme.colorScheme.card;
    final titleColor = isSelected
        ? theme.colorScheme.foreground
        : theme.colorScheme.foreground.withValues(alpha: 0.92);
    final subtitleColor = isSelected
        ? theme.colorScheme.mutedForeground
        : theme.colorScheme.mutedForeground.withValues(alpha: 0.92);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          color: backgroundColor,
          border: Border.all(color: borderColor, width: isSelected ? 1.2 : 1),
        ),
        child: ClipRRect(
          borderRadius: borderRadius,
          child: Stack(
            children: [
              if (isSelected)
                Positioned(
                  left: -1,
                  top: -1,
                  bottom: -1,
                  child: Container(
                    width: 5,
                    color: theme.colorScheme.ring.withValues(alpha: 0.82),
                  ),
                ),
              Padding(
                padding: cardPadding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              color: titleColor,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (trailing != null) ...[
                          const SizedBox(width: 8),
                          trailing!,
                        ],
                      ],
                    ),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          subtitle!,
                          style: TextStyle(fontSize: 13, color: subtitleColor),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: child,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
