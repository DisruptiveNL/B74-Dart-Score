import '../l10n/app_localizations.dart';
import '../models/around_the_clock_game.dart';
import '../models/checkout_ladder_game.dart'
    show CheckoutLadderGame, CheckoutLadderVariant;
import '../models/cricket_game.dart';
import '../models/game.dart';
import '../models/shanghai_game.dart';

/// Localized display names for the per-mode game settings, shared by the
/// history lists, the history detail screens and the rematch dialog so the
/// same setting always reads the same way.

/// Localized display name for an X01 check-in [mode].
String checkInLabel(AppLocalizations l, GameMode mode) {
  switch (mode) {
    case GameMode.straightIn:
      return l.straight;
    case GameMode.doubleIn:
      return l.double_;
    case GameMode.masterIn:
      return l.master;
  }
}

/// Localized display name for an X01 check-out [mode].
String checkOutLabel(AppLocalizations l, CheckoutMode mode) {
  switch (mode) {
    case CheckoutMode.straightOut:
      return l.straight;
    case CheckoutMode.doubleOut:
      return l.double_;
    case CheckoutMode.masterOut:
      return l.master;
  }
}

/// Localized "check-in to check-out" summary of one player's X01 rules, used
/// where the per-player rules matter more than the game defaults.
String checkInOutLabel(
  AppLocalizations l,
  GameMode checkIn,
  CheckoutMode checkOut,
) => '${checkInLabel(l, checkIn)} → ${checkOutLabel(l, checkOut)}';

/// The check-in/check-out label for [playerId] in [game], or null when the game
/// is played without handicaps and the game-wide rules already say everything.
String? handicapRulesLabel(AppLocalizations l, Game game, int? playerId) =>
    game.hasHandicaps
    ? checkInOutLabel(l, game.checkInFor(playerId), game.checkOutFor(playerId))
    : null;

/// Localized display name for how a game's throwing [order] was determined.
String startingOrderLabel(AppLocalizations l, StartingOrder order) {
  switch (order) {
    case StartingOrder.random:
      return l.startingOrderRandom;
    case StartingOrder.fixed:
      return l.startingOrderFixed;
  }
}

/// Names one board segment: the [field] hit and with which [multiplier]
/// (1 single, 2 double, 3 triple), as `S20`, `D20` or `T20`.
///
/// Field 0 is a miss and field 25 the bull, whose outer ring counts 25 and
/// whose centre is the bull's eye. Deliberately not the same notation as
/// `DartEntry.label`: that one names a dart as it is entered, where a single
/// carries no prefix, while a statistics list is only scannable when every
/// entry is spelled the same way.
String segmentLabel(AppLocalizations l, int field, int multiplier) {
  if (field == 0) return l.miss;
  if (field == 25) return multiplier == 2 ? l.bull : '25';
  switch (multiplier) {
    case 2:
      return 'D$field';
    case 3:
      return 'T$field';
    default:
      return 'S$field';
  }
}

/// Localized display name for a Cricket [variant].
String cricketVariantLabel(AppLocalizations l, CricketVariant variant) {
  switch (variant) {
    case CricketVariant.normal:
      return l.cricketVariantNormal;
    case CricketVariant.cutThroat:
      return l.cricketVariantCutThroat;
  }
}

/// Localized display name for a Cricket scoring [mode].
String cricketScoringModeLabel(AppLocalizations l, CricketScoringMode mode) {
  switch (mode) {
    case CricketScoringMode.standard:
      return l.cricketStandard;
    case CricketScoringMode.simple:
      return l.cricketSimple;
  }
}

/// Localized display name for a Shanghai [variant].
String shanghaiVariantLabel(AppLocalizations l, ShanghaiVariant variant) {
  switch (variant) {
    case ShanghaiVariant.classic:
      return l.shanghaiClassic;
    case ShanghaiVariant.clockwise:
      return l.shanghaiClockwise;
    case ShanghaiVariant.sequential:
      return l.shanghaiSequential;
  }
}

/// Localized display name for an Around the Clock [variant].
String aroundTheClockVariantLabel(
  AppLocalizations l,
  AroundTheClockVariant variant,
) {
  switch (variant) {
    case AroundTheClockVariant.basic:
      return l.aroundClockBasic;
    case AroundTheClockVariant.fullSegments:
      return l.aroundClockFullSegments;
    case AroundTheClockVariant.skipRules:
      return l.aroundClockSkipRules;
  }
}

/// Localized display name for a Checkout Ladder [variant].
String checkoutLadderVariantLabel(
  AppLocalizations l,
  CheckoutLadderVariant variant,
) {
  switch (variant) {
    case CheckoutLadderVariant.training:
      return l.ladderTraining;
    case CheckoutLadderVariant.race:
      return l.ladderRace;
  }
}

/// The darts an attempt of [game] holds, with the step when there is one:
/// `6`, or `6, from 110: 9`.
String checkoutLadderDartsLabel(AppLocalizations l, CheckoutLadderGame game) =>
    game.stepFrom != null && game.stepDarts != null
    ? '${game.dartsPerAttempt}, ${l.ladderStepFrom} ${game.stepFrom}: ${game.stepDarts}'
    : '${game.dartsPerAttempt}';

/// The settings of a Checkout Ladder [game] as label and value pairs, in the
/// order the summary, the history detail and the rematch dialog list them.
List<(String, String)> checkoutLadderSettingRows(
  AppLocalizations l,
  CheckoutLadderGame game,
) => [
  (l.ladderVariant, checkoutLadderVariantLabel(l, game.variant)),
  (l.ladderStartNumber, '${game.startNumber}'),
  if (game.isRace && game.targetNumber != null)
    (l.ladderTargetNumber, '${game.targetNumber}'),
  (l.ladderDartsPerAttempt, checkoutLadderDartsLabel(l, game)),
  (l.checkOut, checkOutLabel(l, game.checkOut)),
];
