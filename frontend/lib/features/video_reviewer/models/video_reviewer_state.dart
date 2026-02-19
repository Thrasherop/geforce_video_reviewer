import 'package:flutter/material.dart';

class VideoReviewerState {
  const VideoReviewerState({
    required this.includeReviewed,
    required this.isLoadingFiles,
    required this.isSubmittingAction,
    required this.leftPaneProportion,
    required this.files,
    required this.currentIndex,
    required this.trimRange,
  });

  factory VideoReviewerState.initial() {
    return const VideoReviewerState(
      includeReviewed: false,
      isLoadingFiles: false,
      isSubmittingAction: false,
      leftPaneProportion: 0.42,
      files: <String>[],
      currentIndex: -1,
      trimRange: RangeValues(0, 0),
    );
  }

  final bool includeReviewed;
  final bool isLoadingFiles;
  final bool isSubmittingAction;
  final double leftPaneProportion;
  final List<String> files;
  final int currentIndex;
  final RangeValues trimRange;

  String? get currentPath {
    if (currentIndex < 0 || currentIndex >= files.length) {
      return null;
    }
    return files[currentIndex];
  }

  VideoReviewerState copyWith({
    bool? includeReviewed,
    bool? isLoadingFiles,
    bool? isSubmittingAction,
    double? leftPaneProportion,
    List<String>? files,
    int? currentIndex,
    RangeValues? trimRange,
  }) {
    return VideoReviewerState(
      includeReviewed: includeReviewed ?? this.includeReviewed,
      isLoadingFiles: isLoadingFiles ?? this.isLoadingFiles,
      isSubmittingAction: isSubmittingAction ?? this.isSubmittingAction,
      leftPaneProportion: leftPaneProportion ?? this.leftPaneProportion,
      files: files ?? this.files,
      currentIndex: currentIndex ?? this.currentIndex,
      trimRange: trimRange ?? this.trimRange,
    );
  }
}
