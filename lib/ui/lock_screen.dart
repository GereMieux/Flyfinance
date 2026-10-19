import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../security/lock_service.dart';
import 'theme.dart';

/// Écran de verrouillage. Au premier lancement il fait choisir le code
/// (deux fois), ensuite il le demande, ou l'empreinte.
class LockScreen extends StatefulWidget {
  const LockScreen({super.key});
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  String _pin = '';
  String? _first;
  bool? _hasPin;
  bool _bio = false;
  String? _error;
  Timer? _tick;

  LockService get _lock => context.read<LockService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final has = await _lock.hasPin();
      final bio = has && await _lock.canUseBiometrics();
      if (!mounted) return;
      setState(() {
        _hasPin = has;
        _bio = bio;
      });
      if (bio) _lock.unlockWithBiometrics();
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _prompt {
    if (_hasPin == false) {
      return _first == null
          ? 'Choisissez un code à 4 chiffres'
          : 'Tapez le même code une 2e fois';
    }
    final wait = _lock.lockoutRemaining;
    if (wait != null)
      return 'Trop d’essais. Réessayez dans ${wait.inSeconds + 1} s';
    return 'Entrez votre code';
  }

  Future<void> _press(String d) async {
    if (_pin.length >= 4 || _lock.lockoutRemaining != null) return;
    setState(() {
      _pin += d;
      _error = null;
    });
    if (_pin.length < 4) return;

    if (_hasPin == false) {
      if (_first == null) {
        setState(() {
          _first = _pin;
          _pin = '';
        });
      } else if (_first == _pin) {
        await _lock.setPin(_pin);
      } else {
        setState(() {
          _first = null;
          _pin = '';
          _error = 'Les deux codes sont différents. Recommencez.';
        });
      }
      return;
    }
    final ok = await _lock.unlockWithPin(_pin);
    if (!ok && mounted) {
      setState(() {
        _pin = '';
        _error = 'Code incorrect';
      });
      if (_lock.lockoutRemaining != null) {
        _tick?.cancel();
        _tick = Timer.periodic(const Duration(seconds: 1), (t) {
          if (!mounted) return;
          setState(() {});
          if (_lock.lockoutRemaining == null) t.cancel();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasPin == null) return const Scaffold();
    Widget key(
      String label, {
      VoidCallback? onTap,
      Widget? child,
      String? semantics,
    }) => Semantics(
      button: true,
      label: semantics ?? label,
      child: Material(
        color: child == null ? Palette.card : Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap ?? () => _press(label),
          child: SizedBox(
            width: 76,
            height: 76,
            child: Center(
              child:
                  child ??
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
            ),
          ),
        ),
      ),
    );

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 28,
                    vertical: 24,
                  ),
                  child: Column(
                    children: [
                      const SizedBox(height: 32),
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: Palette.amber,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: const Icon(
                          Icons.lock_outline,
                          color: Palette.ink,
                          size: 36,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Gère-mieux',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _prompt,
                        style: const TextStyle(
                          fontSize: 16,
                          color: Palette.muted,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (var i = 0; i < 4; i++)
                            Container(
                              margin: const EdgeInsets.symmetric(horizontal: 9),
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i < _pin.length ? Palette.amber : null,
                                border: i < _pin.length
                                    ? null
                                    : Border.all(
                                        color: const Color(0xFF4A5A52),
                                        width: 2,
                                      ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 22,
                        child: _error == null
                            ? null
                            : Text(
                                _error!,
                                style: const TextStyle(color: Palette.red),
                              ),
                      ),
                      const Spacer(),
                      for (final row in const [
                        ['1', '2', '3'],
                        ['4', '5', '6'],
                        ['7', '8', '9'],
                      ])
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [for (final d in row) key(d)],
                          ),
                        ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _bio
                              ? key(
                                  'Empreinte',
                                  semantics: 'Déverrouiller avec l’empreinte',
                                  onTap: () => _lock.unlockWithBiometrics(),
                                  child: const Icon(
                                    Icons.fingerprint,
                                    size: 38,
                                    color: Palette.amber,
                                  ),
                                )
                              : const SizedBox(width: 76),
                          key('0'),
                          key(
                            'Effacer',
                            semantics: 'Effacer un chiffre',
                            onTap: () => setState(
                              () => _pin = _pin.isEmpty
                                  ? ''
                                  : _pin.substring(0, _pin.length - 1),
                            ),
                            child: const Icon(Icons.backspace_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 16,
                            color: Palette.mint,
                          ),
                          SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Données chiffrées sur ce téléphone',
                              style: TextStyle(
                                fontSize: 13,
                                color: Palette.muted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
