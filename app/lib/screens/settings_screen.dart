import 'dart:io';

import 'package:flutter/material.dart';

import '../state/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool? _hasPermissions;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  Future<void> _refresh() async {
    final state = AppStateScope.of(context);
    try {
      final ok = await state.enforcement.hasPermissions();
      if (mounted) setState(() => _hasPermissions = ok);
    } catch (_) {
      if (mounted) setState(() => _hasPermissions = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = AppStateScope.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Platform.isIOS
                      ? 'Screen Time authorization'
                      : 'Usage access & accessibility',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  Platform.isIOS
                      ? 'Required to shield apps via FamilyControls. '
                          'Will prompt the system dialog. Requires the '
                          '`com.apple.developer.family-controls` entitlement.'
                      : 'Grant Usage Access AND enable the accessibility '
                          'service in Android Settings so the app can detect '
                          'and close blocked apps.',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(
                      _hasPermissions == true
                          ? Icons.check_circle
                          : Icons.error_outline,
                      color: _hasPermissions == true
                          ? Colors.green
                          : Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(_hasPermissions == true
                        ? 'Granted'
                        : 'Not granted'),
                    const Spacer(),
                    FilledButton(
                      onPressed: () async {
                        await state.enforcement.requestPermissions();
                        await _refresh();
                      },
                      child: const Text('Grant'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
