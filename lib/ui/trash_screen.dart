import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import '../security/lock_service.dart';
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
      appBar: AppBar(
        title: const Text('Ventes annulées'),
        actions: [
          IconButton(
            tooltip: 'Vider la corbeille',
            onPressed: _empty,
            icon: const Icon(Icons.delete_forever_outlined),
          ),
        ],
      ),
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
                color: Palette.redSoft,
                child: Row(
                  children: [
                    Icon(Icons.delete_outline, color: Palette.red),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        "Aujourd'hui : ${todays.length} vente${todays.length > 1 ? 's' : ''} annulée${todays.length > 1 ? 's' : ''}",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Palette.red,
                        ),
                      ),
                    ),
                    Text(
                      app.money(total),
                      style: TextStyle(
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
                      style: TextStyle(
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

  /// Vider la corbeille efface des preuves : seul le détenteur du code
  /// secret peut le faire.
  Future<void> _empty() async {
    final app = context.read<AppState>();
    final lock = context.read<LockService>();
    final pin = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Palette.card,
        title: const Text('Vider la corbeille ?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Les ventes annulées seront effacées pour toujours. '
              'Tapez votre code secret pour confirmer.',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: pin,
              autofocus: true,
              obscureText: true,
              maxLength: 4,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Code secret',
                prefixIcon: Icon(Icons.lock_outline),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Palette.red),
            onPressed: () => Navigator.pop(ctx, pin.text),
            child: const Text('Vider'),
          ),
        ],
      ),
    );
    if (code == null) return;
    if (!await lock.confirmPin(code)) {
      if (mounted) {
        toast(
          context,
          lock.lockoutRemaining != null
              ? 'Trop d’erreurs. Réessayez dans une minute.'
              : 'Code incorrect. La corbeille n’a pas été vidée.',
        );
      }
      return;
    }
    final n = await app.repo.emptyTrash();
    app.changed();
    if (mounted) {
      toast(context, '$n vente${n > 1 ? 's' : ''} effacée${n > 1 ? 's' : ''}.');
    }
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
