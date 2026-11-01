import 'package:chess_game/app/app_dependencies.dart';
import 'package:chess_game/app/chess_app.dart';
import 'package:chess_game/features/game/domain/game_session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<AppDependencies> openSetupScreen(WidgetTester tester) async {
  final dependencies = AppDependencies.placeholder();
  await tester.pumpWidget(
    ChessApp(
      key: UniqueKey(),
      dependencies: dependencies,
      initialLocation: '/setup',
    ),
  );
  await tester.pumpAndSettle();
  return dependencies;
}

Future<void> tapOption(WidgetTester tester, String label) async {
  final target = find.text(label);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'renders visible selectable cards for colors and difficulties without dropdowns',
    (tester) async {
      await openSetupScreen(tester);

      expect(find.byType(DropdownButton), findsNothing);
      expect(find.byType(DropdownMenu), findsNothing);

      for (final color in PlayerColor.values) {
        expect(find.text(color.label), findsOneWidget);
        expect(find.text(color.description), findsOneWidget);
        expect(
          find.byKey(ValueKey('color-option-${color.name}')),
          findsOneWidget,
        );
      }

      for (final difficulty in Difficulty.values) {
        expect(find.text(difficulty.label), findsOneWidget);
        expect(find.text(difficulty.description), findsOneWidget);
        expect(
          find.byKey(ValueKey('difficulty-option-${difficulty.name}')),
          findsOneWidget,
        );
      }

      expect(find.text('Start Game'), findsOneWidget);
    },
  );

  testWidgets(
    'selecting Random resolves to a concrete player color when Start Game is pressed',
    (tester) async {
      final dependencies = await openSetupScreen(tester);

      await tapOption(tester, 'Random');
      await tapOption(tester, 'Beginner');
      await tapOption(tester, 'Start Game');

      final session = dependencies.game.activeGame;
      expect(session, isNotNull);
      expect(session!.configuration.color.isConcrete, isTrue);
      expect(
        session.configuration.color,
        isIn([PlayerColor.white, PlayerColor.black]),
      );
      expect(session.configuration.difficulty, Difficulty.beginner);

      expect(find.text('The board'), findsOneWidget);
      expect(
        find.textContaining(
          '${session.configuration.color.label} pieces · Beginner opponent',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'pressing Start Game creates a session and navigates to the Game screen with selected options',
    (tester) async {
      final dependencies = await openSetupScreen(tester);

      await tapOption(tester, 'Black');
      await tapOption(tester, 'Advanced');
      await tapOption(tester, 'Start Game');

      final session = dependencies.game.activeGame;
      expect(session, isNotNull);
      expect(session!.configuration.color, PlayerColor.black);
      expect(session.configuration.difficulty, Difficulty.advanced);
      expect(dependencies.game.games, hasLength(1));

      expect(find.text('The board'), findsOneWidget);
      expect(
        find.textContaining('Black pieces · Advanced opponent'),
        findsOneWidget,
      );
    },
  );

  test(
    'AI configuration presets are separated from UI and scale across difficulties',
    () {
      final beginner = Difficulty.beginner.aiConfig;
      final intermediate = Difficulty.intermediate.aiConfig;
      final advanced = Difficulty.advanced.aiConfig;

      expect(beginner.skillLevel, lessThan(intermediate.skillLevel));
      expect(intermediate.skillLevel, lessThan(advanced.skillLevel));

      expect(beginner.maxDepth, lessThan(intermediate.maxDepth));
      expect(intermediate.maxDepth, lessThan(advanced.maxDepth));

      expect(beginner.moveTime, lessThan(intermediate.moveTime));
      expect(intermediate.moveTime, lessThan(advanced.moveTime));
    },
  );
}

