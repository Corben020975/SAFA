import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_services.dart';
import 'services/launch_router.dart';
import 'services/notion_import.dart';
import 'ui/screens/capture_screen.dart';
import 'ui/screens/detail_screen.dart';
import 'ui/screens/home_shell.dart';
import 'ui/screens/lock_screen.dart';
import 'ui/screens/onboarding_screen.dart';
import 'ui/screens/settings_screen.dart';
import 'ui/theme.dart';

class CoffreApp extends StatefulWidget {
  const CoffreApp({super.key, required this.services, required this.router});
  final AppServices services;
  final LaunchRouter router;

  @override
  State<CoffreApp> createState() => _CoffreAppState();
}

class _CoffreAppState extends State<CoffreApp> {
  late final AppLifecycleListener _lifecycle;
  late final NotionAutoImport _notionImport = NotionAutoImport(widget.services);
  final _messenger = GlobalKey<ScaffoldMessengerState>();
  late final String _initialRoute = widget.services.settings.onboardingDone
      ? '/'
      : '/onboarding';

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onPause: widget.services.lock.onPaused,
      // Filet de sécurité : relit les listes au retour au premier plan
      // (ex. snooze fait depuis la notification pendant que l'app dormait).
      onResume: () {
        widget.services.lock.onResumed();
        widget.services.db.notifyUpdates({
          TableUpdate.onTable(widget.services.db.items),
        });
        _importFromNotion();
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.router.handleColdStart();
      _importFromNotion();
    });
  }

  /// Nouvelles entrées de la base Notion (Grokbot…) à chaque ouverture.
  Future<void> _importFromNotion() async {
    final result = await _notionImport.run();
    final n = result?.added.length ?? 0;
    if (n == 0) return;
    _messenger.currentState?.showSnackBar(
      SnackBar(
        content: Text(
          n == 1
              ? '1 nouvelle tâche depuis Notion (Inbox)'
              : '$n nouvelles tâches depuis Notion (Inbox)',
        ),
      ),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final Widget page = switch (settings.name) {
      '/' => const HomeShell(),
      '/capture' => CaptureScreen(
        args: settings.arguments is CaptureArgs
            ? settings.arguments! as CaptureArgs
            : const CaptureArgs(),
      ),
      '/item' => DetailScreen(itemId: settings.arguments! as int),
      '/settings' => const SettingsScreen(),
      '/onboarding' => const OnboardingScreen(),
      _ => const HomeShell(),
    };
    return MaterialPageRoute(
      settings: settings,
      fullscreenDialog: settings.name == '/capture',
      builder: (_) => page,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.services.settings;
    return AppScope(
      services: widget.services,
      child: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => MaterialApp(
          title: 'Coffre',
          debugShowCheckedModeBanner: false,
          navigatorKey: widget.router.navigatorKey,
          scaffoldMessengerKey: _messenger,
          theme: buildTheme(Brightness.light),
          darkTheme: buildTheme(Brightness.dark),
          themeMode: settings.themeMode,
          locale: const Locale('fr', 'BE'),
          supportedLocales: const [Locale('fr', 'BE'), Locale('fr')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          initialRoute: _initialRoute,
          onGenerateRoute: _onGenerateRoute,
          builder: (context, child) {
            final mq = MediaQuery.of(context);
            final lock = widget.services.lock;
            return MediaQuery(
              data: mq.copyWith(
                textScaler: combinedTextScaler(
                  mq.textScaler,
                  settings.textScale,
                ),
              ),
              child: ListenableBuilder(
                listenable: lock,
                builder: (context, _) => Stack(
                  children: [
                    ExcludeSemantics(excluding: lock.locked, child: child!),
                    if (lock.locked)
                      Positioned.fill(child: LockScreen(lock: lock)),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
