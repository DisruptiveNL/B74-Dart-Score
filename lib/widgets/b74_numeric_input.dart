import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';

/// B74 competition numeric visit entry. No auto-accept or timer.
class B74NumericInput extends StatefulWidget {
  const B74NumericInput({super.key});
  @override
  State<B74NumericInput> createState() => _B74NumericInputState();
}

class _B74NumericInputState extends State<B74NumericInput> {
  String _value = '';
  bool _busy = false;
  bool _bust = false;
  String? _error;
  static const quick = [26, 30, 57, 41, 45, 60, 95, 100, 140, 180];

  void _set(String value, {bool bust = false}) => setState(() {
    _value = value;
    _bust = bust;
    _error = null;
  });

  Future<void> _accept(GameProvider provider) async {
    if (_busy || _value.isEmpty) return;
    final score = int.tryParse(_value);
    if (score == null || score > 180) {
      setState(() => _error = 'Voer een score van 0 t/m 180 in');
      return;
    }
    final checkout = !_bust && score == provider.currentPlayerState.remaining;
    int? finishDart;
    if (checkout) {
      finishDart = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('CHECKOUT!'),
          content: const Text('Met welke dart is de finish gegooid?'),
          actions: [for (final n in [1, 2, 3])
            TextButton(onPressed: () => Navigator.pop(dialogContext, n), child: Text('DART $n'))],
        ),
      );
      if (finishDart == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await provider.submitNumericVisit(score, finishDart: finishDart, bust: _bust);
      if (mounted) _set('');
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    final disabled = _busy || provider.inputLocked;
    // Keep competition actions visible even on short screens. Only the
    // optional quick scores and numeric keypad scroll.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Text(
            _bust ? 'BUST' : (_value.isEmpty ? '—' : _value),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  alignment: WrapAlignment.center,
                  children: [
                    for (final n in quick)
                      OutlinedButton(
                        onPressed: disabled ? null : () => _set('$n'),
                        child: Text('$n'),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                for (final row in const [
                  ['1', '2', '3'],
                  ['4', '5', '6'],
                  ['7', '8', '9'],
                  ['CLEAR', '0', '⌫'],
                ])
                  Row(children: [
                    for (final key in row)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(3),
                          child: OutlinedButton(
                            onPressed: disabled ? null : () {
                              if (key == 'CLEAR') { _set(''); return; }
                              if (key == '⌫') {
                                _set(_value.isEmpty ? '' : _value.substring(0, _value.length - 1));
                                return;
                              }
                              if (_value.length < 3) _set('$_value$key');
                            },
                            child: Text(key),
                          ),
                        ),
                      ),
                  ]),
              ],
            ),
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              tooltip: 'Undo laatste beurt',
              icon: const Icon(Icons.undo_rounded),
              onPressed: disabled || !provider.canUndoDart
                  ? null
                  : () async { await provider.undoLastDart(); },
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: disabled ? null : () => _set('0'),
                  child: const Text('MISS'),
                )),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(
                  onPressed: disabled ? null : () => _set('0', bust: true),
                  child: const Text('BUST'),
                )),
              ]),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: disabled || _value.isEmpty ? null : () => _accept(provider),
                  child: const Text('ACCEPT'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
