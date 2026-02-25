import 'dart:async';
import 'dart:collection';

import 'package:flutter/material.dart';

import '../models/upload_activity_models.dart';
import '../services/video_reviewer_api_service.dart';
import '../utils/video_path_utils.dart';

class MigrationController extends ChangeNotifier {
  final TextEditingController uploadNameController = TextEditingController();

  List<String> _selectedPaths = <String>[];
  bool _madeForKids = false;
  String _visibilitySetting = 'unlisted';
  bool _isMigrationBusy = false;
  bool _isKeepLocalLoading = false;
  bool _isKeepLocalConsistent = false;
  bool? _keepLocalValue;
  int _keepLocalRequestId = 0;
  String _keepLocalSelectionKey = '';
  String? _lastAutoFilledUploadName;
  bool _isActivityPanelExpanded = false;
  List<UploadJobState> _uploadJobs = <UploadJobState>[];
  final Set<String> _expandedJobIds = <String>{};
  final Map<String, StreamSubscription<Map<String, dynamic>>>
  _uploadJobSubscriptions =
      <String, StreamSubscription<Map<String, dynamic>>>{};

  UnmodifiableListView<String> get selectedPaths =>
      UnmodifiableListView<String>(_selectedPaths);
  bool get madeForKids => _madeForKids;
  String get visibilitySetting => _visibilitySetting;
  bool get isMigrationBusy => _isMigrationBusy;
  bool get isKeepLocalLoading => _isKeepLocalLoading;
  bool get isKeepLocalConsistent => _isKeepLocalConsistent;
  bool? get keepLocalValue => _keepLocalValue;
  bool get isActivityPanelExpanded => _isActivityPanelExpanded;
  UnmodifiableListView<UploadJobState> get uploadJobs =>
      UnmodifiableListView<UploadJobState>(_uploadJobs);

  bool get uploadNameEnabled => _selectedPaths.length == 1;
  bool get isOperationInFlight => _isMigrationBusy || _isKeepLocalLoading;
  bool get isKeepLocalAvailable =>
      _selectedPaths.isNotEmpty && _isKeepLocalConsistent;

  void disposeControllers() {
    uploadNameController.dispose();
    for (final StreamSubscription<Map<String, dynamic>> subscription
        in _uploadJobSubscriptions.values) {
      subscription.cancel();
    }
    _uploadJobSubscriptions.clear();
  }

  void toggleActivityPanelExpanded() {
    _isActivityPanelExpanded = !_isActivityPanelExpanded;
    notifyListeners();
  }

  bool isJobExpanded(String jobId) => _expandedJobIds.contains(jobId);

  void toggleJobExpanded(String jobId) {
    if (_expandedJobIds.contains(jobId)) {
      _expandedJobIds.remove(jobId);
    } else {
      _expandedJobIds.add(jobId);
    }
    notifyListeners();
  }

  void setMadeForKids(bool value) {
    if (_madeForKids == value) {
      return;
    }
    _madeForKids = value;
    notifyListeners();
  }

  void setVisibilitySetting(String value) {
    final String normalized = value.trim().toLowerCase();
    if (normalized.isEmpty || _visibilitySetting == normalized) {
      return;
    }
    _visibilitySetting = normalized;
    notifyListeners();
  }

  bool isPathSelected(String path) => _selectedPaths.contains(path);

  Future<void> togglePathAtIndex({
    required int index,
    required List<String> files,
    required bool isBusy,
    required VideoReviewerApiService apiService,
    required void Function(String message) onError,
  }) async {
    if (index < 0 || index >= files.length || isBusy || isOperationInFlight) {
      return;
    }
    final String path = files[index];
    final bool alreadySelected = _selectedPaths.contains(path);
    if (alreadySelected) {
      _selectedPaths = _selectedPaths
          .where((String item) => item != path)
          .toList();
    } else {
      _selectedPaths = <String>[..._selectedPaths, path];
    }
    notifyListeners();

    final String currentUploadName = uploadNameController.text.trim();
    final bool wasAutoFilled =
        _lastAutoFilledUploadName != null &&
        currentUploadName == _lastAutoFilledUploadName;
    final bool shouldAutoFill = _selectedPaths.length == 1 &&
        (currentUploadName.isEmpty || wasAutoFilled);

    if (shouldAutoFill) {
      final String nextAutoName = extractTitle(_selectedPaths.first);
      uploadNameController.text = nextAutoName;
      _lastAutoFilledUploadName = nextAutoName;
    }

    await refreshKeepLocalStateForSelection(
      apiService: apiService,
      onError: onError,
    );
  }

