import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
              style: TextStyle(color: Palette.red),
            ),
          );
        }
        final data = snap.data ?? _last;
        if (data == null) return const SkeletonList();
        final first = _last == null;
        _last = data;
        final child = widget.builder(context, data);
        // Premier affichage : léger fondu au lieu d'une apparition sèche.
        if (!first) return child;
        return TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Motion.normal,
          curve: Motion.curve,
          builder: (_, v, c) => Opacity(opacity: v, child: c),
          child: child,
        );
      },
    );
  }
}

/// Bouton œil : masque ou affiche tous les montants de l'application.
class EyeButton extends StatelessWidget {
  const EyeButton({super.key, this.onDark = false});

  /// Vrai quand le bouton est posé sur la grande carte verte.
  final bool onDark;
  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    return IconButton.outlined(
      tooltip: s.hideAmounts ? 'Afficher les montants' : 'Masquer les montants',
      onPressed: () {
        Haptics.tap();
        s.toggleAmounts();
      },
      style: IconButton.styleFrom(
        foregroundColor: onDark ? Colors.white : null,
        backgroundColor: onDark ? Colors.black.withValues(alpha: 0.18) : null,
        side: BorderSide(color: onDark ? Colors.transparent : Palette.line),
      ),
      icon: Icon(
        s.hideAmounts
            ? Icons.visibility_off_outlined
            : Icons.visibility_outlined,
      ),
    );
  }
}

/// Icône posée sur une pastille de sa couleur, éclaircie.
class IconBubble extends StatelessWidget {
  const IconBubble(this.icon, this.color, {super.key, this.size = 40});
  final IconData icon;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: Palette.isDark ? 0.16 : 0.12),
      borderRadius: BorderRadius.circular(size * 0.32),
    ),
    child: Icon(icon, color: color, size: size * 0.55),
  );
}

/// Titre de rubrique, avec un lien à droite si besoin.
class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.action, this.onAction});
  final String text;
  final String? action;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
        if (action != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: Text(action!),
          ),
      ],
    ),
  );
}

/// Bandeau d'alerte : icône dans une pastille, titre et détail.
class AlertTile extends StatelessWidget {
  const AlertTile({
    super.key,
    required this.icon,
    required this.color,
    required this.background,
    required this.title,
    this.subtitle,
    this.onTap,
  });
  final IconData icon;
  final Color color;
  final Color background;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: background,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle!,
                      style: TextStyle(fontSize: 13, color: Palette.muted),
                    ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color),
          ],
        ),
      ),
    ),
  );
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
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      // En mode jour, une ombre très légère détache les cartes du fond.
      boxShadow: Palette.isDark
          ? null
          : const [
              BoxShadow(
                color: Color(0x0F13201B),
                blurRadius: 16,
                offset: Offset(0, 4),
              ),
            ],
    ),
    // Un Material pour que les effets de toucher des listes restent visibles.
    child: Material(
      color: color ?? Palette.card,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

/// Écran vide qui explique quoi faire, avec un bouton pour le faire.
class EmptyState extends StatelessWidget {
  const EmptyState(
    this.text, {
    super.key,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
  });
  final String text;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
    child: Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: Palette.cardHigh,
            shape: BoxShape.circle,
          ),
          child: Icon(icon, size: 34, color: Palette.muted),
        ),
        const SizedBox(height: 14),
        Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: Palette.muted, fontSize: 15, height: 1.4),
        ),
        if (actionLabel != null && onAction != null) ...[
          const SizedBox(height: 16),
          FilledButton.tonal(
            onPressed: onAction,
            style: FilledButton.styleFrom(
              backgroundColor: Palette.mintSoft,
              foregroundColor: Palette.mint,
              minimumSize: const Size(48, 46),
            ),
            child: Text(actionLabel!),
          ),
        ],
      ],
    ),
  );
}

