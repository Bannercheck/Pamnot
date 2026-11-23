import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'services/launch_actions.dart';
import 'state/app_controller.dart';
import 'state/app_scope.dart';
import 'theme/pamnot_theme.dart';
import 'ui/home_shell.dart';

class PamnotApp extends StatefulWidget {
  const PamnotApp({super.key, required this.controller});

  final AppController controller;

  @override
  State<PamnotApp> createState() => _PamnotAppState();
}

class _PamnotAppState extends State<PamnotApp> with WidgetsBindingObserver {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _lifecycle = AppLifecycleListener(
      // Save before the OS may suspend or kill the app.
      onInactive: () => unawaited(widget.controller.flush()),
      onHide: () => unawaited(widget.controller.flush()),
      onResume: () {
        widget.controller.refreshDay();
        // A shortcut run while the app was in the background left a request.
        unawaited(LaunchActionsBridge.pull());
      },
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

  /// pamnot:// links stop here. This observer is registered before
  /// MaterialApp's, so they never become Navigator routes (which would push
  /// a second HomeShell or fail to find a route). Only `ses` and `voice` ask
  /// for the voice screen, which opens paused: any app or page can open a
  /// link, so listening needs a tap inside Pamnot. Nothing else in the link
  /// is read, so a link never writes a task.
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    final uri = routeInformation.uri;
    if (uri.scheme != 'pamnot') return false;
    if (uri.host == 'ses' || uri.host == 'voice') voiceRequests.value = VoiceRequest.link;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: widget.controller,
      child: Builder(builder: (context) {
        final app = AppScope.of(context, {Slice.settings});
        return MaterialApp(
          title: 'Pamnot',
          debugShowCheckedModeBanner: false,
          theme: PamnotTheme.light(),
          darkTheme: PamnotTheme.dark(),
          themeMode: app.settings.themeMode,
          locale: Locale(app.isTurkish ? 'tr' : 'en'),
          supportedLocales: const [Locale('tr'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          // iOS Bold Text does not reach a bundled font on its own.
          builder: (context, child) => MediaQuery.boldTextOf(context)
              ? Theme(data: PamnotTheme.bolder(Theme.of(context)), child: child!)
              : child!,
          home: const HomeShell(),
        );
      }),
    );
  }
}
