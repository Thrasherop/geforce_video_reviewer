import 'package:flutter/material.dart';

class MergingTab extends StatelessWidget {
  const MergingTab({
    required this.selectedPaths,
    required this.titleForPath,
    required this.thumbnailUriForPath,
    required this.outputNameController,
    required this.isBusy,
    required this.onMoveLeftPressed,
    required this.onMoveRightPressed,
    required this.onRemovePressed,
    required this.onMergeKeepPressed,
    required this.onMergeArchivePressed,
    super.key,
  });

  final List<String> selectedPaths;
  final String Function(String path) titleForPath;
  final Uri Function(String path) thumbnailUriForPath;
  final TextEditingController outputNameController;
  final bool isBusy;
  final Future<void> Function(int index) onMoveLeftPressed;
  final Future<void> Function(int index) onMoveRightPressed;
  final Future<void> Function(int index) onRemovePressed;
  final Future<void> Function() onMergeKeepPressed;
  final Future<void> Function() onMergeArchivePressed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: outputNameController,
      builder: (BuildContext context, TextEditingValue value, Widget? child) {
        final bool canSubmit = !isBusy &&
            selectedPaths.length >= 2 &&
            value.text.trim().isNotEmpty;

        return SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: outputNameController,
                  decoration: const InputDecoration(
                    hintText: 'Merged file name',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Color(0xFF232323),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: List<Widget>.generate(3, (int index) {
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: index < 2 ? 10 : 0),
                        child: _buildClipSlot(context, index),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: <Widget>[
                    FilledButton(
                      onPressed: canSubmit ? onMergeKeepPressed : null,
                      child: const Text('Merge and keep originals'),
                    ),
                    FilledButton(
                      onPressed: canSubmit ? onMergeArchivePressed : null,
                      child: const Text('Merge and archive originals'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildClipSlot(BuildContext context, int index) {
    if (index >= selectedPaths.length) {
      return Container(
        height: 172,
        decoration: BoxDecoration(
          color: const Color(0xFF181818),
          border: Border.all(color: const Color(0xFF4A4A4A)),
        ),
        alignment: Alignment.center,
        child: const Icon(Icons.add, color: Color(0xFFB0B0B0), size: 32),
      );
    }

    final String path = selectedPaths[index];
    final bool canMoveLeft = !isBusy && index > 0;
    final bool canMoveRight = !isBusy && index < selectedPaths.length - 1;
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E1E),
        border: Border.all(color: const Color(0xFF4A4A4A)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 104,
            width: double.infinity,
            child: Image.network(
              thumbnailUriForPath(path).toString(),
              fit: BoxFit.cover,
              errorBuilder:
                  (BuildContext context, Object error, StackTrace? stackTrace) {
                    return const ColoredBox(
                      color: Color(0xFF111111),
                      child: Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          color: Color(0xFFB0B0B0),
                        ),
                      ),
                    );
                  },
            ),
          ),
          const SizedBox(height: 8),
          Text(
            titleForPath(path),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFEDEDED)),
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: IconButton(
                  onPressed: canMoveLeft ? () => onMoveLeftPressed(index) : null,
                  icon: const Icon(Icons.arrow_left),
                  tooltip: 'Move left',
                ),
              ),
              Expanded(
                child: IconButton(
                  onPressed: canMoveRight ? () => onMoveRightPressed(index) : null,
                  icon: const Icon(Icons.arrow_right),
                  tooltip: 'Move right',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              onPressed: isBusy ? null : () => onRemovePressed(index),
              child: const Text('Remove'),
            ),
          ),
        ],
      ),
    );
  }
}
