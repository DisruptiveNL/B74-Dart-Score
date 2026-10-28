import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/around_the_clock_game.dart';
import '../models/player.dart';
import '../providers/players_provider.dart';
import '../providers/around_the_clock_provider.dart';
import '../widgets/bot_select_section.dart';
import '../widgets/player_dialog.dart';
import '../widgets/player_select_section.dart';
import '../widgets/starting_order_section.dart';
import '../widgets/team_section.dart';
import '../utils/layout.dart';
import '../utils/team_color.dart';
import '../utils/player_label.dart';
import 'around_the_clock_screen.dart';

/// Setup screen for Around the Clock: pick the rule variant and the players,
/// then start the game.
class AroundTheClockSetupScreen extends StatefulWidget {
  const AroundTheClockSetupScreen({super.key});

  @override
  State<AroundTheClockSetupScreen> createState() =>
      _AroundTheClockSetupScreenState();
}

class _AroundTheClockSetupScreenState extends State<AroundTheClockSetupScreen> {
  AroundTheClockVariant _variant = AroundTheClockVariant.basic;
  final List<Player> _selectedPlayers = [];

  // ── Team game ─────────────────────────────────────────────────────────────
  bool _teamGameEnabled = false;

  /// Whether the computer opponent card is open. Off drops every bot.
  bool _botEnabled = false;
  final Map<Player, int> _teamAssignment = {}; // player → team index
  final List<String> _teamNames = ['Team 1', 'Team 2'];
  final List<TextEditingController> _teamNameCtrl = [
    TextEditingController(text: 'Team 1'),
    TextEditingController(text: 'Team 2'),
  ];

  // ── Starting order ────────────────────────────────────────────────────────
  StartingOrder _startingOrder = StartingOrder.random;

  /// Adds a new, default-named team.
  void _addTeam() {
    setState(() {
      final idx = _teamNames.length + 1;
      _teamNames.add('Team $idx');
      _teamNameCtrl.add(TextEditingController(text: 'Team $idx'));
    });
  }

  /// Removes team [ti] (minimum two teams kept) and reassigns its players,
  /// shifting higher team indices down.
  void _removeTeam(int ti) {
    if (_teamNames.length <= 2) return;
    setState(() {
      _teamNames.removeAt(ti);
      _teamNameCtrl.removeAt(ti);
      // Reassign players that were in removed team or have out-of-range index
      for (final p in _selectedPlayers) {
        final current = _teamAssignment[p] ?? 0;
        if (current == ti) {
          _teamAssignment[p] = 0;
        } else if (current > ti) {
          _teamAssignment[p] = current - 1;
        }
      }
    });
  }

  /// The draggable entries of the starting-order section: the teams in a team
  /// game, otherwise the selected players.
  List<StartingOrderEntry> _startingOrderEntries() => _teamGameEnabled
      ? List.generate(
          _teamNames.length,
          (ti) => StartingOrderEntry(
            // The controller instance identifies the team across reorders; the
            // index does not, because it is exactly what the drag changes.
            key: ObjectKey(_teamNameCtrl[ti]),
            label: _teamNames[ti],
            color: teamColor(ti),
          ),
        )
      : _selectedPlayers
            .map(
              (p) => StartingOrderEntry(
                key: ValueKey(p.id),
                label: p.label(context.l10n),
              ),
            )
            .toList();

  /// Moves the entry at [oldIndex] to [newIndex] in the throwing order: the
  /// teams in a team game, otherwise the selected players.
  void _reorderStartingOrder(int oldIndex, int newIndex) {
    setState(() {
      if (_teamGameEnabled) {
        _teamNames.insert(newIndex, _teamNames.removeAt(oldIndex));
        _teamNameCtrl.insert(newIndex, _teamNameCtrl.removeAt(oldIndex));
        // Every team between the old and the new slot shifts by one, so the
        // stored player → team indices have to follow the move.
        for (final p in _selectedPlayers) {
          final ti = _teamAssignment[p] ?? 0;
          if (ti == oldIndex) {
            _teamAssignment[p] = newIndex;
          } else if (oldIndex < newIndex && ti > oldIndex && ti <= newIndex) {
            _teamAssignment[p] = ti - 1;
          } else if (oldIndex > newIndex && ti >= newIndex && ti < oldIndex) {
            _teamAssignment[p] = ti + 1;
          }
        }
      } else {
        _selectedPlayers.insert(newIndex, _selectedPlayers.removeAt(oldIndex));
      }
    });
  }

