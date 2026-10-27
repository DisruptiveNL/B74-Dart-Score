import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/game_provider.dart';
import '../models/dart_throw.dart';

/// Corrects one of the last three numeric or bust visits in the active leg.
class B74ScoreCorrection extends StatelessWidget {
  final int slotIndex;
  const B74ScoreCorrection({super.key, required this.slotIndex});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<GameProvider>();
    return OutlinedButton(
      onPressed: provider.correctableVisits(slotIndex).isEmpty
          ? null
          : () => _openHistory(context),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        minimumSize: const Size(0, 36),
      ),
      child: const Text('CORRECTIE', style: TextStyle(fontWeight: FontWeight.bold)),
    );
  }

  Future<void> _openHistory(BuildContext context) async {
    final provider = context.read<GameProvider>();
    final visits = provider.correctableVisits(slotIndex);
    if (visits.isEmpty) return;
    // Close the history route completely before opening the edit route.
    final selected = await showDialog<DartThrow>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('CORRECTIE'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final visit in visits)
              ListTile(
                title: Text(visit.bust ? 'BUST' : '${visit.score} punten'),
                subtitle: Text('${visit.dartsUsed} darts · restant ${visit.remainingAfter}'),
                trailing: const Icon(Icons.edit_outlined),
                onTap: () => Navigator.pop(dialogContext, visit),
              ),
          ],
        ),
        actions: [TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('ANNULEREN'),
        )],
      ),
    );
    if (selected != null && context.mounted) {
      await _editVisit(context, selected, provider);
    }
  }

  Future<void> _editVisit(
    BuildContext context,
    DartThrow visit,
    GameProvider provider,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CorrectionEditDialog(
        slotIndex: slotIndex,
        visit: visit,
        provider: provider,
      ),
    );
  }
}

/// Owns the controller for exactly as long as the dialog widget is mounted.
/// Disposing it when showDialog's Future completes is too early: the dialog
/// route can still be animating out and rebuilding its TextField.
class _CorrectionEditDialog extends StatefulWidget {
  final int slotIndex;
  final DartThrow visit;
  final GameProvider provider;

  const _CorrectionEditDialog({
    required this.slotIndex,
    required this.visit,
    required this.provider,
  });

  @override
  State<_CorrectionEditDialog> createState() => _CorrectionEditDialogState();
}

class _CorrectionEditDialogState extends State<_CorrectionEditDialog> {
  late final TextEditingController _controller;
  late int _darts;
  late bool _bust;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.visit.score}');
    _darts = widget.visit.dartsUsed;
    _bust = widget.visit.bust;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    final score = _bust
        ? 0
        : int.tryParse(_controller.text.trim());
    if (score == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voer een geldige score in')),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.provider.correctVisit(
        widget.slotIndex,
        widget.visit.id!,
        score,
        _darts,
        bust: _bust,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('BEURT CORRIGEREN'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('SCORE')),
              ButtonSegment(value: true, label: Text('BUST')),
            ],
            selected: {_bust},
            onSelectionChanged: _saving ? null : (selection) {
              setState(() => _bust = selection.first);
            },
          ),
          if (!_bust)
            TextField(
              controller: _controller,
              autofocus: true,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Score (0–180)'),
            ),
          DropdownButton<int>(
            value: _darts,
            items: [1, 2, 3]
                .map((n) => DropdownMenuItem(value: n, child: Text('$n darts')))
                .toList(),
            onChanged: _saving
                ? null
                : (n) {
                    if (n != null) setState(() => _darts = n);
                  },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('ANNULEREN'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: const Text('OPSLAAN'),
        ),
      ],
    );
  }
}
