import 'dart:async';

import 'package:flutter/material.dart';
import '../services/b74_live_tv.dart';
import '../widgets/wifi_pairing.dart';
import '../database/db_helper.dart';
import '../services/competition_single_result_contract.dart';

import '../services/competition_match_catalog.dart';
import '../services/b74_doubles_session.dart';
import '../services/competition_sync_contract.dart';
import 'competition_single_screen.dart';
import 'competition_doubles_screen.dart';
import 'competition_receive_screen.dart';

/// Imported competition matches. Scoring integration follows in Patch 02E.
class CompetitionMatchesScreen extends StatefulWidget {
  const CompetitionMatchesScreen({super.key});

  @override
  State<CompetitionMatchesScreen> createState() =>
      _CompetitionMatchesScreenState();
}

class _CompetitionMatchesScreenState extends State<CompetitionMatchesScreen> {
  late Future<List<CompetitionMatchSummary>> _matches;
  late Future<List<CompetitionDoublesSummary>> _doubles;
  late Future<List<CompetitionDoublesSummary>> _beers;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _reload();

    _refreshTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(_reload);
    });

    // Herstel een eerder goedgekeurde TV-koppeling zonder nieuwe QR-scan.
    B74LiveTv.instance.restore().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _reload() {
    final catalog = CompetitionMatchCatalog();
    _matches = catalog.load();
    _doubles = catalog.loadDoubles();
    _beers = catalog.loadBeers();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Competities & Toernooien'),
      actions: [
        IconButton(
          tooltip: 'B74 Live TV koppelen of ontkoppelen',
          icon: Icon(B74LiveTv.instance.connected ? Icons.tv : Icons.tv_outlined),
          onPressed: () async {
            if (B74LiveTv.instance.connected) {
              final shouldDisconnect = await showDialog<bool>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('B74 Live TV'),
                  content: const Text('De TV is verbonden. Verbinding verbreken?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Annuleren')),
                    TextButton(onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Ontkoppelen')),
                  ],
                ),
              );
              if (shouldDisconnect == true) {
                await B74LiveTv.instance.disconnect();
              }
            } else {
              var busy = false;
              await showDialog<void>(
                context: context,
                builder: (dialogContext) => Dialog(
                  child: SizedBox(width: 420, height: 480, child: Column(children: [
                    const Padding(padding: EdgeInsets.all(12),
                        child: Text('Scan de QR-code op de B74 Live TV')),
                    Expanded(child: QrScanner(onScanned: (qr) async {
                      if (busy || !qr.startsWith('b74-live://')) return;
                      busy = true;
                      try {
                        await B74LiveTv.instance.connect(qr);
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (e) {
                        busy = false;
                        if (dialogContext.mounted) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(content: Text('TV-koppeling mislukt: $e')));
                        }
                      }
                    })),
                  ])),
                ),
              );
            }
            if (mounted) setState(() {});
          },
        ),
        IconButton(
          tooltip: 'Wedstrijden ontvangen',
          icon: const Icon(Icons.wifi_tethering),
          onPressed: () async {
            await Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const CompetitionReceiveScreen(),
              ),
            );
            if (mounted) setState(_reload);
          },
        ),
        IconButton(
          tooltip: 'Vernieuwen',
          icon: const Icon(Icons.refresh),
          onPressed: () => setState(_reload),
        ),
        // Reserveer de rechterbovenhoek voor de permanente B74-indicator.
        // Deze staat in de Navigator-overlay (Patch D).
        const SizedBox(width: 56),
      ],
    ),
    body: FutureBuilder<List<Object>>(
      future: Future.wait<Object>([_matches, _doubles, _beers]),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text('Wedstrijden laden mislukt: ${snapshot.error}'),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final matches = snapshot.data![0] as List<CompetitionMatchSummary>;
        final doubles = snapshot.data![1] as List<CompetitionDoublesSummary>;
        final beers = snapshot.data![2] as List<CompetitionDoublesSummary>;
        if (matches.isEmpty && doubles.isEmpty && beers.isEmpty) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'Nog geen competitiewedstrijden ontvangen.\n'
                'Synchroniseer eerst vanuit Competition Dashboard.',
                textAlign: TextAlign.center,
              ),
            ),
          );
        }
        final groups = <String, _CompetitionGroup>{};
        for (final match in matches) {
          groups.putIfAbsent(match.id, () => _CompetitionGroup(match.id))
              .singles = match;
        }
        for (final item in doubles) {
          groups.putIfAbsent(item.matchId, () => _CompetitionGroup(item.matchId))
              .doubles.add(item);
        }
        for (final item in beers) {
          groups.putIfAbsent(item.matchId, () => _CompetitionGroup(item.matchId))
              .beers.add(item);
        }
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final group in groups.values)
              _CompetitionGroupCard(
                group: group,
                buildDoubles: (item) => _doublesTile(item),
                buildBeer: (item) => _beerTile(item),
              ),
          ],
        );
      },
    ),
  );
  Widget _beerTile(CompetitionDoublesSummary item) =>
