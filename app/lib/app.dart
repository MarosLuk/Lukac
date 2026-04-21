import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'state/app_state.dart';

class TimeRewardsApp extends StatelessWidget {
  const TimeRewardsApp({super.key, required this.state});

  final AppState state;

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      state: state,
      child: MaterialApp(
        title: 'Time Rewards',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
          useMaterial3: true,
        ),
        home: const HomeScreen(),
      ),
    );
  }
}
