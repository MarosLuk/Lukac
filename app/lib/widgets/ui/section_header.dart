import 'package:flutter/material.dart';

/// Small, left-aligned header used above lists and cards. Muted foreground,
/// tightened tracking. Consistent 24/8 vertical spacing.
class SectionHeader extends StatelessWidget {
  const SectionHeader(
    this.label, {
    super.key,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(24, 24, 24, 8),
  });

  final String label;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}
