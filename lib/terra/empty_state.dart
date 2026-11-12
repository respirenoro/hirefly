// C-12: the one empty state. What is empty, what to do about it, and one
// accent action beside it; at most 480 px wide, centred in its area.
import 'package:flutter/material.dart';

import 'palette.dart';
import 'j.dart';

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.what, this.next, this.actionLabel, this.onAction});

  /// "No books yet."
  final String what;

  /// "Search for one, or import a list."
  final String? next;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final t = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(what, textAlign: TextAlign.center, style: t.titleMedium?.copyWith(color: p.text)),
            if (next != null) ...[
              const SizedBox(height: 6),
              Text(next!, textAlign: TextAlign.center, style: t.bodyMedium?.copyWith(color: p.textMuted)),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              JBtn(actionLabel!, primary: true, onTap: onAction),
            ],
          ]),
        ),
      ),
    );
  }
}
