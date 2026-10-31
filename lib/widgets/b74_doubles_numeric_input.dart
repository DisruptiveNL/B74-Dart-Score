import 'package:flutter/material.dart';

/// 701 adapter using the same keypad layout and quick scores as singles.
/// Does not depend on GameProvider, so the 501 workflow stays unchanged.
class B74DoublesNumericInput extends StatefulWidget {
  const B74DoublesNumericInput({
    super.key,
    required this.remaining,
    required this.onSubmit,
    this.disabled = false,
  });

  final int remaining;
  final bool disabled;
  final Future<void> Function(
    int score,
    bool bust,
    bool checkout,
    int? checkoutDart,
  )
  onSubmit;

  @override
  State<B74DoublesNumericInput> createState() => _B74DoublesNumericInputState();
}

class _B74DoublesNumericInputState extends State<B74DoublesNumericInput> {
  String _value = '';
  bool _bust = false;
  bool _busy = false;
  int? _confirmedCheckoutDart;
  String? _error;
  static const quick = [26, 30, 57, 41, 45, 60, 95, 100, 140, 180];

  void _set(String value, {bool bust = false}) => setState(() {
    _value = value;
    _bust = bust;
    _error = null;
  });

  Future<void> _accept() async {
    if (_busy || widget.disabled || _value.isEmpty) return;
    final score = int.tryParse(_value);
    if (score == null || score < 0 || score > 180) {
      setState(() => _error = 'Voer een score van 0 t/m 180 in');
      return;
    }
    bool checkout = false;
    bool bust = _bust;
    if (!bust && score > widget.remaining) bust = true;
    if (!bust && widget.remaining - score == 1) bust = true;
    if (!bust && score == widget.remaining) {
      final dart = await _checkoutDart();
      if (dart == null || !mounted) return;
      _confirmedCheckoutDart = dart;
      checkout = true;
    }
    if (bust) {
      final dart = await showDialog<int>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('BUST'),
          content: const Text('Bij welke dart ontstond de bust?'),
          actions: [
            for (final n in [1, 2, 3])
              TextButton(
                onPressed: () => Navigator.pop(c, n),
                child: Text('DART $n'),
              ),
          ],
        ),
      );
      if (dart == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit(
        bust ? 0 : score,
        bust,
        checkout,
        checkout ? _confirmedCheckoutDart : null,
      );
      if (mounted) _set('');
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Like singles 501: the writer confirms the finishing dart only.
  /// The score was already entered through the numeric keypad.
  Future<int?> _checkoutDart() => showDialog<int>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('CHECKOUT'),
      content: const Text('Met welke dart is uitgegooid?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('ANNULEREN'),
        ),
        for (final dart in [1, 2, 3])
          TextButton(
            onPressed: () => Navigator.pop(context, dart),
            child: Text('DART $dart'),
          ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final disabled = widget.disabled || _busy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _bust ? 'BUST' : (_value.isEmpty ? '—' : _value),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (_error != null)
          Text(
            _error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        // Keep BUST and ACCEPT directly below the keypad, as in singles.
        // An Expanded here pushed both actions to the bottom of the fixed
        // tablet panel, outside the visible viewport on smaller tablets.
        SingleChildScrollView(
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
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(64, 38),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: disabled ? null : () => _set('$n'),
                      child: Text('$n'),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              for (final row in const [
                ['1', '2', '3'],
                ['4', '5', '6'],
                ['7', '8', '9'],
                ['CLEAR', '0', '⌫'],
              ])
                Row(
                  children: [
                    for (final key in row)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 3,
                            vertical: 2,
                          ),
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 2,
                                vertical: 4,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: disabled
                                ? null
                                : () {
                                    if (key == 'CLEAR') {
                                      _set('');
                                      return;
                                    }
                                    if (key == '⌫') {
                                      _set(
                                        _value.isEmpty
                                            ? ''
                                            : _value.substring(
                                                0,
                                                _value.length - 1,
                                              ),
                                      );
                                      return;
                                    }
                                    if (_value.length < 3) _set('$_value$key');
                                  },
                            child: Text(key),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        OutlinedButton(
          onPressed: disabled ? null : () => _set('0', bust: true),
          child: const Text('BUST'),
        ),
        FilledButton(
          onPressed: disabled || _value.isEmpty ? null : _accept,
          child: const Text('ACCEPT'),
        ),
      ],
    );
  }
}
