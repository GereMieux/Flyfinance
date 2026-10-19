import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  late final AppState _state = AppState(widget.repo);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
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
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _state),
        ChangeNotifierProvider.value(value: widget.lock),
        Provider.value(value: widget.shop),
      ],
      child: MaterialApp(
        title: 'FLYFINANCE',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: Consumer<LockService>(
          builder: (_, lock, _) =>
              lock.unlocked ? const Shell() : const LockScreen(),
        ),
      ),
    );
  }
}
