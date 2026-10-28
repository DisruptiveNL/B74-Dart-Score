import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theme_provider.dart';
import '../providers/bot_runner.dart' show GamePace;
import '../providers/pace_provider.dart';
import '../providers/language_provider.dart';
import '../providers/donation_provider.dart';
import '../providers/text_scale_provider.dart';
import '../l10n/app_localizations.dart';
import '../utils/layout.dart';
import 'about_screen.dart';
import 'backup_screen.dart';
import 'donation_screen.dart';

/// Settings screen holding the two display choices and the screens the app
/// links on to.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.settingsTitle)),
      body: ListView(
        padding: contentPadding(context, top: 12, bottom: 28, innerH: 14),
        children: [
          const _DisplaySection(),
          const SizedBox(height: 14),
          const _AppSection(),
        ],
      ),
    );
  }
}

// ── Display ───────────────────────────────────────────────────────────────────

/// The theme and the language, each as one row that opens a menu.
class _DisplaySection extends StatelessWidget {
  const _DisplaySection();

  @override
  Widget build(BuildContext context) {
    final tp = context.watch<ThemeProvider>();
    final lp = context.watch<LanguageProvider>();
    final pace = context.watch<PaceProvider>();
    final cs = Theme.of(context).colorScheme;
    final l = context.l10n;

    return _Card(
      title: l.displaySection,
      icon: Icons.tune_rounded,
      child: Column(
        children: [
          _MenuRow<ThemeMode>(
            icon: Icons.palette_outlined,
            label: l.theme,
            value: tp.mode,
            onSelected: tp.setMode,
            options: [
              _MenuOption(
                value: ThemeMode.system,
                label: l.system,
                leading: const Icon(Icons.brightness_auto_rounded),
              ),
              _MenuOption(
                value: ThemeMode.light,
                label: l.light,
                leading: const Icon(Icons.light_mode_rounded),
              ),
              _MenuOption(
                value: ThemeMode.dark,
                label: l.dark,
                leading: const Icon(Icons.dark_mode_rounded),
              ),
            ],
          ),
          const Divider(height: 1),
          _MenuRow<String?>(
            icon: Icons.language_rounded,
            label: l.language,
            value: lp.languageCode,
            onSelected: lp.setLanguage,
            options: [
              _MenuOption(
                value: null,
                label: l.system,
                leading: const Icon(Icons.language_rounded),
              ),
              _MenuOption(
                value: 'en',
                label: 'English',
                leading: _LanguageBadge('EN', cs: cs),
              ),
              _MenuOption(
                value: 'de',
                label: 'Deutsch',
                leading: _LanguageBadge('DE', cs: cs),
              ),
            ],
          ),
          const Divider(height: 1),
          _MenuRow<GamePace>(
            icon: Icons.speed_rounded,
            label: l.gamePace,
            hint: l.gamePaceHint,
            value: pace.pace,
            onSelected: pace.setPace,
            options: [
              _MenuOption(
                value: GamePace.fast,
                label: l.paceFast,
                leading: const Icon(Icons.fast_forward_rounded),
              ),
              _MenuOption(
                value: GamePace.normal,
                label: l.paceNormal,
                leading: const Icon(Icons.play_arrow_rounded),
              ),
              _MenuOption(
                value: GamePace.slow,
                label: l.paceSlow,
                leading: const Icon(Icons.slow_motion_video_rounded),
              ),
            ],
          ),
          // Only where the app acts on it: a phone draws its text at the size
          // the system asks for, so a slider there would move nothing.
          if (isTabletLayout(context)) ...[
            const Divider(height: 1),
            const _TextSizeRow(),
          ],
        ],
      ),
    );
  }
}

/// The text size, as a slider over the range the app allows.
///
/// The screen it sits on is drawn at the size it sets, so a drag shows what it
/// does while it happens, and the value beside the label says the same thing in
/// numbers for a reader who wants the size they had back.
class _TextSizeRow extends StatelessWidget {
  const _TextSizeRow();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l = context.l10n;
    final scale = context.watch<TextScaleProvider>();
    final percent = (scale.factor * 100).round();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.format_size_rounded, color: cs.onSurfaceVariant),
              const SizedBox(width: 16),
              Expanded(child: Text(l.textSize)),
              Text('$percent %', style: TextStyle(color: cs.onSurfaceVariant)),
              // Finding 100 percent again by dragging is fiddly, so the way
              // back to it is one tap and only offered when there is a way back.
              if (scale.factor != kDefaultTextScale)
                TextButton(
                  onPressed: scale.reset,
                  child: Text(l.textSizeReset),
                ),
            ],
          ),
          Row(
            children: [
              Text(
                'A',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              Expanded(
                child: Slider(
                  value: scale.factor,
                  min: kMinTextScale,
                  max: kMaxTextScale,
                  divisions: kTextScaleDivisions,
                  label: '$percent %',
                  onChanged: scale.setFactor,
                ),
              ),
              Text(
                'A',
                style: TextStyle(fontSize: 20, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              l.textSizeHint,
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

/// The language code of an option, drawn where the other menus carry an icon.
///
/// A language has no icon of its own, and a flag would name a country rather
/// than a language and fall back to two letter boxes on the devices that ship
/// without the emoji. The width matches an icon so both menus line up.
class _LanguageBadge extends StatelessWidget {
  final String code;
  final ColorScheme cs;

  const _LanguageBadge(this.code, {required this.cs});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 24,
    child: Text(
      code,
      textAlign: TextAlign.center,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.bold,
        color: cs.onSurfaceVariant,
      ),
    ),
  );
}

// ── App ───────────────────────────────────────────────────────────────────────

/// The screens the settings link on to: backup, support and about.
class _AppSection extends StatelessWidget {
  const _AppSection();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final isSupporter = context.watch<DonationProvider>().isSupporter;

    return _Card(
      title: l.appSection,
      icon: Icons.apps_rounded,
      child: Column(
        children: [
          _LinkRow(
            icon: Icons.backup_outlined,
            title: l.backupTitle,
            subtitle: l.backupSectionDesc,
            onTap: () => _open(context, const BackupScreen()),
          ),
          const Divider(height: 1),
          _LinkRow(
            icon: Icons.favorite_rounded,
            iconColor: cs.primary,
            title: l.donationSectionTitle,
            subtitle: l.donationSectionDesc,
            trailing: isSupporter
                ? Icon(Icons.star_rounded, color: cs.primary, size: 20)
                : null,
            onTap: () => _open(context, const DonationScreen()),
          ),
          const Divider(height: 1),
          _LinkRow(
            icon: Icons.info_outline_rounded,
            title: l.about,
            subtitle: l.aboutDesc,
            onTap: () => _open(context, const AboutScreen()),
          ),
        ],
      ),
    );
  }

  /// Pushes [screen] onto the navigator.
  void _open(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
}

/// A row that leads to another screen.
class _LinkRow extends StatelessWidget {
  final IconData icon;
  final Color? iconColor;
  final String title;
  final String subtitle;

  /// Replaces the chevron when the row has something to report, as the support
  /// row does once the purchase went through.
  final Widget? trailing;

  final VoidCallback onTap;

  const _LinkRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.iconColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: iconColor ?? cs.onSurfaceVariant),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
      ),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }
}

