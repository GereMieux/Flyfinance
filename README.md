# FLYFINANCE

Application mobile de gestion pour boutiques et grossistes (Côte d'Ivoire, FCFA) :
ventes, stock, crédits clients, recherche et assistant vocal. Elle fonctionne
entièrement hors ligne.

## Ce que fait la version actuelle

- **Verrouillage** : code à 4 chiffres (haché, jamais stocké en clair),
  empreinte ou visage, blocage d'une minute après 5 erreurs, verrouillage
  automatique après 5 minutes en arrière-plan.
- **Base locale chiffrée** (SQLite3MultipleCiphers). La clé est tirée au hasard
  au premier lancement et gardée dans le coffre du téléphone.
- **Accueil** : chiffre d'affaires du jour, de la semaine ou du mois, graphique
  des 7 derniers jours, bénéfice, encaissé, crédits dehors, alerte de rupture,
  et un bouton œil pour masquer tous les montants.
- **Vendre** : prix détail ou gros, paiement tout / moitié / à crédit / autre
  montant, et espèces, Orange Money, MTN MoMo, Moov Money ou Wave.
- **Toutes les ventes** : statuts Soldée, Acompte, Reliquat, Non payé, Annulée,
  tri par statut, encaissement du reste, annulation (le stock revient).
- **Stock** : articles, entrée (achat), sortie (perte), inventaire, liste
  « à commander ». Le stock est la somme des mouvements, jamais un chiffre
  écrasé.
- **Crédits** : total dû, retard de plus de 30 jours, rappel WhatsApp prérempli,
  encaissement qui solde les ventes les plus anciennes d'abord.
- **Recherche** : articles, clients, fournisseurs et ventes, sans accents ni
  majuscules.
- **Assistant vocal** : comprend hors ligne les commandes courantes
  (« Vends 3 sacs de riz à Fatou, elle paie la moitié par Wave », « Qui me
  doit ? », « Combien de riz il reste ? », « J'ai reçu 10 bidons d'huile »,
  « Combien j'ai vendu aujourd'hui ? »), demande toujours « Oui / Non » avant
  d'écrire, et répond à voix haute avec une voix féminine ou masculine.
  Langues de l'écoute et de la voix : français, anglais, arabe, espagnol.

- **Vente en ligne** (onglet « En ligne ») : catalogue tiré du stock avec
  catégories, marques, tailles, couleurs, description et prix en ligne ;
  promotions en pourcentage ou prix promo, sur un article, une catégorie ou
  toute la boutique, avec date de début et de fin, et soldes ; annonces ;
  vitrine telle que la voit le client ; partage du catalogue sur WhatsApp.
  Commandes avec taille, couleur, adresse et frais de livraison, payées par
  Orange Money, Wave ou à la livraison ; demande de paiement envoyée par
  WhatsApp ; le stock commandé est réservé, et la commande livrée devient une
  vente de la boutique (stock, tableau de bord, carnet d'adresses). Ces
  données sont dans une deuxième base chiffrée (`flyfinance_en_ligne`).

## Pas encore fait

- Compréhension des phrases libres par l'IA en ligne (Claude), via un serveur
  qui garde la clé : les phrases non reconnues reçoivent pour l'instant un
  exemple de commande. L'analyseur hors ligne ne comprend que le français et
  un peu d'anglais.
- Sauvegarde et synchronisation entre téléphones (Supabase).
- Vendeurs avec droits limités, impression de reçus, export PDF / Excel.
- Paiement Orange Money et Wave automatique (API marchandes) : pour l'instant
  le client paie sur le numéro du commerçant, qui confirme la réception.
- Photos des articles et boutique en ligne publique (site web où le client
  commande lui-même).

## Développer

```sh
flutter pub get
dart run build_runner build   # régénère lib/data/*.g.dart
flutter test
flutter build apk --release
```

Organisation du code :

| Dossier | Rôle |
| --- | --- |
| `lib/data/` | Tables (drift) et `Repository` : toutes les règles métier |
| `lib/security/` | Code PIN, empreinte, clé de la base |
| `lib/voice/` | Analyseur de phrases, assistant, micro et voix |
| `lib/ui/` | Écrans |
| `test/` | Tests des règles, de l'assistant, du verrouillage et de l'écran d'accueil |