/// Place réservée pendant le chargement : des blocs gris qui « respirent »,
/// comme dans les applications bancaires, plutôt qu'une roue qui tourne.
class SkeletonList extends StatefulWidget {
  const SkeletonList({super.key, this.rows = 4});
  final int rows;
  @override
  State<SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<SkeletonList>
    with SingleTickerProviderStateMixin {
  late final _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Chargement',
    child: FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (var i = 0; i < widget.rows; i++)
              Container(
                height: i == 0 ? 120 : 64,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Palette.card,
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Montant qui défile jusqu'à sa nouvelle valeur au lieu de changer d'un coup.
class AnimatedMoney extends StatelessWidget {
  const AnimatedMoney(this.amount, {super.key, this.style});
  final int amount;
  final TextStyle? style;
  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return TweenAnimationBuilder<double>(
      tween: Tween(end: amount.toDouble()),
      duration: Motion.slow,
      curve: Motion.curve,
      builder: (_, v, _) => Text(
        app.money(v.round()),
        style: (style ?? const TextStyle()).copyWith(fontFeatures: tabular),
        semanticsLabel: app.hideAmounts ? 'Montant masqué' : app.money(amount),
      ),
    );
  }
}

/// Recouvre l'application quand elle passe en arrière-plan, pour que les
/// montants ne se voient pas dans la liste des applications récentes.
class PrivacyCover extends StatelessWidget {
  const PrivacyCover({super.key});
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Palette.ground,
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 44, color: Palette.mint),
          const SizedBox(height: 12),
          Text(
            'FLYFINANCE',
            style: TextStyle(
              fontFamily: appFont,
              fontSize: 20,
              fontWeight: FontWeight.w800,
              letterSpacing: 2,
              color: Palette.text,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    ),
  );
}

/// Ajoute les points des milliers pendant la saisie : 150000 → 150.000.
class ThousandsFormatter extends TextInputFormatter {
  const ThousandsFormatter();
  @override
  TextEditingValue formatEditUpdate(TextEditingValue old, TextEditingValue v) {
    final digits = v.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return const TextEditingValue();
    final n = int.tryParse(digits);
    if (n == null) return old;
    final text = fcfa(n, unit: false);
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

/// Lit un montant saisi avec ou sans points : « 150.000 » → 150000.
int? parseAmount(String text) =>
    int.tryParse(text.replaceAll(RegExp(r'[^0-9]'), ''));

/// Petites vibrations, comme sur les caisses enregistreuses tactiles.
abstract final class Haptics {
  static void tap() => HapticFeedback.selectionClick();
  static void success() => HapticFeedback.mediumImpact();
  static void warning() => HapticFeedback.heavyImpact();
}

String shortDate(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} · ${two(d.hour)}:${two(d.minute)}';
}

/// Message bref en bas de l'écran, avec une petite vibration de
/// confirmation.
void toast(BuildContext context, String text, {bool error = false}) {
  error ? Haptics.warning() : Haptics.success();
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              error ? Icons.error_outline : Icons.check_circle_outline,
              color: error ? const Color(0xFFF28B7A) : const Color(0xFF7FD3A8),
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(text)),
          ],
        ),
      ),
    );
}

/// Champ numérique simple, utilisé dans les boîtes de dialogue.
Future<int?> askNumber(
  BuildContext context, {
  required String title,
  String? hint,
  int? initial,
}) async {
  final c = TextEditingController(
    text: initial == null ? '' : fcfa(initial, unit: false),
  );
  final v = await showDialog<int>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: c,
        autofocus: true,
        keyboardType: TextInputType.number,
        inputFormatters: const [ThousandsFormatter()],
        textInputAction: TextInputAction.done,
        onSubmitted: (t) => Navigator.pop(ctx, parseAmount(t)),
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w700,
          fontFeatures: tabular,
        ),
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Annuler'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, parseAmount(c.text)),
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
        Text(label, style: TextStyle(fontSize: 12, color: Palette.muted)),
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

