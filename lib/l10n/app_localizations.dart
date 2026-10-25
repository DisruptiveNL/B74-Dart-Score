import 'package:flutter/material.dart';

import '../models/bot_level.dart';
import '../utils/match_format.dart';

/// Convenience access to [AppLocalizations] from any [BuildContext] via
/// `context.l10n` (e.g. `context.l10n.newGame`).
extension AppLocalizationsX on BuildContext {
  /// The active localizations for this context.
  AppLocalizations get l10n => AppLocalizations.of(this);
}

/// App-wide localized strings for English and German.
///
/// Each user-visible string is exposed as a getter that returns the English or
/// German variant based on the active [locale]. New strings are added as getters
/// using [_t]; the string values themselves serve as their own documentation.
class AppLocalizations {
  final Locale locale;
  const AppLocalizations(this.locale);

  /// The nearest [AppLocalizations] for [context], defaulting to English.
  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)
        ?? const AppLocalizations(Locale('en'));
  }

  /// Whether the active locale is German.
  bool get _de => locale.languageCode == 'de';

  /// Returns [de] when the locale is German, otherwise [en].
  String _t(String en, String de) => _de ? de : en;

  // ── General ──────────────────────────────────────────────────────────────
  String get appName           => 'DartScore';
  String get ok                => _t('OK', 'OK');
  String get cancel            => _t('Cancel', 'Abbrechen');
  String get save              => _t('Save', 'Speichern');
  String get delete            => _t('Delete', 'Löschen');
  String get edit              => _t('Edit', 'Bearbeiten');
  String get abort             => _t('Cancel', 'Abbrechen');
  String get confirm           => _t('Confirm', 'Bestätigen');
  String get yes               => _t('Yes', 'Ja');
  String get no                => _t('No', 'Nein');
  String get error             => _t('Error', 'Fehler');
  String get back              => _t('Back', 'Zurück');
  String get undo              => _t('Undo', 'Rückgängig');
  String get redo              => _t('Redo', 'Wiederherstellen');

  // ── Onboarding ───────────────────────────────────────────────────────────
  String get welcomeTitle      => _t('Welcome to DartScore!', 'Willkommen bei DartScore!');
  String get welcomeSubtitle   => _t('Create your profile to get started.', 'Erstelle dein Profil um loszulegen.');
  String get yourName          => _t('Your name', 'Dein Name');
  String get letsGo            => _t("Let's go!", 'Loslegen!');
  String get nameRequired      => _t('Please enter a name', 'Bitte einen Namen eingeben');
  String get requiredField     => _t('Required', 'Pflichtfeld');
  String get tapDoubleHint     => _t('Required: tap a double on the board',
                                     'Pflichtfeld: Tippe ein Double auf dem Board');
  String get profileFailed     => _t('Profile could not be created', 'Profil konnte nicht erstellt werden');
  String get myProfile         => _t('My Profile', 'Mein Profil');

  // ── Home ─────────────────────────────────────────────────────────────────
  String get newGame           => _t('New Game', 'Neues Spiel');
  String get managePlayers     => _t('Manage Players', 'Spieler verwalten');
  String get gameHistory       => _t('Game History', 'Spielverlauf');
  String get settings          => _t('Settings', 'Einstellungen');

  // ── Game Setup ───────────────────────────────────────────────────────────
  String get gameSetup         => _t('Game Setup', 'Spiel einrichten');
  String get startScore        => _t('Start Score', 'Startpunkte');
  String get checkIn           => _t('Check-In', 'Check-In');
  String get checkOut          => _t('Check-Out', 'Check-Out');
  String get straightIn        => _t('Straight In', 'Straight In');
  String get doubleIn          => _t('Double In', 'Double In');
  String get straightOut       => _t('Straight Out', 'Straight Out');
  String get doubleOut         => _t('Double Out', 'Double Out');
  String get masterOut         => _t('Master Out', 'Master Out');
  String get legs              => _t('Legs', 'Legs');
  String get sets              => _t('Sets', 'Sets');
  /// One-line "Sets: x  Legs: y" tally for a summary card header.
  String setsLegsWon(int setsWon, int legsWon) =>
      '$sets: $setsWon  $legs: $legsWon';
  /// Compact, singular-aware "x Legs · y Sets" tally for inline display.
  String legsSetsShort(int legsCount, int setsCount) =>
      '$legsCount ${legsCount == 1 ? 'Leg' : 'Legs'} · '
      '$setsCount ${setsCount == 1 ? 'Set' : 'Sets'}';
  String get players           => _t('Players', 'Spieler');
  String get noPlayersAvail    => _t('No players available.', 'Keine Spieler vorhanden.');
  String get addPlayerLink     => _t('Add player', 'Spieler anlegen');
  String get startGame         => _t('Start Game', 'Spiel starten');
  String get startOpenPlay     => _t('Start Solo Game', 'Solo Spiel starten');
  String get minOnePlayer      => _t('Select at least 1 player', 'Mindestens 1 Spieler auswählen');
  String get openPlayHint      => _t('1 player = Solo Game (no opponent)', '1 Spieler = Solo Spiel (kein Gegner)');
  String playerN(int n)        => _t('Player $n', 'Spieler $n');
  String morePlayers(int n)    => _t('Show $n more', '$n weitere anzeigen');
  String get fewerPlayers      => _t('Show fewer', 'Weniger anzeigen');

  // ── Match format presets ─────────────────────────────────────────────────
  String get matchFormat       => _t('Match Format', 'Match-Format');
  String get formatBo3         => _t('Best of 3', 'Best of 3');
  String get formatBo5         => _t('Best of 5', 'Best of 5');
  String get formatBo7         => _t('Best of 7', 'Best of 7');
  String get formatBo9         => _t('Best of 9', 'Best of 9');
  String get formatPdcSets     => _t('PDC Sets', 'PDC Sets');
  String get formatPremier     => _t('Premier League', 'Premier League');
  String get formatCustom      => _t('Custom', 'Eigene');
  // Short rule per preset, shown under the chips.
  String get formatBo3Rule     => _t('First to 2 Legs.', 'First to 2 Legs.');
  String get formatBo5Rule     => _t('First to 3 Legs.', 'First to 3 Legs.');
  String get formatBo7Rule     => _t('First to 4 Legs.', 'First to 4 Legs.');
  String get formatBo9Rule     => _t('First to 5 Legs.', 'First to 5 Legs.');
  String get formatPdcSetsRule => _t(
      'First to 3 Sets, each Set First to 3 Legs.',
      'First to 3 Sets, pro Set First to 3 Legs.');
  String get formatPremierRule => _t(
      'Pure leg race: First to 6 Legs, no Sets.',
      'Reines Leg-Race: First to 6 Legs, keine Sets.');
  String get formatCustomRule  => _t(
      'Choose Legs and Sets yourself.', 'Legs und Sets selbst festlegen.');
  String get firstToHint       => _t(
      'First to means: whoever reaches the chosen number of Legs or Sets first wins.',
      'First to heißt: Wer die gewählte Anzahl an Legs bzw. Sets zuerst erreicht, gewinnt.');

  // ── Placement mode ───────────────────────────────────────────────────────
  String get standardMode      => _t('Standard', 'Standard');
  String get placementMode     => _t('Placement', 'Platzierung');
  String get placementModeHint => _t(
      'Everyone plays each leg to the end to determine a final ranking. Played with 1 set; the match is still won by whoever reaches the chosen number of Legs first.',
      'Jeder spielt jedes Leg bis zum Ende, um eine Endplatzierung zu ermitteln. Es wird mit 1 Set gespielt; das Spiel gewinnt weiterhin, wer die gewählte Anzahl an Legs zuerst erreicht.');
  String get placementEligibilityHint => _t(
      'Placement mode is available with 3+ players or 3+ teams: everyone plays each leg to the end to determine a final ranking.',
      'Platzierung ist ab 3 Spielern oder 3 Teams verfügbar: Jeder spielt jedes Leg bis zum Ende, um eine Endplatzierung zu ermitteln.');
  /// Small badge showing a slot's finishing place for a placement-mode leg.
  String placementBadge(int place) => _t('#$place', 'Platz $place');
  String get finalRanking      => _t('Final Ranking', 'Endplatzierung');
  String get legByLegPlacements => _t('Placements per leg', 'Platzierungen pro Leg');
  /// Short column header for a leg, e.g. "L1".
  String legAbbr(int leg) => 'L$leg';
  String get placementPointsHint => _t(
      'Each leg awards points by finishing position (last place = 1 point, up to the number of players for 1st place), plus a +1 bonus for winning the leg.',
      'Jedes Leg vergibt Punkte nach Platzierung (letzter Platz = 1 Punkt, bis zur Spieleranzahl für Platz 1), zusätzlich gibt es +1 Bonuspunkt für den Leg-Sieg.');

  // ── Game Screen ──────────────────────────────────────────────────────────
  String get openPlay          => _t('Solo Game', 'Solo Spiel');
  String get leg               => _t('Leg', 'Leg');
  String get set_              => _t('Set', 'Set');
  String get quitGame          => _t('Quit Game', 'Spiel beenden');
  String get quitTitle         => _t('Leave Game', 'Spiel verlassen');
  String get quitBody          => _t('Really quit the current game?', 'Spiel wirklich verlassen?');
  String get leave             => _t('Leave', 'Verlassen');
  String get single            => _t('Single', 'Single');
  String get double_           => _t('Double', 'Double');
  String get triple            => _t('Triple', 'Triple');
  String get miss              => _t('Miss', 'Miss');
  String get done              => _t('Done', 'Fertig');
  String get bust              => _t('Bust', 'Bust');
  String get checkoutHint      => _t('Check-Out:', 'Check-Out:');
  String get noCheckoutPossible => _t('No Check-Out possible', 'Kein Check-Out möglich');
  String dart(int n)           => _t('Dart $n', 'Dart $n');
  String bullLabel(bool d)     => d ? _t('Bull (50)', 'Bull (50)') : _t('Bull (25)', 'Bull (25)');
  String get average           => _t('Average', 'Average');

  // ── Live Player Info ─────────────────────────────────────────────────────
  String get livePlayerInfo     => _t('Live Info', 'Live-Info');
  String get liveStatsTooltip   => _t('Show live statistics', 'Live-Statistik anzeigen');
  String get throwingNow        => _t('Throwing now', 'Wirft gerade');
  String get throwsNext         => _t('Throws next', 'Wirft als Nächstes');
  String get throwingOrderLabel => _t('Throwing order', 'Wurfreihenfolge');
  String get rulesLabel         => _t('Rules', 'Regeln');
  String get thisLeg            => _t('This Leg', 'Aktuelles Leg');
  String get matchSoFar         => _t('Match so far', 'Bisheriges Spiel');
  String get legAverage         => _t('Leg Average', 'Leg-Average');
  String get dartsThisLeg       => _t('Darts this Leg', 'Darts in diesem Leg');
  String get visitsThisLeg      => _t('Visits this Leg', 'Aufnahmen in diesem Leg');
  String get bestVisitThisLeg   => _t('Best Visit this Leg', 'Beste Aufnahme im Leg');
  String get first9Average      => _t('First 9 Average', 'First-9-Average');
  String get checkoutsHit       => _t('Check-Outs hit', 'Check-Outs getroffen');
  String get dartsAtFinish      => _t('Darts at a Finish', 'Darts aufs Finish');
  String playerOfTotal(int i, int n) => _t('Player $i of $n', 'Spieler $i von $n');
  String get lastVisits         => _t('Last 3 Visits', 'Letzte 3 Aufnahmen');
  String get continueNow        => _t('Continue', 'Weiter');
  String get noVisitsYet        => _t('No visits yet', 'Noch keine Aufnahmen');
  String get dartsThrown        => _t('Darts', 'Darts');
  String get marksPerRound      => _t('Marks per round', 'Marks pro Aufnahme');
  String get hitRate            => _t('Hit rate', 'Trefferquote');
  String get fieldsClosed       => _t('Fields closed', 'Felder geschlossen');
  String get bestVisit          => _t('Best visit', 'Beste Aufnahme');
  String get pointsPerRound     => _t('Points per round', 'Punkte pro Runde');
  String get shanghaisThrown    => _t('Shanghais', 'Shanghais');
  String get dartsPerTarget     => _t('Darts per target', 'Darts pro Ziel');
  String get longestStreak      => _t('Longest streak', 'Längste Serie');
  String get fieldsSkipped      => _t('Fields skipped', 'Übersprungene Felder');
  String nOfM(int n, int m)     => _t('$n of $m', '$n von $m');
  String marksN(int n)          => _t('$n marks', '$n Marks');
  String pointsN(int n)         => _t('$n points', '$n Punkte');
  String hitsN(int n)           => n == 1 ? _t('1 hit', '1 Treffer') : _t('$n hits', '$n Treffer');

  // ── Game Summary ─────────────────────────────────────────────────────────
  String get gameOverview      => _t('Game Summary', 'Spielübersicht');
  String get gameInfo          => _t('Game Info', 'Spielinfo');
  String wins(String name)     => _t('🎯 $name wins!', '🎯 $name hat gewonnen!');
  String get allThrows         => _t('All Throws', 'Alle Würfe');
  String get backToHome        => _t('Main Menu', 'Hauptmenü');
  String get playAgain         => _t('Replay', 'Wiederholen');
  String get playAgainTitle    => _t('Play again?', 'Spiel wiederholen?');
  String get playAgainQuestion =>
      _t('Start a new game with these settings and players?',
         'Ein neues Spiel mit diesen Einstellungen und Spielern starten?');
  String get saveToPhotos      => _t('Save to Photos', 'In Fotos speichern');
  String get share             => _t('Share', 'Teilen');
  String get savedToPhotos     => _t('Image saved to Photos.', 'Bild in Fotos gespeichert.');

  // ── 9-Darter / Perfect Game ───────────────────────────────────────────────
  String get nineDarter        => _t('9-Darter', '9-Darter');
  String get perfectGame       => _t('Perfect Game', 'Perfektes Spiel');
  String get perfectGames      => _t('Perfect Games', 'Perfekte Spiele');
  String perfectGameLabel(int minDarts) =>
      _t('$minDarts-Darter', '$minDarts-Darter');

  // ── Players ──────────────────────────────────────────────────────────────
  String get playersTitle      => _t('Players', 'Spieler');
  String get noPlayers         => _t('No players added yet.', 'Noch keine Spieler angelegt.');
  String get addPlayer         => _t('Add Player', 'Spieler hinzufügen');
  String get noFavDoubles      => _t('No favorite double', 'Keine Lieblings-Double');
  String get favDoublesPrefix  => _t('Double: ', 'Double: ');
  String get addPlayerTitle    => _t('Add Player', 'Spieler hinzufügen');
  String get editPlayerTitle   => _t('Edit Player', 'Spieler bearbeiten');
  String get nameLabel         => _t('Name', 'Name');
  String get favDoublesTitle      => _t('Favorite Double', 'Lieblings-Double');
  String get favDoublesRequired   => _t('Please select a favorite double', 'Bitte ein Lieblings-Double auswählen');
  String get favDoubleHint        => _t(
      'If multiple checkout routes are possible, the suggested finish prefers one ending on this double.',
      'Sind mehrere Finish-Wege möglich, wird bevorzugt ein Weg vorgeschlagen, der mit diesem Double endet');
  String get nameAlreadyExists => _t('This name is already taken', 'Dieser Name ist bereits vergeben');
  String get deletePlayerTitle => _t('Delete Player', 'Spieler löschen');
  String deletePlayerConfirm(String name) =>
      _t('Really delete $name?', '$name wirklich löschen?');
  String get syncProfile       => _t('Sync Profile', 'Profil synchronisieren');
  String get sharePlayerTooltip => _t('Sync Profile', 'Profil synchronisieren');
  String get setAsMainProfile  => _t('Set as Main Profile', 'Als Hauptprofil festlegen');
  String get alreadyMainProfile => _t('Main Profile', 'Hauptprofil');

  // ── Player Stats ─────────────────────────────────────────────────────────
  String get statistics        => _t('Statistics', 'Statistik');
  String statisticsOf(String name) =>
      _t('Statistics of $name', 'Statistik von $name');
  String syncOf(String name) => _t('Sync of $name', 'Sync von $name');
  String get statsX01Only      => _t('Statistics are collected in X01 mode only.', 'Statistiken werden nur im X01 Spielmodus erhoben.');
  String noGamesFor(String name) =>
      _t('No games for $name yet.', 'Noch keine Spiele für $name.');
  String get highlights        => _t('Highlights', 'Highlights');
  String get count180          => _t('180s', '180er');
  String get count140plus      => _t('140+', '140+');
  String get count100plus      => _t('100+', '100+');
  String get highestCheckout   => _t('Highest Check-Out', 'Höchster Check-Out');
  String get highestVisit      => _t('Highest Visit', 'Höchste Aufnahme');
  String get highestAverage    => _t('Highest Average', 'Höchster Average');
  String get overview          => _t('Overview', 'Übersicht');
  String get gamesPlayed       => _t('Games Played', 'Spiele gespielt');
  String get gamesWon          => _t('Games Won', 'Spiele gewonnen');
  String get legsWon           => _t('Legs Won', 'Legs gewonnen');
  String get totalVisits       => _t('Total Visits', 'Aufnahmen gesamt');
  String get totalDarts        => _t('Total Darts', 'Darts gesamt');
  String get accuracy          => _t('Accuracy', 'Treffsicherheit');
  String get threeDartAvg      => _t('3-Dart Average', '3-Dart Average');
  String get bustRate          => _t('Bust Rate', 'Bust-Rate');
  String get checkoutRate      => _t('Check-Out Rate', 'Check-Out-Quote');
  String get doubleRate        => _t('Double Rate', 'Doppel-Quote');
  String get scoreDistribution => _t('Score Distribution', 'Score-Verteilung');
  String get recentThrows      => _t('Recent Throws', 'Letzte Würfe');
  String get syncedStatsFrom   => _t('Synced statistics from', 'Synchronisierte Statistiken vom');
  String get syncedStats       => _t('Synced statistics', 'Synchronisierte Statistiken');
  String get visits            => _t('Visits', 'Aufnahmen');
  String get darts_            => _t('Darts', 'Darts');
  String get busts             => _t('Busts', 'Busts');

  // ── Extended Player Stats ────────────────────────────────────────────────
  String get dartboardHeatmap   => _t('Dartboard Heatmap', 'Dartscheiben-Heatmap');
  String get allSegments        => _t('All fields thrown', 'Alle geworfenen Felder');
  String get stability          => _t('Consistency', 'Konstanz');
  String get stabilityVeryHigh  => _t('Very Consistent', 'Sehr konstant');
  String get stabilityHigh      => _t('Consistent', 'Konstant');
  String get stabilityMedium    => _t('Variable', 'Variabel');
  String get stabilityLow       => _t('Very Variable', 'Sehr variabel');
  String stabilityHint(String s) =>
      _t('Standard deviation of visits: $s pts. Lower means more consistent.',
         'Standardabweichung der Aufnahmen: $s Punkte. Niedriger heißt gleichmäßiger.');
  String get checkoutBreakdown  => _t('Check-Out by Range', 'Check-Out nach Restpunkten');
  String get topDoubles         => _t('Top Doubles', 'Beste Doppelfelder');
  String get weekComparison     => _t('Week Comparison', 'Wochenvergleich');
  String get thisWeek           => _t('This week', 'Diese Woche');
  String get lastWeek           => _t('Last week', 'Letzte Woche');

  // ── History ───────────────────────────────────────────────────────────────
  String get historyTitle      => _t('Game History', 'Spielverlauf');
  String get open              => _t('Open', 'Offen');
  String get finished          => _t('Finished', 'Abgeschlossen');
  String get clearAll          => _t('Delete All', 'Alles löschen');
  String get clearAllTitle     => _t('Delete all?', 'Alles löschen?');
  String get clearAllBody      =>
      _t('Delete the entire game history permanently?',
         'Gesamten Spielverlauf unwiderruflich löschen?');
  String get resume            => _t('Resume', 'Fortsetzen');
  String get noHistory         => _t('No games played yet.', 'Noch keine Spiele gespielt.');
  String get filterAll         => _t('All', 'Alle');
  String get gameModeX01       => 'X01';
  String get gameModeCricket   => 'Cricket';
  String get gameModeShanghai  => 'Shanghai';
  String get gameModeAroundTheClock => _t('Around the Clock', 'Around the Clock');
  String get gameModeCheckoutLadder => _t('Checkout Ladder', 'Checkout-Leiter');
  String get openAdj           => _t('open', 'offenen');
  String get finishedAdj       => _t('finished', 'abgeschlossenen');
  String deleteVisibleBody(String adj, String mode) => mode.isEmpty
      ? _t('Permanently delete all $adj games?',
           'Alle $adj Spiele unwiderruflich löschen?')
      : _t('Permanently delete all $adj $mode games?',
           'Alle $adj $mode Spiele unwiderruflich löschen?');
  String get points            => _t('Points', 'Punkte');

  /// The chip label for a match format preset (e.g. "Best of 5", "PDC Sets").
  String matchFormatLabel(MatchFormat f) => switch (f) {
        MatchFormat.bo3 => formatBo3,
        MatchFormat.bo5 => formatBo5,
        MatchFormat.bo7 => formatBo7,
        MatchFormat.bo9 => formatBo9,
        MatchFormat.pdcSets => formatPdcSets,
        MatchFormat.premierLeague => formatPremier,
        MatchFormat.custom => formatCustom,
      };

  /// Match format label for a past game derived from its stored legs/sets:
  /// the named preset (e.g. "Best of 5") when one matches, otherwise the custom
  /// label with the concrete counts (e.g. "Eigene 6 Legs, 7 Sets").
  String matchFormatDesc(int legs, int sets) {
    final f = MatchFormatLookup.fromValues(legs, sets);
    if (f != MatchFormat.custom) return matchFormatLabel(f);
    final legLabel = legs == 1 ? 'Leg' : 'Legs';
    final setLabel = sets == 1 ? 'Set' : 'Sets';
    return _t('Custom $legs $legLabel, $sets $setLabel',
              'Eigene $legs $legLabel, $sets $setLabel');
  }

  String gameSummaryInfo(int score, int l, int s, {bool placementMode = false}) =>
      placementMode
          ? _t('$score pts · ${placementFormatLabel(l)}',
               '$score Punkte · ${placementFormatLabel(l)}')
          : _t('$score pts · ${matchFormatDesc(l, s)}',
               '$score Punkte · ${matchFormatDesc(l, s)}');

  /// Label for placement-mode games, showing just the configured leg count
  /// (e.g. "Legs: 3") instead of a "Best of"/PDC match format.
  String placementFormatLabel(int legsCount) => '$legs: $legsCount';

  // ── Game setup / Team / Handicap ─────────────────────────────────────────
  String get handicap            => _t('Handicap', 'Handicap');
  String get handicapDesc        => _t('Individual Check-In / Check-Out rules per player', 'Individuelle Check-In / Check-Out Regeln pro Spieler');
  String get teamGame            => _t('Team Game', 'Team Spiel');
  String get teamGameDesc        => _t('Split players into teams. Each team shares one score.', 'Spieler auf Teams aufteilen. Jedes Team teilt sich einen Score.');
  String get statsTooltip        => _t('Statistics', 'Statistik');
  String get statsLoadError      => _t('Statistics could not be loaded.', 'Statistiken konnten nicht geladen werden.');
  String get gameMode_           => _t('Mode', 'Modus');
  String get gameLabel           => _t('Game', 'Spiel');
  String get unknownDevice       => _t('Unknown device', 'Unbekanntes Gerät');
  String get teamPlayers         => _t('Players', 'Spieler');

  // ── Bot opponent ─────────────────────────────────────────────────────────
  String get modeBotTitle => _t('Against the computer', 'Gegen den Computer');
  String get modeBotNote => _t(
      'You can play against a computer opponent in every mode. Switch it on in the setup and pick one of five tiers, from rookie to legend. You can also bring several bots into a game, even several of the same tier.\n\n'
      'The bot plays by the same rules you do. When it is its turn, it throws by itself, and you see each of its darts on the board. How fast it throws is set under Game pace in the settings.',
      'Du kannst in jedem Modus gegen einen Computergegner spielen. Schalte ihn im Setup ein und wähle eine von fünf Stufen, vom Anfänger bis zur Legende. Du kannst auch mehrere Bots ins Spiel nehmen, sogar mehrere derselben Stufe.\n\n'
      'Der Bot spielt nach denselben Regeln wie du. Wenn er dran ist, wirft er von allein, und du siehst jeden seiner Darts auf dem Board. Wie schnell er wirft, stellst du in den Einstellungen unter Spieltempo ein.');
  String get botOpponent => _t('Computer opponent', 'Computergegner');
  /// The short name of a tier, as the rows of the setup card show it.
  String botTier(BotLevel level) => switch (level) {
        BotLevel.rookie  => _t('Rookie', 'Anfänger'),
        BotLevel.amateur => _t('Amateur', 'Amateur'),
        BotLevel.semiPro => _t('Semi-pro', 'Fortgeschritten'),
        BotLevel.pro     => _t('Pro', 'Profi'),
        BotLevel.legend  => _t('Legend', 'Legende'),
      };
  /// The name a bot of [level] plays under wherever a player's name is shown,
  /// numbered from the second bot of a tier on. One word in German before the
  /// number, so that the compact scoreboard, which shows a person's first
  /// name, still tells the tiers apart.
  String botName(BotLevel level, [int ordinal = 1]) {
    final base = _t('${botTier(level)} bot', '${botTier(level)}-Bot');
    return ordinal == 1 ? base : '$base $ordinal';
  }
  String addBot(BotLevel level)    => _t('Add ${botName(level)}', '${botName(level)} hinzufügen');
  String removeBot(BotLevel level) => _t('Remove ${botName(level)}', '${botName(level)} entfernen');
  String botAverageHint(int average) => _t(
      'about $average points per visit', 'etwa $average Punkte pro Aufnahme');
  /// The line under the tier rows naming the slots the bots throw in, in the
  /// throwing order the setup keeps. [slots] are counted from one and hold
  /// at least one entry.
  String botSlotsHint(List<int> slots) {
    if (slots.length == 1) {
      return _t('The bot throws as player ${slots.single}.',
          'Der Bot wirft als Spieler ${slots.single}.');
    }
    final list = '${slots.sublist(0, slots.length - 1).join(', ')} '
        '${_t('and', 'und')} ${slots.last}';
    return _t('The bots throw as players $list.',
        'Die Bots werfen als Spieler $list.');
  }

  // ── Starting order ───────────────────────────────────────────────────────
  String get startingOrder       => _t('Starting order', 'Startreihenfolge');
  String get startingOrderFixed  => _t('Fixed', 'Festgelegt');
  String get startingOrderRandom => _t('Random', 'Zufällig');
  String get startingOrderFixedHint => _t(
      'Throw for the bull and sort the list by it: whoever lands closest starts the round.',
      'Wirf aufs Bull und sortiere die Liste danach: Wer am nächsten dran ist, beginnt die Runde.');
  String get startingOrderTeamHint => _t(
      'Throw for the bull and sort the teams by it: whoever lands closest starts the round. Only one player per team throws.',
      'Wirf aufs Bull und sortiere die Teams danach: Wer am nächsten dran ist, beginnt die Runde. Pro Team wirft nur einer.');
  String get startingOrderRandomHint => _t(
      'The order is drawn randomly when the game starts.',
      'Die Reihenfolge wird beim Start zufällig ausgelost.');

  // ── Settings ─────────────────────────────────────────────────────────────
  String get settingsTitle     => _t('Settings', 'Einstellungen');
  String get displaySection    => _t('Display', 'Darstellung');
  String get appSection        => _t('App', 'App');
  String get language          => _t('Language', 'Sprache');
  String get theme             => _t('Theme', 'Design');
  String get system            => _t('System', 'System');
  String get light             => _t('Light', 'Hell');
  String get dark              => _t('Dark', 'Dunkel');
  String get textSize          => _t('Text size', 'Schriftgröße');
  String get textSizeHint      =>
      _t('How large the app draws its text on this device.',
         'Wie groß die App ihre Schrift auf diesem Gerät zeichnet.');
  String get textSizeReset     => _t('Standard', 'Standard');
  String get gamePace          => _t('Game pace', 'Spieltempo');
  String get paceFast          => _t('Fast', 'Schnell');
  String get paceNormal        => _t('Normal', 'Normal');
  String get paceSlow          => _t('Slow', 'Langsam');
  String get gamePaceHint      => _t(
      'How long a finished visit stays on the board before the turn moves on, and how quickly a computer opponent throws. Continue moves on at once, whenever you like.',
      'Wie lange eine fertige Aufnahme auf dem Board stehen bleibt, bevor der Zug weitergeht, und wie schnell ein Computergegner wirft. Mit Weiter geht es jederzeit sofort weiter.');
  String get whatItDoes        => _t('What it does', 'Was es bewirkt');
  String get profileSharing    => _t('Share & Import Profile', 'Profil teilen & importieren');
  String get shareHint         =>
      _t('Share your profile as a QR code with friends.',
         'Teile dein Profil als QR-Code mit Freunden.');
  String get scanImport        => _t('Scan & Import Profile', 'Profil scannen & importieren');
  String get scanImportDesc    => _t('Scan a friend\'s QR code', 'QR-Code eines Freundes scannen');
  String get importFromLibrary => _t('Import from Photo Library', 'Aus Foto-Bibliothek importieren');
  String get importFromLibDesc => _t('Select a saved QR code image', 'Gespeichertes QR-Code Bild auswählen');
  String get noPlayersSettings => _t('No players added yet.', 'Noch keine Spieler angelegt.');
  String get swapInputSide     => _t('Swap sides', 'Seiten tauschen');
  String get playersPickOne    =>
      _t('Pick a player to see their statistics.',
         'Wähle einen Spieler, um seine Statistik zu sehen.');
  String get historyPickGame   =>
      _t('Pick a game to see how it went.',
         'Wähle ein Spiel, um den Verlauf zu sehen.');

  // ── Donation ─────────────────────────────────────────────────────────────
  String get donationTitle      => _t('Support Developer', 'Entwickler unterstützen');
  String get donationSectionTitle => _t('Support', 'Unterstützen');
  String get donationSectionDesc  => _t('Buy me a coffee', 'Kauf mir einen Kaffee');
  String get donationSubtitle   => _t(
      'DartScore is free and has no ads. If you enjoy it, a small donation helps keep it alive and supports future development.',
      'DartScore ist kostenlos und hat keine Werbung. Wenn dir die App gefällt, hilft eine kleine Spende dabei, sie am Leben zu erhalten und weiterzuentwickeln.');
  String get donationUnavailable => _t(
      'In-app purchases are not available on this device.',
      'In-App-Käufe sind auf diesem Gerät nicht verfügbar.');
  String get donationNoProducts => _t(
      'The donation options could not be loaded from the store. Please try again later.',
      'Die Spendenoptionen konnten nicht aus dem Store geladen werden. Bitte versuche es später noch einmal.');
  String get donationSomeMissing => _t(
      'Some donation options are currently unavailable.',
      'Einige Spendenoptionen sind gerade nicht verfügbar.');
  String get donationThankYouTitle => _t('Thank you! 🎯', 'Danke! 🎯');
  String get donationThankYouBody  => _t(
      'Your support means a lot and helps keep DartScore free for everyone.',
      'Deine Unterstützung bedeutet mir viel und hilft dabei, DartScore für alle kostenlos zu halten.');

  // ── About ────────────────────────────────────────────────────────────────
  String get about             => _t('About', 'Über die App');
  String get aboutDesc         => _t('Version, license, project', 'Version, Lizenz, Projekt');
  String get aboutTitle        => _t('About DartScore', 'Über DartScore');
  String get version           => _t('Version', 'Version');
  String get developer         => _t('Developer', 'Entwickler');
  String get support           => _t('Support', 'Support');
  String get supportDesc       => _t('Get help or report an issue', 'Hilfe erhalten oder ein Problem melden');
  String get sourceCode        => _t('Source code', 'Quelltext');
  String get sourceCodeDesc    => _t('Read the code this app is built from', 'Den Code lesen, aus dem diese App gebaut ist');
  String get license           => _t('License', 'Lizenz');
  String get licenseDesc       => _t('GNU General Public License v3.0', 'GNU General Public License v3.0');
  String get licenseFullText   => _t('Read full license text', 'Vollständigen Lizenztext lesen');
  String get openSourceLicenses     => _t('Open Source Licenses', 'Open-Source-Lizenzen');
  String get openSourceLicensesDesc => _t('Packages used in this app', 'In dieser App verwendete Pakete');
  String get licenseUnnamedComponent =>
      _t('Unnamed component', 'Unbenannte Komponente');
  String get licensesPickPackage    =>
      _t('Pick a package to read its license.',
         'Wähle ein Paket, um seine Lizenz zu lesen.');
  String licenseCount(int n) => n == 1
      ? _t('1 license', '1 Lizenz')
      : _t('$n licenses', '$n Lizenzen');
  String get linkOpenError     => _t('Could not open the link.', 'Der Link konnte nicht geöffnet werden.');

  // ── Sync ──────────────────────────────────────────────────────────────────
  String get syncTitle         => _t('Profile Sync', 'Profil-Sync');
  String get syncSend          => _t('Send', 'Senden');
  String get syncReceive       => _t('Receive', 'Empfangen');

  // How far back a sync reaches
  String get syncRangeLabel    => _t('Time range', 'Zeitraum');
  String get syncRangeDay      => _t('1 day', '1 Tag');
  String get syncRangeWeek     => _t('7 days', '7 Tage');
  String get syncRangeMonth    => _t('30 days', '30 Tage');
  String get syncRangeAll      => _t('Everything', 'Alles');
  String get syncRangeNote     =>
      _t('Older visits are not transferred one by one, only as a total. The statistics on the other device are still correct, only its "All Throws" list does not reach back as far.',
         'Ältere Aufnahmen werden nicht einzeln übertragen, sondern nur als Summe. Die Statistiken stimmen auf dem anderen Gerät trotzdem, nur die Liste "Alle Würfe" reicht dort nicht so weit zurück.');
  String syncVisitCount(int n) =>
      _t('$n visit${n != 1 ? 's' : ''}',
         '$n ${n != 1 ? 'Aufnahmen' : 'Aufnahme'}');
  String syncLegacyShare(int n) =>
      _t('$n of them from earlier syncs',
         'davon $n aus früheren Syncs');
  String get syncLegacyNote    =>
      _t('Visits from a sync made before this version always travel in full, because there is no telling any more which device played them. Once this device has received this player once, they are filed under a device and the time range reaches them too.',
         'Aufnahmen aus einem Sync vor dieser Version werden immer vollständig übertragen, weil sich nicht mehr feststellen lässt, welches Gerät sie gespielt hat. Sobald dieses Gerät die Daten dieses Spielers einmal empfangen hat, sind sie zugeordnet und der Zeitraum greift auch dort.');
  String syncRangeInPacket(String range) =>
      _t('Range: $range', 'Zeitraum: $range');

  // How the data gets across, chosen from how much of it there is
  String get syncViaStaticQr   =>
      _t('fits into one QR code', 'passt in einen QR-Code');
  String syncViaAnimatedQr(int seconds) =>
      _t('animated QR code, about $seconds seconds',
         'animierter QR-Code, etwa $seconds Sekunden');
  String get syncViaServer     =>
      _t('too much for a QR code, transferred over Wi-Fi',
         'zu viel für einen QR-Code, Übertragung über WLAN');
  String get syncStartStream     => _t('Start the code', 'Code starten');
  String get syncStartStreamHint =>
      _t('Start the code once the other device is scanning.',
         'Starte den Code, sobald das andere Gerät scannt.');
  String get syncAnimatedHint  =>
      _t('Hold both devices steady until the receiver is finished.',
         'Halte beide Geräte ruhig, bis der Empfänger fertig ist.');
  String get syncStopStreamHint =>
      _t('Hold both devices steady until the receiver is finished. Tap the code to stop it.',
         'Halte beide Geräte ruhig, bis der Empfänger fertig ist. Tippe auf den Code, um ihn anzuhalten.');
  String get syncSendDesc      =>
      _t('Pick a player and a time range. Which way the data travels follows from how much of it there is.',
         'Wähle Spieler und Zeitraum. Auf welchem Weg die Daten reisen, ergibt sich aus ihrer Menge.');
  String get syncReceiveDesc   =>
      _t('Scan the sender\'s QR code to import the profile.',
         'Scanne den QR-Code des Senders, um das Profil zu importieren.');
  String get selectPlayer      => _t('Select player', 'Spieler auswählen');
  String get fileOpenFailed    =>
      _t('This file could not be read as a DartScore backup or profile.',
         'Diese Datei konnte nicht als DartScore-Sicherung oder -Profil gelesen werden.');
  String get syncShareFile     =>
      _t('Send as a file', 'Als Datei senden');
  String get syncShareFileHint =>
      _t('AirDrop, mail, a chat. The other device opens it in DartScore.',
         'AirDrop, Mail, ein Chat. Das andere Gerät öffnet sie direkt in DartScore.');
  /// The same, for a device where tapping the file will not do.
  ///
  /// Android file managers that do not know an extension offer no way to open
  /// it and send the user to the store instead, so the one route that works has
  /// to be the one named.
  String get syncShareFileHintShare =>
      _t('Nearby Share, mail, a chat. On the other device, share the file and pick DartScore.',
         'Nearby Share, Mail, ein Chat. Auf dem anderen Gerät die Datei teilen und DartScore wählen.');
  String get startServer       => _t('Show the code', 'Code anzeigen');
  String get stopServer        => _t('Cancel', 'Abbrechen');
  String get profileAndStats   =>
      _t('Profile · Statistics · Visits', 'Profil · Statistiken · Aufnahmen');
  String get qrScanHint        =>
      _t('Hold the sender\'s QR code in frame', 'QR-Code des Senders ins Bild halten');
  String get syncKeepHolding   =>
      _t('Keep holding, the code is still being read',
         'Weiter halten, der Code wird noch gelesen');
  String syncScanProgress(int received, int total) =>
      _t('$received of $total parts', '$received von $total Teilen');
  String get syncReadFailed    =>
      _t('The data could not be read.', 'Die Daten konnten nicht gelesen werden.');
  String get syncPairTitle     =>
      _t('Confirm transfer', 'Übertragung bestätigen');
  String get syncPairBody      =>
      _t('A device is asking for this profile. Both screens have to show the same number.',
         'Ein Gerät fragt nach diesem Profil. Auf beiden Bildschirmen muss dieselbe Zahl stehen.');
  String get syncPairWaiting   =>
      _t('Waiting for the other device to confirm',
         'Warten auf die Bestätigung am anderen Gerät');
  String get syncApprove       => _t('Confirm', 'Bestätigen');
  String get syncReject        => _t('Decline', 'Ablehnen');
  String get syncNotConfirmed  =>
      _t('The transfer was not confirmed in time.',
         'Die Übertragung wurde nicht rechtzeitig bestätigt.');
  String get syncRejected      =>
      _t('The other device declined the transfer.',
         'Das andere Gerät hat die Übertragung abgelehnt.');
  String get syncTooLarge      =>
      _t('The other device sent more data than this app accepts.',
         'Das andere Gerät hat mehr Daten gesendet, als diese App annimmt.');
  String get syncNoWifiAddress =>
      _t('This device is not on a Wi-Fi network.\nTurn Wi-Fi on, join a network and try again.',
         'Dieses Gerät ist in keinem WLAN.\nSchalte WLAN ein, verbinde dich mit einem Netzwerk und versuche es erneut.');
  String get syncServerFailed  =>
      _t('The transfer could not be started.\nClose the app and open it again.',
         'Die Übertragung konnte nicht gestartet werden.\nSchließe die App und öffne sie erneut.');
  String get syncUnreachable   =>
      _t('The other device did not answer.\nGuest networks, public Wi-Fi and hotspots in hotels, cafes or trains often stop devices from reaching each other. Try a different Wi-Fi.',
         'Das andere Gerät hat nicht geantwortet.\nIn Gäste-WLANs, öffentlichen WLANs und Hotspots in Hotels, Cafés oder Zügen können sich Geräte oft nicht gegenseitig erreichen. Versuche ein anderes WLAN.');
  String get syncUnreachableOnHotspot =>
      _t('The other device did not answer.\nStay close to it and leave its hotspot switched on until the transfer is finished.',
         'Das andere Gerät hat nicht geantwortet.\nBleib in seiner Nähe und lass seinen Hotspot an, bis die Übertragung fertig ist.');
  String get syncIosNoOwnNetwork =>
      _t('Apps on iOS may not open a hotspot of their own. Without a shared Wi-Fi, switch the personal hotspot on in the iOS settings and let the other device join it, or send the profile as a file over AirDrop.',
         'Apps dürfen unter iOS keinen eigenen Hotspot öffnen. Ohne gemeinsames WLAN schaltest du in den iOS-Einstellungen den persönlichen Hotspot ein und verbindest das andere Gerät damit, oder du sendest das Profil per AirDrop als Datei.');
  String get backupIosNoOwnNetwork =>
      _t('Apps on iOS may not open a hotspot of their own. Without a shared Wi-Fi, switch the personal hotspot on in the iOS settings and let the other device join it, or save the backup to a file and send it over AirDrop.',
         'Apps dürfen unter iOS keinen eigenen Hotspot öffnen. Ohne gemeinsames WLAN schaltest du in den iOS-Einstellungen den persönlichen Hotspot ein und verbindest das andere Gerät damit, oder du speicherst die Sicherung als Datei und schickst sie per AirDrop.');
  String get syncCodeExpired   =>
      _t('This code has expired.\nCreate a new one on the other device.',
         'Dieser Code ist abgelaufen.\nErzeuge auf dem anderen Gerät einen neuen.');
  String get routeSharedWifi   => _t('Over a shared Wi-Fi', 'Über ein gemeinsames WLAN');
  String get routeSharedWifiHint =>
      _t('Both devices need to be connected to the same Wi-Fi.',
         'Beide Geräte müssen mit dem selben WLAN verbunden sein.');
  String get routeOwnNetwork   => _t('Over a hotspot from this device', 'Über einen Hotspot dieses Geräts');
  String get routeOwnNetworkHint =>
      _t('This device opens a Wi-Fi hotspot and the other one joins it when it scans the code. For anywhere without a Wi-Fi. This device has no internet while the hotspot runs.',
         'Dieses Gerät öffnet einen WLAN-Hotspot, das andere tritt ihm beim Scannen des Codes bei. Für überall dort, wo kein WLAN ist. Solange der Hotspot läuft, hat dieses Gerät kein Internet.');
  String hotspotNetworkName(String ssid) =>
      _t('Hotspot: $ssid', 'Hotspot: $ssid');
  String get hotspotSendHint   =>
      _t('The other device joins the hotspot by itself when it scans the code.',
         'Das andere Gerät tritt dem Hotspot beim Scannen des Codes von selbst bei.');
  String hotspotJoining(String ssid) =>
      _t('Joining $ssid', 'Verbinde mit $ssid');
  String get hotspotIncompatible =>
      _t('Turn the mobile hotspot in the Android settings off first. It cannot run at the same time as this one.',
         'Schalte zuerst den mobilen Hotspot in den Android-Einstellungen aus. Er kann nicht gleichzeitig mit diesem laufen.');
  String get hotspotDenied     =>
      _t('Without the nearby devices permission this device cannot open a hotspot.',
         'Ohne die Berechtigung für Geräte in der Nähe kann dieses Gerät keinen Hotspot öffnen.');
  String get hotspotFailed     =>
      _t('The hotspot could not be opened. Use a shared Wi-Fi instead.',
         'Der Hotspot konnte nicht geöffnet werden. Nutze stattdessen ein gemeinsames WLAN.');
  String get hotspotStopped    =>
      _t('The hotspot was closed. Start the transfer again.',
         'Der Hotspot wurde geschlossen. Starte die Übertragung neu.');
  String get hotspotJoinFailed =>
      _t('The hotspot was not joined.',
         'Die Verbindung zum Hotspot kam nicht zustande.');
  String hotspotJoinManually(String ssid, String password) =>
      _t('Open the Wi-Fi settings, pick "$ssid", enter $password, come back here and scan again.',
         'Öffne die WLAN-Einstellungen, wähle "$ssid", gib $password ein, komm zurück und scanne erneut.');
  String get syncNotBackupCode =>
      _t('That is a backup code. It belongs in Backup, not here.',
         'Das ist ein Backup-Code. Er gehört ins Backup, nicht hierher.');
  String get syncServerSent    => _t('Profile sent', 'Profil übertragen');
  String get syncServerSentHint =>
      _t('Show the code again for another transfer.',
         'Für eine weitere Übertragung den Code neu anzeigen.');

  String get syncImporting     => _t('Importing', 'Wird importiert');
  String syncImportProgress(int done, int total) =>
      _t('$done of $total visits', '$done von $total Aufnahmen');
  String get syncImportDone    => _t('Import complete', 'Import abgeschlossen');
  String get syncImportFailed  => _t('Import failed', 'Import fehlgeschlagen');
  String get connectionFailed  =>
      _t('Connection failed.\nCheck that both devices are connected to the same Wi-Fi.',
         'Verbindung fehlgeschlagen.\nPrüfe, ob beide Geräte mit dem selben WLAN verbunden sind.');
  String get importNewPlayer   => _t('Import new player', 'Neuen Spieler importieren');
  String get updatePlayer      => _t('Update player', 'Spieler aktualisieren');
  String get nameConflictTitle => _t('Name already exists', 'Name bereits vorhanden');
  String nameConflictBody(String name) =>
      _t('"$name" already exists. What should happen?',
         '"$name" existiert bereits. Was soll passieren?');
  String importAs(String name) => _t('Import as "$name"', 'Als "$name" importieren');
  String get renameAndImport   => _t('Rename and import', 'Umbenennen und importieren');
  String get alternativeName   => _t('Alternative name', 'Alternativer Name');
  String fromDevice(String d)  => _t('From: $d', 'Von: $d');
  String get import_           => _t('Import', 'Importieren');
  String get syncAwaitingReturn =>
      _t('The data is through. Waiting for the other device to send its own back, so both are up to date after one transfer.',
         'Die Daten sind durch. Warte darauf, dass das andere Gerät seine eigenen zurückschickt, damit beide nach einer Übertragung aktuell sind.');
  String get update            => _t('Update', 'Aktualisieren');
  String importedMsg(String name) => _t('$name imported.', '$name importiert.');
  String updatedMsg(String name) => _t('$name updated.', '$name aktualisiert.');
  String importedWithThrows(String name, int n) =>
      _t('$name updated · $n new visits imported.',
         '$name aktualisiert · $n neue Aufnahmen importiert.');
  String importedWithCount(String name, int n) =>
      _t('$name imported · $n visits.',
         '$name importiert · $n Aufnahmen.');
  String overwriteProfile(String name) =>
      _t('The profile of "$name" will be overwritten with this data.',
         'Das Profil von "$name" wird mit diesen Daten überschrieben.');
  String get throws            => _t('Throws', 'Würfe');

  // ── Backup ────────────────────────────────────────────────────────────────
  String get backupTitle       => _t('Backup', 'Sicherung');
  String get backupSectionDesc =>
      _t('Back up and restore', 'Sichern und wiederherstellen');
  String get backupCreate      => _t('Create backup', 'Sicherung erstellen');
  String get backupCreateDesc  =>
      _t('Writes all players, games and throws into one file',
         'Schreibt alle Spieler, Spiele und Würfe in eine Datei');
  String get backupRestore     => _t('Restore backup', 'Sicherung wiederherstellen');
  String get backupRestoreDesc =>
      _t('Reads a backup file back in',
         'Liest eine Sicherungsdatei wieder ein');
  String get backupWhereHint   =>
      _t('Pick where the file goes: iCloud Drive, Google Drive, Files, mail or a chat. Nothing is uploaded anywhere by the app itself.',
         'Du wählst, wohin die Datei geht: iCloud Drive, Google Drive, Dateien, E-Mail oder ein Chat. Die App selbst lädt nichts irgendwo hoch.');
  String get backupCreated     => _t('Backup created.', 'Sicherung erstellt.');
  String get backupToFile      => _t('To a file', 'In eine Datei');
  String get backupToFileDesc  =>
      _t('iCloud Drive, Google Drive, Files, mail, anywhere you like',
         'iCloud Drive, Google Drive, Dateien, E-Mail, wohin du magst');
  String get backupToDevice    => _t('To another device on the same Wi-Fi', 'An anderes Gerät im selben WLAN');
  String get backupToDeviceDesc =>
      _t('Both devices are connected to the same Wi-Fi',
         'Beide Geräte sind mit dem selben WLAN verbunden');
  String get backupToDeviceDirect =>
      _t('To another device over a hotspot', 'An anderes Gerät über einen Hotspot');
  String get backupToDeviceDirectDesc =>
      _t('This device opens a Wi-Fi hotspot for it, for anywhere without a Wi-Fi',
         'Dieses Gerät öffnet dafür einen WLAN-Hotspot, für überall dort, wo kein WLAN ist');
  String get backupFromFile    => _t('From a file', 'Aus einer Datei');
  String get backupFromFileDesc =>
      _t('Pick a backup you saved earlier',
         'Eine zuvor gespeicherte Sicherung auswählen');
  String get backupFromDevice  => _t('From another device', 'Von einem anderen Gerät');
  String get backupFromDeviceDesc =>
      _t('Scan the code the other device is showing',
         'Den Code scannen, den das andere Gerät anzeigt');
  String get backupSendHint    =>
      _t('Show this code to the other device and confirm the number both screens display. Everything on that device is replaced by this database.',
         'Zeige diesen Code dem anderen Gerät und bestätige die Zahl, die beide Bildschirme anzeigen. Alles auf jenem Gerät wird durch diese Datenbank ersetzt.');
  String get backupSendPrep    => _t('Preparing the database', 'Datenbank wird vorbereitet');
  String get backupSent        => _t('Database transferred.', 'Datenbank übertragen.');
  String get backupSendAgain   => _t('Send again', 'Erneut senden');
  String get backupReceiveHint =>
      _t('Scan the code on the device you want the data from.',
         'Scanne den Code auf dem Gerät, dessen Daten du übernehmen willst.');
  String get backupReceiving   => _t('Receiving the database', 'Datenbank wird empfangen');
  String backupReceivingAt(int percent) =>
      _t('Receiving the database, $percent%',
         'Datenbank wird empfangen, $percent%');
  String backupSending(int percent) =>
      _t('Sending the database, $percent%',
         'Datenbank wird gesendet, $percent%');
  String get backupNotSyncCode =>
      _t('That is a profile sync code. Use it in the sync screen of the player list.',
         'Das ist ein Code für den Profil-Sync. Verwende ihn in der Sync-Ansicht der Spielerliste.');
  String get backupNotABackup  =>
      _t('This file is not a DartScore backup.',
         'Diese Datei ist keine DartScore-Sicherung.');
  String get backupTooNew      =>
      _t('This backup comes from a newer version of DartScore. Update the app first.',
         'Diese Sicherung stammt aus einer neueren Version von DartScore. Aktualisiere zuerst die App.');
  String get backupRestoreQ    => _t('Restore backup?', 'Sicherung wiederherstellen?');
  String get backupRestoreWarn =>
      _t('Every player, game and statistic on this device is replaced by the backup. That cannot be undone.',
         'Alle Spieler, Spiele und Statistiken auf diesem Gerät werden durch die Sicherung ersetzt. Das lässt sich nicht rückgängig machen.');
  String get backupDeviceNote  =>
      _t('Games from the backup stay filed under the device they were played on, so this device and that one can still sync afterwards.',
         'Spiele aus der Sicherung bleiben dem Gerät zugeordnet, auf dem sie gespielt wurden. Dieses und jenes Gerät können danach weiterhin synchronisieren.');
  String get backupRestored    => _t('Backup restored.', 'Sicherung wiederhergestellt.');
  String get backupUnknownDate => _t('Date unknown', 'Datum unbekannt');
  String get backupSaveFirstQ  =>
      _t('Save the current data first?',
         'Vorher die aktuellen Daten sichern?');
  String get backupSaveFirst   => _t('Create a backup now', 'Jetzt eine Sicherung erstellen');
  String get backupSaveFirstDesc =>
      _t('The only way back if the restored data turns out to be the wrong one',
         'Der einzige Weg zurück, falls die wiederhergestellten Daten die falschen sind');
  String get backupContinueAnyway => _t('Continue', 'Weiter');
  String get backupSourceHint  =>
      _t('Where should the backup come from? You get to see what it holds before anything is replaced.',
         'Woher soll die Sicherung kommen? Was sie enthält, siehst du, bevor irgendetwas ersetzt wird.');
  String get backupOutgoingTitle => _t('Being handed over', 'Wird übergeben');
  String get backupIncomingTitle => _t('This backup', 'Diese Sicherung');
  String get backupWhen        => _t('Version of', 'Stand');
  String get backupDevice      => _t('From', 'Von');
  String get backupSize        => _t('Size', 'Größe');
  String get backupGames       => _t('Games', 'Spiele');

  // ── Game Mode Selection ──────────────────────────────────────────────────
  String get selectGameMode       => _t('Select Game Mode', 'Spielmodus wählen');
  String get comingSoon           => _t('Coming Soon', 'Demnächst');
  String get modeInfoTitle        => _t('Game Mode Info', 'Spielmodus Info');

  // X01
  String get modeX01Name          => 'X01';
  String get modeX01Tagline       => _t('Classic countdown', 'Klassischer Countdown');
  String get modeX01Description   => _t(
    'Count down from a starting score (301, 501, 701 ...) to exactly zero.\n\n'
    'Each player throws 3 darts per visit. The total score of those darts is subtracted from the remaining score.\n\n'
    'You win a leg by reaching exactly 0. Depending on the Check-In/Check-Out rules, the first and/or last dart must land on a double (or master).\n\n'
    'A bust occurs when you score more than your remaining points, leave exactly 1, or fail the required Check-Out. In that case your score resets to where it was before the visit.',
    'Zähle von einem Startpunktestand (301, 501, 701 ...) genau auf null herunter.\n\n'
    'Jeder Spieler wirft pro Aufnahme 3 Darts. Die Gesamtpunkte dieser Darts werden vom verbleibenden Restpunkt abgezogen.\n\n'
    'Ein Leg gewinnst du, indem du genau 0 erreichst. Je nach Check-In/Check-Out-Regel muss der erste und/oder letzte Dart auf einem Double (oder Master) landen.\n\n'
    'Ein Bust passiert, wenn du mehr Punkte wirfst als du noch hast, genau 1 Punkt übrig lässt oder das geforderte Check-Out verfehlst. Dein Stand wird dann auf den Wert vor der Aufnahme zurückgesetzt.',
  );

  // Cricket
  String get modeCricketName        => 'Cricket';
  String get modeCricketTagline     => _t('Close numbers, score points', 'Felder schließen, Punkte sammeln');
  String get modeCricketDescription => _t(
    'Cricket is played on the numbers 15, 16, 17, 18, 19, 20 and the Bull. All other fields do not count.\n\n'
    'GOAL\n'
    'Close all 7 fields and have at least as many points as your opponent.\n\n'
    'CLOSING A FIELD\n'
    'Each field must be hit 3 times to "open" it for you:\n'
    '  Single = 1 hit\n'
    '  Double = 2 hits\n'
    '  Triple = 3 hits (closed instantly)\n\n'
    'Example: a Triple 20 closes the 20 with a single dart.\n\n'
    'SCORING POINTS\n'
    'Once you have opened a field (3 hits), every additional hit on it scores points equal to the field value, as long as your opponent has not closed it yet.\n\n'
    'Example:\n'
    '  You hit 20, 20, 20 -> field 20 is open\n'
    '  You hit 20 again -> +20 points for you\n'
    '  Opponent hits 20, 20, 20 -> field 20 is now closed for both, no more scoring on 20\n\n'
    'WINNING\n'
    'You win when all 7 fields are closed by you AND you have equal or more points than your opponent. If you close all fields but are behind on points, you must keep scoring until you catch up.\n\n'
    'CUT THROAT VARIANT\n'
    'Rules are reversed: points do not go to your own account. Instead, every hit on an open field adds points to each opponent who has not yet closed that field. The player with the fewest points wins. Strategy shifts: open fields quickly to avoid giving opponents points, and target fields your opponents have not closed yet.\n\n'
    'Example:\n'
    '  You open the 20 (3 hits) and hit it again -> opponent gets +20 points\n'
    '  Opponent closes the 20 -> further hits on 20 no longer score\n'
    '  You have 0 points, opponent has 20 points -> you are winning',
    'Cricket wird auf den Feldern 15, 16, 17, 18, 19, 20 und dem Bull gespielt. Alle anderen Felder zählen nicht.\n\n'
    'ZIEL\n'
    'Schließe alle 7 Felder und habe mindestens genauso viele Punkte wie dein Gegner.\n\n'
    'EIN FELD SCHLIESSEN\n'
    'Jedes Feld muss 3x getroffen werden, um es zu "öffnen":\n'
    '  Einfach = 1 Treffer\n'
    '  Doppel = 2 Treffer\n'
    '  Triple = 3 Treffer (direkt geschlossen)\n\n'
    'Beispiel: Ein Triple auf die 20 schließt das Feld sofort mit einem Dart.\n\n'
    'PUNKTE MACHEN\n'
    'Sobald du ein Feld geöffnet hast (3 Treffer), bringt jeder weitere Treffer darauf Punkte in Höhe des Feldwerts, solange dein Gegner das Feld noch nicht ebenfalls geschlossen hat.\n\n'
    'Beispiel:\n'
    '  Du triffst 20, 20, 20 -> Feld 20 ist offen\n'
    '  Du triffst nochmal 20 -> +20 Punkte für dich\n'
    '  Gegner trifft 20, 20, 20 -> Feld 20 ist nun für beide geschlossen, niemand kann mehr auf 20 punkten\n\n'
    'GEWINNBEDINGUNG\n'
    'Du gewinnst, wenn alle 7 Felder von dir geschlossen sind UND du gleich viele oder mehr Punkte hast als dein Gegner. Hast du alle Felder geschlossen aber weniger Punkte, musst du weiter punkten bis du gleichauf bist.\n\n'
    'CUT THROAT VARIANTE\n'
    'Die Regeln sind umgekehrt: Punkte gehen nicht auf dein eigenes Konto. Stattdessen bekommt jeder Gegner, der das Feld noch nicht geschlossen hat, die Punkte gutgeschrieben. Gewinner ist der Spieler mit den wenigsten Punkten. Die Strategie dreht sich um: öffne Felder schnell, um Gegner nicht zu belasten, und triff gezielt Felder, die deine Gegner noch nicht geschlossen haben.\n\n'
    'Beispiel:\n'
    '  Du öffnest die 20 (3 Treffer) und triffst sie nochmals -> Gegner bekommt +20 Punkte\n'
    '  Gegner schließt die 20 -> weitere Treffer auf die 20 bringen keine Punkte mehr\n'
    '  Du hast 0 Punkte, Gegner hat 20 Punkte -> du liegst vorne',
  );

  // Shanghai
  String get modeShanghaiName        => 'Shanghai';
  String get modeShanghaiTagline     => _t('Hit the right number each round', 'Jede Runde die richtige Zahl treffen');
  String get modeShanghaiDescription => _t(
    'Shanghai is played on the numbers 1 to 9. Only hits on the currently active field count. The maximum score per visit is 9 times the field value (3 darts, all Triple).\n\n'
    'SHANGHAI: INSTANT WIN\n'
    'If a player hits all three segments of the active field (Single, Double, and Triple) in one visit, this is called a Shanghai and wins the game immediately. Exception: if the following player also throws a Shanghai in their turn, the game continues. Otherwise the player with the most points wins.\n\n'
    'VARIANT 1: Classic (fields 1-9)\n'
    'Players take turns throwing 3 darts at the active number. Only hits on that number score. Numbers advance from 1 to 9.\n\n'
    'Example (active field: 6):\n'
    '  Single 6, Double 6, Triple 6 -> 6 + 12 + 18 = 36 points\n'
    '  Single 6, Double 6, miss -> 18 points, no Shanghai\n\n'
    'VARIANT 2: Clockwise (7 throws per player)\n'
    'Each player throws 7 darts. The target number advances with every dart in clockwise order: dart 1 targets 1, dart 2 targets 2, and so on up to 20, then the Bull. A Shanghai in this variant means hitting 3 consecutive clockwise numbers in one visit.\n\n'
    'Example:\n'
    '  Single 1, Double 2, Triple 3 -> Shanghai!\n\n'
    'VARIANT 3: Sequential\n'
    'A player throws at 1 until they hit it, then moves on to 2, and so on. The game can end in as few as 20 darts. A Shanghai here also consists of three different consecutive fields.',
    'Shanghai wird auf den Zahlen 1 bis 9 gespielt. Nur Treffer auf dem jeweils aktiven Feld zählen. Der maximale Punktestand pro Aufnahme beträgt das 9-Fache des Feldwerts (3 Darts, alle Triple).\n\n'
    'SHANGHAI: SOFORTSIEG\n'
    'Trifft ein Spieler alle drei Segmente des aktiven Feldes (Single, Double und Triple) in einer Aufnahme, nennt man das Shanghai und gewinnt das Spiel sofort. Ausnahme: Erzielt der Nachwerfer in seinem Zug ebenfalls einen Shanghai, wird das Spiel fortgesetzt. Ansonsten gewinnt der Spieler mit den meisten Punkten.\n\n'
    'VARIANTE 1: Klassisch (Felder 1-9)\n'
    'Die Spieler werfen abwechselnd 3 Darts auf die aktive Zahl. Nur Treffer auf dieser Zahl zählen. Die Zahlen gehen von 1 bis 9.\n\n'
    'Beispiel (aktives Feld: 6):\n'
    '  Single 6, Doppel 6, Triple 6 -> 6 + 12 + 18 = 36 Punkte\n'
    '  Single 6, Doppel 6, Fehler -> 18 Punkte, kein Shanghai\n\n'
    'VARIANTE 2: Im Uhrzeigersinn (7 Würfe pro Spieler)\n'
    'Jeder Spieler wirft 7 Darts. Die Zielzahl wechselt mit jedem Dart im Uhrzeigersinn: Dart 1 zielt auf die 1, Dart 2 auf die 2, usw. bis zur 20, dann das Bull. Ein Shanghai bedeutet hier drei aufeinanderfolgende Felder im Uhrzeigersinn in einer Aufnahme zu treffen.\n\n'
    'Beispiel:\n'
    '  Single 1, Doppel 2, Triple 3 -> Shanghai!\n\n'
    'VARIANTE 3: Sequenziell\n'
    'Ein Spieler wirft so lange auf die 1, bis er sie getroffen hat, dann auf die 2 usw. Das Spiel kann in bereits 20 Darts enden. Ein Shanghai besteht auch hier aus drei verschiedenen aufeinanderfolgenden Zahlenfeldern.',
  );

  // Around the Clock
  String get modeAroundClockName        => 'Around the Clock';
  String get modeAroundClockTagline     => _t('Hit every number in order', 'Alle Zahlen der Reihe nach treffen');
  String get modeAroundClockDescription => _t(
    'Around the Clock is played clockwise starting from 1 up to the Bull\'s Eye. You must hit each number at least once before moving to the next. The first player to reach and hit the Bull\'s Eye wins.\n\n'
    'CLOCKWISE ORDER\n'
    '1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5, 20, Bull\n\n'
    'FULL SEGMENT VARIANT\n'
    'A stricter variant requires hitting all three segments of each number before advancing: Single, Double, and Triple. Only then can you move to the next clockwise number.\n\n'
    'Example:\n'
    '  Single 1, Double 1, Triple 1 -> advance to 18\n'
    '  Single 18, Double 18, Triple 18 -> advance to 4\n\n'
    'POPULAR VARIANT: Skip Rules\n'
    'In the most popular variant, Double and Triple fields have a special bonus, similar to Shanghai:\n'
    '  Double: skip one field ahead\n'
    '  Triple: skip two fields ahead\n'
    '  Bull\'s Eye (inner Bull): joker, skip the current field and advance to the next\n\n'
    'Example:\n'
    '  You hit Double 18 -> skip 4, continue at 13\n'
    '  You hit Triple 4 -> skip 13 and 6, continue at 10\n'
    '  You hit Bull\'s Eye -> skip current field, advance by one',
    'Around the Clock wird im Uhrzeigersinn gespielt, beginnend bei der 1 bis zum Bull\'s Eye. Du musst jedes Feld mindestens einmal treffen, bevor du zum nächsten darfst. Der erste Spieler, der das Bull\'s Eye trifft, gewinnt.\n\n'
    'REIHENFOLGE IM UHRZEIGERSINN\n'
    '1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5, 20, Bull\n\n'
    'ALLE-SEGMENTE-VARIANTE\n'
    'Eine strengere Variante verlangt, dass du alle drei Segmente jedes Feldes triffst, bevor du weiter darfst: Single, Double und Triple. Erst dann kannst du zur nächsten Zahl im Uhrzeigersinn wechseln.\n\n'
    'Beispiel:\n'
    '  Single 1, Doppel 1, Triple 1 -> weiter zur 18\n'
    '  Single 18, Doppel 18, Triple 18 -> weiter zur 4\n\n'
    'BELIEBTE VARIANTE: Überspringen\n'
    'In der beliebtesten Variante haben Doppel- und Triple-Felder sowie das Bull eine besondere Funktion, ähnlich wie bei Shanghai:\n'
    '  Doppel: ein Feld überspringen\n'
    '  Triple: zwei Felder überspringen\n'
    '  Bull\'s Eye (inneres Bull): Joker, aktuelle Zahl überspringen und beim nächsten Feld weiterspielen\n\n'
    'Beispiel:\n'
    '  Du triffst Doppel 18 -> überspringe 4, weiter bei 13\n'
    '  Du triffst Triple 4 -> überspringe 13 und 6, weiter bei 10\n'
    '  Du triffst Bull\'s Eye -> überspringe aktuelle Zahl, rücke um eins vor',
  );

  // Checkout Ladder
  String get modeCheckoutLadderName        => _t('Checkout Ladder', 'Checkout-Leiter');
  String get modeCheckoutLadderTagline     => _t('Check out, number by number', 'Checkouts Zahl für Zahl');
  String get modeCheckoutLadderDescription => _t(
    'A training game for checkout routes. Everybody starts on 81 and checks their way up, one number at a time.\n\n'
    'AN ATTEMPT\n'
    'An attempt is 6 darts, two visits, in which the number has to be checked exactly, under the chosen check-out rule. 9 or 12 darts can be set up, and an attempt can get more darts from a number on, for example 9 darts from 110.\n\n'
    'UP AND DOWN\n'
    '  Checked: on to the next number, with two attempts\n'
    '  Climbing and missed twice: down one number\n'
    '  Falling: only one attempt per number\n'
    '  Never below the start number, where you simply try again\n\n'
    'SAFEHOUSE\n'
    'Check a number with the first visit of the attempt (darts 1 to 3) and you can never fall below the number above it again. That rewards the safe route, for example 15, 20, Bull for 85.\n\n'
    'BUST\n'
    'Too many points, a rest of 1, or a finish outside the check-out rule: the rest goes back to where the visit began, and the attempt goes on with its next visit.\n\n'
    'TRAINING\n'
    'Alone, or as a team sharing one ladder. The members take the visits in turn, so one sets up the rest and the other checks it, and the starter changes with every attempt. No winner: you end it whenever you like, at the latest by checking 170.\n\n'
    'RACE\n'
    'Every player or team climbs their own ladder from the start to the target number. Whoever checks the target first wins, but the round is played out until everybody has had as many attempts. If several get there, the fewest darts win, and if that is level too, a sudden death attempt on the number above the target decides.',
    'Ein Trainingsspiel für Checkout-Wege. Alle starten bei 81 und checken sich Zahl für Zahl nach oben.\n\n'
    'EIN VERSUCH\n'
    'Ein Versuch sind 6 Darts, also zwei Aufnahmen, in denen die Zahl genau gecheckt werden muss, nach der gewählten Check-out-Regel. Einstellbar sind auch 9 oder 12 Darts, und ab einer bestimmten Zahl kann ein Versuch mehr Darts bekommen, zum Beispiel 9 Darts ab 110.\n\n'
    'HOCH UND RUNTER\n'
    '  Gecheckt: weiter zur nächsten Zahl, mit zwei Versuchen\n'
    '  Beim Steigen zweimal verfehlt: eine Zahl runter\n'
    '  Beim Fallen: nur ein Versuch pro Zahl\n'
    '  Nie unter die Startzahl, dort versuchst du es einfach weiter\n\n'
    'SAFEHOUSE\n'
    'Checkst du eine Zahl mit der ersten Aufnahme des Versuchs (Darts 1 bis 3), kannst du nie mehr unter die Zahl darüber fallen. Das belohnt den sicheren Weg, zum Beispiel 15, 20, Bull bei 85.\n\n'
    'BUST\n'
    'Zu viele Punkte, ein Rest von 1 oder ein Finish außerhalb der Check-out-Regel: Der Rest springt auf den Stand vor der Aufnahme zurück, und der Versuch geht mit seiner nächsten Aufnahme weiter.\n\n'
    'TRAINING\n'
    'Allein oder als Team mit einer gemeinsamen Leiter. Die Mitglieder werfen die Aufnahmen abwechselnd, einer stellt den Rest, der andere checkt, und der Starter wechselt mit jedem Versuch. Kein Sieger: Du beendest es, wann du willst, spätestens mit dem Check der 170.\n\n'
    'RENNEN\n'
    'Jeder Spieler oder jedes Team klettert eine eigene Leiter von der Start- zur Zielzahl. Wer das Ziel zuerst checkt, gewinnt, aber die Runde wird zu Ende gespielt, bis alle gleich viele Versuche hatten. Schaffen es mehrere, gewinnen die wenigsten Darts, und ist auch das gleich, entscheidet ein Sudden-Death-Versuch auf die Zahl über dem Ziel.',
  );

  // ── Misc numbers/units ───────────────────────────────────────────────────
  String dartsN(int n) => _t('$n dart${n != 1 ? 's' : ''}', '$n Dart${n != 1 ? 's' : ''}');
  String legLabel(int l) => 'Leg $l';
  String setLabel(int s) => 'Set $s';

  // ── Compact / abbreviation labels ────────────────────────────────────────
  String get straight       => _t('Straight', 'Straight');
  String get master         => _t('Master', 'Master');
  String get setsAbbr       => _t('S', 'S');
  String get legsAbbr       => _t('L', 'L');
  String get highAbbr       => _t('High', 'High');
  String get shareSubject   => _t('DartScore Result', 'DartScore Ergebnis');
  String get noThrowData    => _t('No throw data available.', 'Keine Wurfdaten vorhanden.');
  String get guest          => _t('Guest', 'Gast');
  String get addTeam        => _t('Add team', 'Team hinzufügen');
  String get removeTeam     => _t('Remove team', 'Team entfernen');
  String get teamNameLabel  => _t('Team name', 'Teamname');
  String get doublesLabel   => _t('Doubles', 'Doubles');

  // ── Cricket History ──────────────────────────────────────────────────────────
  String cricketGameInfo(String variant) =>
      _t('Cricket · $variant', 'Cricket · $variant');
  String get cricketVariantNormal    => _t('Normal', 'Normal');
  String get cricketVariantCutThroat => 'Cut Throat';

  // ── Cricket Setup ────────────────────────────────────────────────────────────
  String get cricketSetup         => _t('Cricket Setup', 'Cricket einrichten');
  String get cricketVariant       => _t('Variant', 'Variante');
  String get cricketNormal        => _t('Normal', 'Normal');
  String get cricketCutThroat     => 'Cut Throat';
  String get cricketCutThroatDesc =>
      _t('Points go to opponents who haven\'t closed the field. Fewest points wins.',
         'Punkte gehen an Gegner, die das Feld noch nicht geschlossen haben. Wenigste Punkte gewinnt.');
  String get cricketScoringMode   => _t('Scoring Mode', 'Wertungsmodus');
  String get cricketStandard      => _t('Standard (S/D/T)', 'Standard (E/D/T)');
  String get cricketSimple        => _t('Simple (singles only)', 'Einfach (nur Singles)');
  String get cricketSimpleDesc    =>
      _t('Every dart counts as 1 mark regardless of segment hit.',
         'Jeder Dart zählt als 1 Treffer unabhängig vom getroffenen Segment.');
  String get cricketMinPlayers    =>
      _t('Cricket requires at least 2 players.', 'Cricket benötigt mindestens 2 Spieler.');

  // ── Cricket Game ─────────────────────────────────────────────────────────────
  String get bull                 => 'Bull';
  String get cricketMiss          => _t('Miss', 'Miss');
  String get cricketScore         => _t('Score', 'Punkte');
  String get cricketMarks         => _t('Marks', 'Treffer');
  String get cricketQuit          => _t('Quit', 'Beenden');

  // ── Cricket Summary ──────────────────────────────────────────────────────────
  String get cricketSummaryTitle  => _t('Game Summary', 'Spielübersicht');
  String get cricketFieldsClosed  => _t('Fields closed', 'Felder geschlossen');
  String get cricketTotalScore    => _t('Total Score', 'Gesamtpunkte');
  String get cricketWins          =>  _t('wins!', 'hat gewonnen!');
  String cricketWinner(String name) => '🎯 $name $cricketWins';

  // ── Shanghai History ─────────────────────────────────────────────────────────
  String shanghaiGameInfo(String variant) =>
      _t('Shanghai · $variant', 'Shanghai · $variant');

  // ── Shanghai Setup ───────────────────────────────────────────────────────────
  String get shanghaiSetup        => _t('Shanghai Setup', 'Shanghai einrichten');
  String get shanghaiVariant      => _t('Variant', 'Variante');
  String get shanghaiClassic      => _t('Classic (1-9)', 'Klassisch (1-9)');
  String get shanghaiClockwise    => _t('Clockwise', 'Im Uhrzeigersinn');
  String get shanghaiSequential   => _t('Sequential', 'Sequenziell');
  String get shanghaiClassicDesc  =>
      _t('9 rounds, target advances from 1 to 9. Each player throws 3 darts at the active number per round.',
         '9 Runden, die Zielzahl steigt von 1 bis 9. Jeder Spieler wirft pro Runde 3 Darts auf die aktive Zahl.');
  String get shanghaiClockwiseDesc =>
      _t('One visit of 7 darts per player. The target advances by one with every dart, from 1 to 7.',
         'Eine Aufnahme mit 7 Darts pro Spieler. Die Zielzahl steigt mit jedem Dart von 1 bis 7.');
  String get shanghaiSequentialDesc =>
      _t('Throw at 1 until you hit it, then move on to 2, and so on up to 20. First to finish wins.',
         'Wirf auf die 1, bis du sie triffst, dann auf die 2 usw. bis 20. Wer zuerst fertig ist, gewinnt.');
  String get shanghaiMinPlayers   =>
      _t('Shanghai requires at least 2 players.', 'Shanghai benötigt mindestens 2 Spieler.');

  // ── Shanghai Game ────────────────────────────────────────────────────────────
  String get shanghaiTarget       => _t('Target', 'Ziel');
  String get shanghaiMiss         => _t('Miss', 'Miss');
  String get shanghaiScore        => _t('Score', 'Punkte');
  String get shanghaiQuit         => _t('Quit', 'Beenden');
  String get shanghaiInstantWin   => _t('Shanghai! Instant win', 'Shanghai! Sofortsieg');
  String get shanghaiPending      => _t('Shanghai pending', 'Shanghai ausstehend');
  String get shanghaiHintTitle    => _t('Shanghai chance', 'Shanghai-Chance');
  String shanghaiHintStreak(int n) => n == 1
      ? _t('1 more hit in a row', 'noch 1 Treffer in Folge')
      : _t('$n more hits in a row', 'noch $n Treffer in Folge');

  // ── Shanghai Summary ─────────────────────────────────────────────────────────
  String get shanghaiSummaryTitle => _t('Game Summary', 'Spielübersicht');
  String get shanghaiTotalScore   => _t('Total Score', 'Gesamtpunkte');
  String shanghaiDartsUsed(int n) => dartsN(n);
  String get shanghaiWins         => _t('wins!', 'hat gewonnen!');
  String shanghaiWinner(String name) => '🎯 $name $shanghaiWins';

  // ── Around the Clock History ─────────────────────────────────────────────────
  String aroundClockGameInfo(String variant) =>
      _t('Around the Clock · $variant', 'Around the Clock · $variant');

  // ── Around the Clock Setup ───────────────────────────────────────────────────
  String get aroundClockSetup       => _t('Around the Clock Setup', 'Around the Clock einrichten');
  String get aroundClockVariant     => _t('Variant', 'Variante');
  String get aroundClockBasic       => _t('Basic', 'Standard');
  String get aroundClockFullSegments => _t('Full Segments', 'Alle Segmente');
  String get aroundClockSkipRules   => _t('Skip Rules', 'Überspringen');
  String get aroundClockBasicDesc   =>
      _t('Hit each number at least once, in clockwise order, then the Bull. First to the Bull wins.',
         'Triff jede Zahl mindestens einmal in der Reihenfolge im Uhrzeigersinn, dann das Bull. Wer zuerst das Bull trifft, gewinnt.');
  String get aroundClockFullSegmentsDesc =>
      _t('Hit Single, Double and Triple of each number before advancing to the next.',
         'Triff Single, Double und Triple jeder Zahl, bevor du zur nächsten weiterziehst.');
  String get aroundClockSkipRulesDesc =>
      _t('Double skips one field ahead, Triple skips two, and the Bull\'s Eye is a joker that skips the current field.',
         'Doppel überspringt ein Feld, Triple überspringt zwei, und das Bull\'s Eye ist ein Joker, der das aktuelle Feld überspringt.');
  String get aroundClockMinPlayers  =>
      _t('Select at least 1 player.', 'Wähle mindestens 1 Spieler aus.');

  // ── Around the Clock Game ────────────────────────────────────────────────────
  String get aroundClockTarget      => _t('Target', 'Ziel');
  String get aroundClockMiss        => _t('Miss', 'Miss');
  String get aroundClockQuit        => _t('Quit', 'Beenden');
  String get aroundClockProgress    => _t('Progress', 'Fortschritt');
  String aroundClockProgressN(int hit, int total) =>
      _t('$hit/$total hit', '$hit/$total getroffen');
  String get aroundClockHintTitle   => _t('Open', 'Offen');
  String get aroundClockJoker       => _t('Joker', 'Joker');

  // ── Around the Clock Summary ─────────────────────────────────────────────────
  String get aroundClockSummaryTitle => _t('Game Summary', 'Spielübersicht');
  String aroundClockDartsUsed(int n) => dartsN(n);
  String get aroundClockWins         => _t('wins!', 'hat gewonnen!');
  String aroundClockWinner(String name) => '🎯 $name $aroundClockWins';

  // ── Checkout Ladder History ──────────────────────────────────────────────────
  String checkoutLadderTrainingInfo(int start) =>
      _t('Checkout Ladder · Training from $start', 'Checkout-Leiter · Training ab $start');
  String checkoutLadderRaceInfo(int start, int target) =>
      _t('Checkout Ladder · Race $start to $target', 'Checkout-Leiter · Rennen $start bis $target');

  // ── Checkout Ladder Setup ────────────────────────────────────────────────────
  String get ladderSetup           => _t('Checkout Ladder Setup', 'Checkout-Leiter einrichten');
  String get ladderVariant         => _t('Variant', 'Variante');
  String get ladderTraining        => _t('Training', 'Training');
  String get ladderRace            => _t('Race', 'Rennen');
  String get ladderTrainingDesc    =>
      _t('Alone or as a team on one ladder. No winner: you end it whenever you like.',
         'Allein oder als Team auf einer Leiter. Kein Sieger: Du beendest es, wann du willst.');
  String get ladderRaceDesc        =>
      _t('Everybody climbs their own ladder. Whoever checks the target number first wins.',
         'Jeder klettert seine eigene Leiter. Wer die Zielzahl zuerst checkt, gewinnt.');
  String get ladderNumbers         => _t('Numbers', 'Zahlen');
  String get ladderStartNumber     => _t('Start', 'Start');
  String get ladderTargetNumber    => _t('Target', 'Ziel');
  String get ladderDartsPerAttempt => _t('Darts per attempt', 'Darts pro Versuch');
  String get ladderStep            => _t('More darts from a number on', 'Mehr Darts ab einer Zahl');
  String get ladderStepFrom        => _t('From', 'Ab');
  String ladderStepDesc(int from, int darts) =>
      _t('From $from on an attempt holds $darts darts.', 'Ab $from hat ein Versuch $darts Darts.');
  String get ladderMinPlayers      =>
      _t('Select at least 1 player.', 'Wähle mindestens 1 Spieler aus.');
  String get ladderRaceMinSlots    =>
      _t('A race needs at least 2 players or teams.', 'Ein Rennen braucht mindestens 2 Spieler oder Teams.');

  // ── Checkout Ladder Game ─────────────────────────────────────────────────────
  String ladderRaceTo(int n)       => _t('Race to $n', 'Rennen bis $n');
  String ladderTrainingFrom(int n) => _t('Training from $n', 'Training ab $n');
  String ladderSuddenDeath(int n)  => _t('Sudden death on $n', 'Sudden Death auf $n');
  String get ladderClimbing        => _t('climbing', 'steigend');
  String get ladderFalling         => _t('falling', 'fallend');
  String ladderAttemptOf(int a, int of) => _t('Attempt $a of $of', 'Versuch $a von $of');
  String get ladderLastAttempt     => _t('Last attempt', 'Letzter Versuch');
  String ladderFloor(int n)        => _t('Floor $n', 'Boden $n');
  String get ladderTargetChecked   => _t('Target checked', 'Ziel gecheckt');
  String get ladderCompleted       => _t('Ladder completed', 'Leiter geschafft');
  String get ladderOut             => _t('Out', 'Raus');
  String get ladderRest            => _t('Rest', 'Rest');
  String get ladderNumber          => _t('Number', 'Zahl');
  String get ladderFloorLabel      => _t('Floor', 'Boden');
  String ladderVisitChecked(int n) => _t('Checked $n', '$n gecheckt');
  String ladderVisitRest(int n)    => _t('Rest $n', 'Rest $n');
  String get ladderVisitBust       => _t('Bust', 'Bust');
  String get ladderLeaveTitle      => _t('Leave Training', 'Training verlassen');
  String get ladderLeaveBody       =>
      _t('Continue it later from the history, or end it now and see the summary?',
         'Später aus dem Verlauf weiterspielen oder jetzt beenden und die Übersicht sehen?');
  String get ladderContinueLater   => _t('Continue later', 'Später weiter');
  String get ladderEndTraining     => _t('End training', 'Training beenden');

  // ── Checkout Ladder Summary ──────────────────────────────────────────────────
  String get ladderSummaryTitle    => _t('Game Summary', 'Spielübersicht');
  String ladderWinner(String name) => '🎯 $name $aroundClockWins';
  String get ladderHighestChecked  => _t('Highest checked', 'Höchste gecheckte Zahl');
  String get ladderEndedOn         => _t('Ended on', 'Endstand');
  String get ladderChecksAttempts  => _t('Checks / attempts', 'Checks / Versuche');
  String get ladderCheckRate       => _t('Check rate', 'Check-Quote');
  String get ladderDartsPerCheck   => _t('Darts per check', 'Ø Darts pro Check');
  String get ladderSafehouses      => _t('Safehouses', 'Safehouses');
  String get ladderDrops           => _t('Drops', 'Rückfälle');
  String get ladderBusts           => _t('Busts', 'Busts');
}

// ── Delegate ──────────────────────────────────────────────────────────────────

/// Localizations delegate that supplies [AppLocalizations] for the supported
/// English and German locales.
class AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const AppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'de'].contains(locale.languageCode);

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      AppLocalizations(locale);

  @override
  bool shouldReload(AppLocalizationsDelegate old) => false;
}
