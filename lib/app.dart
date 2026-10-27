import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'theme/pamuk_theme.dart';
import 'ui/home_shell.dart';

class PamukApp extends StatefulWidget {
  const PamukApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<PamukApp> createState() => _PamukAppState();
}

class _PamukAppState extends State<PamukApp> with WidgetsBindingObserver {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = AppLifecycleListener(
      // Save before the OS may suspend or kill the app.
      onInactive: () => unawaited(widget.controller.flush()),
      onHide: () => unawaited(widget.controller.flush()),
      onResume: widget.controller.refreshDay,
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) => setState(() {});

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: widget.controller,
      child: Builder(builder: (context) {
        final app = AppScope.of(context, {Slice.settings});
        return MaterialApp(
          title: 'Pamuk',
          debugShowCheckedModeBanner: false,
          theme: PamukTheme.light(),
          darkTheme: PamukTheme.dark(),
          themeMode: app.settings.themeMode,
          locale: Locale(app.isTurkish ? 'tr' : 'en'),
          supportedLocales: const [Locale('tr'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: const HomeShell(),
        );
      }),
    );
  }
}
