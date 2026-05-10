import 'package:flutter/widgets.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

/// A single navigation item in the sidebar.
class NavItem extends StatelessWidget {
  const NavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.route,
    required this.currentRoute,
    required this.onTap,
    this.collapsed = false,
    this.shortcutHint,
  });

  final IconData icon;
  final String label;
  final String route;
  final String currentRoute;
  final VoidCallback onTap;
  final bool collapsed;
  final String? shortcutHint;

  bool get isSelected => currentRoute == route;

  @override
  Widget build(BuildContext context) {
    final theme = ShadTheme.of(context);
    final selectedBg = theme.colorScheme.accent;
    final selectedFg = theme.colorScheme.accentForeground;
    final defaultFg = theme.colorScheme.mutedForeground;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        padding: EdgeInsets.symmetric(
          horizontal: collapsed ? 10 : 12,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          color: isSelected ? selectedBg : null,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRect(
          // The sidebar width animates between collapsed (60) and expanded
          // (220) over 150 ms. The `collapsed` flag flips at frame 0 but
          // AnimatedContainer interpolates width, so during the in-between
          // frames a "non-collapsed" Row would still render Text+Expanded
          // into a 23-px gap and trip the overflow assertion (ClipRect hides
          // it visually but doesn't suppress the assert). LayoutBuilder
          // drives child visibility off the *actual* current width instead.
          child: LayoutBuilder(
            builder: (context, constraints) {
              final hasRoomForLabel = !collapsed && constraints.maxWidth >= 90;
              return Row(
                children: [
                  Icon(
                    icon,
                    size: 18,
                    color: isSelected ? selectedFg : defaultFg,
                  ),
                  if (hasRoomForLabel) ...[
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        label,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected ? selectedFg : defaultFg,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        softWrap: false,
                      ),
                    ),
                    if (shortcutHint != null) ...[
                      const SizedBox(width: 4),
                      Text(
                        shortcutHint!,
                        style: TextStyle(
                          fontSize: 11,
                          color: defaultFg.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
