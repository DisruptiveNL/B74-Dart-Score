import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/layout.dart';

/// Holds how the tablet layouts are arranged: which side of the screen the
/// score input sits on, and where the divider stands on each screen that has
/// one. Everything here persists across launches.
///
/// These only ever apply to a layout that puts two panes side by side, which is
/// a tablet. A phone is portrait only and stacks its rows, so the values are
/// loaded but never read there.
class TabletLayoutProvider extends ChangeNotifier {
  static const _sideKey = 'input_side';

  InputSide _side = kDefaultInputSide;

  /// The dividers, keyed by the screen and the orientation they belong to.
  ///
  /// Both halves of that key earn their place. A screen, because the game, the
  /// history and the player list divide different things: a list of names next
  /// to a page of statistics wants a different share than a scoreboard next to
  /// an input. An orientation, because a division that reads well across a
  /// landscape tablet leaves an upright one with two columns too narrow for
  /// what is in them.
  final Map<String, double> _splits = {};

  /// The side the input sits on.
  InputSide get side => _side;

  /// Creates the provider and asynchronously loads the stored values.
  TabletLayoutProvider() {
    _load();
  }

  /// The shared_preferences key for one divider.
  static String _splitKey(SplitPane pane, bool landscape) =>
      'tablet_split_${pane.name}_${landscape ? 'landscape' : 'portrait'}';

  /// Share of the width the first pane of [pane] takes in this orientation,
  /// between [kMinSplitFraction] and [kMaxSplitFraction].
  double splitFraction(SplitPane pane, {required bool landscape}) =>
      _splits[_splitKey(pane, landscape)] ?? kDefaultSplitFraction;

  /// Reads the saved values from shared_preferences, keeping the defaults when
  /// nothing was ever stored or the stored side is not one of the values.
  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();

    final savedSide = prefs.getString(_sideKey);
    if (savedSide != null) {
      _side = InputSide.values.firstWhere(
        (s) => s.name == savedSide,
        orElse: () => kDefaultInputSide,
      );
    }

    for (final pane in SplitPane.values) {
      for (final landscape in [true, false]) {
        final key = _splitKey(pane, landscape);
        final saved = prefs.getDouble(key);
        if (saved != null) {
          _splits[key] = saved
              .clamp(kMinSplitFraction, kMaxSplitFraction)
              .toDouble();
        }
      }
    }

    if (savedSide != null || _splits.isNotEmpty) notifyListeners();
  }

  /// Moves the input to [side], notifies listeners and persists the choice.
  ///
  /// Stored by name rather than by index so the enum stays free to grow.
  Future<void> setSide(InputSide side) async {
    if (side == _side) return;
    _side = side;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sideKey, side.name);
  }

  /// Moves the divider of [pane] in this orientation so its first pane takes
  /// [fraction] of the width.
  ///
  /// A drag calls this on every frame, so it only notifies; the result reaches
  /// disk through [persistSplitFraction] once the gesture is over.
  void setSplitFraction(
    SplitPane pane,
    double fraction, {
    required bool landscape,
  }) {
    final clamped = fraction
        .clamp(kMinSplitFraction, kMaxSplitFraction)
        .toDouble();
    if (clamped == splitFraction(pane, landscape: landscape)) return;
    _splits[_splitKey(pane, landscape)] = clamped;
    notifyListeners();
  }

  /// Writes the divider of [pane] in this orientation down as it stands.
  Future<void> persistSplitFraction(
    SplitPane pane, {
    required bool landscape,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(
      _splitKey(pane, landscape),
      splitFraction(pane, landscape: landscape),
    );
  }
}
