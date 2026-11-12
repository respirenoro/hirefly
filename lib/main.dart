import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/content.dart';
import 'engine/inbox.dart';
import 'terra/speech/speech_models.dart';
import 'ui/shell.dart';
import 'ui/ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final models = Directory(p.join((await getApplicationSupportDirectory()).path, 'speech_models'));
  final home = Directory(p.join((await getApplicationDocumentsDirectory()).path, 'HireFly'));
  final content = await Content.load(user: home);
  runApp(ProviderScope(
    overrides: [contentProvider.overrideWithValue(content), speechModelDirProvider.overrideWithValue(models), hireflyHomeProvider.overrideWithValue(home)],
    child: const HireFlyApp(),
  ));
}

class HireFlyApp extends StatelessWidget {
  const HireFlyApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'HireFly',
        debugShowCheckedModeBanner: false,
        theme: appTheme(),
        home: const Shell(),
      );
}
