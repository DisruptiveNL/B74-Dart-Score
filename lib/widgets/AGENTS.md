# Widgets

The building blocks the screens are assembled from. Owns rendering and local UI interaction. Owns no app state, no database access and no statistics formula.

## Entry Points

### Input and dartboard

- `dartboard_input.dart`, dartboard-style tap input for the modes scored like X01, generic over the provider it reads, `DartboardInput<GameProvider>` in X01. `GameProvider` and `CheckoutLadderProvider` both implement `DartboardInputSource`, so a mode scored per dart implements that rather than copying the input
- `dartboard_icon.dart`, decorative dartboard SVG widget
- `dartboard_target_painter.dart`, paints a dartboard with a target segment highlighted
- `visit_darts_row.dart`, the darts of a visit as chips, one slot per dart the visit may hold: triple blue, double green, single plain, miss dimmed, empty an outline. What Cricket, Shanghai and Around the Clock show instead of counting dots, on the board and in the live info
- `visit_pause.dart`, `VisitPauseBar`, the thin bar that drains over the pause a finished visit stays on the board for, and `ContinueButton`, the button that ends it with the bar above it at the same width. X01 draws the bar under its visit row at the row's width and its own button in the style of its action row, three grid columns wide under the 17, 18 and 19; the three target modes put `ContinueButton` where their throw buttons sit, three buttons wide
- `bot_select_section.dart`, the card under the roster that adds computer opponents by tier: a switch in the header like the handicap and team cards, then one row per `BotLevel` with its expected average and a counter (minus, count, plus), and under them one line naming the slots the bots throw in. Every tier is always listed, so the card keeps one height however many bots are in the game. Plus adds one more bot of that tier, numbered by the setup screen with the lowest free ordinal, and goes off at `kMaxBotsPerTier` (five); minus removes the bot of that tier that throws last, so the others keep their slots. Switching the card off drops every bot. Shared by all four setups; the roster above never lists a bot
- `cricket_marks_widget.dart`, renders Cricket marks (slash / X / circle-X) for a field
- `finish_suggestion_widget.dart`, checkout hint display
- `favorite_double_picker.dart`, picks a player's favorite doubles

### Shared setup blocks, used by every mode

- `team_section.dart`, team naming, add/remove and assignment
- `starting_order_section.dart`, random vs. fixed plus the drag-to-sort list
- `player_select_section.dart`, the roster with a checkbox each, the add button and the star on the main profile

### Shared result rendering

- `game_info_card.dart`, the card listing a finished game's settings
- `summary_body.dart`, the body every summary and history detail is laid into, one column or two
- `summary_player_card.dart`, the player/team stat card for the X01 summary and history screens
- `final_ranking_card.dart`, the placement-mode ranking card and per-leg table
- `stat_row.dart`, the label/value row used by every stat list
- `throw_row.dart`, one recorded visit as a list entry, shared by the throw log and the lifetime recent-throws list
- `throw_log_card.dart`, the "All Throws" log for the X01 summary and history screens
- `rematch_button.dart`, "Play Again" plus its confirmation dialog
- `checkout_ladder_result.dart`, the Checkout Ladder's result cards and banner, shared by its summary and its history detail the way the X01 pair shares its cards

### Transfers and players

- `wifi_pairing.dart`, the QR scanner, the pairing number dialog, the QR card, the route selector and the one mapping from a start failure to what it says on screen, all shared by sync and backup
- `player_dialog.dart`, create/edit player dialog

## Contracts and Invariants

- A widget never holds mutable app state and never touches SQLite. It takes what it renders as a parameter or reads a provider
- The shared result widgets are shared on purpose: the X01 summary and the X01 history detail render the same result through `SummaryPlayerCard`, `FinalRankingCard` and `ThrowLogCard`. Fix the widget, not one of the two screens
- A recorded visit is rendered by `ThrowRow` wherever it appears, the throw log of a game and the lifetime recent-throws list alike. It fills four slots over two lines and decides from its parameters which of them a caller has anything to put in; a list that needs a fifth thing belongs in the widget, not in a copy of it
- `GameInfoCard` takes `dense: true` from the four history detail screens and the default from the four post-game summaries. That split is a convention across both sets, not a per-mode oversight
- Colors come from `ThemeProvider`, team accents from `utils/team_color.dart`, double and triple affordances from `utils/segment_color.dart`
- Two panes side by side are built with `SidePaneLayout` from `utils/layout.dart`, never with a hand rolled `Row`. It is what carries the minimum pane width and the input side, and a second layout would answer both differently
- `SummaryBody` divides all eight summary and history detail screens. Its divider stands in the middle and stays there, because both columns hold cards of the same kind; only the game, the history and the player list have anything to rebalance, and only those three let it be dragged
- Strings come from `AppLocalizations`, and the per-mode setting names from `utils/game_labels.dart`

## Patterns

A block that a second game mode is about to need belongs here, parameterised, rather than copied into the second setup screen. `TeamSection` and `StartingOrderSection` are what that looks like when it is done.

## Anti-patterns

- Do not compute stats in a widget. `ThrowStats` is the one aggregation
- Do not hardcode a color that should follow the theme
- Do not copy `wifi_pairing.dart` for a third transfer flow; both sync and backup already share it
- `TransferRouteSelector` hides the own-network row rather than disabling it when the device cannot raise one. An option that can never be picked here is not a choice, and explaining why would say more about Android versions than anyone wants to read while sending a profile
- `transferStartMessage` is the one place a transfer failure becomes a sentence. A second copy is how the two screens would start telling the user different things about the same fault
- Do not build a second player roster into a setup screen. `PlayerSelectSection` is the one, and it takes the order `PlayersProvider` hands it: main profile first, everyone else alphabetically

## Related Context

- Screens that compose these: `../screens/AGENTS.md`
- What the pairing UI is driving: `../services/AGENTS.md`
