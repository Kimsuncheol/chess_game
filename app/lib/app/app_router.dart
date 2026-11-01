import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/widgets/page_layout.dart';
import '../features/home/presentation/home_screen.dart';
import '../features/game_setup/presentation/game_setup_screen.dart';
import '../features/game/presentation/game_screen.dart';
import '../features/game_result/presentation/game_result_screen.dart';
import '../features/history/presentation/history_screen.dart';
import '../features/settings/presentation/settings_screen.dart';

GoRouter createRouter({String initialLocation = '/'}) => GoRouter(
  initialLocation: initialLocation,
  routes: [
    GoRoute(
      path: '/',
      name: 'home',
      builder: (_, _) => const HomeScreen(),
      routes: [
        GoRoute(
          path: 'setup',
          name: 'setup',
          builder: (_, _) => const GameSetupScreen(),
        ),
        GoRoute(
          path: 'game/:gameId',
          name: 'game',
          builder: (_, state) =>
              GameScreen(gameId: state.pathParameters['gameId']!),
          routes: [
            GoRoute(
              path: 'result',
              name: 'result',
              builder: (_, state) =>
                  GameResultScreen(gameId: state.pathParameters['gameId']!),
            ),
          ],
        ),
        GoRoute(
          path: 'history',
          name: 'history',
          builder: (_, _) => const HistoryScreen(),
        ),
        GoRoute(
          path: 'settings',
          name: 'settings',
          builder: (_, _) => const SettingsScreen(),
        ),
      ],
    ),
  ],
  errorBuilder: (context, state) => PageLayout(
    title: 'Page not found',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeading('Let’s get you back to the board.'),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => context.go('/'),
          child: const Text('Return home'),
        ),
      ],
    ),
  ),
);
