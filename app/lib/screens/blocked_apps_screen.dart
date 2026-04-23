import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/enforcement_service.dart';
import '../state/providers.dart';

class BlockedAppsScreen extends ConsumerWidget {
  const BlockedAppsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (Platform.isIOS) return const _IosPicker();
    if (Platform.isAndroid) return const _AndroidPicker();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          'App shielding is only supported on Android and iOS.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

/// Which section a given row is currently bucketed into. An app belongs to
/// exactly one of these; the two checkboxes per row are mutually exclusive.
enum _Bucket { none, blocked, allowed }

class _AndroidPicker extends ConsumerStatefulWidget {
  const _AndroidPicker();

  @override
  ConsumerState<_AndroidPicker> createState() => _AndroidPickerState();
}

class _AndroidPickerState extends ConsumerState<_AndroidPicker>
    with WidgetsBindingObserver {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';
  bool _dialogShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _ensurePermissionsOrPrompt());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(permissionStatusProvider);
      _ensurePermissionsOrPrompt();
    }
  }

  Future<void> _ensurePermissionsOrPrompt() async {
    if (!mounted || _dialogShown) return;
    final enforcement = ref.read(enforcementServiceProvider);
    final usage = await enforcement.hasUsageAccess();
    final accessibility = await enforcement.hasAccessibilityAccess();
    if (!mounted || (usage && accessibility)) return;

    _dialogShown = true;
    if (!usage) {
      await _showPermissionStep(
        stepLabel: 'Step 1 of 2',
        title: 'Enable Usage Access',
        bullets: const [
          'On the next screen, scroll the list and tap Time Rewards.',
          'Turn the "Permit usage access" toggle ON.',
          'Press Back to return here — Time Rewards will prompt for step 2.',
        ],
        why:
            'Usage Access lets Time Rewards see which app is in the '
            'foreground so the shield can enforce the allow-list.',
        primaryLabel: 'Open Usage Access',
        onPrimary: enforcement.openUsageAccessSettings,
      );
    } else if (!accessibility) {
      await _showPermissionStep(
        stepLabel: 'Step 2 of 2',
        title: 'Enable the Accessibility service',
        bullets: const [
          'On the next screen, find "Installed apps" (or "Downloaded services" '
              'on some devices).',
          'Tap Time Rewards.',
          'Turn the toggle ON and tap Allow on the confirmation dialog.',
          'Press Back to return here.',
        ],
        why:
            'The accessibility service is what actually sends you back HOME '
            'when you open an app that is not on the allow-list.',
        primaryLabel: 'Open Accessibility settings',
        onPrimary: enforcement.openAccessibilitySettings,
      );
    }
    _dialogShown = false;
  }

  Future<void> _showPermissionStep({
    required String stepLabel,
    required String title,
    required List<String> bullets,
    required String why,
    required String primaryLabel,
    required Future<void> Function() onPrimary,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  stepLabel,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                for (final line in bullets) ...[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('•  '),
                      Expanded(child: Text(line)),
                    ],
                  ),
                  const SizedBox(height: 6),
                ],
                const SizedBox(height: 6),
                Text(
                  why,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  'Android does not allow apps to grant this permission '
                  'programmatically — it has to be toggled manually.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await onPrimary();
              },
              child: Text(primaryLabel),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installedAsync = ref.watch(installedAppsProvider);
    final blocked =
        (ref.watch(blockedAppsProvider).valueOrNull ?? const <String>[])
            .toSet();
    final allowed =
        (ref.watch(allowedAppsProvider).valueOrNull ?? const <String>[])
            .toSet();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            decoration: InputDecoration(
              hintText: 'Search apps',
              prefixIcon: Icon(
                Icons.search,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        _searchCtrl.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Tick an app in one column: Block to shield it, Allow to '
                  'keep it usable even while the shield is on.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Suggest essentials'),
                onPressed: () => _suggestEssentials(context, allowed),
              ),
            ],
          ),
        ),
        Expanded(
          child: installedAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not list apps. Make sure permissions are granted in Settings.\n\n$e',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            data: (apps) {
              final filtered = _query.isEmpty
                  ? apps
                  : apps
                      .where((a) =>
                          a.label.toLowerCase().contains(_query) ||
                          a.packageName.toLowerCase().contains(_query))
                      .toList();
              if (filtered.isEmpty) {
                return Center(
                  child: Text(
                    'No matches',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.only(bottom: 24),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  indent: 24,
                  endIndent: 24,
                ),
                itemBuilder: (_, i) {
                  final a = filtered[i];
                  final bucket = allowed.contains(a.packageName)
                      ? _Bucket.allowed
                      : blocked.contains(a.packageName)
                          ? _Bucket.blocked
                          : _Bucket.none;
                  return _AppRow(
                    app: a,
                    bucket: bucket,
                    onChanged: (next) => _applyBucket(a.packageName, next),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Applies a mutually-exclusive bucket transition for [pkg]: enforces the
  /// "an app can be in neither, in blocked, or in allowed — never both"
  /// invariant by removing from the opposite list on every change.
  void _applyBucket(String pkg, _Bucket next) {
    final blocked = {
      ...(ref.read(blockedAppsProvider).valueOrNull ?? const <String>[])
    };
    final allowed = {
      ...(ref.read(allowedAppsProvider).valueOrNull ?? const <String>[])
    };
    switch (next) {
      case _Bucket.blocked:
        allowed.remove(pkg);
        blocked.add(pkg);
        break;
      case _Bucket.allowed:
        blocked.remove(pkg);
        allowed.add(pkg);
        break;
      case _Bucket.none:
        blocked.remove(pkg);
        allowed.remove(pkg);
        break;
    }
    ref
        .read(blockedAppsProvider.notifier)
        .setPackages(blocked.toList()..sort());
    ref
        .read(allowedAppsProvider.notifier)
        .setPackages(allowed.toList()..sort());
  }

  /// Resolves a small canonical set of essential apps from the platform and
  /// offers to add them to the allow-list. The user must confirm before
  /// anything is persisted.
  Future<void> _suggestEssentials(
    BuildContext context,
    Set<String> currentAllowed,
  ) async {
    final List<InstalledApp> essentials;
    try {
      essentials = await ref.read(essentialAppsProvider.future);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not look up essentials: $e')),
      );
      return;
    }
    if (!context.mounted) return;
    if (essentials.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No essential apps found')),
      );
      return;
    }
    final accept = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Suggested essentials'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'These default system apps will be added to the always-allowed '
              'list so they stay usable while the shield is active:',
            ),
            const SizedBox(height: 12),
            ...essentials.map(
              (e) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• ${e.label}'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (accept != true) return;
    // Merge essentials into the allow-list and remove any of them from the
    // blocked-list to preserve mutual exclusion.
    final blocked = {
      ...(ref.read(blockedAppsProvider).valueOrNull ?? const <String>[])
    };
    final allowed = {...currentAllowed};
    for (final e in essentials) {
      allowed.add(e.packageName);
      blocked.remove(e.packageName);
    }
    await ref
        .read(blockedAppsProvider.notifier)
        .setPackages(blocked.toList()..sort());
    await ref
        .read(allowedAppsProvider.notifier)
        .setPackages(allowed.toList()..sort());
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.bucket,
    required this.onChanged,
  });

  final InstalledApp app;
  final _Bucket bucket;
  final ValueChanged<_Bucket> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10),
            ),
            alignment: Alignment.center,
            child: Text(
              app.label.isEmpty ? '?' : app.label[0].toUpperCase(),
              style: theme.textTheme.titleSmall?.copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  app.label,
                  style: theme.textTheme.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  app.packageName,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          _BucketToggle(
            label: 'Block',
            selected: bucket == _Bucket.blocked,
            onTap: () => onChanged(
              bucket == _Bucket.blocked ? _Bucket.none : _Bucket.blocked,
            ),
          ),
          const SizedBox(width: 8),
          _BucketToggle(
            label: 'Allow',
            selected: bucket == _Bucket.allowed,
            onTap: () => onChanged(
              bucket == _Bucket.allowed ? _Bucket.none : _Bucket.allowed,
            ),
          ),
        ],
      ),
    );
  }
}

