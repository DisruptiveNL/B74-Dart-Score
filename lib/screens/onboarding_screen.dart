import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/players_provider.dart';
import '../widgets/dartboard_icon.dart';
import '../widgets/favorite_double_picker.dart';
import '../utils/layout.dart';

/// First-launch walkthrough that creates the primary player (name and favorite
/// double) before entering the app.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _nameCtrl = TextEditingController();

  /// Anchors for the two things that can be missing, so the one that is can be
  /// scrolled into view when the button is pressed without it.
  final _nameKey = GlobalKey();
  final _doubleKey = GlobalKey();

  String? _selectedDouble;
  bool _saving = false;
  bool _showDoubleError = false;
  bool _showNameError = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  /// Creates the primary player from the entered name and double, then finishes
  /// onboarding.
  ///
  /// A press that cannot create the profile never passes silently. Both fields
  /// are required, and saying nothing about the one that is missing is what
  /// made the button look dead: the keyboard opens over this screen on its own,
  /// and on a tablet it covers everything below the name field, so a message
  /// placed there is out of sight. The keyboard is closed first and the field
  /// at fault scrolled into view, so the reason is always on screen.
  Future<void> _save() async {
    final l = context.l10n;
    final name = _nameCtrl.text.trim();
    final missingName = name.isEmpty;
    final missingDouble = _selectedDouble == null;

    if (missingName || missingDouble) {
      setState(() {
        _showNameError = missingName;
        _showDoubleError = missingDouble;
      });
      FocusScope.of(context).unfocus();
      await _revealError();
      return;
    }

    setState(() => _saving = true);
    try {
      final provider = context.read<PlayersProvider>();
      final player = await provider.addPlayer(name, isPrimary: true);
      await provider.updatePlayer(
        player.copyWith(favoriteDoubles: _selectedDouble),
      );
      // PlayersProvider now has a primary player → _AppGate rebuilds to HomeScreen.
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.profileFailed)));
    }
  }

  /// Scrolls the field the press was rejected over into view, after the frame
  /// in which the keyboard closing has given the screen its height back.
  Future<void> _revealError() async {
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final target = (_showNameError ? _nameKey : _doubleKey).currentContext;
    if (target == null || !target.mounted) return;
    await Scrollable.ensureVisible(
      target,
      alignment: 0.5,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l = context.l10n;

    // Whether both required fields are filled, which is what the button
    // colours itself by.
    final canSubmit =
        _nameCtrl.text.trim().isNotEmpty && _selectedDouble != null;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Icon + Title ────────────────────────────────────────
                  const DartboardIcon(size: 100),
                  const SizedBox(height: 20),
                  Text(
                    l.welcomeTitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l.welcomeSubtitle,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 36),

                  // ── Name ────────────────────────────────────────────────
                  TextField(
                    key: _nameKey,
                    controller: _nameCtrl,
                    autofocus: true,
                    textCapitalization: TextCapitalization.words,
                    textInputAction: TextInputAction.done,
                    maxLength: 12,
                    decoration: InputDecoration(
                      labelText: l.yourName,
                      border: const OutlineInputBorder(),
                      prefixIcon: const Icon(Icons.person_outline),
                      helperText: l.requiredField,
                      errorText: _showNameError ? l.nameRequired : null,
                    ),
                    // Every keystroke, because the button reads the field to
                    // decide whether it looks ready.
                    onChanged: (value) => setState(() {
                      if (value.trim().isNotEmpty) _showNameError = false;
                    }),
                    onSubmitted: (_) => FocusScope.of(context).unfocus(),
                  ),
                  const SizedBox(height: 24),

                  // ── Favorite double (required) ────────────────────────────
                  Row(
                    key: _doubleKey,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        l.favDoublesTitle,
                        style: theme.textTheme.titleSmall,
                      ),
                      if (_selectedDouble != null) ...[
                        Text(': ', style: theme.textTheme.titleSmall),
                        Text(
                          _selectedDouble!,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_selectedDouble == null && !_showDoubleError)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Center(
                        child: Text(
                          l.tapDoubleHint,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 8),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 240),
                      child: FavoriteDoublePicker(
                        value: _selectedDouble,
                        onChanged: (val) => setState(() {
                          _selectedDouble = val;
                          _showDoubleError = false;
                        }),
                      ),
                    ),
                  ),
                  if (_showDoubleError)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Center(
                        child: Text(
                          l.favDoublesRequired,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.error,
                          ),
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          l.favDoubleHint,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── CTA ──────────────────────────────────────────────────
                  //
                  // Greyed out until the profile is complete, and still
                  // pressable there: a button that goes quiet under the finger
                  // is exactly what this screen was rejected for, so the grey
                  // one answers with the field it is waiting for rather than
                  // with nothing.
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.arrow_forward_rounded),
                    label: Text(l.letsGo),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      textStyle: theme.textTheme.titleMedium,
                      backgroundColor: canSubmit
                          ? null
                          : cs.surfaceContainerHighest,
                      foregroundColor: canSubmit ? null : cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
