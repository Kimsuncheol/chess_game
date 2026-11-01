import 'game_session.dart';

/// Tunable AI engine parameters kept separate from presentation widgets.
class AiDifficultyConfig {
  const AiDifficultyConfig({
    required this.difficulty,
    required this.skillLevel,
    required this.maxDepth,
    required this.moveTime,
    this.limitStrength = true,
    this.targetElo,
    this.threads = 1,
    this.hashSizeMb = 32,
  });

  final Difficulty difficulty;
  final int skillLevel;
  final int maxDepth;
  final Duration moveTime;
  final bool limitStrength;
  final int? targetElo;
  final int threads;
  final int hashSizeMb;

  static const Map<Difficulty, AiDifficultyConfig> presets = {
    Difficulty.beginner: AiDifficultyConfig(
      difficulty: Difficulty.beginner,
      skillLevel: 3,
      maxDepth: 5,
      moveTime: Duration(milliseconds: 300),
      limitStrength: true,
      targetElo: 1000,
    ),
    Difficulty.intermediate: AiDifficultyConfig(
      difficulty: Difficulty.intermediate,
      skillLevel: 10,
      maxDepth: 10,
      moveTime: Duration(milliseconds: 600),
      limitStrength: true,
      targetElo: 1500,
    ),
    Difficulty.advanced: AiDifficultyConfig(
      difficulty: Difficulty.advanced,
      skillLevel: 18,
      maxDepth: 16,
      moveTime: Duration(milliseconds: 1200),
      limitStrength: false,
      targetElo: 2000,
    ),
  };

  static AiDifficultyConfig forDifficulty(Difficulty difficulty) =>
      presets[difficulty]!;
}

