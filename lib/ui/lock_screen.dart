import 'dart:async';

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../security/lock_service.dart';
import 'theme.dart';
import 'widgets.dart';

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

  /// Augmente à chaque code faux : relance la secousse des points.
  int _shakes = 0;

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
    if (wait != null) {
      return 'Trop d’essais. Réessayez dans ${wait.inSeconds + 1} s';
    }
    return 'Entrez votre code';
  }

  Future<void> _press(String d) async {
    if (_pin.length >= 4 || _lock.lockoutRemaining != null) return;
    Haptics.tap();
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
        Haptics.warning();
        setState(() {
          _first = null;
          _pin = '';
          _shakes++;
          _error = 'Les deux codes sont différents. Recommencez.';
        });
      }
      return;
    }
    final ok = await _lock.unlockWithPin(_pin);
    if (!ok && mounted) {
      Haptics.warning();
      setState(() {
        _pin = '';
        _shakes++;
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
                        'FLYFINANCE',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1.5,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _prompt,
                        style: TextStyle(fontSize: 16, color: Palette.muted),
                      ),
                      const SizedBox(height: 24),
                      // Les points tremblent quand le code est faux, comme
                      // sur les applications bancaires.
                      TweenAnimationBuilder<double>(
                        key: ValueKey(_shakes),
                        tween: Tween(begin: _shakes == 0 ? 1 : 0, end: 1),
                        duration: const Duration(milliseconds: 420),
                        builder: (_, v, child) => Transform.translate(
                          offset: Offset(
                            math.sin(v * math.pi * 6) * 12 * (1 - v),
                            0,
                          ),
                          child: child,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            for (var i = 0; i < 4; i++)
                              AnimatedContainer(
                                duration: Motion.fast,
                                curve: Motion.curve,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                ),
                                width: i < _pin.length ? 18 : 16,
                                height: i < _pin.length ? 18 : 16,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: i < _pin.length
                                      ? Palette.amber
                                      : Colors.transparent,
                                  border: Border.all(
                                    color: i < _pin.length
                                        ? Palette.amber
                                        : Palette.faint,
                                    width: 2,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 22,
                        child: _error == null
                            ? null
                            : Text(
                                _error!,
                                style: TextStyle(color: Palette.red),
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
                                  child: Icon(
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
                            onTap: () => setState(() {
                              Haptics.tap();
                              _pin = _pin.isEmpty
                                  ? ''
                                  : _pin.substring(0, _pin.length - 1);
                            }),
                            child: const Icon(Icons.backspace_outlined),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.verified_user_outlined,
                            size: 16,
                            color: Palette.mint,
                          ),
                          const SizedBox(width: 6),
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
