import 'package:drift/drift.dart' show TableUpdate;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_services.dart';
import 'services/launch_router.dart';
import 'ui/screens/capture_screen.dart';
import 'ui/screens/detail_screen.dart';
import 'ui/screens/inbox_screen.dart';
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
  late final String _initialRoute =
      widget.services.settings.onboardingDone ? '/' : '/onboarding';

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      // Filet de sécurité : relit les listes au retour au premier plan
      // (ex. snooze fait depuis la notification pendant que l'app dormait).
      onResume: () => widget.services.db.notifyUpdates({
        TableUpdate.onTable(widget.services.db.items),
      }),
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => widget.router.handleColdStart(),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
    final Widget page = switch (settings.name) {
      '/' => const InboxScreen(),
      '/capture' => CaptureScreen(
        args: settings.arguments is CaptureArgs
            ? settings.arguments! as CaptureArgs
            : const CaptureArgs(),
      ),
      '/item' => DetailScreen(itemId: settings.arguments! as int),
      '/settings' => const SettingsScreen(),
      '/onboarding' => const OnboardingScreen(),
      _ => const InboxScreen(),
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
            return MediaQuery(
              data: mq.copyWith(
                textScaler: combinedTextScaler(mq.textScaler, settings.textScale),
              ),
              child: child!,
            );
          },
        ),
      ),
    );
  }
}
