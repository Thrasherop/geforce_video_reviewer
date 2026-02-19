import 'package:flutter/material.dart';

class HorizontalSplitHandle extends StatelessWidget {
  const HorizontalSplitHandle({super.key, required this.onDragDelta});

  final ValueChanged<double> onDragDelta;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (DragUpdateDetails details) {
          onDragDelta(details.delta.dx);
        },
        child: SizedBox(
          width: 14,
          child: Center(
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: const Color(0xFF4A4A4A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
