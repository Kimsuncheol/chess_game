import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_dependencies.dart';
import '../../../core/widgets/page_layout.dart';
import '../application/game_controller.dart';
import '../domain/game_session.dart';
import 'board_preview.dart';

class GameScreen extends StatefulWidget {
  const GameScreen({required this.gameId, super.key});
  final String gameId;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  int _unityViewGeneration = 0;
  bool? _lastKnownFinished;
  bool _navigatingToResult = false;

  void _recreateUnityView() {
    setState(() {
      _unityViewGeneration++;
    });
  }

  void _checkResultTransition(GameSession game) {
    final wasFinished = _lastKnownFinished;
    _lastKnownFinished = game.isFinished;
    if (wasFinished == false && game.isFinished && !_navigatingToResult) {
      _navigatingToResult = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.go('/game/${game.id}/result');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).game;
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final game = controller.find(widget.gameId);
        return PageLayout(
          title: 'The board',
          actions: game == null
              ? null
              : [
                  IconButton(
                    key: const ValueKey('game-menu-button'),
                    tooltip: 'Game menu',
                    onPressed: () => _openGameMenu(context, game),
                    icon: const Icon(Icons.tune_rounded),
                  ),
                ],
          child: game == null
              ? const MissingGame()
              : _buildGameContent(context, controller, game),
        );
      },
    );
  }

  Widget _buildGameContent(
    BuildContext context,
    GameController controller,
    GameSession game,
  ) {
    _checkResultTransition(game);
    final pendingPromotion =
        controller.pendingPromotion?.gameId == game.id
            ? controller.pendingPromotion
            : null;

    final boardColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ContestantIndicator(
          key: const ValueKey('ai-indicator'),
          name: 'AI · ${game.configuration.difficulty.label}',
          colorLabel: 'Playing as ${game.aiColor.label}',
          statusLabel: controller.isAiThinking
              ? 'AI is thinking'
              : (game.isAiTurn && !game.isFinished ? 'AI turn' : 'Waiting'),
          isActive:
              !game.isFinished && (game.isAiTurn || controller.isAiThinking),
          icon: Icons.smart_toy_outlined,
        ),
        const SizedBox(height: 12),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: UnityBoardArea(
              key: ValueKey('unity-view-${game.id}-$_unityViewGeneration'),
              gameId: game.id,
              onRecreateRequested: _recreateUnityView,
            ),
          ),
        ),
        const SizedBox(height: 12),
        _ContestantIndicator(
          key: const ValueKey('player-indicator'),
          name: 'Player (You)',
          colorLabel: 'Playing as ${game.humanColor.label}',
          statusLabel: !game.isFinished && game.isHumanTurn
              ? 'Your turn'
              : 'Waiting',
          isActive: !game.isFinished && game.isHumanTurn,
          icon: Icons.person_outline_rounded,
        ),
      ],
    );

    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionHeading(
          game.isFinished ? 'Session complete.' : 'A fresh position.',
          subtitle:
              '${game.configuration.color.label} pieces · ${game.configuration.difficulty.label} opponent',
        ),
        const SizedBox(height: 20),
        _TurnStatusBanner(controller: controller, game: game),
        if (pendingPromotion != null) ...[
          const SizedBox(height: 20),
          _PromotionSelector(
            promotion: pendingPromotion,
            onSelect: (piece) => controller.selectPromotion(piece),
            onCancel: controller.cancelPromotion,
          ),
        ],
        if (controller.isPaused && !game.isFinished) ...[
          const SizedBox(height: 20),
          Card(
            key: const ValueKey('paused-panel'),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Game paused',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Board input is paused. Resume when you are ready to continue.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => controller.resumeGame(game.id),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Resume game'),
                  ),
                ],
              ),
            ),
          ),
        ],
        const SizedBox(height: 20),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Move list',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (game.moves.isEmpty)
                  const Text('No moves yet. Every good game begins here.')
                else
                  Text(
                    game.moves.join(' · '),
                    key: const ValueKey('move-list-moves'),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            if (!game.isFinished)
              OutlinedButton.icon(
                key: const ValueKey('pause-resume-button'),
                onPressed: controller.busy || controller.isApplyingMove
                    ? null
                    : () => controller.isPaused
                        ? controller.resumeGame(game.id)
                        : controller.pauseGame(game.id),
                icon: Icon(
                  controller.isPaused
                      ? Icons.play_arrow_rounded
                      : Icons.pause_rounded,
                ),
                label: Text(
                  controller.isPaused ? 'Resume game' : 'Pause game',
                ),
              ),
            OutlinedButton.icon(
              key: const ValueKey('restart-game-button'),
              onPressed: controller.busy || controller.isApplyingMove
                  ? null
                  : () => _confirmRestart(context, game),
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Restart game'),
            ),
            OutlinedButton.icon(
              onPressed: controller.renderer.isAvailable
                  ? controller.resetCamera
                  : null,
              icon: const Icon(Icons.center_focus_strong_rounded),
              label: const Text('Reset camera'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('reload-unity-view-button'),
              onPressed: _recreateUnityView,
              icon: const Icon(Icons.view_in_ar_outlined),
              label: const Text('Reload 3D view'),
            ),
            if (!game.isFinished)
              OutlinedButton.icon(
                key: const ValueKey('resign-session-button'),
                onPressed: controller.busy || controller.isApplyingMove
                    ? null
                    : () => _confirmResign(context, game),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Resign session'),
              ),
            if (game.isFinished)
              FilledButton(
                onPressed: () => context.go('/game/${game.id}/result'),
                child: const Text('View result'),
              ),
          ],
        ),
        if (controller.error != null) ErrorNotice(controller.error!),
        const SizedBox(height: 20),
        TextButton(
          onPressed: () => context.go('/'),
          child: const Text('Save session & return home'),
        ),
        const SizedBox(height: 8),
        Text(
          'Session-only storage · Available until you close the app',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 850 &&
            MediaQuery.textScalerOf(context).scale(1) < 1.6;
        return wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 6, child: boardColumn),
                  const SizedBox(width: 32),
                  Expanded(flex: 5, child: details),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  boardColumn,
                  const SizedBox(height: 28),
                  details,
                ],
              );
      },
    );
  }

  Future<void> _openGameMenu(BuildContext context, GameSession game) async {
    final controller = AppScope.of(context).game;
    final action = await showDialog<_GameMenuAction>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        key: const ValueKey('game-menu-dialog'),
        title: const Text('Game menu'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!game.isFinished)
                ListTile(
                  leading: Icon(
                    controller.isPaused
                        ? Icons.play_arrow_rounded
                        : Icons.pause_rounded,
                  ),
                  title: Text(
                    controller.isPaused ? 'Resume game' : 'Pause game',
                  ),
                  onTap: () => Navigator.pop(
                    dialogContext,
                    _GameMenuAction.togglePause,
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.refresh_rounded),
                title: const Text('Restart game'),
                onTap: () => Navigator.pop(
                  dialogContext,
                  _GameMenuAction.restart,
                ),
              ),
              if (!game.isFinished)
                ListTile(
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Resign session'),
                  onTap: () => Navigator.pop(
                    dialogContext,
                    _GameMenuAction.resign,
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.view_in_ar_outlined),
                title: const Text('Reload 3D view'),
                onTap: () => Navigator.pop(
                  dialogContext,
                  _GameMenuAction.reloadBoard,
                ),
              ),
              ListTile(
                leading: const Icon(Icons.home_outlined),
                title: const Text('Save session & return home'),
                onTap: () => Navigator.pop(
                  dialogContext,
                  _GameMenuAction.returnHome,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );

    if (action == null || !context.mounted) return;
    switch (action) {
      case _GameMenuAction.togglePause:
        if (controller.isPaused) {
          await controller.resumeGame(game.id);
        } else {
          await controller.pauseGame(game.id);
        }
      case _GameMenuAction.restart:
        await _confirmRestart(context, game);
      case _GameMenuAction.resign:
        await _confirmResign(context, game);
      case _GameMenuAction.reloadBoard:
        _recreateUnityView();
      case _GameMenuAction.returnHome:
        context.go('/');
    }
  }

  Future<void> _confirmRestart(BuildContext context, GameSession game) async {
    final controller = AppScope.of(context).game;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restart this game?'),
        content: const Text(
          'This will clear the current moves and start a fresh board with the same settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep playing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Restart'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    await controller.restart(game.id);
  }

  Future<void> _confirmResign(BuildContext context, GameSession game) async {
    final controller = AppScope.of(context).game;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Resign this session?'),
        content: const Text(
          'This will end the session and add the result to your history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep session'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Resign'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    _navigatingToResult = true;
    final finished = await controller.resign(game.id);
    if (context.mounted && finished != null) {
      context.go('/game/${game.id}/result');
    } else {
      _navigatingToResult = false;
    }
  }
}

enum _GameMenuAction {
  togglePause,
  restart,
  resign,
  reloadBoard,
  returnHome,
}

/// Hosts the Unity 3D board surface through the interface-based [BoardRenderer]
/// bridge and restores the full board snapshot whenever mounted or recreated.
class UnityBoardArea extends StatefulWidget {
  const UnityBoardArea({
    required this.gameId,
    required this.onRecreateRequested,
    super.key,
  });

  final String gameId;
  final VoidCallback onRecreateRequested;

  @override
  State<UnityBoardArea> createState() => _UnityBoardAreaState();
}

class _UnityBoardAreaState extends State<UnityBoardArea> {
  bool _attachedOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_attachedOnce) {
      _attachedOnce = true;
      final controller = AppScope.of(context).game;
      scheduleMicrotask(() {
        if (!mounted) return;
        unawaited(controller.attachBoard(widget.gameId));
      });
    }
  }

  @override
  void didUpdateWidget(covariant UnityBoardArea oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameId != widget.gameId) {
      final controller = AppScope.of(context).game;
      scheduleMicrotask(() {
        if (!mounted) return;
        unawaited(controller.attachBoard(widget.gameId));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context).game;
    final game = controller.find(widget.gameId);
    if (game == null) return const SizedBox.shrink();

    if (controller.boardError != null) {
      return Card(
        key: const ValueKey('unity-error-state'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline_rounded,
                color: Theme.of(context).colorScheme.error,
                size: 36,
              ),
              const SizedBox(height: 12),
              Text(
                '3D board unavailable',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(controller.boardError!),
              const SizedBox(height: 16),
              FilledButton.icon(
                key: const ValueKey('retry-board-button'),
                onPressed: () => controller.attachBoard(game.id),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Retry board connection'),
              ),
            ],
          ),
        ),
      );
    }

    if (!controller.isBoardReady) {
      return Card(
        key: const ValueKey('unity-loading-state'),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.hourglass_top_rounded, size: 36),
              const SizedBox(height: 12),
              Text(
                'Loading 3D board…',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Preparing the Unity board view and synchronizing position.',
              ),
            ],
          ),
        ),
      );
    }

    final inputEnabled = controller.isPlayerInputEnabledFor(game);
    final highlightedDestinations = controller.legalMovesForSelection
        .where((uci) => uci.length >= 4)
        .map((uci) => uci.substring(2, 4))
        .toSet();

    return Column(
      key: const ValueKey('unity-board-area'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IgnorePointer(
          key: const ValueKey('unity-input-guard'),
          ignoring: !inputEnabled,
          child: BoardPreview(
            key: const ValueKey('unity-board-surface'),
            flipped: game.humanColor == PlayerColor.black,
            fen: game.fen,
            selectedSquare: controller.selectedSquare,
            highlightedSquares: highlightedDestinations,
            onSquareTap: (square) => controller.onSquareTapped(game.id, square),
          ),
        ),
        if (!controller.renderer.isAvailable) ...[
          const SizedBox(height: 12),
          const InfoPanel(
            title: 'Board preview',
            icon: Icons.view_in_ar_outlined,
            message:
                'The 3D board and offline opponent are not connected yet. Moves are unavailable in this preview.',
          ),
        ],
      ],
    );
  }
}

