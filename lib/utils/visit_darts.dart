import '../l10n/app_localizations.dart';

/// One dart of a visit as the scoreboards of the target modes show it: its
/// label, the ring it landed in, and whether it missed.
typedef VisitDart = ({String label, int multiplier, bool miss});

/// The dart [field] and [multiplier] describe, labelled the way X01 labels a
/// hit: `S20`, `D20`, `T20`, `25` for the outer bull, `Bull` for the inner,
/// and the localized miss for a dart that landed nowhere. Shared by Cricket,
/// Shanghai and Around the Clock, whose throws all carry a field and a ring.
VisitDart visitDartFrom(int field, int multiplier, AppLocalizations l) {
  if (field == 0 || multiplier == 0) {
    return (label: l.miss, multiplier: 0, miss: true);
  }
  if (field == 25) {
    return (
      label: multiplier == 2 ? 'Bull' : '25',
      multiplier: multiplier,
      miss: false,
    );
  }
  final ring = switch (multiplier) {
    3 => 'T',
    2 => 'D',
    _ => 'S',
  };
  return (label: '$ring$field', multiplier: multiplier, miss: false);
}
