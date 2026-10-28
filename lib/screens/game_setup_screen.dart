import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/game.dart';
import '../models/player.dart';
import '../providers/players_provider.dart';
import '../providers/game_provider.dart';
import '../widgets/bot_select_section.dart';
import '../widgets/player_dialog.dart';
import '../widgets/player_select_section.dart';
import '../widgets/starting_order_section.dart';
import '../widgets/team_section.dart';
import 'game_screen.dart';
import '../utils/layout.dart';
import '../utils/match_format.dart';
import '../utils/team_color.dart';
import '../utils/player_label.dart';

/// Setup screen for an X01 game: start score, in/out modes, legs/sets, player
/// selection, and optional per-player handicaps or team configuration.
class GameSetupScreen extends StatefulWidget {
  const GameSetupScreen({super.key});

  @override
  State<GameSetupScreen> createState() => _GameSetupScreenState();
}

class _GameSetupScreenState extends State<GameSetupScreen> {
  int _startScore = 501;
  GameMode _gameMode = GameMode.straightIn;
  CheckoutMode _checkoutMode = CheckoutMode.doubleOut;
  int _legs = 3;
  int _sets = 1;
  // Default for solo games: first to 1 leg, 1 set.
  int _soloLegs = 1;
  // Default matches the previous standard of 3 legs / 1 set (best of 5).
  MatchFormat _format = MatchFormat.bo5;
  final List<Player> _selectedPlayers = [];

  /// Whether the computer opponent card is open. Off drops every bot.
  bool _botEnabled = false;

  // ── Handicap ─────────────────────────────────────────────────────────────
  bool _handicapEnabled = false;
  final Map<Player, PlayerHandicap> _handicaps = {};

  // ── Team game ─────────────────────────────────────────────────────────────
  bool _teamGameEnabled = false;
  final Map<Player, int> _teamAssignment = {}; // player → team index
  final List<String> _teamNames = ['Team 1', 'Team 2'];
  final List<TextEditingController> _teamNameCtrl = [
    TextEditingController(text: 'Team 1'),
    TextEditingController(text: 'Team 2'),
  ];

  // ── Starting order ───────────────────────────────────────────────────────
  StartingOrder _startingOrder = StartingOrder.random;

  // ── Placement mode ───────────────────────────────────────────────────────
  bool _placementMode = false;

  /// Whether placement mode can be offered: at least 3 players, or at least
  /// 3 teams in team mode.
  bool get _placementEligible =>
      _teamGameEnabled ? _teamNames.length >= 3 : _selectedPlayers.length >= 3;

  /// Whether placement mode is enabled and currently selectable.
  bool get _placementActive => _placementMode && _placementEligible;

  /// Applies a match format preset: a non-custom preset fills [_legs]/[_sets],
  /// while [MatchFormat.custom] keeps the current values for manual editing.
  void _selectFormat(MatchFormat f) {
    setState(() {
      _format = f;
      if (f != MatchFormat.custom) {
        _legs = f.legs!;
        _sets = f.sets!;
      }
    });
  }

  /// Short, plain rule description for the selected match format preset.
  String _formatRule(AppLocalizations l, MatchFormat f) => switch (f) {
    MatchFormat.bo3 => l.formatBo3Rule,
    MatchFormat.bo5 => l.formatBo5Rule,
    MatchFormat.bo7 => l.formatBo7Rule,
    MatchFormat.bo9 => l.formatBo9Rule,
    MatchFormat.pdcSets => l.formatPdcSetsRule,
    MatchFormat.premierLeague => l.formatPremierRule,
    MatchFormat.custom => l.formatCustomRule,
  };

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

  static const _scoreOptions = [101, 170, 201, 301, 501, 701, 1001];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final allPlayers = context.watch<PlayersProvider>().players;

    final l = context.l10n;
    final size = MediaQuery.sizeOf(context);
    // Two columns need a tablet and a window wide enough to divide; a small
    // one upright is neither.
    final twoColumns =
        isTabletLayout(context) && fitsTwoPanes(size.width, kMinSetupPaneWidth);

