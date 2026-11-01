import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class PageLayout extends StatelessWidget {
  const PageLayout({
    required this.title,
    required this.child,
    this.actions,
    this.maxWidth = 1120,
    super.key,
  });
  final String title;
  final Widget child;
  final List<Widget>? actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(title),
      actions: actions,
      leading: context.canPop()
          ? IconButton(
              tooltip: 'Back',
              onPressed: () => context.pop(),
              icon: const Icon(Icons.arrow_back_rounded),
            )
          : null,
    ),
    body: SafeArea(
      top: false,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          key: const ValueKey('page-scroll'),
          padding: EdgeInsets.all(constraints.maxWidth < 600 ? 20 : 40),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        ),
      ),
    ),
  );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {this.subtitle, super.key});
  final String title;
  final String? subtitle;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Semantics(
        header: true,
        child: Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium
              ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.8),
        ),
      ),
      if (subtitle != null) ...[
        const SizedBox(height: 12),
        Text(
          subtitle!,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            height: 1.5,
          ),
        ),
      ],
    ],
  );
}

class InfoPanel extends StatelessWidget {
  const InfoPanel({
    required this.title,
    required this.message,
    this.icon = Icons.info_outline_rounded,
    super.key,
  });
  final String title;
  final String message;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon),
          const SizedBox(height: 12),
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            message,
            style: TextStyle(
              height: 1.5,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    ),
  );
}

class ErrorNotice extends StatelessWidget {
  const ErrorNotice(this.message, {super.key});
  final String message;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
      ),
    ),
  );
}

String shortDate(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
