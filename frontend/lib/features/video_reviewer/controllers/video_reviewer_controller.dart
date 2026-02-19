import 'package:flutter/material.dart';

import '../models/video_reviewer_state.dart';
import '../services/split_pane_preferences_store.dart';
import '../services/video_reviewer_api_service.dart';
import '../utils/video_path_utils.dart';
import 'merging_controller.dart';

class VideoReviewerController extends ChangeNotifier {
  VideoReviewerController({
    required VideoReviewerApiService apiService,
    required SplitPanePreferencesStore splitPanePreferencesStore,
    required MergingController mergingController,
  }) : _apiService = apiService,
       _splitPanePreferencesStore = splitPanePreferencesStore,
       _mergingController = mergingController;

  final VideoReviewerApiService _apiService;
  final SplitPanePreferencesStore _splitPanePreferencesStore;
  final MergingController _mergingController;

  VideoReviewerState _state = VideoReviewerState.initial();
  VideoReviewerState get state => _state;

  String? get currentPath => _state.currentPath;

  void setIncludeReviewed(bool value) {
    _state = _state.copyWith(includeReviewed: value);
    notifyListeners();
  }

  void setTrimRange(RangeValues values) {
    _state = _state.copyWith(trimRange: values);
    notifyListeners();
  }

  void setCurrentIndex(int index) {
    _state = _state.copyWith(currentIndex: index);
    notifyListeners();
  }

  Future<void> loadSavedSplitPaneProportion() async {
    try {
      final double? savedValue =
          await _splitPanePreferencesStore.loadLeftPaneProportion();
      if (savedValue == null || !savedValue.isFinite) {
        return;
      }
      _state = _state.copyWith(
        leftPaneProportion: savedValue.clamp(0.22, 0.72).toDouble(),
      );
      notifyListeners();
    } catch (error, stackTrace) {
      debugPrint('Failed to load split pane preference: $error\n$stackTrace');
    }
  }