    return Scaffold(
      appBar: AppBar(title: Text(l.gameSetup)),
      body: twoColumns
          ? _twoColumnBody(context, theme, l, allPlayers)
          : ListView(
              padding: contentPadding(context, top: 16, bottom: 16, innerH: 16),
              children: [
                ..._modeSections(theme, l),
                const SizedBox(height: 16),
                _playersCard(context, allPlayers),
                _botCard(context),
                ..._matchFormatBlock(theme, l),
                ..._playerExtras(),
                const SizedBox(height: 24),
                if (!_selectedPlayers.any((p) => !p.isBot))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      l.minOnePlayer,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                _startButton(theme, l),
              ],
            ),
    );
  }

  /// The setup as two columns: what the game is on one side, who plays it on
  /// the other, with the start button on a bar under both.
  ///
  /// Each column scrolls on its own, which is why the button cannot sit at the
  /// end of one of them: it would be somewhere the other column has long
  /// scrolled past.
  ///
  /// The divider stands in the middle and stays there. The screens that let it
  /// be dragged put two different things beside each other, a list against what
  /// it opens; these two are the same kind of thing and want the same width.
  Widget _twoColumnBody(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l,
    List<Player> allPlayers,
  ) {
    return Column(
      children: [
        Expanded(
          child: SidePaneLayout(
            side: InputSide.left,
            minPaneWidth: kMinSetupPaneWidth,
            primary: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
              children: [
                ..._modeSections(theme, l),
                ..._matchFormatBlock(theme, l),
              ],
            ),
            secondary: ListView(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 16),
              children: [
                _playersCard(context, allPlayers),
                _botCard(context),
                ..._playerExtras(),
              ],
            ),
          ),
        ),
        _startBar(theme, l),
      ],
    );
  }

  /// The bar under both columns, carrying the start button and, while nobody
  /// is picked, the reason it does nothing.
  Widget _startBar(ThemeData theme, AppLocalizations l) {
    return Material(
      color: theme.colorScheme.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: !_selectedPlayers.any((p) => !p.isBot)
                    ? Text(
                        l.minOnePlayer,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: 16),
              _startButton(theme, l),
            ],
          ),
        ),
      ),
    );
  }

  /// The button that starts the game, disabled until somebody plays it. A bot
  /// alone is nobody: it needs a person to play against.
  Widget _startButton(ThemeData theme, AppLocalizations l) {
    return FilledButton.icon(
      onPressed: _selectedPlayers.any((p) => !p.isBot) ? _startGame : null,
      icon: const Icon(Icons.play_arrow),
      label: Text(_selectedPlayers.length == 1 ? l.startOpenPlay : l.startGame),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
        textStyle: theme.textTheme.titleMedium,
      ),
    );
  }

  /// The cards describing the game itself: what is thrown down from, and how a
  /// leg is entered and left.
  List<Widget> _modeSections(ThemeData theme, AppLocalizations l) {
    return [
      _Section(
        title: l.startScore,
        child: Wrap(
          spacing: 8,
          children: _scoreOptions.map((s) {
            return ChoiceChip(
              label: Text('$s'),
              selected: _startScore == s,
              onSelected: (_) => setState(() => _startScore = s),
            );
          }).toList(),
        ),
      ),
      const SizedBox(height: 16),
      _Section(
        title: l.checkIn,
        child: Wrap(
          spacing: 8,
          children:
              [
                    (GameMode.straightIn, l.straight),
                    (GameMode.doubleIn, l.double_),
                    (GameMode.masterIn, l.master),
                  ]
                  .map(
                    (e) => ChoiceChip(
                      label: Text(e.$2),
                      selected: _gameMode == e.$1,
                      onSelected: (_) => setState(() => _gameMode = e.$1),
                    ),
                  )
                  .toList(),
        ),
      ),
      const SizedBox(height: 16),
      _Section(
        title: l.checkOut,
        child: Wrap(
          spacing: 8,
          children:
              [
                    (CheckoutMode.straightOut, l.straight),
                    (CheckoutMode.doubleOut, l.double_),
                    (CheckoutMode.masterOut, l.master),
                  ]
                  .map(
                    (e) => ChoiceChip(
                      label: Text(e.$2),
                      selected: _checkoutMode == e.$1,
                      onSelected: (_) => setState(() => _checkoutMode = e.$1),
                    ),
                  )
                  .toList(),
        ),
      ),
    ];
  }

  /// The match format and the legs and sets that go with it, or in a solo game
  /// the note that there is no match to win and the legs alone.
  ///
  /// Nothing at all while nobody is picked: a format is a statement about
  /// players, and there are none yet.
  List<Widget> _matchFormatBlock(ThemeData theme, AppLocalizations l) {
    if (_selectedPlayers.isEmpty) return const [];

    // ── Solo: only the number of legs is open ─────────────────────────────
    if (_selectedPlayers.length == 1) {
      return [
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: theme.colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 18,
                color: theme.colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l.openPlayHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: l.matchFormat,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                children: [
                  ChoiceChip(
                    label: Text(l.formatCustom),
                    selected: true,
                    onSelected: (_) {},
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                l.formatCustomRule,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Stepper(
                      label: l.legs,
                      value: _soloLegs,
                      min: 1,
                      max: kMaxLegs,
                      onChanged: (v) => setState(() => _soloLegs = v),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _Stepper(
                      label: l.sets,
                      value: 1,
                      min: 1,
                      max: 1,
                      enabled: false,
                      onChanged: (_) {},
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l.firstToHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ];
    }

    return [
      const SizedBox(height: 16),
      _Section(
        title: l.matchFormat,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Mode toggle: standard match formats vs. placement mode.
            SegmentedButton<bool>(
              segments: [
                ButtonSegment(value: false, label: Text(l.standardMode)),
                ButtonSegment(
                  value: true,
                  label: Text(l.placementMode),
                  enabled: _placementEligible,
                ),
              ],
              selected: {_placementActive},
              onSelectionChanged: (s) => setState(() {
                _placementMode = s.first;
                if (_placementMode) {
                  _legs = 3;
                } else {
                  _format = MatchFormat.bo5;
                  _legs = MatchFormat.bo5.legs!;
                  _sets = MatchFormat.bo5.sets!;
                }
              }),
            ),
            const SizedBox(height: 8),
            Text(
              _placementActive
                  ? l.placementModeHint
                  : l.placementEligibilityHint,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (!_placementActive) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: MatchFormat.values
                    .map(
                      (f) => ChoiceChip(
                        label: Text(l.matchFormatLabel(f)),
                        selected: _format == f,
                        onSelected: (_) => _selectFormat(f),
                      ),
                    )
                    .toList(),
              ),
              const SizedBox(height: 8),
              Text(
                _formatRule(l, _format),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              // Legs/sets stay visible for every format; only editable for the
              // custom preset so the first-to hint always makes sense.
              Row(
                children: [
                  Expanded(
                    child: _Stepper(
                      label: l.legs,
                      value: _legs,
                      min: 1,
                      max: kMaxLegs,
                      enabled: _format == MatchFormat.custom,
                      onChanged: (v) => setState(() => _legs = v),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _Stepper(
                      label: l.sets,
                      value: _sets,
                      min: 1,
                      max: kMaxSets,
                      enabled: _format == MatchFormat.custom,
                      onChanged: (v) => setState(() => _sets = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                l.firstToHint,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ] else
              // Placement mode: only the number of legs is configurable, sets
              // are fixed to 1.
              _Stepper(
                label: l.legs,
                value: _legs,
                min: 1,
                max: kMaxLegs,
                enabled: true,
                onChanged: (v) => setState(() => _legs = v),
              ),
          ],
        ),
      ),
    ];
  }

  /// Who is playing: the card the rest of the screen follows from.
  Widget _playersCard(BuildContext context, List<Player> allPlayers) {
    return PlayerSelectSection(
      allPlayers: allPlayers,
      selectedPlayers: _selectedPlayers,
      onToggle: (p, selected) {
        setState(() {
          if (selected) {
            _selectedPlayers.add(p);
          } else {
            _selectedPlayers.removeWhere((s) => s.id == p.id);
          }
        });
      },
      onAddPlayer: () => _showAddPlayerDialog(context),
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
        if (!v) _selectedPlayers.removeWhere((p) => p.isBot);
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
      onRemove: (bot) =>
          setState(() => _selectedPlayers.removeWhere((p) => p.id == bot.id)),
    );
  }

  /// What the picked players can still be arranged into: rules of their own,
  /// teams, and the order they throw in. Empty in a solo game, where there is
  /// nobody to arrange them against.
  List<Widget> _playerExtras() {
    return [
      if (_selectedPlayers.length >= 2) ...[
        // ── Handicap ────────────────────────────────────────────────────────
        const SizedBox(height: 16),
        _HandicapSection(
          enabled: _handicapEnabled,
          players: _selectedPlayers,
          handicaps: _handicaps,
          gameCheckIn: _gameMode,
          gameCheckOut: _checkoutMode,
          teamAssignment: _teamGameEnabled ? _teamAssignment : null,
          teamNames: _teamGameEnabled ? _teamNames : null,
          onToggle: (v) => setState(() {
            _handicapEnabled = v;
            if (v) {
              for (final p in _selectedPlayers) {
                _handicaps.putIfAbsent(
                  p,
                  () => PlayerHandicap(
                    checkIn: _gameMode,
                    checkOut: _checkoutMode,
                  ),
                );
              }
            }
          }),
          onChanged: (p, h) => setState(() => _handicaps[p] = h),
        ),
        // ── Team game ───────────────────────────────────────────────────────
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
                _teamAssignment[_selectedPlayers[i]] = i % _teamNames.length;
              }
            }
          }),
          onAssignmentChanged: (p, t) => setState(() => _teamAssignment[p] = t),
          onNameChanged: (i, name) => setState(() => _teamNames[i] = name),
          onAddTeam: _addTeam,
          onRemoveTeam: _removeTeam,
        ),
        // ── Starting order ──────────────────────────────────────────────────
        const SizedBox(height: 16),
        StartingOrderSection(
          order: _startingOrder,
          entries: _startingOrderEntries(),
          teamMode: _teamGameEnabled,
          onOrderChanged: (o) => setState(() => _startingOrder = o),
          onReorder: _reorderStartingOrder,
        ),
      ],
    ];
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

  /// Builds the game from the chosen settings (including team and handicap
  /// config), applies the chosen throwing order, starts it, and opens the play
  /// screen.
  Future<void> _startGame() async {
    final isSolo = _selectedPlayers.length == 1;
    final game = Game(
      startScore: _startScore,
      gameMode: _gameMode,
      checkoutMode: _checkoutMode,
      legs: isSolo ? _soloLegs : _legs,
      sets: isSolo ? 1 : (_placementActive ? 1 : _sets),
      createdAt: DateTime.now(),
      placementMode: !isSolo && _placementActive,
      startingOrder: _startingOrder,
    );
    final players = _startingOrder == StartingOrder.random
        ? (List.of(_selectedPlayers)..shuffle(Random()))
        : List.of(_selectedPlayers);

    // Build team config if team game is enabled
    List<TeamConfig>? teamConfigs;
    if (_teamGameEnabled && _selectedPlayers.length >= 2) {
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

    // Build handicap map (playerId → PlayerHandicap) if enabled. Handicaps are
    // per player and stay valid in a team game, where each member throws under
    // their own check-in/check-out rules.
    final Map<int, PlayerHandicap>? handicapMap = _handicapEnabled
        ? {
            for (final p in players)
              if (p.id != null && _handicaps.containsKey(p))
                p.id!: _handicaps[p]!,
          }
        : null;

    final gameWithTeams = Game(
      startScore: game.startScore,
      gameMode: game.gameMode,
      checkoutMode: game.checkoutMode,
      legs: game.legs,
      sets: game.sets,
      createdAt: game.createdAt,
      teams: teamConfigs,
      handicaps: handicapMap,
      placementMode: game.placementMode,
      startingOrder: game.startingOrder,
    );

    final provider = context.read<GameProvider>();
    await provider.startGame(gameWithTeams, players);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const GameScreen()),
      );
    }
  }
}

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

/// A labeled +/- stepper for an integer value clamped to [min]..[max].
///
/// When [enabled] is false the value stays visible but the buttons are
/// disabled, used to display a preset's legs/sets without allowing edits.
class _Stepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final bool enabled;
  final void Function(int) onChanged;

  const _Stepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final valueColor = enabled
        ? theme.textTheme.headlineSmall?.color
        : theme.disabledColor;
    return Column(
      children: [
        Text(label, style: theme.textTheme.labelMedium),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.remove),
              onPressed: enabled && value > min
                  ? () => onChanged(value - 1)
                  : null,
            ),
            Text(
              '$value',
              style: theme.textTheme.headlineSmall?.copyWith(color: valueColor),
            ),
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: enabled && value < max
                  ? () => onChanged(value + 1)
                  : null,
            ),
          ],
        ),
      ],
    );
  }
}

