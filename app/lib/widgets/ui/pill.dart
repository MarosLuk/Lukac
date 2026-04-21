import 'package:flutter/material.dart';

/// A small, rounded pill used for status + accent labels. Thin border,
/// transparent background by default, compact padding.
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.icon,
    this.foreground,
    this.background,
    this.border,
  });

  final String label;
  final IconData? icon;
  final Color? foreground;
  final Color? background;
  final Color? border;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fg = foreground ?? theme.colorScheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: background ?? Colors.transparent,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: border ?? theme.colorScheme.outlineVariant,
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}
