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

class _AndroidPicker extends ConsumerStatefulWidget {
  const _AndroidPicker();

  @override
  ConsumerState<_AndroidPicker> createState() => _AndroidPickerState();
}

class _AndroidPickerState extends ConsumerState<_AndroidPicker> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installedAsync = ref.watch(installedAppsProvider);
    final selected =
        (ref.watch(blockedAppsProvider).valueOrNull ?? const <String>[])
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
                  final isSelected = selected.contains(a.packageName);
                  return _AppRow(
                    app: a,
                    selected: isSelected,
                    onChanged: (v) {
                      final next = {...selected};
                      if (v) {
                        next.add(a.packageName);
                      } else {
                        next.remove(a.packageName);
                      }
                      ref
                          .read(blockedAppsProvider.notifier)
                          .setPackages(next.toList()..sort());
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AppRow extends StatelessWidget {
  const _AppRow({
    required this.app,
    required this.selected,
    required this.onChanged,
  });

  final InstalledApp app;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: () => onChanged(!selected),
      child: Padding(
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
            Switch(
              value: selected,
              onChanged: onChanged,
            ),
          ],
        ),
      ),
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
              'iOS stores your shielded app selection at the system level. '
              'Tap below to choose which apps to shield.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              icon: const Icon(Icons.apps),
              label: const Text('Pick apps'),
              onPressed: () async {
                final enforcement = ref.read(enforcementServiceProvider);
                final ok = await enforcement.pickAppsNative();
                if (ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Selection saved')),
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
          ],
        ),
      ),
    );
  }
}
