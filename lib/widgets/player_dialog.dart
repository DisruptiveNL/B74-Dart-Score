import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../utils/layout.dart';
import 'favorite_double_picker.dart';

/// Modal dialog to create or edit a player: name, favorite double, and (when
/// editing) the option to make them the primary profile or delete them.
/// Validates that the name is non-empty, unique, and a favorite double is set.
class PlayerDialog extends StatefulWidget {
  final String? initialName;
  final String? initialDouble;
  final bool isPrimary;
  final List<String> existingNames;
  final void Function(String name, String favoriteDouble) onSave;
  final VoidCallback? onDelete;
  final VoidCallback? onSetPrimary;

  const PlayerDialog({
    super.key,
    this.initialName,
    this.initialDouble,
    this.isPrimary = false,
    this.existingNames = const [],
    required this.onSave,
    this.onDelete,
    this.onSetPrimary,
  });

  @override
  State<PlayerDialog> createState() => _PlayerDialogState();
}

class _PlayerDialogState extends State<PlayerDialog> {
  late final TextEditingController _nameCtrl;
  String? _selectedDouble;
  bool _showDoubleError = false;
  bool _showNameError = false;
  late bool _isPrimary;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialName ?? '');
    _selectedDouble = widget.initialDouble;
    _isPrimary = widget.isPrimary;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final canSave =
        _nameCtrl.text.trim().isNotEmpty &&
        _selectedDouble != null &&
        !_showNameError;
    final isEditing = widget.initialName != null;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: contentMaxWidth(context)),
        child: Dialog(
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 40,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 12, 12, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Title row with X close button ─────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isEditing ? l.editPlayerTitle : l.addPlayerTitle,
                        style: theme.textTheme.headlineSmall,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: l.cancel,
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Scrollable content ────────────────────────────────────
                Flexible(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6, right: 12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _nameCtrl,
                            autofocus: !isEditing,
                            textInputAction: TextInputAction.done,
                            maxLength: 12,
                            decoration: InputDecoration(
                              labelText: l.nameLabel,
                              border: const OutlineInputBorder(),
                              errorText: _showNameError
                                  ? l.nameAlreadyExists
                                  : null,
                            ),
                            textCapitalization: TextCapitalization.words,
                            onChanged: (_) =>
                                setState(() => _showNameError = false),
                            onSubmitted: (_) =>
                                FocusScope.of(context).unfocus(),
                          ),
                          const SizedBox(height: 16),
                          Row(
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
                          if (isEditing && widget.onSetPrimary != null) ...[
                            const SizedBox(height: 8),
                            const Divider(height: 1),
                            SwitchListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _isPrimary,
                              onChanged: widget.isPrimary
                                  ? null
                                  : (val) => setState(() => _isPrimary = val),
                              secondary: Icon(
                                Icons.star_rounded,
                                color: _isPrimary
                                    ? cs.primary
                                    : cs.onSurfaceVariant,
                              ),
                              title: Text(
                                _isPrimary
                                    ? l.alreadyMainProfile
                                    : l.setAsMainProfile,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Bottom action row ─────────────────────────────────────
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Row(
                    children: [
                      if (widget.onDelete != null)
                        IconButton.outlined(
                          icon: Icon(Icons.delete_outline, color: cs.error),
                          tooltip: l.delete,
                          style: IconButton.styleFrom(
                            side: BorderSide(
                              color: cs.error.withValues(alpha: 0.5),
                            ),
                          ),
                          onPressed: () {
                            Navigator.pop(context);
                            widget.onDelete!();
                          },
                        ),
                      const Spacer(),
                      FilledButton.icon(
                        icon: const Icon(Icons.save_outlined),
                        label: Text(l.save),
                        onPressed: canSave ? _save : _onSaveAttempt,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Handles a save tap while the form is invalid by surfacing the missing-
  /// favorite-double error.
  void _onSaveAttempt() {
    setState(() => _showDoubleError = _selectedDouble == null);
  }

  /// Validates the input and, if valid, invokes [onSave] (and [onSetPrimary]
  /// when newly promoted) and closes the dialog; otherwise shows field errors.
  void _save() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty || _selectedDouble == null) {
      setState(() => _showDoubleError = _selectedDouble == null);
      return;
    }
    if (widget.existingNames.contains(name.toLowerCase())) {
      setState(() => _showNameError = true);
      return;
    }
    widget.onSave(name, _selectedDouble!);
    if (_isPrimary && !widget.isPrimary && widget.onSetPrimary != null) {
      widget.onSetPrimary!();
    }
    Navigator.pop(context);
  }
}
