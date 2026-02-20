import 'package:flutter/material.dart';

class TrimmingTab extends StatelessWidget {
  const TrimmingTab({
    required this.newFileNameController,
    required this.trimRange,
    required this.maxTrimEnd,
    required this.isBusy,
    required this.onTrimRangeChanged,
    required this.onRenamePressed,
    required this.onRenameTrimPressed,
    required this.onDeletePressed,
    required this.onPreviousPressed,
    required this.onNextPressed,
    super.key,
  });

  final TextEditingController newFileNameController;
  final RangeValues trimRange;
  final double maxTrimEnd;
  final bool isBusy;
  final ValueChanged<RangeValues> onTrimRangeChanged;
  final Future<void> Function() onRenamePressed;
  final Future<void> Function() onRenameTrimPressed;
  final Future<void> Function() onDeletePressed;
  final Future<void> Function() onPreviousPressed;
  final Future<void> Function() onNextPressed;
   
  @override
  Widget build(BuildContext context) {
    final bool rangeEnabled = maxTrimEnd.isFinite && maxTrimEnd > 0;
    final double sliderMax = rangeEnabled ? maxTrimEnd : 1;
    final double safeStart = trimRange.start.clamp(0, sliderMax).toDouble();
    final double safeEnd = trimRange.end.clamp(safeStart, sliderMax).toDouble();
    final RangeValues safeTrimRange = RangeValues(safeStart, safeEnd);
    final String startLabel = _displayMmSs(safeTrimRange.start);
    final String endLabel = _displayMmSs(safeTrimRange.end);

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            TextField(
              controller: newFileNameController,
              decoration: const InputDecoration(
                hintText: 'New file name',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF232323),
              ),
            ),
            const SizedBox(height: 12),
            Text('Trim $startLabel - $endLabel'),
            RangeSlider(
              values: safeTrimRange,
              min: 0,
              max: sliderMax,
              divisions: rangeEnabled ? 1000 : 1,
              onChanged: rangeEnabled ? onTrimRangeChanged : null,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                FilledButton(
                  onPressed: isBusy ? null : onRenamePressed,
                  child: const Text('Rename'),
                ),
                const SizedBox(width: 10),
                FilledButton(
                  onPressed: isBusy ? null : onRenameTrimPressed,
                  child: const Text('Rename + Trim'),
                ),
                const SizedBox(width: 10),
                FilledButton.tonal(
                  onPressed: isBusy ? null : onDeletePressed,
                  child: const Text('Delete'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: <Widget>[
                OutlinedButton(
                  onPressed: isBusy ? null : onPreviousPressed,
                  child: const Text('Previous'),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: isBusy ? null : onNextPressed,
                  child: const Text('Next'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _displayMmSs(double seconds) {
    final int totalSeconds = seconds.floor();
    final int mins = totalSeconds ~/ 60;
    final int secs = totalSeconds % 60;
    return '$mins:${secs.toString().padLeft(2, '0')}';
  }
}
