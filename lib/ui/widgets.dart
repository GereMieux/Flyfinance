import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../data/repository.dart';
import 'theme.dart';

/// Charge des données depuis le dépôt et les recharge après chaque
/// enregistrement (voir [AppState.changed]).
class Loader<T> extends StatefulWidget {
  const Loader({super.key, required this.load, required this.builder});
  final Future<T> Function(Repository repo) load;
  final Widget Function(BuildContext context, T data) builder;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  Future<T>? _future;
  int _rev = -1;
  T? _last;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = context.watch<AppState>();
    if (state.revision != _rev) {
      _rev = state.revision;
      _future = widget.load(state.repo);
    }
  }

  @override
  void didUpdateWidget(covariant Loader<T> old) {
    super.didUpdateWidget(old);
    if (old.load != widget.load) {
      _future = widget.load(context.read<AppState>().repo);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Erreur : ${snap.error}',
              style: const TextStyle(color: Palette.red),
            ),
          );
        }
        final data = snap.data ?? _last;
        if (data == null) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        _last = data;
        return widget.builder(context, data);
      },
    );
  }
}

/// Bouton œil : masque ou affiche tous les montants de l'application.
class EyeButton extends StatelessWidget {
  const EyeButton({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return IconButton.outlined(
      tooltip: s.hideAmounts ? 'Afficher les montants' : 'Masquer les montants',
      onPressed: s.toggleAmounts,
      style: IconButton.styleFrom(side: const BorderSide(color: Palette.line)),
      icon: Icon(
        s.hideAmounts
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
      ),
    );
  }
}

Color statusColor(SaleStatus s) => switch (s) {
  SaleStatus.soldee => Palette.mint,
  SaleStatus.acompte => Palette.amber,
  SaleStatus.reliquat => Palette.blue,
  SaleStatus.nonPaye => Palette.red,
  SaleStatus.annulee => Palette.grey,
};

class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.padding, this.color});
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final Color? color;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding ?? const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: color ?? Palette.card,
      borderRadius: BorderRadius.circular(20),
    ),
    child: child,
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(this.text, {super.key, this.icon = Icons.inbox_outlined});
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
    child: Column(
      children: [
        Icon(icon, size: 40, color: Palette.muted),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Palette.muted, fontSize: 15),
        ),
      ],
    ),
  );
}

String shortDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} · ${two(d.hour)}:${two(d.minute)}';
}

void toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

/// Champ numérique simple, utilisé dans les boîtes de dialogue.
Future<int?> askNumber(
  BuildContext context, {
  required String title,
  String? hint,
  int? initial,
}) async {
  final c = TextEditingController(text: initial?.toString() ?? '');
  final v = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Palette.card,
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            ctx,
            int.tryParse(c.text.replaceAll(RegExp(r'[^0-9]'), '')),
          ),
          child: const Text('Valider'),
        ),
      ],
    ),
  );
  return v;
}

/// Petit encadré « libellé / valeur » utilisé sous les gros montants.
Widget statChip(String label, String value, Color color) => Expanded(
  child: Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: Palette.cardHigh,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, color: Palette.muted)),
        FittedBox(
          child: Text(
            value,
            style: TextStyle(fontWeight: FontWeight.w700, color: color),
          ),
        ),
      ],
    ),
  ),
);
