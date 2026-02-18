import 'package:flutter/material.dart';

class VideoListPane extends StatelessWidget {
  const VideoListPane({
    required this.files,
    required this.selectedIndex,
    required this.titleForPath,
    required this.onItemSelected,
    super.key,
  });

  final List<String> files;
  final int selectedIndex;
  final String Function(String path) titleForPath;
  final Future<void> Function(int index) onItemSelected;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF202020),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: const Center(
          child: Text(
            'Load a directory to see videos.',
            style: TextStyle(color: Color(0xFFB0B0B0)),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(10),
        itemCount: files.length,
        itemBuilder: (BuildContext context, int index) {
          final bool isSelected = index == selectedIndex;
          return InkWell(
            onTap: () => onItemSelected(index),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    height: 108,
                    decoration: BoxDecoration(
                      color: const Color(0xFF111111),
                      border: Border.all(
                        color: isSelected
                            ? const Color(0xFF4C8DFF)
                            : const Color(0xFF3A3A3A),
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.play_circle_fill,
                        color: Color(0xFFB0B0B0),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    titleForPath(files[index]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFEDEDED),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