  void retainOnlyExistingPaths({
    required List<String> availablePaths,
    required VideoReviewerApiService apiService,
    required void Function(String message) onError,
  }) {
    final Set<String> available = availablePaths.toSet();
    final List<String> retained = _selectedPaths.where(available.contains).toList();
    if (retained.length == _selectedPaths.length) {
      return;
    }
    _selectedPaths = retained;
    _keepLocalSelectionKey = '';
    notifyListeners();
    refreshKeepLocalStateForSelection(
      apiService: apiService,
      onError: onError,
      force: true,
    );
  }

  Future<void> submitUpload({
    required VideoReviewerApiService apiService,
    required bool archiveAfterUpload,
    required bool isBusy,
    required void Function(String message) onError,
    required void Function(String message) onInfo,
  }) async {
    if (_selectedPaths.isEmpty) {
      onError('Select at least one file for migration.');
      return;
    }
    if (isBusy || isOperationInFlight) {
      return;
    }

    final String? uploadName = uploadNameEnabled
        ? uploadNameController.text.trim()
        : null;

    _isMigrationBusy = true;
    notifyListeners();

    try {
      final VideoReviewerApiResult result = await apiService.submitMigrationUpload(
        targetFiles: _selectedPaths,
        migrateFiles: archiveAfterUpload,
        madeForKids: _madeForKids,
        visibilitySetting: _visibilitySetting,
        uploadName: uploadName,
      );
      if (result.hasError) {
        onError(result.errorOr('Migration upload failed.'));
        return;
      }

      final String jobId = (result.json['job_id'] ?? '').toString();
      if (jobId.isEmpty) {
        onInfo('Upload job started.');
      } else {
        _startUploadJob(
          apiService: apiService,
          jobId: jobId,
          totalFiles: (result.json['total_files'] as num?)?.toInt() ??
              _selectedPaths.length,
        );
        onInfo('Upload job started: $jobId');
      }
    } catch (_) {
      onError('Migration upload failed.');
    } finally {
      _isMigrationBusy = false;
      notifyListeners();
    }
  }

  Future<void> setKeepLocalForSelection({
    required bool designation,
    required VideoReviewerApiService apiService,
    required bool isBusy,
    required void Function(String message) onError,
  }) async {
    if (_selectedPaths.isEmpty || !_isKeepLocalConsistent) {
      return;
    }
    if (isBusy || isOperationInFlight) {
      return;
    }

    _isKeepLocalLoading = true;
    notifyListeners();

    try {
      final VideoReviewerApiResult result = await apiService.setKeepLocalDesignation(
        targetFiles: _selectedPaths,
        designation: designation,
      );
      if (result.hasError) {
        onError(result.errorOr('Failed to update keep-local value.'));
      } else {
        _keepLocalValue = designation;
      }
    } catch (_) {
      onError('Failed to update keep-local value.');
    } finally {
      await refreshKeepLocalStateForSelection(
        apiService: apiService,
        onError: onError,
        force: true,
      );
    }
  }

