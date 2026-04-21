import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/providers.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final permissionsAsync = ref.watch(permissionStatusProvider);
    final granted = permissionsAsync.valueOrNull ?? false;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
      children: [
        Card(
          child: Column(
            children: [
              _PermissionsRow(granted: granted, loading: permissionsAsync.isLoading),
              const Divider(height: 1),
              const _NotificationAccessRow(),
              const Divider(height: 1),
              const _AboutRow(),
            ],
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.shield_outlined, size: 18),
            label: Text(
              granted ? 'Permissions granted' : 'Grant permissions',
            ),
            onPressed: granted
                ? null
                : () async {
                    final enforcement =
                        ref.read(enforcementServiceProvider);
                    await enforcement.requestPermissions();
                    // Refresh the permission status provider.
                    ref.invalidate(permissionStatusProvider);
                  },
          ),
        ),
        const SizedBox(height: 12),
        Text(
          Platform.isIOS
              ? 'iOS requires the `com.apple.developer.family-controls` '
                  'entitlement. The system will prompt once.'
              : 'Android requires Usage Access and the accessibility service '
                  'to detect and close shielded apps.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _PermissionsRow extends StatelessWidget {
  const _PermissionsRow({required this.granted, required this.loading});

  final bool granted;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final label = Platform.isIOS
        ? 'Screen Time authorization'
        : 'Usage access & accessibility';
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(
        granted ? Icons.check_circle_outline : Icons.error_outline,
        color: granted ? cs.primary : cs.onSurfaceVariant,
      ),
      title: Text(label, style: theme.textTheme.bodyLarge),
      subtitle: Text(
        loading
            ? 'Checking…'
            : (granted ? 'Granted' : 'Not granted'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _NotificationAccessRow extends ConsumerWidget {
  const _NotificationAccessRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final grantedAsync = ref.watch(notificationAccessProvider);
    final granted = grantedAsync.valueOrNull ?? false;

    final label = Platform.isIOS ? 'Focus mode' : 'Notification access';
    final subtitle = Platform.isIOS
        ? 'To suppress notifications from shielded apps, enable a Focus '
            'mode that hides their badges.'
        : 'Lets the app hide notifications from shielded apps while the '
            'shield is active.';

    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(
        granted
            ? Icons.notifications_off
            : Icons.notifications_off_outlined,
        color: granted ? cs.primary : cs.onSurfaceVariant,
      ),
      title: Text(label, style: theme.textTheme.bodyLarge),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: cs.onSurfaceVariant,
        ),
      ),
      trailing: TextButton(
        onPressed: () async {
          final enforcement = ref.read(enforcementServiceProvider);
          await enforcement.requestNotificationAccess();
          ref.invalidate(notificationAccessProvider);
        },
        child: const Text('Open Settings'),
      ),
    );
  }
}

class _AboutRow extends StatelessWidget {
  const _AboutRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: Icon(
        Icons.info_outline,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      title: Text('About Time Rewards', style: theme.textTheme.bodyLarge),
      subtitle: Text(
        'Earn screen-time on selected apps by completing tasks.',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