class _ContestantIndicator extends StatelessWidget {
  const _ContestantIndicator({
    required this.name,
    required this.colorLabel,
    required this.statusLabel,
    required this.isActive,
    required this.icon,
    super.key,
  });

  final String name;
  final String colorLabel;
  final String statusLabel;
  final bool isActive;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: isActive ? scheme.primary : scheme.outlineVariant,
          width: isActive ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 10),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        colorLabel,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            Text(
              statusLabel,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? scheme.onSurface : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TurnStatusBanner extends StatelessWidget {
  const _TurnStatusBanner({
    required this.controller,
    required this.game,
  });

  final GameController controller;
  final GameSession game;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, icon) = _resolveStatus();
    return Semantics(
      liveRegion: true,
      child: Card(
        key: const ValueKey('turn-status-banner'),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        height: 1.4,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  (String, String, IconData) _resolveStatus() {
    if (controller.boardError != null) {
      return (
        'Board connection issue',
        controller.boardError!,
        Icons.warning_amber_rounded,
      );
    }
    if (!controller.isBoardReady) {
      return (
        'Loading 3D board…',
        'Waiting for Unity board readiness before enabling moves.',
        Icons.hourglass_top_rounded,
      );
    }
    if (game.isFinished) {
      return (
        'Game over · ${game.result}',
        game.termination ?? 'Session ended',
        Icons.flag_outlined,
      );
    }
    if (controller.isPaused) {
      return (
        'Game paused',
        'Resume the game when you are ready to make your next move.',
        Icons.pause_circle_outline_rounded,
      );
    }
    if (controller.pendingPromotion?.gameId == game.id) {
      return (
        'Promotion required',
        'Select a promotion piece to complete your pawn move.',
        Icons.upgrade_rounded,
      );
    }
    if (controller.isApplyingMove) {
      return (
        'Applying move…',
        'Updating the authoritative position and 3D board.',
        Icons.sync_rounded,
      );
    }
    if (controller.isAiThinking) {
      return (
        'AI is thinking',
        'The ${game.configuration.difficulty.label} AI is calculating its response. Board input is locked.',
        Icons.psychology_outlined,
      );
    }
    if (game.isHumanTurn) {
      return (
        'Your turn · ${game.sideToMove.label} to move',
        'Select one of your ${game.humanColor.label.toLowerCase()} pieces to move.',
        Icons.touch_app_outlined,
      );
    }
    return (
      'AI turn · ${game.sideToMove.label} to move',
      'Waiting for the ${game.configuration.difficulty.label} opponent.',
      Icons.smart_toy_outlined,
    );
  }
}

class _PromotionSelector extends StatelessWidget {
  const _PromotionSelector({
    required this.promotion,
    required this.onSelect,
    required this.onCancel,
  });

  final PendingPromotion promotion;
  final ValueChanged<PromotionPiece> onSelect;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Card(
    key: const ValueKey('promotion-selector'),
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose promotion piece',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Promote pawn moving ${promotion.from} → ${promotion.to}:',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final piece in promotion.choices)
                OutlinedButton(
                  key: ValueKey('promotion-choice-${piece.uciCode}'),
                  onPressed: () => onSelect(piece),
                  child: Text(
                    '${piece.symbolFor(promotion.color)} ${piece.label}',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextButton(
            key: const ValueKey('cancel-promotion-button'),
            onPressed: onCancel,
            child: const Text('Cancel promotion'),
          ),
        ],
      ),
    ),
  );
}

class MissingGame extends StatelessWidget {
  const MissingGame({super.key});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const SectionHeading(
        'Session not found.',
        subtitle:
            'Preview sessions are kept only while the app is open. Start a new one to continue.',
      ),
      const SizedBox(height: 24),
      FilledButton(
        onPressed: () => context.go('/setup'),
        child: const Text('Set up a game'),
      ),
    ],
  );
}