  Future<void> refreshKeepLocalStateForSelection({
    required VideoReviewerApiService apiService,
    required void Function(String message) onError,
    bool force = false,
  }) async {
    final List<String> selected = List<String>.from(_selectedPaths);
    if (selected.isEmpty) {
      _isKeepLocalLoading = false;
      _isKeepLocalConsistent = false;
      _keepLocalValue = null;
      _keepLocalSelectionKey = '';
      notifyListeners();
      return;
    }

    selected.sort();
    final String selectionKey = selected.join('|');
    if (!force && selectionKey == _keepLocalSelectionKey) {
      return;
    }
    _keepLocalSelectionKey = selectionKey;
    final int requestId = ++_keepLocalRequestId;

    _isKeepLocalLoading = true;
    notifyListeners();

    try {
      final VideoReviewerApiResult result = await apiService.getKeepLocalStatuses(
        targetFiles: selected,
      );
      if (requestId != _keepLocalRequestId) {
        return;
      }

      if (result.hasError) {
        _isKeepLocalLoading = false;
        _isKeepLocalConsistent = false;
        _keepLocalValue = null;
        notifyListeners();
        onError(result.errorOr('Failed to load keep-local values.'));
        return;
      }

      final List<bool> values = <bool>[];
      for (final String path in selected) {
        final dynamic rawValue = result.json[path];
        if (rawValue is bool) {
          values.add(rawValue);
        }
      }

      if (values.length != selected.length || values.isEmpty) {
        _isKeepLocalLoading = false;
        _isKeepLocalConsistent = false;
        _keepLocalValue = null;
        notifyListeners();
        return;
      }

      final bool sharedValue = values.first;
      _isKeepLocalLoading = false;
      _isKeepLocalConsistent = values.every((bool value) => value == sharedValue);
      _keepLocalValue = _isKeepLocalConsistent ? sharedValue : null;
      notifyListeners();
    } catch (_) {
      if (requestId != _keepLocalRequestId) {
        return;
      }
      _isKeepLocalLoading = false;
      _isKeepLocalConsistent = false;
      _keepLocalValue = null;
      notifyListeners();
      onError('Failed to load keep-local values.');
    }
  }

  void _startUploadJob({
    required VideoReviewerApiService apiService,
    required String jobId,
    required int totalFiles,
  }) {
    final UploadJobState newJob = UploadJobState(
      jobId: jobId,
      createdAt: DateTime.now(),
      isComplete: false,
      totalFiles: totalFiles,
      finishedFiles: 0,
      overallPercent: 0,
      summaryMessage: 'Queued',
      filesByPath: <String, UploadFileState>{},
    );
    _uploadJobs = <UploadJobState>[newJob, ..._uploadJobs];
    _expandedJobIds.add(jobId);
    notifyListeners();

    _uploadJobSubscriptions[jobId]?.cancel();
    final StreamSubscription<Map<String, dynamic>> subscription = apiService
        .streamMigrationUploadStatus(jobId: jobId)
        .listen(
          (Map<String, dynamic> event) {
            _applyUploadEvent(jobId, event);
          },
          onError: (Object error) {
            _markJobStreamError(jobId, error.toString());
          },
          onDone: () {
            _uploadJobSubscriptions.remove(jobId);
            _completeJobIfFinished(jobId);
          },
          cancelOnError: false,
        );
    _uploadJobSubscriptions[jobId] = subscription;
  }

