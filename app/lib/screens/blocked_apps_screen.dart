import 'dart:io';

import 'package:flutter/material.dart';

import '../services/enforcement_service.dart';
import '../state/app_state.dart';

class BlockedAppsScreen extends StatefulWidget {
  const BlockedAppsScreen({super.key});

  @override
  State<BlockedAppsScreen> createState() => _BlockedAppsScreenState();
}

class _BlockedAppsScreenState extends State<BlockedAppsScreen> {
  Future<List<InstalledApp>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Platform.isAndroid && _future == null) {
      _future = AppStateScope.of(context).enforcement.listInstalledApps();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (Platform.isIOS) return _IosPicker();
    return _AndroidPicker(future: _future!);
  }
}

class _AndroidPicker extends StatelessWidget {
  const _AndroidPicker({required this.future});
  final Future<List<InstalledApp>> future;

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    return FutureBuilder<List<InstalledApp>>(
      future: future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Could not list apps. Make sure permissions are granted in Settings.\n\n${snap.error}',
            ),
          );
        }
        final apps = snap.data ?? const [];
        final selected = state.blockedApps.toSet();
        return ListView(
          children: [
            for (final a in apps)
              CheckboxListTile(
                title: Text(a.label),
                subtitle: Text(a.packageName),
                value: selected.contains(a.packageName),
                onChanged: (v) {
                  final next = {...selected};
                  if (v == true) {
                    next.add(a.packageName);
                  } else {
                    next.remove(a.packageName);
                  }
                  state.setBlockedApps(next.toList()..sort());
                },
              ),
          ],
        );
      },
    );
  }
}

class _IosPicker extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'iOS uses the Family Activity Picker. Tap below to choose '
              'which apps to shield. Selection is stored by the system.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.apps),
              label: const Text('Pick apps'),
              onPressed: () async {
                final ok = await state.enforcement.pickAppsNative();
                if (ok && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Selection saved')),
                  );
                  // Trigger a re-sync with whatever the OS now holds.
                  await state.setBlockedApps(state.blockedApps);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
