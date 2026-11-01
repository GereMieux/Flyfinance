import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../security/lock_service.dart';
import '../theme.dart';
import '../widgets.dart';

/// Demande le code secret du propriétaire avant une action sensible.
Future<bool> askOwnerPin(
  BuildContext context, {
  required String title,
  required String text,
  String action = 'Valider',
}) async {
  final lock = context.read<LockService>();
  final pin = TextEditingController();
  final code = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: Palette.card,
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(text),
          const SizedBox(height: 12),
          TextField(
            controller: pin,
            autofocus: true,
            obscureText: true,
            maxLength: 4,
            keyboardType: TextInputType.number,
            onSubmitted: (t) => Navigator.pop(ctx, t),
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
          onPressed: () => Navigator.pop(ctx, pin.text),
          child: Text(action),
        ),
      ],
    ),
  );
  if (code == null) return false;
  if (await lock.confirmPin(code)) return true;
  if (context.mounted) {
    toast(
      context,
      lock.lockoutRemaining != null
          ? 'Trop d’erreurs. Réessayez dans une minute.'
          : 'Code incorrect.',
      error: true,
    );
  }
  return false;
}

/// Ligne « libellé … montant » des bilans.
class AmountLine extends StatelessWidget {
  const AmountLine(
    this.label,
    this.amount, {
    super.key,
    this.strong = false,
    this.color,
  });
  final String label;
  final int amount;
  final bool strong;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: strong ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            app.money(amount),
            style: TextStyle(
              fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
              fontFeatures: tabular,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Barre horizontale proportionnelle, pour les classements.
class BarRow extends StatelessWidget {
  const BarRow({
    super.key,
    required this.label,
    required this.value,
    required this.max,
    this.detail = '',
    this.color,
  });
  final String label;
  final int value;
  final int max;
  final String detail;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final f = max <= 0 ? 0.0 : (value / max).clamp(0.02, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                app.money(value),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontFeatures: tabular,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: f.toDouble(),
              minHeight: 7,
              backgroundColor: Palette.cardHigh,
              color: color ?? Palette.mint,
            ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(detail, style: TextStyle(color: Palette.muted, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

const monthNames = [
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

String monthLabel(DateTime m) => '${monthNames[m.month - 1]} ${m.year}';
