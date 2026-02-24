import 'dart:math' as math;

import 'package:flutter/material.dart';

class VideoListPane extends StatelessWidget {
  static const double _gridPadding = 10;
  static const double _gridSpacing = 12;
  static const double _minTileWidth = 180;
  static const double _thumbnailHeight = 108;
  static const double _titleSpacing = 6;
  static const double _tileVerticalBuffer = 8;
  static const TextStyle _titleTextStyle = TextStyle(
    fontSize: 13,
    color: Color(0xFFEDEDED),
  );

  const VideoListPane({
    required this.files,
    required this.selectedIndex,
    required this.titleForPath,
    required this.thumbnailUriForPath,
    required this.onItemSelected,
    this.onOverlayIconPressed,
    this.overlayIconData = Icons.add,
    this.overlayEnabledForPath,
    this.overlayIconForPath,
    super.key,
  });

  final List<String> files;
  final int selectedIndex;
  final String Function(String path) titleForPath;
  final Uri Function(String path) thumbnailUriForPath;
  final Future<void> Function(int index) onItemSelected;
  final Future<void> Function(int index)? onOverlayIconPressed;
  final IconData overlayIconData;
  final bool Function(String path)? overlayEnabledForPath;
  final IconData Function(String path)? overlayIconForPath;

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

    final TextStyle resolvedTitleStyle = DefaultTextStyle.of(
      context,
    ).style.merge(_titleTextStyle);
    final TextPainter titlePainter = TextPainter(
      text: TextSpan(text: 'Sample', style: resolvedTitleStyle),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final double tileMainAxisExtent =
        _thumbnailHeight + _titleSpacing + titlePainter.height + _tileVerticalBuffer;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF202020),
        border: Border.all(color: const Color(0xFF3A3A3A)),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double contentWidth =
              (constraints.maxWidth - (_gridPadding * 2)).clamp(0, double.infinity);
          final int crossAxisCount = math.max(
            1,
            ((contentWidth + _gridSpacing) / (_minTileWidth + _gridSpacing)).floor(),
          );

          return GridView.builder(
            padding: const EdgeInsets.all(_gridPadding),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisSpacing: _gridSpacing,
              mainAxisSpacing: _gridSpacing,
              mainAxisExtent: tileMainAxisExtent,
              crossAxisCount: crossAxisCount,
            ),
            itemCount: files.length,
            itemBuilder: (BuildContext context, int index) {
              final bool isSelected = index == selectedIndex;
              final String path = files[index];
              final bool showOverlay = onOverlayIconPressed != null;
              final bool isOverlayEnabled =
                  overlayEnabledForPath?.call(path) ?? true;
              return InkWell(
                onTap: () => onItemSelected(index),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      height: _thumbnailHeight,
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                border: Border.all(
                                  color: isSelected
                                      ? const Color(0xFF4C8DFF)
                                      : const Color(0xFF3A3A3A),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: Image.network(
                                thumbnailUriForPath(path).toString(),
                                fit: BoxFit.cover,
                                errorBuilder:
                                    (
                                      BuildContext context,
                                      Object error,
                                      StackTrace? stackTrace,
                                    ) => _buildThumbnailFallback(),
                                loadingBuilder:
                                    (
                                      BuildContext context,
                                      Widget child,
                                      ImageChunkEvent? loadingProgress,
                                    ) {
                                      if (loadingProgress == null) {
                                        return child;
                                      }
                                      return _buildThumbnailFallback();
                                    },
                              ),
                            ),
                          ),
                          if (showOverlay)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: const Color(0xAA111111),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: IconButton(
                                  visualDensity: VisualDensity.compact,
                                  constraints: const BoxConstraints(
                                    minWidth: 32,
                                    minHeight: 32,
                                  ),
                                  iconSize: 20,
                                  onPressed: isOverlayEnabled
                                      ? () => onOverlayIconPressed?.call(index)
                                      : null,
                                  icon: Icon(
                                    overlayIconForPath?.call(path) ??
                                        overlayIconData,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: _titleSpacing),
                    Text(
                      titleForPath(path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _titleTextStyle,
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildThumbnailFallback() {
    return const ColoredBox(
      color: Color(0xFF111111),
      child: Center(
        child: Icon(
          Icons.play_circle_fill,
          color: Color(0xFFB0B0B0),
        ),
      ),
    );
  }
}
