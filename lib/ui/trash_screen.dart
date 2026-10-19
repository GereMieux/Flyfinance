import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import 'day_sales_screen.dart';
import 'theme.dart';
import 'widgets.dart';

/// Corbeille : toutes les ventes annulées, pour que le patron puisse
/// vérifier qui a annulé quoi et quand.
class TrashScreen extends StatefulWidget {
  const TrashScreen({super.key});
  @override
  State<TrashScreen> createState() => _TrashScreenState();
}

class _TrashScreenState extends State<TrashScreen> {
  @override
  void initState() {
    super.initState();
    // Ouvrir la corbeille vaut « vu » : la notification de l'accueil s'efface.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final app = context.read<AppState>();
      app.markCancellationsSeen(app.repo.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Ventes annulées')),
      body: Loader<List<CancelledSale>>(
        load: (r) => r.cancelledSales(),
        builder: (context, all) {
          if (all.isEmpty) {
            return const EmptyState(
              'Aucune vente annulée.',
              icon: Icons.delete_outline,
            );
          }
          final now = app.repo.now();
          final today = DateTime(now.year, now.month, now.day);
          final todays = all.where((c) => !c.cancelledAt.isBefore(today));
          final total = todays.fold<int>(
            0,
            (s, c) => s + c.detail.summary.sale.total,
          );
          String? lastDay;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: [
              Panel(
                color: const Color(0xFF3A1F1B),
                child: Row(
                  children: [
                    const Icon(Icons.delete_outline, color: Palette.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Aujourd'hui : ${todays.length} vente${todays.length > 1 ? 's' : ''} annulée${todays.length > 1 ? 's' : ''}",
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Palette.red,
                        ),
                      ),
                    ),
                    Text(
                      app.money(total),
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: Palette.red,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              for (final c in all) ...[
                if (_day(c.cancelledAt, today) != lastDay)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                    child: Text(
                      lastDay = _day(c.cancelledAt, today),
                      style: const TextStyle(
                        color: Palette.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                SaleCard(c.detail, note: 'Annulée à ${_time(c.cancelledAt)}'),
              ],
            ],
          );
        },
      ),
    );
  }

  String _two(int n) => n.toString().padLeft(2, '0');
  String _time(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
  String _day(DateTime d, DateTime today) {
    final day = DateTime(d.year, d.month, d.day);
    if (day == today) return "Aujourd'hui";
    if (day == today.subtract(const Duration(days: 1))) return 'Hier';
    return '${_two(d.day)}/${_two(d.month)}/${d.year}';
  }
}
