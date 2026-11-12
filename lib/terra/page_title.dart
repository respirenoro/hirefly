import 'package:flutter/material.dart';

/// A page's title: the same style everywhere, and a heading to screen readers.
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Semantics(header: true, child: Text(text, style: Theme.of(context).textTheme.headlineMedium, maxLines: 2, overflow: TextOverflow.ellipsis));
}