  Future<void> updateLeftPaneProportion(double value) async {
    _state = _state.copyWith(leftPaneProportion: value.clamp(0.22, 0.72));
    notifyListeners();
    try {
      await _splitPanePreferencesStore.saveLeftPaneProportion(
        _state.leftPaneProportion,
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to save split pane preference: $error\n$stackTrace');
    }
  }

  Future<void> loadDirectory({
    required String directory,
    required void Function(String message) onError,
    required void Function(String message) onInfo,
    required Future<void> Function(int index) onLoadVideoAtIndex,
    required VoidCallback onNoSelection,
  }) async {
    final String dir = directory.trim();
    if (dir.isEmpty) {
      onError('Please enter a directory.');
      return;
    }

    _state = _state.copyWith(isLoadingFiles: true);
    notifyListeners();

    try {
      final VideoReviewerApiResult result = await _apiService.loadFiles(
        directory: dir,
        includeReviewed: _state.includeReviewed,
      );
      final Map<String, dynamic> json = result.json;

      if (result.hasError) {
        onError(result.errorOr('Failed to load files'));
        _state = _state.copyWith(isLoadingFiles: false);
        notifyListeners();
        return;
      }

      final List<String> nextFiles =
          ((json['files'] ?? <dynamic>[]) as List<dynamic>)
              .map((dynamic file) => file.toString())
              .toList();
      if (nextFiles.isEmpty) {
        onInfo('No videos found in this directory.');
      }

      _state = _state.copyWith(
        files: nextFiles,
        currentIndex: nextFiles.isEmpty ? -1 : 0,
        trimRange: const RangeValues(0, 0),
        isLoadingFiles: false,
      );
      _mergingController.clear();
      notifyListeners();

      if (_state.currentIndex >= 0) {
        await onLoadVideoAtIndex(_state.currentIndex);
      } else {
        onNoSelection();
      }
    } catch (_) {
      _state = _state.copyWith(isLoadingFiles: false);
      notifyListeners();
      onError('Error loading files.');
    }
  }

  Future<void> navigate(
    int delta, {
    required Future<void> Function(int index) onLoadVideoAtIndex,
  }) async {
    if (_state.files.isEmpty) {
      return;
    }
    final int target = _state.currentIndex + delta;
    if (target < 0 || target >= _state.files.length) {
      return;
    }
    await onLoadVideoAtIndex(target);
  }

  Future<void> jumpToIndex({
    required String indexInput,
    required void Function(String message) onError,
    required Future<void> Function(int index) onLoadVideoAtIndex,
    required VoidCallback onJumpInputConsumed,
  }) async {
    if (_state.files.isEmpty) {
      onError('Load a directory first.');
      return;
    }
    final int? parsed = int.tryParse(indexInput.trim());
    if (parsed == null || parsed < 1 || parsed > _state.files.length) {
      onError('Enter a number from 1 to ${_state.files.length}.');
      return;
    }
    onJumpInputConsumed();
    await onLoadVideoAtIndex(parsed - 1);
  }

  Future<void> submitActionAndRefresh({
    required Map<String, dynamic> payload,
    required String directoryInput,
    required void Function(String message) onError,
    required Future<void> Function(int index) onLoadVideoAtIndex,
    required VoidCallback onNoSelection,
  }) async {
    _state = _state.copyWith(isSubmittingAction: true);
    notifyListeners();

    try {
      final VideoReviewerApiResult result = await _apiService.submitAction(
        payload,
      );
      final Map<String, dynamic> json = result.json;
      if (result.hasError) {
        onError(result.errorOr('Action failed'));
        _state = _state.copyWith(isSubmittingAction: false);
        notifyListeners();
        return;
      }

      final String? preferredPath = (json['new_path'] ?? json['current_path'])
          ?.toString();
      final String pathForReload =
          preferredPath ?? payload['path']?.toString() ?? currentPath ?? '';
      final String directoryOverride = extractDirectoryPath(pathForReload);
      await _reloadFilesAndPreserveSelection(
        preferredPath: preferredPath,
        directoryInput: directoryInput,
        directoryOverride: directoryOverride.isEmpty ? null : directoryOverride,
        onError: onError,
        onLoadVideoAtIndex: onLoadVideoAtIndex,
        onNoSelection: onNoSelection,
      );
    } catch (_) {
      onError('Action failed.');
      _state = _state.copyWith(isSubmittingAction: false);
      notifyListeners();
    }
  }

  Future<void> submitHistoryAction({
    required String endpoint,
    required bool includeNewPathFallback,
    required String directoryInput,
    required void Function(String message) onError,
    required Future<void> Function(int index) onLoadVideoAtIndex,
    required VoidCallback onNoSelection,
  }) async {
    final String fallbackPath = currentPath ?? '';
    final String folderPath = extractDirectoryPath(fallbackPath).isNotEmpty
        ? extractDirectoryPath(fallbackPath)
        : directoryInput.trim();

    if (folderPath.isEmpty) {
      onError('Load a directory before using this action.');
      return;
    }

    _state = _state.copyWith(isSubmittingAction: true);
    notifyListeners();

    try {
      final VideoReviewerApiResult result = await _apiService.submitHistoryAction(
        endpoint: endpoint,
        directory: folderPath,
        path: fallbackPath,
      );
      final Map<String, dynamic> json = result.json;
      if (result.hasError) {
        onError(result.errorOr('History action failed'));
        _state = _state.copyWith(isSubmittingAction: false);
        notifyListeners();
        return;
      }

      final String? preferredPath =
          (json['current_path'] ??
                  (includeNewPathFallback ? json['new_path'] : null) ??
                  (fallbackPath.isEmpty ? null : fallbackPath))
              ?.toString();
      await _reloadFilesAndPreserveSelection(
        preferredPath: preferredPath,
        directoryInput: folderPath,
        directoryOverride: folderPath,
        onError: onError,
        onLoadVideoAtIndex: onLoadVideoAtIndex,
        onNoSelection: onNoSelection,
      );
    } catch (_) {
      onError('History action failed.');
      _state = _state.copyWith(isSubmittingAction: false);
      notifyListeners();
    }
  }

  Future<void> _reloadFilesAndPreserveSelection({
    required String? preferredPath,
    required String directoryInput,
    required void Function(String message) onError,
    required Future<void> Function(int index) onLoadVideoAtIndex,
    required VoidCallback onNoSelection,
    String? directoryOverride,
  }) async {
    final String directory = (directoryOverride ?? directoryInput).trim();
    if (directory.isEmpty) {
      onError('Directory is required for refresh.');
      _state = _state.copyWith(isSubmittingAction: false);
      notifyListeners();
      return;
    }

    final VideoReviewerApiResult result = await _apiService.loadFiles(
      directory: directory,
      includeReviewed: _state.includeReviewed,
    );
    final Map<String, dynamic> json = result.json;
    if (result.hasError) {
      onError(result.errorOr('Reload failed'));
      _state = _state.copyWith(isSubmittingAction: false);
      notifyListeners();
      return;
    }

    final List<String> nextFiles =
        ((json['files'] ?? <dynamic>[]) as List<dynamic>)
            .map((dynamic item) => item.toString())
            .toList();

    int nextIndex = -1;
    if (nextFiles.isNotEmpty) {
      if (preferredPath != null) {
        nextIndex = nextFiles.indexOf(preferredPath);
      }
      if (nextIndex < 0) {
        nextIndex = _state.currentIndex.clamp(0, nextFiles.length - 1);
      }
    }

    _state = _state.copyWith(
      files: nextFiles,
      currentIndex: nextIndex,
      isSubmittingAction: false,
    );
    _mergingController.retainOnlyExistingPaths(nextFiles);
    notifyListeners();

    if (nextIndex >= 0) {
      await onLoadVideoAtIndex(nextIndex);
    } else {
      onNoSelection();
    }
  }
}