  /// Localized description of the currently selected rule variant.
  String _variantDesc(AppLocalizations l) {
    switch (_variant) {
      case AroundTheClockVariant.basic:
        return l.aroundClockBasicDesc;
      case AroundTheClockVariant.fullSegments:
        return l.aroundClockFullSegmentsDesc;
      case AroundTheClockVariant.skipRules:
        return l.aroundClockSkipRulesDesc;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final allPlayers = context.watch<PlayersProvider>().players;

    return Scaffold(
      appBar: AppBar(title: Text(l.aroundClockSetup)),
      body: ListView(
        padding: contentPadding(context, top: 16, bottom: 16, innerH: 16),
        children: [
          // ── Variant ──────────────────────────────────────────────────────
          _Section(
            title: l.aroundClockVariant,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(l.aroundClockBasic),
                      selected: _variant == AroundTheClockVariant.basic,
                      onSelected: (_) => setState(
                        () => _variant = AroundTheClockVariant.basic,
                      ),
                    ),
                    ChoiceChip(
                      label: Text(l.aroundClockFullSegments),
                      selected: _variant == AroundTheClockVariant.fullSegments,
                      onSelected: (_) => setState(
                        () => _variant = AroundTheClockVariant.fullSegments,
                      ),
                    ),
                    ChoiceChip(
                      label: Text(l.aroundClockSkipRules),
                      selected: _variant == AroundTheClockVariant.skipRules,
                      onSelected: (_) => setState(
                        () => _variant = AroundTheClockVariant.skipRules,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _variantDesc(l),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Players ───────────────────────────────────────────────────────
          PlayerSelectSection(
            allPlayers: allPlayers,
            selectedPlayers: _selectedPlayers,
            onToggle: (p, selected) {
              setState(() {
                if (selected) {
                  _selectedPlayers.add(p);
                } else {
                  _selectedPlayers.removeWhere((s) => s.id == p.id);
                }
                if (_selectedPlayers.length < 2) {
                  _teamGameEnabled = false;
                }
              });
            },
            onAddPlayer: () => _showAddPlayerDialog(context),
          ),
          const SizedBox(height: 16),
          _botCard(context),

          // ── Team game ────────────────────────────────────────────────────
          if (_selectedPlayers.length >= 2) ...[
            const SizedBox(height: 16),
            TeamSection(
              enabled: _teamGameEnabled,
              players: _selectedPlayers,
              teamAssignment: _teamAssignment,
              teamNames: _teamNames,
              teamNameCtrl: _teamNameCtrl,
              onToggle: (v) => setState(() {
                _teamGameEnabled = v;
                if (v) {
                  for (var i = 0; i < _selectedPlayers.length; i++) {
                    _teamAssignment[_selectedPlayers[i]] =
                        i % _teamNames.length;
                  }
                }
              }),
              onAssignmentChanged: (p, t) =>
                  setState(() => _teamAssignment[p] = t),
              onNameChanged: (i, name) => setState(() => _teamNames[i] = name),
              onAddTeam: _addTeam,
              onRemoveTeam: _removeTeam,
            ),
          ],

          // ── Starting order ───────────────────────────────────────────────
          if (_selectedPlayers.length >= 2) ...[
            const SizedBox(height: 16),
            StartingOrderSection(
              order: _startingOrder,
              entries: _startingOrderEntries(),
              teamMode: _teamGameEnabled,
              onOrderChanged: (o) => setState(() => _startingOrder = o),
              onReorder: _reorderStartingOrder,
            ),
          ],

          const SizedBox(height: 24),
          if (!_canStart)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l.aroundClockMinPlayers,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ),
          FilledButton.icon(
            onPressed: _canStart ? _startGame : null,
            icon: const Icon(Icons.play_arrow),
            label: Text(l.startGame),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 18),
              textStyle: theme.textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }

  /// Opens the create-player dialog and adds the new player to the selection.
  void _showAddPlayerDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => PlayerDialog(
        onSave: (name, doubles) async {
          final provider = context.read<PlayersProvider>();
          final player = await provider.addPlayer(name);
          final updated = player.copyWith(favoriteDoubles: doubles);
          await provider.updatePlayer(updated);
          setState(() => _selectedPlayers.add(updated));
        },
      ),
    );
  }

  /// The computer opponents, picked by tier. A bot joins the selection the
  /// way a person does, so everything below the card treats it as a player.
  /// A second plus on a tier adds its next free number, so two bots of one
  /// strength can play, and a removed one frees its number again.
  Widget _botCard(BuildContext context) {
    return BotSelectSection(
      enabled: _botEnabled,
      selectedPlayers: _selectedPlayers,
      onEnabledChanged: (v) => setState(() {
        _botEnabled = v;
        if (!v) {
          _selectedPlayers.removeWhere((p) => p.isBot);
          if (_selectedPlayers.length < 2) _teamGameEnabled = false;
        }
      }),
      onAdd: (level) async {
        final taken = {
          for (final p in _selectedPlayers)
            if (p.botLevel == level) p.botOrdinal!,
        };
        var ordinal = 1;
        while (taken.contains(ordinal)) {
          ordinal++;
        }
        final bot = await context.read<PlayersProvider>().botFor(
          level,
          ordinal: ordinal,
        );
        if (!mounted) return;
        setState(() => _selectedPlayers.add(bot));
      },
      onRemove: (bot) => setState(() {
        _selectedPlayers.removeWhere((p) => p.id == bot.id);
        if (_selectedPlayers.length < 2) _teamGameEnabled = false;
      }),
    );
  }

  /// Whether a game can start: somebody in it, and at least one person.
  /// Around the Clock is happy to be played alone, but not by a bot alone.
  bool get _canStart => _selectedPlayers.any((p) => !p.isBot);

  /// Builds the game with the chosen throwing order and navigates to the play
  /// screen.
  Future<void> _startGame() async {
    final players = _startingOrder == StartingOrder.random
        ? (List.of(_selectedPlayers)..shuffle(Random()))
        : List.of(_selectedPlayers);

    // Build team config if team game is enabled
    List<TeamConfig>? teamConfigs;
    if (_teamGameEnabled) {
      teamConfigs = List.generate(_teamNames.length, (ti) {
        final teamPlayers = players
            .where((p) => (_teamAssignment[p] ?? 0) == ti)
            .toList();
        return TeamConfig(
          name: _teamNames[ti],
          playerIds: teamPlayers.map((p) => p.id!).toList(),
        );
      }).where((t) => t.playerIds.isNotEmpty).toList();
      // Slots follow the team list, so a random order has to draw the teams
      // as well. Shuffling the players alone would leave team 1 always first.
      if (_startingOrder == StartingOrder.random) teamConfigs.shuffle(Random());
    }

    final game = AroundTheClockGame(
      variant: _variant,
      legs: 1,
      sets: 1,
      createdAt: DateTime.now(),
      playerIds: players.map((p) => p.id!).toList(),
      teams: teamConfigs,
      startingOrder: _startingOrder,
    );

    await context.read<AroundTheClockProvider>().startGame(game, players);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const AroundTheClockScreen()),
      );
    }
  }
}

// ── Shared helper widgets (mirrors shanghai_setup_screen.dart) ────────────────

/// A titled card grouping a block of setup options.
class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}
