import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../features/settings/domain/app_settings.dart';
import 'app_dependencies.dart';
import 'app_router.dart';
import 'app_theme.dart';

class ChessApp extends StatefulWidget {
  const ChessApp({
    required this.dependencies,
    this.initialLocation = '/',
    super.key,
  });

  /// Ownership transfers to this app; disposed together with its router.
  final AppDependencies dependencies;
  final String initialLocation;
  @override
  State<ChessApp> createState() => _ChessAppState();
}

class _ChessAppState extends State<ChessApp> {
  late final GoRouter _router = createRouter(
    initialLocation: widget.initialLocation,
  );
  late Future<void> _initialization = widget.dependencies.initialize();
  @override
  void dispose() {
    _router.dispose();
    widget.dependencies.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AppScope(
    dependencies: widget.dependencies,
    child: ListenableBuilder(
      listenable: widget.dependencies.settings,
      builder: (context, _) {
        final settings = widget.dependencies.settings.settings;
        final themeMode = switch (settings.appearance) {
          Appearance.system => ThemeMode.system,
          Appearance.light => ThemeMode.light,
          Appearance.dark => ThemeMode.dark,
        };
        return FutureBuilder<void>(
          future: _initialization,
          builder: (context, snapshot) {
            Widget mediaBuilder(BuildContext context, Widget? child) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                data: media.copyWith(
                  disableAnimations:
                      media.disableAnimations ||
                      media.accessibleNavigation ||
                      settings.reducedMotion,
                ),
                child: child!,
              );
            }

            if (snapshot.connectionState != ConnectionState.done ||
                snapshot.hasError) {
              return MaterialApp(
                title: 'Still Chess',
                debugShowCheckedModeBanner: false,
                theme: AppTheme.light,
                darkTheme: AppTheme.dark,
                themeMode: themeMode,
                builder: mediaBuilder,
                home: Scaffold(
                  body: SafeArea(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: snapshot.hasError
                            ? Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Text(
                                    'Your chess space could not be opened.',
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton(
                                    onPressed: () => setState(() {
                                      _initialization = widget.dependencies
                                          .initialize();
                                    }),
                                    child: const Text('Try again'),
                                  ),
                                ],
                              )
                            : const CircularProgressIndicator(
                                semanticsLabel: 'Opening Still Chess',
                              ),
                      ),
                    ),
                  ),
                ),
              );
            }
            return MaterialApp.router(
              title: 'Still Chess',
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light,
              darkTheme: AppTheme.dark,
              themeMode: themeMode,
              themeAnimationDuration: settings.reducedMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              routerConfig: _router,
              builder: mediaBuilder,
            );
          },
        );
      },
    ),
  );
}