// ── Menu row ──────────────────────────────────────────────────────────────────

/// One option of a [_MenuRow].
class _MenuOption<T> {
  /// What picking this option sets.
  final T value;

  /// The name of the option, shown in the menu and, for the active one, as the
  /// value of the row itself.
  final String label;

  /// Drawn ahead of the label. An icon for most menus, a language code for the
  /// one that has no icons to give.
  final Widget leading;

  const _MenuOption({
    required this.value,
    required this.label,
    required this.leading,
  });
}

/// A settings row that names its current value and opens a menu to change it.
///
/// The whole row is the target, not just the value at its end, which is why
/// the anchor is driven through a controller instead of building the menu
/// around a button. The trailing icon is deliberately not the chevron the link
/// rows carry: in the same card the two have to say apart whether a tap opens
/// a menu or leaves for another screen.
class _MenuRow<T> extends StatefulWidget {
  final IconData icon;
  final String label;
  final T value;
  final List<_MenuOption<T>> options;
  final ValueChanged<T> onSelected;

  /// What the setting does, folded away behind an info icon in the row and
  /// shown under it on a tap. Only for a setting whose name does not say it.
  final String? hint;

  const _MenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
    this.hint,
  });

  @override
  State<_MenuRow<T>> createState() => _MenuRowState<T>();
}

class _MenuRowState<T> extends State<_MenuRow<T>> {
  final _controller = MenuController();

  /// Whether the hint is unfolded. View state: it says nothing about the
  /// setting and is meant to be forgotten with the screen.
  bool _hintOpen = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final current = widget.options.firstWhere((o) => o.value == widget.value);
    final hint = widget.hint;

    // The row is the anchor, not the value at its end: MenuAnchor counts a tap
    // on its own child as inside the menu, and a tap anywhere else closes it.
    // Anchoring the value alone would let a tap on the label close the menu and
    // reopen it in the same gesture.
    return MenuAnchor(
      controller: _controller,
      style: const MenuStyle(alignment: AlignmentDirectional.bottomEnd),
      menuChildren: [
        for (final option in widget.options)
          _MenuEntry<T>(
            option: option,
            selected: option.value == widget.value,
            onTap: () => widget.onSelected(option.value),
          ),
      ],
      child: Column(
        children: [
          ListTile(
            leading: Icon(widget.icon, color: cs.onSurfaceVariant),
            title: hint == null
                ? Text(widget.label)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(child: Text(widget.label)),
                      IconButton(
                        icon: Icon(
                          _hintOpen
                              ? Icons.info_rounded
                              : Icons.info_outline_rounded,
                          size: 18,
                        ),
                        color: cs.onSurfaceVariant,
                        visualDensity: VisualDensity.compact,
                        tooltip: context.l10n.whatItDoes,
                        onPressed: () => setState(() => _hintOpen = !_hintOpen),
                      ),
                    ],
                  ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  current.label,
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.unfold_more_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
              ],
            ),
            onTap: () =>
                _controller.isOpen ? _controller.close() : _controller.open(),
          ),
          if (hint != null)
            AnimatedSize(
              duration: const Duration(milliseconds: 150),
              alignment: Alignment.topCenter,
              child: _hintOpen
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(56, 0, 16, 12),
                      child: Text(
                        hint,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
        ],
      ),
    );
  }
}

/// One entry of the menu a [_MenuRow] opens, checked while it is the active
/// choice.
class _MenuEntry<T> extends StatelessWidget {
  final _MenuOption<T> option;
  final bool selected;
  final VoidCallback onTap;

  const _MenuEntry({
    required this.option,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return MenuItemButton(
      leadingIcon: option.leading,
      trailingIcon: selected
          ? Icon(Icons.check_rounded, size: 18, color: cs.primary)
          : null,
      onPressed: onTap,
      child: Text(
        option.label,
        style: TextStyle(
          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          color: selected ? cs.primary : null,
        ),
      ),
    );
  }
}

// ── Card wrapper ──────────────────────────────────────────────────────────────

/// A titled, icon-headed section card wrapping a settings group.
class _Card extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _Card({required this.title, required this.icon, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Row(
            children: [
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(
                title,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: cs.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        Card(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: child,
          ),
        ),
      ],
    );
  }
}
