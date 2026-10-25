import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/checkout_ladder_game.dart';
import '../models/player.dart';
import '../providers/checkout_ladder_provider.dart';
import '../providers/players_provider.dart';
import '../widgets/bot_select_section.dart';
import '../widgets/player_dialog.dart';
import '../widgets/player_select_section.dart';
import '../widgets/starting_order_section.dart';
import '../widgets/team_section.dart';
import '../utils/layout.dart';
import '../utils/team_color.dart';
import '../utils/player_label.dart';
import 'checkout_ladder_screen.dart';

/// Setup screen for the Checkout Ladder: training or race, the numbers it is
/// played on, the darts an attempt holds, the check-out rule and the players,
/// then start the game.
class CheckoutLadderSetupScreen extends StatefulWidget {
  const CheckoutLadderSetupScreen({super.key});

  @override
  State<CheckoutLadderSetupScreen> createState() =>
      _CheckoutLadderSetupScreenState();
}

class _CheckoutLadderSetupScreenState extends State<CheckoutLadderSetupScreen> {
  /// The darts an attempt may hold: two, three or four visits.
  static const _dartChoices = [6, 9, 12];

  /// Space between two number rows, so the buttons of one never touch the
  /// buttons of the next.
  static const double _stepperGap = 14;

  CheckoutLadderVariant _variant = CheckoutLadderVariant.training;
  int _start  = 81;
  int _target = 100;
  int _darts  = 6;
  bool _stepEnabled = false;
  int _stepFrom  = 110;
  int _stepDarts = 9;
  CheckoutMode _checkOut = CheckoutMode.doubleOut;
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

