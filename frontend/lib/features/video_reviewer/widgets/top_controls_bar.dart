import 'package:flutter/material.dart';

class TopControlsBar extends StatelessWidget {
  const TopControlsBar({
    required this.directoryController,
    required this.includeReviewed,
    required this.isLoading,
    required this.indexText,
    required this.indexController,
    required this.onIncludeReviewedChanged,
    required this.onLoadPressed,
    required this.onGoPressed,
    required this.onSettingsPressed,
    super.key,
  });

  final TextEditingController directoryController;
  final bool includeReviewed;
  final bool isLoading;
  final String indexText;
  final TextEditingController indexController;
  final ValueChanged<bool> onIncludeReviewedChanged;
  final Future<void> Function() onLoadPressed;
  final Future<void> Function() onGoPressed;
  final VoidCallback onSettingsPressed;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 520,
            child: TextField(
              controller: directoryController,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Enter directory to view',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF232323),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Row(
            children: <Widget>[
              Checkbox(
                value: includeReviewed,
                onChanged: (bool? value) =>
                    onIncludeReviewedChanged(value ?? false),
              ),
              const Text('Include Reviewed'),
            ],
          ),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: isLoading ? null : onLoadPressed,
            child: Text(isLoading ? 'Loading...' : 'Load'),
          ),
          const SizedBox(width: 24),
          Container(
            width: 64,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFF111111),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              indexText,
              style: const TextStyle(
                color: Color(0xFFEDEDED),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 84,
            child: TextField(
              controller: indexController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Go to #',
                border: OutlineInputBorder(),
                filled: true,
                fillColor: Color(0xFF232323),
              ),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: onGoPressed, child: const Text('Go')),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onSettingsPressed,
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
          ),
        ],
      ),
    );
  }
}
