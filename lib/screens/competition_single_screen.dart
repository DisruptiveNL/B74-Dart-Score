import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../database/db_helper.dart';
import '../models/player.dart';
import '../providers/game_provider.dart';
import '../services/competition_match_catalog.dart';
import '../services/competition_single_launcher.dart';
import '../services/competition_single_result_builder.dart';
import '../services/competition_single_result_sender.dart';
import 'game_screen.dart';

/// Competition X01 entry point. Existing games are resumed, never duplicated.
class CompetitionSingleScreen extends StatefulWidget {
  const CompetitionSingleScreen({
    super.key,
    required this.match,
    required this.single,
  });
  final CompetitionMatchSummary match;
  final CompetitionSingleSummary single;

  @override
  State<CompetitionSingleScreen> createState() =>
      _CompetitionSingleScreenState();
}

class _CompetitionSingleScreenState extends State<CompetitionSingleScreen> {
  bool _busy = false;
  String? _error;
  final _launcher = CompetitionSingleLauncher();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '8765');
  final _token = TextEditingController();
  final _builder = CompetitionSingleResultBuilder();
  final _sender = CompetitionSingleResultSender();
  String? _sendMessage;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    _token.dispose();
    _sender.close();
    super.dispose();
  }

  Future<void> _sendResult() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _sendMessage = null;
    });
    try {
      final match = widget.match;
      final single = widget.single;
      await _builder.prepare(match, single);
      final status = await _sender.send(
        matchId: match.id,
        slot: single.slot,
        host: _host.text.trim(),
        port: int.parse(_port.text.trim()),
        token: _token.text.trim(),
      );
      if (mounted) {
        setState(
          () => _sendMessage =
              'Dashboard heeft het resultaat opgeslagen ($status).',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _play({bool? homeStarts}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final match = widget.match;
      final single = widget.single;
      final provider = context.read<GameProvider>();
      final existing = await _launcher.existingGameId(match.id, single.slot);
      if (existing != null) {
        final db = DbHelper.instance;
        final game = await db.getGame(existing);
        if (game == null) throw StateError('Opgeslagen X01-game ontbreekt');
        final ids = await db.getGamePlayerIds(existing);
        final players = <Player>[];
        for (final id in ids) {
          final player = await db.getPlayer(id);
          if (player == null) throw StateError('Opgeslagen speler ontbreekt');
          players.add(player);
        }
        await provider.resumeGame(game, players);
      } else {
        if (homeStarts == null) throw StateError('Bepaal eerst wie begint');
        final players = await _launcher.players(single, homeStarts: homeStarts);
        await provider.startGame(
          CompetitionSingleLauncher.game(match),
          players,
          competitionMatchId: match.id,
          competitionSlot: single.slot,
          starterExternalId: homeStarts ? single.homeId : single.awayId,
        );
      }
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute<void>(builder: (_) => const GameScreen()),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _isFinishedOrArchived() async {
    final result = await DbHelper.instance.competitionSingleResult(
      widget.match.id,
      widget.single.slot,
    );
    if (result?['status'] == 'archived') return true;
    final id = await _launcher.existingGameId(
      widget.match.id,
      widget.single.slot,
    );
    if (id == null) return false;
    final game = await DbHelper.instance.getGame(id);
    return game?.finishedAt != null;
  }

  @override
  Widget build(BuildContext context) {
    final fixed = CompetitionSingleLauncher.homeStarts(
      widget.match,
      widget.single,
    );
    return Scaffold(
      appBar: AppBar(title: Text('Single ${widget.single.slot}')),
      body: FutureBuilder<int?>(
        future: _launcher.existingGameId(widget.match.id, widget.single.slot),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Fout: ${snapshot.error}'));
          }
          if (!snapshot.hasData &&
              snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final existing = snapshot.data != null;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${widget.match.home}: ${widget.single.homePlayer}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Center(child: Text('VS')),
                    ),
                    Text(
                      '${widget.match.away}: ${widget.single.awayPlayer}',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 24),
                    if (existing)
                      FutureBuilder<bool>(
                        future: _isFinishedOrArchived(),
                        builder: (context, state) {
                          if (!state.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          if (!state.data!) {
                            return FilledButton(
                              onPressed: _busy ? null : () => _play(),
                              child: const Text('Hervat X01-wedstrijd'),
                            );
                          }
                          return FutureBuilder<Map<String, Object?>?>(
                            future: DbHelper.instance.competitionSingleResult(
                              widget.match.id,
                              widget.single.slot,
                            ),
                            builder: (context, result) {
                              if (!result.hasData &&
                                  result.connectionState !=
                                      ConnectionState.done) {
                                return const Center(
                                  child: CircularProgressIndicator(),
                                );
                              }
                              if (result.data?['status'] == 'archived') {
                                return const Text(
                                  'Resultaat ontvangen en gearchiveerd.',
                                );
                              }
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  const Text(
                                    'Single uitgespeeld. Vul de gegevens in '
                                    'die het Dashboard toont bij Single-resultaten ontvangen.',
                                  ),
                                  const SizedBox(height: 12),
                                  TextField(
                                    controller: _host,
                                    decoration: const InputDecoration(
                                      labelText: 'Dashboard IP-adres',
                                    ),
                                  ),
                                  TextField(
                                    controller: _port,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Poort',
                                    ),
                                  ),
                                  TextField(
                                    controller: _token,
                                    decoration: const InputDecoration(
                                      labelText: 'Koppeltoken',
                                    ),
                                  ),
                                  const SizedBox(height: 16),
                                  FilledButton.icon(
                                    onPressed: _busy ? null : _sendResult,
                                    icon: const Icon(Icons.send),
                                    label: const Text('VERZEND RESULTAAT'),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      )
                    else if (fixed == null) ...[
                      const Text('Wie heeft het bullen gewonnen?'),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _busy ? null : () => _play(homeStarts: true),
                        child: Text('${widget.single.homePlayer} begint'),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _play(homeStarts: false),
                        child: Text('${widget.single.awayPlayer} begint'),
                      ),
                    ] else
                      FilledButton(
                        onPressed: _busy
                            ? null
                            : () => _play(homeStarts: fixed),
                        child: Text(
                          'Start X01 — ${fixed ? widget.single.homePlayer : widget.single.awayPlayer} begint',
                        ),
                      ),
                    if (_busy)
                      const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child: LinearProgressIndicator(),
                      ),
                    if (_sendMessage != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(_sendMessage!),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