FutureBuilder<B74DoublesSession?>(
                  key: ValueKey('beer-result-${item.gameId}'),
                  future: B74DoublesSession.load(item.gameId),
                  builder: (context, resultSnapshot) {
                    final engine = resultSnapshot.data?.engine;
                    final winner = engine?.winner;
                    final finished = winner != null;
                    final score = engine == null ? ''
                        : '${engine.legsWon[0]}–${engine.legsWon[1]}';
                    return FutureBuilder<Map<String, Object?>?>(
                      future: DbHelper.instance.competitionDoublesResult(item.gameId),
                      builder: (context, syncSnapshot) {
                        final synced = syncSnapshot.data?['status'] == 'archived';
                        final syncLabel = synced
                            ? 'Gesynchroniseerd' : 'Wacht op synchronisatie';
                        return Card(
                          color: finished ? Colors.green.withValues(alpha: 0.14) : null,
                          child: ListTile(
                            key: ValueKey('beer-${item.gameId}'),
                            title: Text('Biergame — ${item.homeTeam} vs ${item.awayTeam}'
                                '${finished ? '  •  $score' : ''}'),
                            subtitle: Text(
                              '${item.homePlayers.join(' + ')}  vs  ${item.awayPlayers.join(' + ')}\n'
                              '1001 · 1 leg · ${item.checkIn == 'double' ? 'Double In' : 'Straight In'} · Revisie ${item.revision}'
                              '${finished ? '\nGespeeld · Winnaar: ${winner == 0 ? item.homeTeam : item.awayTeam} · $syncLabel' : (item.started ? ' · Gestart' : ' · Ontvangen')}'
                              '${resultSnapshot.hasError || syncSnapshot.hasError ? '\nStatus laden mislukt' : ''}',
                            ),
                            isThreeLine: true,
                            trailing: Icon(finished
                                ? (synced ? Icons.cloud_done : Icons.cloud_upload_outlined)
                                : Icons.chevron_right),
                            onTap: () async {
                              await Navigator.push(context, MaterialPageRoute<void>(
                                builder: (_) => CompetitionDoublesScreen(match: item),
                              ));
                              if (context.mounted) (context as Element).markNeedsBuild();
                            },
                          ),
                        );
                      },
                    );
                  },
                );

  Widget _doublesTile(CompetitionDoublesSummary item) =>
FutureBuilder<B74DoublesSession?>(
                  key: ValueKey('doubles-result-${item.gameId}'),
                  future: B74DoublesSession.load(item.gameId),
                  builder: (context, resultSnapshot) {
                    final session = resultSnapshot.data;
                    final engine = session?.engine;
                    final winner = engine?.winner;
                    final finished = winner != null;
                    final score = engine == null
                        ? ''
                        : '${engine.legsWon[0]}–${engine.legsWon[1]}';
                    return FutureBuilder<Map<String, Object?>?>(
                      future: DbHelper.instance.competitionDoublesResult(item.gameId),
                      builder: (context, syncSnapshot) {
                        final synced = syncSnapshot.data?['status'] == 'archived';
                        final syncLabel = synced
                            ? 'Gesynchroniseerd'
                            : 'Wacht op synchronisatie';
                        return Card(
                      color: finished
                          ? Colors.green.withValues(alpha: 0.14)
                          : null,
                      child: ListTile(
                        key: ValueKey('doubles-${item.gameId}'),
                        title: Text(
                          'Koppel ${item.slot} — ${item.homeTeam} vs ${item.awayTeam}'
                          '${finished ? '  •  $score' : ''}',
                        ),
                        subtitle: Text(
                          '${item.homePlayers.join(' + ')}  vs  ${item.awayPlayers.join(' + ')}\n'
                          '701 · Best of ${item.bestOf} · ${item.checkIn == 'double' ? 'Double In' : 'Straight In'} · Revisie ${item.revision}'
                          '${finished ? '\nGespeeld · Winnaar: ${winner == 0 ? item.homeTeam : item.awayTeam} · $syncLabel' : (item.started ? ' · Gestart' : ' · Ontvangen')}'
                          '${resultSnapshot.hasError ? '\nUitslag laden mislukt' : ''}',
                        ),
                        isThreeLine: true,
                        trailing: Icon(
                          finished
                              ? (synced ? Icons.cloud_done : Icons.cloud_upload_outlined)
                              : Icons.chevron_right,
                        ),
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                              builder: (_) =>
                                  CompetitionDoublesScreen(match: item),
                            ),
                          );
                          if (context.mounted) {
                            (context as Element).markNeedsBuild();
                          }
                        },
                      ),
                    );
                      },
                    );
                  },
                );

}

