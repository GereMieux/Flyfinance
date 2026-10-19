import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:local_auth/local_auth.dart';
import 'package:provider/provider.dart';

import 'app_state.dart';
import 'data/database.dart';
import 'data/repository.dart';
import 'data/shop_database.dart';
import 'data/shop_repository.dart';
import 'security/lock_service.dart';
import 'ui/lock_screen.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';
import 'ui/widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  const store = DeviceSecretStore();
  final key = await databaseKey(store);
  final repo = Repository(AppDatabase.encrypted(key));
  runApp(
    GereMieuxApp(
      repo: repo,
      shop: ShopRepository(ShopDatabase.encrypted(key), repo),
      lock: LockService(store, auth: LocalAuthentication()),
    ),
  );
}

class GereMieuxApp extends StatefulWidget {
  const GereMieuxApp({
    super.key,
    required this.repo,
    required this.shop,
    required this.lock,
  });
  final Repository repo;
  final ShopRepository shop;
  final LockService lock;

  @override
  State<GereMieuxApp> createState() => _GereMieuxAppState();
}

class _GereMieuxAppState extends State<GereMieuxApp>
    with WidgetsBindingObserver {
  late final AppState _state = AppState(widget.repo, store: widget.lock.store)
    ..addListener(_onPrefs);

  /// Mode clair ou sombre réellement affiché.
  Brightness? _shown;

  /// Vrai quand l'application passe en arrière-plan : on cache alors les
  /// chiffres dans l'aperçu des applications récentes.
  bool _privacy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _state.loadPrefs();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) widget.lock.onPaused();
    if (s == AppLifecycleState.resumed) widget.lock.onResumed();
    final hide = s != AppLifecycleState.resumed;
    if (hide != _privacy) setState(() => _privacy = hide);
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  void _onPrefs() => setState(() {});

  Brightness _brightness() => switch (_state.appearance) {
    Appearance.jour => Brightness.light,
    Appearance.nuit => Brightness.dark,
    Appearance.auto =>
      WidgetsBinding.instance.platformDispatcher.platformBrightness,
  };

  /// Les couleurs de [Palette] sont lues à la construction des écrans : au
  /// changement de mode, on reconstruit donc tout, y compris les pages
  /// ouvertes, sans perdre ce qui est en cours de saisie.
  void _repaintAll() {
    void visit(Element e) {
      e.markNeedsBuild();
      e.visitChildren(visit);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) (context as Element).visitChildren(visit);
    });
  }

  @override
  Widget build(BuildContext context) {
    final b = _brightness();
    if (_shown != null && _shown != b) _repaintAll();
    _shown = b;
    final theme = buildTheme(b);
    SystemChrome.setSystemUIOverlayStyle(overlayStyle(b));
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _state),
        ChangeNotifierProvider.value(value: widget.lock),
        Provider.value(value: widget.shop),
      ],
      child: MaterialApp(
        title: 'FLYFINANCE',
        debugShowCheckedModeBanner: false,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        // Le texte suit la taille choisie dans le téléphone, sans casser
        // la mise en page.
        builder: (context, child) {
          final mq = MediaQuery.of(context);
          return MediaQuery(
            data: mq.copyWith(
              textScaler: mq.textScaler.clamp(
                minScaleFactor: 0.9,
                maxScaleFactor: 1.3,
              ),
            ),
            child: Stack(
              children: [
                child!,
                if (_privacy) const Positioned.fill(child: PrivacyCover()),
              ],
            ),
          );
        },
        // Calendriers et heures en français (choix des dates d'échéance).
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: Consumer<LockService>(
          builder: (_, lock, _) =>
              lock.unlocked ? const Shell() : const LockScreen(),
        ),
      ),
    );
  }
}
