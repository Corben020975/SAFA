import 'package:flutter/material.dart';

import '../views/flux_view.dart';
import '../views/jour_view.dart';
import '../widgets/quick_composer.dart';

/// Écran principal : vues Jour et Flux, barre de capture toujours en bas.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  final _composer = TextEditingController();
  final _composerFocus = FocusNode();

  @override
  void dispose() {
    _composer.dispose();
    _composerFocus.dispose();
    super.dispose();
  }

  void _tryExample(String text) {
    _composer.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _composerFocus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          JourView(onTryExample: _tryExample),
          const FluxView(),
        ],
      ),
      // La barre de capture remonte au-dessus du clavier ; les onglets
      // disparaissent pendant la saisie pour laisser la place.
      bottomNavigationBar: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QuickComposer(controller: _composer, focusNode: _composerFocus),
            if (!keyboard)
              NavigationBar(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                destinations: const [
                  NavigationDestination(
                    icon: Icon(Icons.wb_sunny_outlined),
                    selectedIcon: Icon(Icons.wb_sunny),
                    label: 'Jour',
                  ),
                  NavigationDestination(
                    icon: Icon(Icons.view_agenda_outlined),
                    selectedIcon: Icon(Icons.view_agenda),
                    label: 'Flux',
                  ),
                ],
              )
            else
              const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}
