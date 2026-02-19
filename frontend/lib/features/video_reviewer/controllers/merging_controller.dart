import 'package:flutter/material.dart';

import '../utils/video_path_utils.dart';

class MergingController extends ChangeNotifier {
  final TextEditingController outputNameController = TextEditingController();
  List<String> _selectedPaths = <String>[];

  List<String> get selectedPaths => List<String>.unmodifiable(_selectedPaths);

  bool get hasEnoughClipsToMerge => _selectedPaths.length >= 2;

  void disposeControllers() {
    outputNameController.dispose();
  }

  bool canAddPath(String path, {required bool isBusy}) {
    return !isBusy && !_selectedPaths.contains(path) && _selectedPaths.length < 3;
  }

  String? addPath(String path, {required bool isBusy}) {
    if (isBusy) {
      return null;
    }
    if (_selectedPaths.contains(path)) {
      return 'This clip is already selected for merge.';
    }
    if (_selectedPaths.length >= 3) {
      return 'You can select up to 3 clips.';
    }
    final String? previousFirstPath =
        _selectedPaths.isEmpty ? null : _selectedPaths.first;
    _selectedPaths = <String>[..._selectedPaths, path];
    _updateOutputName(previousFirstPath: previousFirstPath);
    notifyListeners();
    return null;
  }

  void clear() {
    _selectedPaths = <String>[];
    outputNameController.clear();
    notifyListeners();
  }

  void retainOnlyExistingPaths(List<String> availablePaths) {
    final String? previousFirstPath =
        _selectedPaths.isEmpty ? null : _selectedPaths.first;
    _selectedPaths = _selectedPaths.where(availablePaths.contains).take(3).toList();
    _updateOutputName(previousFirstPath: previousFirstPath);
    notifyListeners();
  }

  void removeAt(int index, {required bool isBusy}) {
    if (isBusy || index < 0 || index >= _selectedPaths.length) {
      return;
    }
    final String? previousFirstPath =
        _selectedPaths.isEmpty ? null : _selectedPaths.first;
    _selectedPaths = <String>[
      ..._selectedPaths.take(index),
      ..._selectedPaths.skip(index + 1),
    ];
    _updateOutputName(previousFirstPath: previousFirstPath);
    notifyListeners();
  }

  void moveLeft(int index, {required bool isBusy}) {
    if (isBusy || index <= 0 || index >= _selectedPaths.length) {
      return;
    }
    final String? previousFirstPath =
        _selectedPaths.isEmpty ? null : _selectedPaths.first;
    final List<String> nextPaths = <String>[..._selectedPaths];
    final String swap = nextPaths[index - 1];
    nextPaths[index - 1] = nextPaths[index];
    nextPaths[index] = swap;
    _selectedPaths = nextPaths;
    _updateOutputName(previousFirstPath: previousFirstPath);
    notifyListeners();
  }

  void moveRight(int index, {required bool isBusy}) {
    if (isBusy || index < 0 || index >= _selectedPaths.length - 1) {
      return;
    }
    final String? previousFirstPath =
        _selectedPaths.isEmpty ? null : _selectedPaths.first;
    final List<String> nextPaths = <String>[..._selectedPaths];
    final String swap = nextPaths[index + 1];
    nextPaths[index + 1] = nextPaths[index];
    nextPaths[index] = swap;
    _selectedPaths = nextPaths;
    _updateOutputName(previousFirstPath: previousFirstPath);
    notifyListeners();
  }

  String? validateForSubmit() {
    if (_selectedPaths.length < 2) {
      return 'Select at least 2 clips to merge.';
    }
    if (_selectedPaths.length > 3) {
      return 'You can only merge up to 3 clips.';
    }
    final Set<String> uniquePaths = _selectedPaths.toSet();
    if (uniquePaths.length != _selectedPaths.length) {
      return 'Duplicate clips cannot be merged together.';
    }
    final String newName = outputNameController.text.trim();
    if (newName.isEmpty) {
      return 'Merged file name cannot be empty.';
    }
    return null;
  }

  Map<String, dynamic> buildMergePayload({required bool archiveOriginals}) {
    return <String, dynamic>{
      'action': 'merge',
      'path': _selectedPaths[0],
      'paths': <String>[..._selectedPaths],
      'new_name': outputNameController.text.trim(),
      'archive_originals': archiveOriginals,
    };
  }

  String _defaultMergedNameForPath(String path) {
    return '${extractTitle(path)}_merged';
  }

  void _updateOutputName({String? previousFirstPath}) {
    final String currentText = outputNameController.text.trim();
    final String previousDefault = previousFirstPath == null
        ? ''
        : _defaultMergedNameForPath(previousFirstPath);
    final bool shouldUseDefault =
        currentText.isEmpty ||
        (previousFirstPath != null && currentText == previousDefault);

    if (_selectedPaths.isEmpty) {
      if (shouldUseDefault) {
        outputNameController.clear();
      }
      return;
    }

    if (!shouldUseDefault) {
      return;
    }
    outputNameController.text = _defaultMergedNameForPath(_selectedPaths.first);
  }
}