/// « lundi 19 octobre », pour l'en-tête de l'accueil.
String longDate(DateTime d) {
  const days = [
    'lundi',
    'mardi',
    'mercredi',
    'jeudi',
    'vendredi',
    'samedi',
    'dimanche',
  ];
  const months = [
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
  final day = days[d.weekday - 1];
  return '${day[0].toUpperCase()}${day.substring(1)} ${d.day} ${months[d.month - 1]}';
}

/// Bouton soleil / lune : choisir le mode jour, le mode nuit, ou suivre le
/// téléphone.
class AppearanceButton extends StatelessWidget {
  const AppearanceButton({super.key});

  static const _choices = [
    (Appearance.auto, Icons.brightness_auto_outlined, 'Comme le téléphone'),
    (Appearance.jour, Icons.light_mode_outlined, 'Mode jour'),
    (Appearance.nuit, Icons.dark_mode_outlined, 'Mode nuit'),
  ];

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return IconButton(
      tooltip: 'Mode jour ou nuit',
      icon: Icon(
        Palette.isDark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
      ),
      onPressed: () => showModalBottomSheet<void>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text(
                    'Affichage',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                for (final (value, icon, label) in _choices)
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    leading: Icon(icon),
                    title: Text(
                      label,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    trailing: app.appearance == value
                        ? Icon(Icons.check_circle, color: Palette.mint)
                        : null,
                    onTap: () {
                      Haptics.tap();
                      app.setAppearance(value);
                      Navigator.pop(ctx);
                    },
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pavé numérique en bas de l'écran pour saisir une quantité, sans le
/// clavier du téléphone. Renvoie la quantité choisie (0 pour retirer
/// l'article) ou `null` si on ferme.
Future<int?> askQuantity(
  BuildContext context, {
  required String title,
  required int unitPrice,
  int initial = 0,
  int? max,
}) => showModalBottomSheet<int>(
  context: context,
  isScrollControlled: true,
  backgroundColor: Palette.card,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (_) => QuantityPad(
    title: title,
    unitPrice: unitPrice,
    initial: initial,
    max: max,
  ),
);

class QuantityPad extends StatefulWidget {
  const QuantityPad({
    super.key,
    required this.title,
    required this.unitPrice,
    this.initial = 0,
    this.max,
  });
  final String title;
  final int unitPrice;
  final int initial;
  final int? max;

  @override
  State<QuantityPad> createState() => _QuantityPadState();
}

class _QuantityPadState extends State<QuantityPad> {
  late String _digits = widget.initial > 0 ? '${widget.initial}' : '';

  /// Le premier chiffre tapé remplace la quantité affichée.
  late bool _fresh = widget.initial > 0;

  int get _value => int.tryParse(_digits) ?? 0;
  bool get _tooMany => widget.max != null && _value > widget.max!;

  void _tap(String k) {
    HapticFeedback.selectionClick();
    setState(() {
      if (k == '⌫') {
        _digits = _fresh || _digits.isEmpty
            ? ''
            : _digits.substring(0, _digits.length - 1);
      } else if (k == 'C') {
        _digits = '';
      } else {
        final next = (_fresh ? '' : _digits) + k;
        if (next.length <= 6) _digits = next.replaceFirst(RegExp(r'^0+'), '');
      }
      _fresh = false;
    });
  }

  Widget _key(String k) => Expanded(
    child: Padding(
      padding: const EdgeInsets.all(5),
      child: Material(
        color: k == 'C' || k == '⌫' ? Palette.cardHigh : Palette.ground,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _tap(k),
          child: SizedBox(
            height: 58,
            child: Center(
              child: k == '⌫'
                  ? Icon(Icons.backspace_outlined, color: Palette.text)
                  : Text(
                      k,
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        color: k == 'C' ? Palette.amber : Palette.text,
                      ),
                    ),
            ),
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final v = _value;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Palette.faint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(
              widget.max == null
                  ? fcfa(widget.unitPrice)
                  : '${fcfa(widget.unitPrice)} · ${widget.max} en stock',
              style: TextStyle(color: Palette.muted),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Palette.ground,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: _tooMany ? Palette.red : Palette.mint,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    _digits.isEmpty ? '0' : _digits,
                    key: const ValueKey('qty-display'),
                    style: TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      fontFeatures: tabular,
                      color: _digits.isEmpty ? Palette.faint : Palette.text,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    _tooMany
                        ? 'Maximum ${widget.max}'
                        : '= ${fcfa(v * widget.unitPrice)}',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _tooMany ? Palette.red : Palette.mint,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
              ['C', '0', '⌫'],
            ])
              Row(children: [for (final k in row) _key(k)]),
            const SizedBox(height: 8),
            Row(
              children: [
                if (widget.initial > 0) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context, 0),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Retirer'),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    onPressed: v == 0 || _tooMany
                        ? null
                        : () => Navigator.pop(context, v),
                    child: const Text('Valider'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