// ── Handicap section ──────────────────────────────────────────────────────────

/// Optional section to set per-player check-in/check-out handicaps that override
/// the game-wide modes.
///
/// Handicaps stay per player in a team game, so when [teamAssignment] and
/// [teamNames] are given the players are listed under their team to make the
/// assignment visible while their rules are set.
class _HandicapSection extends StatelessWidget {
  final bool enabled;
  final List<Player> players;
  final Map<Player, PlayerHandicap> handicaps;
  final GameMode gameCheckIn;
  final CheckoutMode gameCheckOut;

  /// Team index per player, or null when the game is played individually.
  final Map<Player, int>? teamAssignment;

  /// Team names, or null when the game is played individually.
  final List<String>? teamNames;
  final ValueChanged<bool> onToggle;
  final void Function(Player, PlayerHandicap) onChanged;

  const _HandicapSection({
    required this.enabled,
    required this.players,
    required this.handicaps,
    required this.gameCheckIn,
    required this.gameCheckOut,
    this.teamAssignment,
    this.teamNames,
    required this.onToggle,
    required this.onChanged,
  });

  /// Whether the players are listed grouped under their teams.
  bool get _grouped => teamAssignment != null && teamNames != null;

  /// One block per team: a colored header with the team name, then that team's
  /// players. Teams nobody is assigned to are skipped.
  List<Widget> _teamGroups(BuildContext context, ThemeData theme) {
    final names = teamNames!;
    final assignment = teamAssignment!;
    final blocks = <Widget>[];

    for (var ti = 0; ti < names.length; ti++) {
      // Unassigned players fall back to team 0, mirroring _startGame.
      final members = players
          .where((p) => (assignment[p] ?? 0).clamp(0, names.length - 1) == ti)
          .toList();
      if (members.isEmpty) continue;

      blocks.add(
        Padding(
          padding: EdgeInsets.only(bottom: 8, top: blocks.isEmpty ? 0 : 4),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: teamColor(ti),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                names[ti],
                style: theme.textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: teamColor(ti),
                ),
              ),
            ],
          ),
        ),
      );
      blocks.addAll(
        members.map(
          (p) => Padding(
            padding: const EdgeInsets.only(left: 18),
            child: _playerRow(context, theme, p),
          ),
        ),
      );
    }
    return blocks;
  }

  /// The avatar/name header plus the two mode dropdowns for one player.
  Widget _playerRow(BuildContext context, ThemeData theme, Player p) {
    final cs = theme.colorScheme;
    final h =
        handicaps[p] ??
        PlayerHandicap(checkIn: gameCheckIn, checkOut: gameCheckOut);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 12,
                backgroundColor: cs.primaryContainer,
                child: Text(
                  p.label(context.l10n).isNotEmpty
                      ? p.label(context.l10n)[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: cs.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                p.label(context.l10n),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: _ModeDropdown<GameMode>(
                  label: context.l10n.checkIn,
                  value: h.checkIn,
                  items: [
                    (GameMode.straightIn, context.l10n.straight),
                    (GameMode.doubleIn, context.l10n.double_),
                    (GameMode.masterIn, context.l10n.master),
                  ],
                  onChanged: (v) => onChanged(p, h.copyWith(checkIn: v)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ModeDropdown<CheckoutMode>(
                  label: context.l10n.checkOut,
                  value: h.checkOut,
                  items: [
                    (CheckoutMode.straightOut, context.l10n.straight),
                    (CheckoutMode.doubleOut, context.l10n.double_),
                    (CheckoutMode.masterOut, context.l10n.master),
                  ],
                  onChanged: (v) => onChanged(p, h.copyWith(checkOut: v)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Toggle row
            Row(
              children: [
                Icon(Icons.tune_rounded, size: 20, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.handicap,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Switch(value: enabled, onChanged: onToggle),
              ],
            ),
            if (enabled) ...[
              Text(
                context.l10n.handicapDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (_grouped)
                ..._teamGroups(context, theme)
              else
                ...players.map((p) => _playerRow(context, theme, p)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A labeled dropdown over [(value, label)] pairs, used for the in/out modes.
class _ModeDropdown<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<(T, String)> items;
  final ValueChanged<T> onChanged;

  const _ModeDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<T>(
          initialValue: value,
          isDense: true,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          items: items
              .map((e) => DropdownMenuItem<T>(value: e.$1, child: Text(e.$2)))
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ],
    );
  }
}