  void _applyUploadEvent(String jobId, Map<String, dynamic> event) {
    final int jobIndex = _uploadJobs.indexWhere(
      (UploadJobState item) => item.jobId == jobId,
    );
    if (jobIndex < 0) {
      return;
    }
    final UploadJobState job = _uploadJobs[jobIndex];

    final String state = (event['state'] ?? '').toString();
    final String message = (event['message'] ?? '').toString();
    final int? eventTotalFiles = (event['total_files'] as num?)?.toInt();
    final int? eventFinishedFiles = (event['finished_files'] as num?)?.toInt();
    final Map<String, UploadFileState> nextFiles = Map<String, UploadFileState>.from(
      job.filesByPath,
    );

    final String filePath = (event['file_path'] ?? '').toString();
    if (filePath.isNotEmpty) {
      final int rawPercent = (event['percent'] as num?)?.toInt() ?? 0;
      final UploadFileState nextFile = UploadFileState(
        filePath: filePath,
        state: state.isEmpty ? 'queued' : state,
        percent: rawPercent.clamp(0, 100),
        message: message,
        error: event['error']?.toString(),
        updatedAt: DateTime.now(),
      );
      nextFiles[filePath] = nextFile;
    }

    final int totalFiles = eventTotalFiles ?? job.totalFiles;
    final int terminalCount = nextFiles.values
        .where((UploadFileState file) => file.isTerminal)
        .length;
    final int finishedFiles = eventFinishedFiles ?? terminalCount;
    final bool completeFromEvent = state == 'complete';
    final bool isComplete = completeFromEvent ||
        (totalFiles > 0 && finishedFiles >= totalFiles);

    final int overallPercent = _computeOverallPercent(
      totalFiles: totalFiles,
      finishedFiles: finishedFiles,
      filesByPath: nextFiles,
      isComplete: isComplete,
    );
    final UploadJobState updatedJob = job.copyWith(
      filesByPath: nextFiles,
      totalFiles: totalFiles,
      finishedFiles: finishedFiles,
      isComplete: isComplete,
      overallPercent: overallPercent,
      summaryMessage: message.isEmpty ? job.summaryMessage : message,
      completedAt: isComplete ? DateTime.now() : null,
      clearCompletedAt: !isComplete,
    );

    _uploadJobs = <UploadJobState>[
      ..._uploadJobs.take(jobIndex),
      updatedJob,
      ..._uploadJobs.skip(jobIndex + 1),
    ];
    notifyListeners();
  }

  int _computeOverallPercent({
    required int totalFiles,
    required int finishedFiles,
    required Map<String, UploadFileState> filesByPath,
    required bool isComplete,
  }) {
    if (isComplete) {
      return 100;
    }
    final int denominator = totalFiles > filesByPath.length
        ? totalFiles
        : filesByPath.length;
    if (denominator <= 0) {
      return 0;
    }
    final int summedPercent = filesByPath.values.fold(
      0,
      (int sum, UploadFileState file) => sum + file.percent,
    );
    final int avgPercent = (summedPercent / denominator).round();
    final int finishedRatioPercent = totalFiles <= 0
        ? 0
        : ((finishedFiles / totalFiles) * 100).round();
    return avgPercent > finishedRatioPercent ? avgPercent : finishedRatioPercent;
  }

  void _markJobStreamError(String jobId, String error) {
    final int jobIndex = _uploadJobs.indexWhere(
      (UploadJobState item) => item.jobId == jobId,
    );
    if (jobIndex < 0) {
      return;
    }
    final UploadJobState job = _uploadJobs[jobIndex];
    final UploadJobState updatedJob = job.copyWith(
      summaryMessage: 'Status stream error: $error',
      isComplete: true,
      overallPercent: 100,
      completedAt: DateTime.now(),
    );
    _uploadJobs = <UploadJobState>[
      ..._uploadJobs.take(jobIndex),
      updatedJob,
      ..._uploadJobs.skip(jobIndex + 1),
    ];
    notifyListeners();
  }

  void _completeJobIfFinished(String jobId) {
    final int jobIndex = _uploadJobs.indexWhere(
      (UploadJobState item) => item.jobId == jobId,
    );
    if (jobIndex < 0) {
      return;
    }
    final UploadJobState job = _uploadJobs[jobIndex];
    if (job.isComplete) {
      return;
    }
    final bool allTerminal = job.filesByPath.isNotEmpty &&
        job.filesByPath.values.every((UploadFileState file) => file.isTerminal);
    if (!allTerminal) {
      return;
    }
    final UploadJobState updatedJob = job.copyWith(
      isComplete: true,
      overallPercent: 100,
      finishedFiles: job.totalFiles > 0 ? job.totalFiles : job.filesByPath.length,
      completedAt: DateTime.now(),
      summaryMessage: 'All files finished',
    );
    _uploadJobs = <UploadJobState>[
      ..._uploadJobs.take(jobIndex),
      updatedJob,
      ..._uploadJobs.skip(jobIndex + 1),
    ];
    notifyListeners();
  }
}
