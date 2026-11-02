import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dartboard_input.dart';

/// Dartboard UI adapter for the first Double In visit of a doubles/team game.
/// No match rules or persistence live in this widget.
class B74DoublesOpeningInput extends StatefulWidget {
  const B74DoublesOpeningInput({
    super.key,
    required this.remaining,
    required this.onSubmit,
  });

  final int remaining;
  final Future<void> Function({
    required int score,
    required bool bust,
    required bool checkout,
    required int? checkoutDart,
    required int? openingDouble,
    required int? openingDart,
  }) onSubmit;

  @override
  State<B74DoublesOpeningInput> createState() => _B74DoublesOpeningInputState();
}

class _B74DoublesOpeningInputState extends State<B74DoublesOpeningInput> {
  late final _OpeningSource source;

  @override
  void initState() {
    super.initState();
    source = _OpeningSource(widget.remaining, widget.onSubmit);
  }

  @override
  void dispose() {
    source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChangeNotifierProvider<_OpeningSource>.value(
    value: source,
    child: const DartboardInput<_OpeningSource>(fillHeight: true),
  );
}

class _OpeningSource extends ChangeNotifier implements DartboardInputSource {
  _OpeningSource(this.remaining, this.submit);

  final int remaining;
  final Future<void> Function({
    required int score,
    required bool bust,
    required bool checkout,
    required int? checkoutDart,
    required int? openingDouble,
    required int? openingDart,
  }) submit;
  final List<DartEntry> _darts = [];
  final List<DartEntry> _redo = [];
  bool _busy = false;

  @override
  bool get inputLocked => _busy || _darts.length >= 3;
  @override
  bool get visitPending => false;
  @override
  List<DartEntry> get currentVisitDarts => List.unmodifiable(_darts);
  @override
  bool get liveBust => _outcome().bust;
  @override
  bool get canUndoDart => !_busy && _darts.isNotEmpty;
  @override
  bool get canRedoDart => !_busy && _redo.isNotEmpty;
  @override
  Future<void> flushHeldVisit() async {}

  ({int score, bool bust, bool checkout, int? openingDouble, int? openingDart}) _outcome() {
    int? openingDouble;
    int? openingDart;
    var score = 0;
    var bust = false;
    var checkout = false;
    for (var i = 0; i < _darts.length; i++) {
      final dart = _darts[i];
      if (openingDouble == null && dart.modifier == 2 && dart.field != 0) {
        openingDouble = dart.score;
        openingDart = i + 1;
      }
      if (openingDouble == null) continue;
      score += dart.score;
      final left = remaining - score;
      if (left < 0 || left == 1 || (left == 0 && dart.modifier != 2)) {
        bust = true;
        break;
      }
      if (left == 0) {
        checkout = true;
        break;
      }
    }
    if (bust) return (score: 0, bust: true, checkout: false, openingDouble: null, openingDart: null);
    return (score: score, bust: false, checkout: checkout,
      openingDouble: openingDouble, openingDart: openingDart);
  }

  @override
  Future<void> tapField(int field, int modifier) async {
    if (inputLocked) return;
    if (field == 0) modifier = 1;
    if (field == 25 && modifier == 3) return;
    if (field != 0 && field != 25 && (field < 1 || field > 20)) return;
    final score = field == 0 ? 0 : field * modifier;
    _darts.add(DartEntry(field: field, modifier: modifier, score: score));
    _redo.clear();
    final result = _outcome();
    notifyListeners();
    if (_darts.length < 3 && !result.bust && !result.checkout) return;
    _busy = true;
    notifyListeners();
    try {
      await submit(
        score: result.score,
        bust: result.bust,
        checkout: result.checkout,
        checkoutDart: result.checkout ? _darts.length : null,
        openingDouble: result.openingDouble,
        openingDart: result.openingDart,
      );
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  @override
  Future<void> undoLastDart() async {
    if (!canUndoDart) return;
    _redo.add(_darts.removeLast());
    notifyListeners();
  }

  @override
  Future<void> redoLastDart() async {
    if (!canRedoDart) return;
    final dart = _redo.removeLast();
    await tapField(dart.field, dart.modifier);
  }
}
