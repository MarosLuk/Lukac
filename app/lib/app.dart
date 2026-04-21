import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'screens/home_screen.dart';
import 'state/providers.dart';
import 'theme.dart';

class TimeRewardsApp extends ConsumerWidget {
  const TimeRewardsApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Bootstrap the side-effect provider that keeps the native shield in sync
    // with ledger + blocked-apps changes. Watching at the app root keeps it
    // alive for the lifetime of the ProviderScope.
    ref.watch(shieldSyncProvider);

    return MaterialApp(
      title: 'Time Rewards',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: const HomeScreen(),
    );
  }
}
