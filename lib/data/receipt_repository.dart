import 'dart:convert';

import 'package:drift/drift.dart';

import '../services/receipt_pdf.dart';
import 'database.dart';
import 'repository.dart';

/// Reçus de caisse et apparence des documents (logo, modèle, phrase de fin).
extension Recus on Repository {
  /// Le reçu d'une vente, avec ses paiements.
  Future<ReceiptData> saleReceipt(
    int saleId, {
    ReceiptKind kind = ReceiptKind.recu,
  }) async {
    final all = await sales();
    final summary = all.firstWhere((s) => s.sale.id == saleId);
    final detail = (await salesWithLines([summary])).single;
    final pays =
        await (db.select(db.payments)
              ..where((p) => p.saleId.equals(saleId))
              ..orderBy([(p) => OrderingTerm(expression: p.createdAt)]))
            .get();
    return ReceiptData.fromSale(detail, pays, kind: kind);
  }

  Future<BrandSettings> brand() async {
    final rows = {
      for (final s in await (db.select(
        db.settings,
      )..where((s) => s.key.like('brand.%'))).get())
        s.key: s.value,
    };
    final logo = rows['brand.logo'];
    return BrandSettings(
      logo: logo == null ? null : base64Decode(logo),
      style: ReceiptStyle.values.firstWhere(
        (v) => v.name == rows['brand.style'],
        orElse: () => ReceiptStyle.neon,
      ),
      paper: PaperSize.values.firstWhere(
        (v) => v.name == rows['brand.paper'],
        orElse: () => PaperSize.ticket80,
      ),
      thanks: rows['brand.thanks'],
    );
  }

  /// Enregistre l'apparence. Le logo est gardé dans la base chiffrée,
  /// pas dans la galerie du téléphone.
  Future<void> saveBrand({
    required Uint8List? logo,
    required ReceiptStyle style,
    required PaperSize paper,
    required String thanks,
  }) => db.transaction(() async {
    Future<void> put(String key, String? value) async {
      if (value == null || value.trim().isEmpty) {
        await (db.delete(db.settings)..where((s) => s.key.equals(key))).go();
      } else {
        await db
            .into(db.settings)
            .insertOnConflictUpdate(
              SettingsCompanion.insert(key: key, value: value.trim()),
            );
      }
    }

    await put('brand.logo', logo == null ? null : base64Encode(logo));
    await put('brand.style', style.name);
    await put('brand.paper', paper.name);
    await put('brand.thanks', thanks);
  });
}