class _BucketToggle extends StatelessWidget {
  const _BucketToggle({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      showCheckmark: true,
      visualDensity: VisualDensity.compact,
      selectedColor: cs.primaryContainer,
      labelStyle: theme.textTheme.labelMedium,
    );
  }
}

class _IosPicker extends ConsumerWidget {
  const _IosPicker();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Family Activity Picker',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'iOS stores your shielded and always-allowed selections at the '
              'system level. The allowed selection is subtracted from the '
              'shielded one when the shield is active.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.apps),
              label: const Text('Pick apps to shield'),
              onPressed: () async {
                final enforcement = ref.read(enforcementServiceProvider);
                final ok = await enforcement.pickAppsNative();
                if (ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Shielded selection saved')),
                  );
                  // Trigger a re-sync with whatever the OS now holds.
                  final current =
                      ref.read(blockedAppsProvider).valueOrNull ??
                          const <String>[];
                  await ref
                      .read(blockedAppsProvider.notifier)
                      .setPackages(current);
                }
              },
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              icon: const Icon(Icons.verified_user_outlined),
              label: const Text('Pick always-allowed apps'),
              onPressed: () async {
                final enforcement = ref.read(enforcementServiceProvider);
                final ok = await enforcement.pickAllowedAppsNative();
                if (ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Allowed selection saved')),
                  );
                  // Trigger a re-sync so the bridge's applyShield() runs with
                  // the new allowedSelection subtracted from the shielded set.
                  final current =
                      ref.read(allowedAppsProvider).valueOrNull ??
                          const <String>[];
                  await ref
                      .read(allowedAppsProvider.notifier)
                      .setPackages(current);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