class _MatchCard extends StatelessWidget {
  const _MatchCard({required this.match});
  final CompetitionMatchSummary match;

  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 16),
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '${match.home}  –  ${match.away}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 4),
          Text(
            'Wedstrijdcode: ${match.id.length > 8 ? match.id.substring(0, 8).toUpperCase() : match.id}  •  Ontvangen: '
            '${DateTime.fromMillisecondsSinceEpoch(match.receivedAt).day}-'
            '${DateTime.fromMillisecondsSinceEpoch(match.receivedAt).month}-'
            '${DateTime.fromMillisecondsSinceEpoch(match.receivedAt).year}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 6),
          Text(
            '501 / Best of ${match.rules['bestOf']}  •  '
            '${_startLabel(match.rules['startPolicy'] as String)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final single in match.singles)
            FutureBuilder<Map<String, Object?>?>(
              future: DbHelper.instance.competitionSingleResult(
                match.id,
                single.slot,
              ),
              builder: (context, snapshot) {
                final row = snapshot.data;
                Map<String, dynamic>? result;
                if (row?['payload'] is String) {
                  try {
                    result = CompetitionSingleResultContract.decode(
                      row!['payload'] as String,
                    );
                  } catch (_) {
                    /* Keep the list usable if a row is malformed. */
                  }
                }
                final finished = result != null;
                final archived = row?['status'] == 'archived';
                final winner = result?['winnerPlayerId'] == single.homeId
                    ? single.homePlayer
                    : single.awayPlayer;
                return Card(
                  clipBehavior: Clip.antiAlias,
                  color: finished ? Colors.green.withValues(alpha: 0.14) : null,
                  child: ListTile(
                    title: Text(
                      'Single ${single.slot}${finished ? '  •  ${result['homeLegs']}–${result['awayLegs']}' : ''}',
                    ),
                    subtitle: Text(
                      '${match.home}: ${single.homePlayer}${_bond(single.homeBond)}\n'
                      'VS\n${match.away}: ${single.awayPlayer}${_bond(single.awayBond)}'
                      '${finished ? '\nWinnaar: $winner  •  ${archived ? 'Gesynchroniseerd' : 'Wacht op synchronisatie'}' : ''}',
                    ),
                    isThreeLine: true,
                    trailing: Icon(
                      finished
                          ? (archived
                                ? Icons.cloud_done
                                : Icons.cloud_upload_outlined)
                          : Icons.chevron_right,
                    ),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => CompetitionSingleScreen(
                            match: match,
                            single: single,
                          ),
                        ),
                      );
                      if (context.mounted) {
                        (context as Element).markNeedsBuild();
                      }
                    },
                  ),
                );
              },
            ),
        ],
      ),
    ),
  );

  static String _bond(String? bond) =>
      bond == null || bond.trim().isEmpty ? '' : ' ($bond)';

  static String _startLabel(String policy) => switch (policy) {
    CompetitionX01Rules.bull => 'Bullstart',
    CompetitionX01Rules.fixedHome => 'Thuis begint',
    _ => 'Uit begint',
  };
}


class _CompetitionGroup {
  _CompetitionGroup(this.id);
  final String id;
  CompetitionMatchSummary? singles;
  final List<CompetitionDoublesSummary> doubles = [];
  final List<CompetitionDoublesSummary> beers = [];
}

class _CompetitionGroupCard extends StatelessWidget {
  const _CompetitionGroupCard({
    required this.group,
    required this.buildDoubles,
    required this.buildBeer,
  });
  final _CompetitionGroup group;
  final Widget Function(CompetitionDoublesSummary) buildDoubles;
  final Widget Function(CompetitionDoublesSummary) buildBeer;

  @override
  Widget build(BuildContext context) {
    final match = group.singles;
    final other = group.doubles.isNotEmpty
        ? group.doubles.first
        : (group.beers.isNotEmpty ? group.beers.first : null);
    final home = match?.home ?? other?.homeTeam ?? 'Thuisteam onbekend';
    final away = match?.away ?? other?.awayTeam ?? 'Uitteam onbekend';
    final kind = match?.matchType;
    final title = kind == 'cup' ? 'BEKER' : kind == 'regular' ? 'COMPETITIE' : 'TYPE ONBEKEND';
    final doubleIn = match?.rules['checkIn'];
    final allDoubles = [...group.doubles]..sort((a,b) => a.slot.compareTo(b.slot));
    final allBeers = [...group.beers]..sort((a,b) => a.slot.compareTo(b.slot));
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        key: ValueKey('match-group-${group.id}'),
        leading: Icon(kind == 'cup' ? Icons.emoji_events : Icons.assignment_outlined),
        title: Text('$home – $away'),
        subtitle: Text('$title · Wedstrijdcode: ${group.id}\n'
          '${match == null ? 'Singles nog niet ontvangen' : 'Singles ${match.singles.length}'}'
          ' · Koppels ${allDoubles.length} · Biergame ${allBeers.length}'
          '${doubleIn == 'double' ? ' · Double In (Singles)' : doubleIn == 'straight' ? ' · Straight In (Singles)' : ''}'),
        children: [
          if (match != null) ...[
            const ListTile(title: Text('Singles 501')),
            _MatchCard(match: match),
          ],
          if (allDoubles.isNotEmpty) ...[
            const ListTile(title: Text('Koppels 701')),
            for (final item in allDoubles) buildDoubles(item),
          ],
          if (allBeers.isNotEmpty) ...[
            const ListTile(title: Text('Biergame 1001')),
            for (final item in allBeers) buildBeer(item),
          ],
        ],
      ),
    );
  }
}
