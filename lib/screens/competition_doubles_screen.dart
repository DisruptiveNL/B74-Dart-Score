import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../services/b74_doubles_live_stats.dart';
import '../services/b74_live_tv.dart';
import '../utils/layout.dart';

import '../services/b74_doubles_session.dart';
import '../widgets/b74_doubles_numeric_input.dart';
import '../widgets/b74_doubles_opening_input.dart';
import '../services/competition_match_catalog.dart';

/// 701 competition screen, isolated from the singles 501 workflow.
class CompetitionDoublesScreen extends StatefulWidget {
  const CompetitionDoublesScreen({super.key, required this.match});
  final CompetitionDoublesSummary match;

  @override
  State<CompetitionDoublesScreen> createState() =>
      _CompetitionDoublesScreenState();
}

class _CompetitionDoublesScreenState extends State<CompetitionDoublesScreen> {
  B74DoublesSession? _session;
  String? _error;
  bool _busy = false;
  bool _dummyAutoPending = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    try {
      var session = await B74DoublesSession.load(widget.match.gameId);
      if (mounted) {
        B74LiveTv.instance.attachDoubles(session,
          homeTeam: widget.match.homeTeam,
          awayTeam: widget.match.awayTeam,
          homePlayers: widget.match.homePlayers,
          awayPlayers: widget.match.awayPlayers);
        setState(() {
          _session = session;
          _error = null;
        });
        _queueDummyVisit();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  void _queueDummyVisit() {
    if (!mounted || _busy || _dummyAutoPending ||
        _session?.isDummyTurn != true) {
      return;
    }
    _dummyAutoPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (mounted && !_busy && _session?.isDummyTurn == true) {
          await _run((s) => s.completeVisit(score: 0));
        }
      } finally {
        _dummyAutoPending = false;
        // Covers consecutive Dummy positions without requiring a tap.
        if (mounted && _session?.isDummyTurn == true && _error == null) {
          _queueDummyVisit();
        }
      }
    });
  }

  Future<void> _run(Future<void> Function(B74DoublesSession) action) async {
    if (_busy || _session == null) return;
    if (await DbHelper.instance.isCompetitionMatchLocked(widget.match.matchId)) {
      if (mounted) setState(() => _error = 'Wedstrijd afgesloten: scorewijzigingen zijn niet toegestaan.');
      return;
    }
    if (await DbHelper.instance.isCompetitionMatchLocked(widget.match.matchId)) {
      if (mounted) setState(() => _error = 'Wedstrijd afgesloten: scorewijzigingen zijn niet toegestaan.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action(_session!);
      await _reload();
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        // _reload() runs while _busy is true, so it cannot schedule a
        // Dummy visit itself. Queue it only after the command finishes.
        if (_error == null) {
          _queueDummyVisit();
        }
      }
    }
  }

  String _team(int index) =>
      index == 0 ? widget.match.homeTeam : widget.match.awayTeam;
  String _player(int team, int player) =>
      (team == 0 ? widget.match.homePlayers : widget.match.awayPlayers)[player];

  Future<void> _showCorrection(B74DoublesSession session) async {
    final selected = await showDialog<int>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('CORRECTIE'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final visit in session.correctableVisits)
              ListTile(
                title: Text(visit.bust ? 'BUST' : '${visit.score} punten'),
                subtitle: Text('Beurt ${visit.sequence + 1}'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => Navigator.pop(c, visit.sequence),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('ANNULEREN'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final old = session.correctableVisits.firstWhere(
      (v) => v.sequence == selected,
    );
    final controller = TextEditingController(text: '${old.score}');
    var bust = old.bust;
    try {
      final change = await showDialog<({int score, bool bust})>(
        context: context,
        builder: (c) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('BEURT CORRIGEREN'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('SCORE')),
                    ButtonSegment(value: true, label: Text('BUST')),
                  ],
                  selected: {bust},
                  onSelectionChanged: (values) =>
                      update(() => bust = values.first),
                ),
                if (!bust)
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Score (0–180)',
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('ANNULEREN'),
              ),
              FilledButton(
                onPressed: () {
                  final score = bust ? 0 : int.tryParse(controller.text);
                  if (score == null || score < 0 || score > 180) return;
                  Navigator.pop(c, (score: score, bust: bust));
                },
                child: const Text('OPSLAAN'),
              ),
            ],
          ),
        ),
      );
      if (change != null && mounted) {
        await _run(
          (s) =>
              s.correctVisit(selected, score: change.score, bust: change.bust),
        );
      }
    } finally {
      // Wait for the dialog route to finish its exit animation before dispose.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      controller.dispose();
    }
  }

  Widget _scoreInput(B74DoublesSession session, dynamic engine) {
    if (session.checkIn == 'double' &&
        !engine.isOpened(engine.currentVisit.team)) {
      return SizedBox(
        height: 465,
        child: B74DoublesOpeningInput(
          key: ValueKey('opening-${widget.match.gameId}-${session.events.length}'),
          remaining: engine.remaining[engine.currentVisit.team] as int,
          checkOut: session.checkOut,
          onSubmit: ({required score, required bust, required checkout,
              required checkoutDart, required openingDouble, required openingDart}) =>
              _run((s) => s.completeVisit(
                score: score,
                bust: bust,
                validCheckout: checkout,
                checkoutDart: checkoutDart,
                openingDouble: openingDouble,
                openingDart: openingDart,
              )),
        ),
      );
    }
    return B74DoublesNumericInput(
      key: ValueKey('${widget.match.gameId}-${engine.leg}-${session.events.length}'),
      remaining: engine.remaining[engine.currentVisit.team] as int,
      disabled: _busy,
      checkOut: session.checkOut,
      onSubmit: (score, bust, checkout, darts) => _run((s) => s.completeVisit(
        score: score, bust: bust, validCheckout: checkout,
        checkoutDart: darts,
      )),
    );
  }

  Widget _statsPanel(B74DoublesSession session, dynamic engine) {
    final stats = B74DoublesLiveStats.fromEvents(
      session.events,
      startTeam: session.startTeam,
      bestOf: session.bestOf,
      openingBullRequired: session.openingBullRequired,
      startingScore: session.startingScore,
      playersPerTeam: session.playersPerTeam,
      checkIn: session.checkIn,
    );
    final turn = engine.currentVisit;
    final current = stats.player(turn.team, turn.player);
    final colors = Theme.of(context).colorScheme;
    Widget statRow(String label, String value) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
    return ListView(
      children: [
        Card(
          color: colors.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_player(turn.team, turn.player)} · Aan de beurt',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                const Text('Laatste 3 beurten'),
                Text(
                  current.lastThree.isEmpty
                      ? 'Nog geen beurten'
                      : current.lastThree.join(' · '),
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Spelerstatistieken',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                statRow(
                  '3-dart gemiddelde',
                  current.threeDartAverage.toStringAsFixed(2),
                ),
                statRow(
                  'First 9',
                  current.firstNineAverage?.toStringAsFixed(2) ?? '—',
                ),
                statRow(
                  'Beurten / darts',
                  '${current.visits} / ${current.dartsThrown}',
                ),
                statRow('Beste beurt', '${current.bestVisit}'),
                statRow(
                  '100+ / 140+ / 180',
                  '${current.hundreds} / ${current.oneForties} / ${current.oneEighties}',
                ),
              ],
            ),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Alle ${session.playersPerTeam * 2} spelers',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                for (var team = 0; team < 2; team++)
                  for (var player = 0; player < session.playersPerTeam; player++)
                    statRow(
                      '${_player(team, player)} · ${stats.player(team, player).visits} beurten',
                      stats
                          .player(team, player)
                          .threeDartAverage
                          .toStringAsFixed(2),
                    ),
              ],
            ),
          ),
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text(
            'Normale beurt = 3 darts; checkout = gekozen dart. First 9 alleen bij 9 volledig geregistreerde darts.',
            style: TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final engine = session?.engine;
    return Scaffold(
      appBar: AppBar(title: Text(widget.match.homePlayers.length == 4
          ? 'Biergame · 1001' : 'Koppel ${widget.match.slot} · 701')),
      body: session == null || engine == null
          ? Center(
              child: _error != null
                  ? Text(_error!)
                  : session == null
                      ? const CircularProgressIndicator()
                      : const Text('Scoresessie niet beschikbaar'),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  '${widget.match.homeTeam} vs ${widget.match.awayTeam}',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(widget.match.homePlayers.length == 4
                  ? '1001 · 1 leg' : 'Best of ${widget.match.bestOf} · Leg ${engine.leg}'),
                const SizedBox(height: 12),
                Row(
                  children: [
                    for (var team = 0; team < 2; team++)
                      Expanded(
                        child: Card(
                          color:
                              engine.winner == team ||
                                  (engine.winner == null &&
                                      !engine.awaitingStarter &&
                                      engine.currentVisit.team == team)
                              ? Theme.of(context).colorScheme.primaryContainer
                              : Theme.of(
                                  context,
                                ).colorScheme.surfaceContainerHigh,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: 14,
                              horizontal: 8,
                            ),
                            child: Column(
                              children: [
                                Text(
                                  _team(team),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                FittedBox(
                                  child: Text(
                                    '${engine.remaining[team]}',
                                    style: const TextStyle(
                                      fontSize: 58,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Text('Legs: ${engine.legsWon[team]}'),
                                Text(
                                  (team == 0 ? widget.match.homePlayers : widget.match.awayPlayers).join(' + '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                if (session.events.isNotEmpty &&
                    (() {
                      final last = session.events.last;
                      return last.contains('"type":"visit"');
                    })())
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () async {
                            final confirmed = await showDialog<bool>(
                              context: context,
                              builder: (c) => AlertDialog(
                                title: const Text(
                                  'Laatste beurt terugdraaien?',
                                ),
                                content: const Text(
                                  'Ook een checkout en legwinst worden hersteld. '
                                  'De correctie blijft bewaard in de historie.',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(c, false),
                                    child: const Text('ANNULEREN'),
                                  ),
                                  FilledButton(
                                    onPressed: () => Navigator.pop(c, true),
                                    child: const Text('TERUGDRAAIEN'),
                                  ),
                                ],
                              ),
                            );
                            if (confirmed == true) {
                              await _run((s) => s.undoLastVisit());
                            }
                          },
                    icon: const Icon(Icons.undo),
                    label: const Text('LAATSTE BEURT CORRIGEREN'),
                  ),
                if (session.checkIn != 'double' && session.correctableVisits.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _showCorrection(session),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('CORRECTIE (LAATSTE 3)'),
                  ),
                if (engine.winner != null) ...[
                  Card(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          const Icon(Icons.emoji_events, size: 40),
                          Text(
                            'Wedstrijd afgelopen · ${_team(engine.winner!)} wint!',
                            style: Theme.of(context).textTheme.titleLarge,
                            textAlign: TextAlign.center,
                          ),
                          Text(
                            '${engine.legsWon[0]} – ${engine.legsWon[1]}',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const Text('Uitslag is nog corrigeerbaar'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('TERUG NAAR WEDSTRIJDEN'),
                  ),
                ] else if (engine.awaitingStarter) ...[
                  const SizedBox(height: 16),
                  Text(
                    engine.needsBull
                        ? 'Beslissende leg: bull verplicht'
                        : (engine.leg == 1 &&
                                  session.events.isEmpty &&
                                  session.openingBullRequired
                              ? 'Kies de starter voor deze leg'
                              : 'Bevestig of wijzig de starter'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  if (!engine.needsBull &&
                      !(engine.leg == 1 && session.openingBullRequired) &&
                      engine.suggestedStarter != null)
                    Text('Voorgesteld: ${_team(engine.suggestedStarter!)}'),
                  for (var team = 0; team < 2; team++)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: ElevatedButton(
                        onPressed: _busy
                            ? null
                            : () => _run(
                                (s) => s.confirmStarter(
                                  team,
                                  viaBull:
                                      engine.needsBull ||
                                      (engine.leg == 1 &&
                                          session.events.isEmpty &&
                                          session.openingBullRequired),
                                ),
                              ),
                        child: Text(
                          '${engine.needsBull || (engine.leg == 1 && session.openingBullRequired) ? 'Bullwinnaar' : 'Starter'}: ${_team(team)}',
                        ),
                      ),
                    ),
                ] else ...[
                  const SizedBox(height: 8),
                  Text(
                    'Aan de beurt: ${_team(engine.currentVisit.team)} · '
                    '${_player(engine.currentVisit.team, engine.currentVisit.player)}',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (session.isDummyTurn)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Text('Dummy: 0 punten / 3 darts worden automatisch geregistreerd'),
                    )
                  else if (isTabletLayout(context))
                    SizedBox(
                      height: 570,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _scoreInput(session, engine)),
                          const VerticalDivider(width: 18),
                          Expanded(child: _statsPanel(session, engine)),
                        ],
                      ),
                    )
                  else ...[
                    SizedBox(height: 465, child: _scoreInput(session, engine)),
                    _statsPanel(session, engine),
                  ],
                ],
              ],
            ),
    );
  }
}
