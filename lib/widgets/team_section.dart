import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/player.dart';
import '../utils/team_color.dart';
import '../utils/player_label.dart';

/// Optional section to enable team play, name teams, add/remove them, and assign
/// each selected player to a team. Shared by every game mode's setup screen.
class TeamSection extends StatelessWidget {
  final bool enabled;
  final List<Player> players;
  final Map<Player, int> teamAssignment;
  final List<String> teamNames;
  final List<TextEditingController> teamNameCtrl;
  final ValueChanged<bool> onToggle;
  final void Function(Player, int) onAssignmentChanged;
  final void Function(int, String) onNameChanged;
  final VoidCallback onAddTeam;
  final void Function(int) onRemoveTeam;

  const TeamSection({
    super.key,
    required this.enabled,
    required this.players,
    required this.teamAssignment,
    required this.teamNames,
    required this.teamNameCtrl,
    required this.onToggle,
    required this.onAssignmentChanged,
    required this.onNameChanged,
    required this.onAddTeam,
    required this.onRemoveTeam,
  });

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
            Row(
              children: [
                Icon(
                  Icons.groups_rounded,
                  size: 20,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    context.l10n.teamGame,
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
                context.l10n.teamGameDesc,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              // Team name inputs + remove buttons
              ...List.generate(
                teamNames.length,
                (ti) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: teamColor(ti),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: teamNameCtrl[ti],
                          decoration: InputDecoration(
                            // Deliberately not "Team ${ti + 1}": the starting
                            // order can move a team, so a positional label would
                            // contradict the name in the field.
                            labelText: context.l10n.teamNameLabel,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          onChanged: (v) => onNameChanged(ti, v),
                        ),
                      ),
                      if (teamNames.length > 2) ...[
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(
                            Icons.remove_circle_outline,
                            size: 20,
                          ),
                          color: cs.error,
                          onPressed: () => onRemoveTeam(ti),
                          tooltip: context.l10n.removeTeam,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              // Add team button
              if (teamNames.length < players.length)
                TextButton.icon(
                  onPressed: onAddTeam,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(context.l10n.addTeam),
                ),
              const SizedBox(height: 4),
              const Divider(),
              const SizedBox(height: 4),
              // Player assignment via dropdown
              ...players.map((p) {
                final assigned = teamAssignment[p] ?? 0;
                final clampedAssigned = assigned.clamp(0, teamNames.length - 1);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: teamColor(
                          clampedAssigned,
                        ).withValues(alpha: 0.2),
                        child: Text(
                          p.label(context.l10n).isNotEmpty
                              ? p.label(context.l10n)[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: teamColor(clampedAssigned),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          p.label(context.l10n),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                      DropdownButton<int>(
                        value: clampedAssigned,
                        underline: const SizedBox(),
                        isDense: true,
                        items: List.generate(
                          teamNames.length,
                          (ti) => DropdownMenuItem(
                            value: ti,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: BoxDecoration(
                                    color: teamColor(ti),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  teamNames[ti],
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ],
                            ),
                          ),
                        ),
                        onChanged: (v) {
                          if (v != null) onAssignmentChanged(p, v);
                        },
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 4),
            ],
          ],
        ),
      ),
    );
  }
}