  @override
  void dispose() {
    for (final c in _teamNameCtrl) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isRace => _variant == CheckoutLadderVariant.race;

  /// Moves the start number to [value] and keeps the target and the step
  /// above it, so no setting can name a number the ladder never reaches.
  void _setStart(int value) {
    setState(() {
      _start = value.clamp(2, kCheckoutLadderTop - 1);
      if (_target <= _start) _target = _start + 1;
      if (_stepFrom <= _start) _stepFrom = _start + 1;
    });
  }

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
      ? List.generate(_teamNames.length, (ti) => StartingOrderEntry(
            // The controller instance identifies the team across reorders; the
            // index does not, because it is exactly what the drag changes.
            key:   ObjectKey(_teamNameCtrl[ti]),
            label: _teamNames[ti],
            color: teamColor(ti),
          ))
      : _selectedPlayers
          .map((p) => StartingOrderEntry(key: ValueKey(p.id), label: p.label(context.l10n)))
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

  /// How many ladders the game would hold: one per team that has a member,
  /// otherwise one per selected player.
  int get _slotCount {
    if (!_teamGameEnabled) return _selectedPlayers.length;
    final used = <int>{
      for (final p in _selectedPlayers) _teamAssignment[p] ?? 0,
    };
    return used.length;
  }

  /// Whether a game can start: at least one person, and two ladders for a race.
  bool get _canStart =>
      _selectedPlayers.any((p) => !p.isBot) && (!_isRace || _slotCount >= 2);

  @override
  Widget build(BuildContext context) {
    final l          = context.l10n;
    final theme      = Theme.of(context);
    final allPlayers = context.watch<PlayersProvider>().players;
    final hintStyle  = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l.ladderSetup)),
      body: ListView(
        padding: contentPadding(context, top: 16, bottom: 16, innerH: 16),
        children: [
          // ── Variant ──────────────────────────────────────────────────────
          _Section(
            title: l.ladderVariant,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final (v, label) in [
                      (CheckoutLadderVariant.training, l.ladderTraining),
                      (CheckoutLadderVariant.race,     l.ladderRace),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: _variant == v,
                        onSelected: (_) => setState(() => _variant = v),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(_isRace ? l.ladderRaceDesc : l.ladderTrainingDesc,
                    style: hintStyle),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Numbers ──────────────────────────────────────────────────────
          _Section(
            title: l.ladderNumbers,
            child: Column(
              children: [
                _NumberStepper(
                  label: l.ladderStartNumber,
                  value: _start,
                  min: 2,
                  max: kCheckoutLadderTop - 1,
                  onChanged: _setStart,
                ),
                if (_isRace) ...[
                  const SizedBox(height: _stepperGap),
                  _NumberStepper(
                    label: l.ladderTargetNumber,
                    value: _target,
                    min: _start + 1,
                    max: kCheckoutLadderTop,
                    onChanged: (v) => setState(() => _target = v),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Darts per attempt ────────────────────────────────────────────
          _Section(
            title: l.ladderDartsPerAttempt,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _DartsChoice(
                  value: _darts,
                  choices: _dartChoices,
                  onChanged: (v) => setState(() => _darts = v),
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l.ladderStep),
                  value: _stepEnabled,
                  onChanged: (v) => setState(() => _stepEnabled = v),
                ),
                if (_stepEnabled) ...[
                  const SizedBox(height: _stepperGap / 2),
                  _NumberStepper(
                    label: l.ladderStepFrom,
                    value: _stepFrom,
                    min: _start + 1,
                    max: kCheckoutLadderTop,
                    onChanged: (v) => setState(() => _stepFrom = v),
                  ),
                  const SizedBox(height: _stepperGap),
                  _DartsChoice(
                    value: _stepDarts,
                    choices: _dartChoices,
                    onChanged: (v) => setState(() => _stepDarts = v),
                  ),
                  const SizedBox(height: 8),
                  Text(l.ladderStepDesc(_stepFrom, _stepDarts), style: hintStyle),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Check-out ────────────────────────────────────────────────────
          _Section(
            title: l.checkOut,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (m, label) in [
                  (CheckoutMode.straightOut, l.straight),
                  (CheckoutMode.doubleOut,   l.double_),
                  (CheckoutMode.masterOut,   l.master),
                ])
                  ChoiceChip(
                    label: Text(label),
                    selected: _checkOut == m,
                    onSelected: (_) => setState(() => _checkOut = m),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // ── Players ──────────────────────────────────────────────────────
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
                if (_selectedPlayers.length < 2) _teamGameEnabled = false;
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
                    _teamAssignment[_selectedPlayers[i]] = i % _teamNames.length;
                  }
                }
              }),
              onAssignmentChanged: (p, t) =>
                  setState(() => _teamAssignment[p] = t),
              onNameChanged: (i, name) =>
                  setState(() => _teamNames[i] = name),
              onAddTeam: _addTeam,
              onRemoveTeam: _removeTeam,
            ),
          ],

          // ── Starting order ───────────────────────────────────────────────
          if (_selectedPlayers.length >= 2) ...[
            const SizedBox(height: 16),
            StartingOrderSection(
              order:    _startingOrder,
              entries:  _startingOrderEntries(),
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
                _isRace && _selectedPlayers.any((p) => !p.isBot)
                    ? l.ladderRaceMinSlots
                    : l.ladderMinPlayers,
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
  /// way a person does, so everything below the card treats it as a player,
  /// a partner in a team as much as an opponent in a race.
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
        final bot = await context
            .read<PlayersProvider>()
            .botFor(level, ordinal: ordinal);
        if (!mounted) return;
        setState(() => _selectedPlayers.add(bot));
      },
      onRemove: (bot) => setState(() {
        _selectedPlayers.removeWhere((p) => p.id == bot.id);
        if (_selectedPlayers.length < 2) _teamGameEnabled = false;
      }),
    );
  }

  /// Builds the game with the chosen throwing order and navigates to the play
  /// screen.
  Future<void> _startGame() async {
    final players = _startingOrder == StartingOrder.random
        ? (List.of(_selectedPlayers)..shuffle(Random()))
        : List.of(_selectedPlayers);

    List<TeamConfig>? teamConfigs;
    if (_teamGameEnabled) {
      teamConfigs = List.generate(_teamNames.length, (ti) {
        final teamPlayers = players
            .where((p) => (_teamAssignment[p] ?? 0) == ti)
            .toList();
        return TeamConfig(
          name:      _teamNames[ti],
          playerIds: teamPlayers.map((p) => p.id!).toList(),
        );
      }).where((t) => t.playerIds.isNotEmpty).toList();
      // Slots follow the team list, so a random order has to draw the teams
      // as well. Shuffling the players alone would leave team 1 always first.
      if (_startingOrder == StartingOrder.random) teamConfigs.shuffle(Random());
    }

    final game = CheckoutLadderGame(
      variant:         _variant,
      startNumber:     _start,
      targetNumber:    _isRace ? _target : null,
      dartsPerAttempt: _darts,
      stepFrom:        _stepEnabled ? _stepFrom : null,
      stepDarts:       _stepEnabled ? _stepDarts : null,
      checkOut:        _checkOut,
      createdAt:       DateTime.now(),
      playerIds:       players.map((p) => p.id!).toList(),
      teams:           teamConfigs,
      startingOrder:   _startingOrder,
    );

    await context.read<CheckoutLadderProvider>().startGame(game, players);

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const CheckoutLadderScreen()),
      );
    }
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

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
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// One choice chip per entry of [choices], the darts an attempt may hold.
class _DartsChoice extends StatelessWidget {
  final int value;
  final List<int> choices;
  final ValueChanged<int> onChanged;
  const _DartsChoice({
    required this.value,
    required this.choices,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final d in choices)
          ChoiceChip(
            label: Text(l.dartsN(d)),
            selected: value == d,
            onSelected: (_) => onChanged(d),
          ),
      ],
    );
  }
}

/// A labelled number between [min] and [max] with a minus and a plus beside
/// it, and a tap on the number to type it in. A tap on a button moves it by
/// one; holding a button moves it by ten at once and by
/// ten again every [_StepButton.repeatEvery] for as long as it is held, so 81
/// to 170 is one press rather than ninety taps.
class _NumberStepper extends StatelessWidget {
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _NumberStepper({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  /// Moves the value by [delta], held inside [min] and [max].
  void _move(int delta) => onChanged((value + delta).clamp(min, max));

  /// Asks for the number in a dialog and takes it when it is confirmed.
  Future<void> _enter(BuildContext context) async {
    final entered = await showDialog<int>(
      context: context,
      builder: (_) => _NumberDialog(
          title: label, value: value, min: min, max: max),
    );
    if (entered != null) onChanged(entered);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: theme.textTheme.bodyLarge)),
        _StepButton(
          icon: Icons.remove_rounded,
          enabled: value > min,
          onTap: () => _move(-1),
          onHold: () => _move(-10),
        ),
        // A tap on the number types it in, for a jump the buttons would take
        // a while to make.
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => _enter(context),
          child: SizedBox(
            width: 56,
            height: 40,
            child: Center(
              child: Text(
                '$value',
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ),
        _StepButton(
          icon: Icons.add_rounded,
          enabled: value < max,
          onTap: () => _move(1),
          onHold: () => _move(10),
        ),
      ],
    );
  }
}

/// The dialog behind a tap on a [_NumberStepper]'s number: one number field,
/// already holding the value and selected, so typing replaces it. OK is only
/// offered for a number between [min] and [max]; anything else says why.
class _NumberDialog extends StatefulWidget {
  final String title;
  final int value;
  final int min;
  final int max;

