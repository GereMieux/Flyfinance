import 'package:flutter/material.dart';

import 'assistant_screen.dart';
import 'credits_screen.dart';
import 'home_screen.dart';
import 'online_shop_screen.dart';
import 'search_screen.dart';
import 'stock_screen.dart';
import 'theme.dart';

/// Barre d'onglets : Accueil, Recherche, Vocal (au centre), Stock, Crédits,
/// En ligne.
class Shell extends StatefulWidget {
  const Shell({super.key});
  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      const HomeScreen(),
      SearchScreen(onVoice: () => setState(() => _tab = 2)),
      const AssistantScreen(),
      const StockScreen(embedded: true),
      const CreditsScreen(embedded: true),
      const OnlineShopScreen(embedded: true),
    ];
    return Scaffold(
      body: pages[_tab],
      bottomNavigationBar: NavigationBar(
        backgroundColor: Palette.card,
        indicatorColor: Palette.cardHigh,
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Accueil',
          ),
          NavigationDestination(icon: Icon(Icons.search), label: 'Recherche'),
          NavigationDestination(
            icon: Icon(Icons.mic_none),
            selectedIcon: Icon(Icons.mic, color: Palette.amber),
            label: 'Vocal',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            label: 'Stock',
          ),
          NavigationDestination(
            icon: Icon(Icons.credit_card),
            label: 'Crédits',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag),
            label: 'En ligne',
          ),
        ],
      ),
    );
  }
}
