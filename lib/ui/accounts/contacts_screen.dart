import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../app_state.dart';
import '../../data/accounts_repository.dart';
import '../../data/repository.dart';
import '../theme.dart';
import '../widgets.dart';
import 'broadcast_screen.dart';
import 'client_account_screen.dart';
import 'common.dart';
import 'reminders_screen.dart';
import 'supplier_account_screen.dart';

class _Data {
  _Data(this.clients, this.suppliers, this.reminders);
  final List<ClientAccount> clients;
  final List<SupplierAccount> suppliers;
  final int reminders;
}

/// Carnet d'adresses : clients et fournisseurs, chacun avec son compte.
class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key, this.suppliers = false});
  final bool suppliers;

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late bool _suppliers = widget.suppliers;
  final _q = TextEditingController();

  Future<_Data> _load(Repository r) async => _Data(
    await r.clientAccounts(),
    await r.supplierAccounts(),
    (await r.remindersDue()).length,
  );

  void _open(Widget w) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => w));

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Clients et fournisseurs'),
        actions: const [
          Padding(padding: EdgeInsets.only(right: 12), child: EyeButton()),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: Palette.green,
        foregroundColor: Palette.text,
        onPressed: () async {
          final id = await editContact(
            context,
            kind: _suppliers ? 'fournisseur' : 'client',
          );
          if (id == null) return;
          app.changed();
          _open(
            _suppliers ? SupplierAccountScreen(id) : ClientAccountScreen(id),
          );
        },
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(_suppliers ? 'Fournisseur' : 'Client'),
      ),
      body: Loader<_Data>(
        load: _load,
        builder: (context, d) {
          final q = normalize(_q.text);
          bool hit(String name, String? phone, String? address) =>
              q.isEmpty ||
              normalize(name).contains(q) ||
              (phone ?? '').contains(q) ||
              normalize(address ?? '').contains(q);
          final clients = d.clients
              .where(
                (a) => hit(a.contact.name, a.contact.phone, a.contact.address),
              )
              .toList();
          final suppliers = d.suppliers
              .where(
                (a) => hit(a.contact.name, a.contact.phone, a.contact.address),
              )
              .toList();
          final owedToMe = d.clients.fold<int>(0, (s, a) => s + a.due);
          final iOwe = d.suppliers.fold<int>(
            0,
            (s, a) => s + (a.balance > 0 ? a.balance : 0),
          );
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            children: [
              SegmentedButton<bool>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  selectedBackgroundColor: Palette.amber,
                  selectedForegroundColor: Palette.ink,
                  side: BorderSide(color: Palette.line),
                ),
                segments: [
                  ButtonSegment(
                    value: false,
                    label: Text('Clients (${d.clients.length})'),
                  ),
                  ButtonSegment(
                    value: true,
                    label: Text('Fournisseurs (${d.suppliers.length})'),
                  ),
                ],
                selected: {_suppliers},
                onSelectionChanged: (s) => setState(() => _suppliers = s.first),
              ),
              const SizedBox(height: 12),
              Panel(
                color: _suppliers ? Palette.redSoft : Palette.amberSoft,
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _suppliers
                            ? 'Je dois aux fournisseurs'
                            : 'Les clients me doivent',
                        style: TextStyle(
                          color: _suppliers ? Palette.red : Palette.amber,
                        ),
                      ),
                    ),
                    Text(
                      app.money(_suppliers ? iOwe : owedToMe),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_suppliers) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _open(const BroadcastScreen()),
                        icon: const Icon(Icons.campaign_outlined, size: 18),
                        label: const Text('Annoncer'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Badge.count(
                        count: d.reminders,
                        isLabelVisible: d.reminders > 0,
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                          ),
                          onPressed: () => _open(const RemindersScreen()),
                          icon: const Icon(
                            Icons.notifications_active_outlined,
                            size: 18,
                          ),
                          label: const Text('Relances'),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Nom, téléphone ou quartier',
                ),
              ),
              const SizedBox(height: 12),
              if (_suppliers && suppliers.isEmpty)
                const EmptyState(
                  'Aucun fournisseur.\nTouchez « Fournisseur » pour en ajouter un.',
                  icon: Icons.local_shipping_outlined,
                ),
              if (!_suppliers && clients.isEmpty)
                const EmptyState(
                  'Aucun client.\nTouchez « Client » pour en ajouter un.',
                  icon: Icons.people_outline,
                ),
              if (_suppliers)
                for (final a in suppliers)
                  _tile(
                    name: a.contact.name,
                    sub: _sub(a.contact.phone, a.contact.address),
                    amount: a.balance == 0
                        ? null
                        : a.balance > 0
                        ? ('Je dois', app.money(a.balance), Palette.red)
                        : ('Avance', app.money(-a.balance), Palette.mint),
                    supplier: true,
                    onTap: () => _open(SupplierAccountScreen(a.contact.id)),
                  )
              else
                for (final a in clients)
                  _tile(
                    name: a.contact.name,
                    sub: _sub(a.contact.phone, a.contact.address),
                    amount: a.due > 0
                        ? ('Doit', app.money(a.due), Palette.amber)
                        : a.provision > 0
                        ? ('Provision', app.money(a.provision), Palette.blue)
                        : null,
                    supplier: false,
                    onTap: () => _open(ClientAccountScreen(a.contact.id)),
                  ),
            ],
          );
        },
      ),
    );
  }

  String _sub(String? phone, String? address) => [?phone, ?address].join(' · ');

  Widget _tile({
    required String name,
    required String sub,
    required (String, String, Color)? amount,
    required bool supplier,
    required VoidCallback onTap,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Material(
      color: Palette.card,
      borderRadius: BorderRadius.circular(16),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: supplier
              ? Palette.purple.withValues(alpha: 0.15)
              : Palette.mintSoft,
          child: Text(
            name.characters.first.toUpperCase(),
            style: TextStyle(
              color: supplier ? Palette.purple : Palette.mint,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: sub.isEmpty
            ? null
            : Text(
                sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Palette.muted),
              ),
        trailing: amount == null
            ? Icon(Icons.chevron_right, color: Palette.muted)
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    amount.$1,
                    style: TextStyle(fontSize: 12, color: amount.$3),
                  ),
                  Text(
                    amount.$2,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: amount.$3,
                    ),
                  ),
                ],
              ),
      ),
    ),
  );
}