  const _NumberDialog({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
  });

  @override
  State<_NumberDialog> createState() => _NumberDialogState();
}

class _NumberDialogState extends State<_NumberDialog> {
  late final TextEditingController _ctrl = TextEditingController(
      text: '${widget.value}')
    ..selection = TextSelection(
        baseOffset: 0, extentOffset: '${widget.value}'.length);

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  /// The number typed in, or null while it is empty or out of range.
  int? get _valid {
    final n = int.tryParse(_ctrl.text);
    return n != null && n >= widget.min && n <= widget.max ? n : null;
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final valid = _valid;
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
        child: AlertDialog(
          title: Text(widget.title),
          content: TextField(
            controller: _ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3),
            ],
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall,
            decoration: InputDecoration(
              helperText: valid != null
                  ? l.ladderNumberRange(widget.min, widget.max)
                  : null,
              errorText: valid == null
                  ? l.ladderNumberRange(widget.min, widget.max)
                  : null,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (valid != null) Navigator.pop(context, valid);
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(l.cancel),
            ),
            FilledButton(
              onPressed:
                  valid == null ? null : () => Navigator.pop(context, valid),
              child: Text(l.ok),
            ),
          ],
        ),
      ),
    );
  }
}

/// A round minus or plus button of [_NumberStepper]. A tap calls [onTap];
/// holding it calls [onHold] at once and again every [repeatEvery] until it is
/// let go or the number reaches its bound.
class _StepButton extends StatefulWidget {
  /// How often a held button moves the number again.
  static const repeatEvery = Duration(milliseconds: 800);

  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final VoidCallback onHold;

  const _StepButton({
    required this.icon,
    required this.enabled,
    required this.onTap,
    required this.onHold,
  });

  @override
  State<_StepButton> createState() => _StepButtonState();
}

class _StepButtonState extends State<_StepButton> {
  Timer? _repeat;

  /// Moves the number once and keeps moving it while the button is held.
  void _startHold() {
    if (!widget.enabled) return;
    widget.onHold();
    _repeat?.cancel();
    _repeat = Timer.periodic(_StepButton.repeatEvery, (_) {
      // Read through [widget] on every tick: each move rebuilds the stepper
      // with the new value, and only the newest callback adds to that one.
      if (!mounted || !widget.enabled) return _stopHold();
      widget.onHold();
    });
  }

  /// Stops the repeat once the button is let go.
  void _stopHold() {
    _repeat?.cancel();
    _repeat = null;
  }

  @override
  void dispose() {
    _stopHold();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = widget.enabled;
    return GestureDetector(
      onLongPressStart: (_) => _startHold(),
      onLongPressEnd: (_) => _stopHold(),
      onLongPressCancel: _stopHold,
      child: Material(
        color: enabled ? cs.secondaryContainer : cs.surfaceContainerHighest,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: enabled ? widget.onTap : null,
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(widget.icon,
                size: 22,
                color: enabled
                    ? cs.onSecondaryContainer
                    : cs.onSurface.withValues(alpha: 0.38)),
          ),
        ),
      ),
    );
  }
}
