# Providers

The state machines. Owns the rules of each game mode, the in-flight game state, and the only calls into `db_helper.dart`. Owns no layout and no wire format.

## Entry Points

- `bot_runner.dart`, the `BotRunner` mixin every game provider carries: the bot's dart timers, the pause a finished visit stays on the board for, and the stop on quit, rebuild and background. A provider only says who is on turn (`isBotTurn`) and how one bot dart is aimed and recorded (`throwBotDart`)
- `game_provider.dart`, X01: score calculation, bust detection, turn logic; its bot aims through `x01Target` and goes down the same `_addDart` path a tap does
- `cricket_provider.dart`, Cricket: marks, scoring, cut-throat logic; its bot aims through `cricketTarget`
- `shanghai_provider.dart`, Shanghai: round targets, scoring, the Shanghai win; its bot aims through `shanghaiTarget` and a dart on any other number is recorded as a miss, since a Shanghai dart is scored on the target alone
- `around_the_clock_provider.dart`, Around the Clock: per-player target progress; its bot aims through `aroundTheClockTarget`
- `checkout_ladder_provider.dart`, Checkout Ladder: persists the darts and feeds them to `CheckoutLadderEngine`, which holds every rule, so live play, undo, redo and resume are one replay. Its bot aims through `x01Target` at the rest of the attempt. A visit there ends early on a check or a bust, so it is never counted in threes
- `players_provider.dart`, player CRUD, loads from the DB and notifies listeners. Keeps the computer opponents apart in `bots` and creates a tier's row on first use through `botFor`
- `donation_provider.dart`, in-app purchase / supporter state via `in_app_purchase`
- `theme_provider.dart` and `language_provider.dart`, light/dark and en/de, both persisted via `shared_preferences`
- `pace_provider.dart`, the `GamePace` the reader picked, persisted via `shared_preferences` and handed to the game providers through `TurnPacing.pace`, which they read as they go rather than depending on the provider
- `tablet_layout_provider.dart`, which side the input sits on and where each divider stands, persisted via `shared_preferences`
- `text_scale_provider.dart`, the text size the reader picked, persisted via `shared_preferences`

## Contracts and Invariants

- A provider is the only place mutable app state lives. A widget that keeps game state of its own is a bug, not a shortcut
- Persistence goes through `db_helper.dart` and nowhere else. `notifyListeners()` after the write, not before
- Changing a model means changing the schema and the migrations in `db_helper.dart` in the same step
- Statistics come from `ThrowStats` in `utils/throw_stats.dart`. A provider does not carry a second formula for an average, a high, a bust count or a checkout rate
- `GameProvider` is the one place that decides `DartThrow.checkoutDarts`, in `_submitVisit`, via `checkoutDartsInVisit`. It is stored rather than derived because nothing downstream can work it out again: counting the darts that flew while a single dart could have finished needs the individual darts and the player's own check-out rule, and a throw that arrives over sync carries neither. Two statistics rest on it, the check-out rate over visits and the double rate over darts, so a second formula anywhere would make them disagree
- Undo, redo and resume all rebuild the board from the stored throws, and everything about the turn is read off those throws, never counted from how many visits a leg happens to hold. Whose turn it is comes from who threw last, the member of a team from the member who threw its last visit (in Cricket, from the member who threw its last dart, since a visit there is counted in darts), and the leg and set from `openLegAndSet`, which moves past a leg its last visit already decided. Visit counts only describe a game whose every leg opened with the first slot and the first member, and no leg after the first one does: the slot after the winner opens it, and a team's rotation runs on across legs and sets
- `DonationProvider` owns everything `in_app_purchase` touches. No screen talks to the plugin
- The runner schedules after every change of turn (`scheduleBot`) and is held back (`botSuspended`) while undo and redo rebuild the board, so no bot dart lands on a half restored board. Start and resume call `releaseBot` and `dropHeldVisit` first. `leaveGame` is what every live screen calls on quit, and the mixin watches the app lifecycle itself so a bot pauses in the background on both platforms
- A completed visit waits out `TurnPacing.visitPause` on the board through `holdVisit`, with `inputLocked` true, before the settle it was handed runs. The pause and the bot's delay come from the `GamePace` in `TurnPacing.pace`, which `PaceProvider` keeps, and a tap on the dart row calls `flushHeldVisit` to move on at once. In X01 the visit is not recorded until then (`_settleVisit`), which is why undo in that window is just a dart off the board and why `leaveGame` and the app going to the background flush it first: a pending visit exists nowhere else. The other three modes record every dart at once and only hold `_endVisit`, so a kill during the pause loses nothing and the replay reads a full visit. The bot waits out the same pause and never schedules while one is held
- `isBotTurn` locks the input, undo and redo in every mode. Bot darts are never undone on their own: undo skips back over every trailing bot dart to the last human dart, and `canUndo` is false when only bots have thrown. Tests drive the bot with `botDartDelay = Duration.zero` and a seeded `BotThrower`, and wait on `isBotTurn || botThrowing`, never on a guessed duration
- `TextScaleProvider` holds a factor, not a font size, and the app applies it in one place: the `MaterialApp` builder in `main.dart`, and only on a tablet sized window. A screen that scales its own text again is a screen the setting no longer describes
- `TabletLayoutProvider` keys a divider by the screen **and** the orientation it belongs to. A scoreboard next to an input divides differently than a list next to a page of statistics, and a share that reads well across a landscape tablet leaves an upright one with two columns too narrow. The values are loaded on a phone too, they are simply never read there

## Patterns

A new game mode gets its own provider next to these, with the same shape: load the game, accept a throw, decide the turn, decide the leg and set, write the result. Mirror the existing four rather than inventing a new lifecycle.

## Anti-patterns

- No `print()` or `debugPrint()`, here or anywhere else in committed code
- Do not reach into another mode's provider to reuse a rule. Shared rules belong in `utils/`
- Do not reorder `StartingOrder`: `random` is index 0 because that is the DB default
- Do not reorder `BotLevel` either, and do not insert a bot row by hand: `PlayersProvider.botFor(level, ordinal:)` is the one place that makes one, so each numbered bot stays a single row that every game it plays in shares. The first bot of a tier keeps the uuid it had before the numbering, `uuidFor(1)` is `uuid`

## Related Context

- Screens that read these: `../screens/AGENTS.md`
- Sync and backup, which write player and game rows outside the normal game flow: `../services/AGENTS.md`
