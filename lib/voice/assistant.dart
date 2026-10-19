import '../app_state.dart';
import '../data/database.dart';
import '../data/repository.dart';
import 'intent_parser.dart';

/// Une action qui modifie l'argent ou le stock : elle n'est exécutée
/// qu'après un « Oui » de l'utilisateur.
class PendingAction {
  PendingAction(this.title, this.lines, this.run);
  final String title;
  final List<(String, String)> lines;
  final Future<String> Function() run;
}

class AssistantReply {
  AssistantReply(this.text, {this.lines = const [], this.action});
  final String text;
  final List<(String, String)> lines;
  final PendingAction? action;
}

/// Comprend une phrase, la relie aux données de la boutique et prépare la
/// réponse. Les calculs viennent toujours du [Repository], jamais de l'IA.
class Assistant {
  Assistant(this.repo, {IntentParser? parser})
    : parser = parser ?? IntentParser();
  final Repository repo;
  final IntentParser parser;

  Future<AssistantReply> handle(String text) async {
    final intent = parser.parse(text);
    return switch (intent) {
      SellIntent() => _sell(intent),
      AddStockIntent() => _addStock(intent),
      StockQueryIntent() => _stock(intent),
      DebtQueryIntent() => _debts(intent),
      SalesTodayIntent() => _today(),
      UnknownIntent() => AssistantReply(
        "Je n'ai pas compris. Essayez par exemple : « Vends 3 sacs de riz à "
        'Fatou », « Qui me doit ? » ou « Combien de riz il reste ? ».',
      ),
    };
  }

  Future<AssistantReply> _sell(SellIntent i) async {
    final product = bestMatch(i.product, await repo.products(), (p) => p.name);
    if (product == null) {
      return AssistantReply(
        "Je ne trouve pas l'article « ${i.product} ». Ajoutez-le d'abord dans le stock.",
      );
    }
    final available = await repo.stockOf(product.id);
    if (i.qty > available) {
      return AssistantReply(
        'Il ne reste que $available ${product.unit} de ${product.name}.',
      );
    }
    final total = i.qty * product.price;
    final paid = switch (i.pay) {
      PayKind.full => total,
      PayKind.half => total ~/ 2,
      PayKind.none => 0,
      PayKind.amount => (i.amount ?? 0).clamp(0, total),
    };

    Contact? contact;
    String? newClient;
    if (i.client != null) {
      contact = bestMatch(
        i.client!,
        await repo.contacts(kind: 'client'),
        (c) => c.name,
      );
      if (contact == null) newClient = _title(i.client!);
    }
    if (paid < total && contact == null && newClient == null) {
      return AssistantReply(
        'Pour une vente à crédit, dites le nom du client. Par exemple : « Vends 2 riz à Fatou à crédit ».',
      );
    }
    final who = contact?.name ?? newClient;
    final method = i.method ?? 'especes';
    final lines = <(String, String)>[
      ('${i.qty} × ${product.name}', fcfa(total)),
      if (paid > 0) ('Payé (${paymentMethods[method]})', fcfa(paid)),
      if (paid < total)
        ('À crédit${who == null ? '' : ' pour $who'}', fcfa(total - paid)),
      if (newClient != null) ('Nouveau client', newClient),
    ];
    return AssistantReply(
      'Je prépare cette vente. Je confirme ?',
      lines: lines,
      action: PendingAction('Vente', lines, () async {
        final contactId =
            contact?.id ??
            (newClient == null ? null : await repo.addContact(newClient));
        await repo.recordSale(
          lines: [CartLine(product, i.qty)],
          contactId: contactId,
          paidNow: paid,
          method: method,
        );
        final left = await repo.stockOf(product.id);
        final alert = left <= product.alertMin
            ? ' Attention, bientôt en rupture.'
            : '';
        return 'Vente enregistrée. Il reste $left ${product.unit} de ${product.name}.$alert';
      }),
    );
  }

  Future<AssistantReply> _addStock(AddStockIntent i) async {
    final product = bestMatch(i.product, await repo.products(), (p) => p.name);
    if (product == null) {
      return AssistantReply("Je ne trouve pas l'article « ${i.product} ».");
    }
    final lines = [
      ('Entrée en stock', '${i.qty} ${product.unit} de ${product.name}'),
    ];
    return AssistantReply(
      'Je l’ajoute au stock ?',
      lines: lines,
      action: PendingAction('Entrée en stock', lines, () async {
        await repo.adjustStock(product.id, i.qty, 'achat');
        final left = await repo.stockOf(product.id);
        return 'C’est noté. Vous avez maintenant $left ${product.unit} de ${product.name}.';
      }),
    );
  }

  Future<AssistantReply> _stock(StockQueryIntent i) async {
    if (i.product == null) {
      final low = await repo.lowStock();
      if (low.isEmpty) return AssistantReply('Aucun article n’est en rupture.');
      return AssistantReply(
        '${low.length} article${low.length > 1 ? 's' : ''} à commander.',
        lines: [
          for (final s in low) (s.product.name, '${s.qty} ${s.product.unit}'),
        ],
      );
    }
    final all = await repo.stock();
    final s = bestMatch(i.product!, all, (s) => s.product.name);
    if (s == null) return AssistantReply("Je ne trouve pas « ${i.product} ».");
    return AssistantReply(
      'Il reste ${s.qty} ${s.product.unit} de ${s.product.name}.'
      '${s.low ? ' C’est bientôt la rupture.' : ''}',
    );
  }

  Future<AssistantReply> _debts(DebtQueryIntent i) async {
    final debtors = await repo.debtors();
    if (i.client != null) {
      final d = bestMatch(i.client!, debtors, (d) => d.contact.name);
      if (d == null) {
        return AssistantReply('${_title(i.client!)} ne vous doit rien.');
      }
      return AssistantReply(
        '${d.contact.name} vous doit ${spokenFcfa(d.due)}.',
      );
    }
    if (debtors.isEmpty) {
      return AssistantReply('Personne ne vous doit d’argent.');
    }
    final total = debtors.fold<int>(0, (s, d) => s + d.due);
    return AssistantReply(
      '${debtors.length} client${debtors.length > 1 ? 's' : ''} vous '
      'doi${debtors.length > 1 ? 'vent' : 't'} ${spokenFcfa(total)}.',
      lines: [for (final d in debtors) (d.contact.name, fcfa(d.due))],
    );
  }

  Future<AssistantReply> _today() async {
    final n = repo.now();
    final s = await repo.statsSince(DateTime(n.year, n.month, n.day));
    return AssistantReply(
      'Aujourd’hui : ${s.count} vente${s.count > 1 ? 's' : ''} pour '
      '${spokenFcfa(s.sales)}, bénéfice ${spokenFcfa(s.profit)}.',
    );
  }

  String _title(String s) => s
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');
}
