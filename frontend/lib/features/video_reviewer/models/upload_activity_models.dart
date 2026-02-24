import 'dart:collection';

class UploadFileState {
  const UploadFileState({
    required this.filePath,
    required this.state,
    required this.percent,
    required this.message,
    this.error,
    required this.updatedAt,
  });

  final String filePath;
  final String state;
  final int percent;
  final String message;
  final String? error;
  final DateTime updatedAt;

  bool get isTerminal => state == 'success' || state == 'error';

  UploadFileState copyWith({
    String? filePath,
    String? state,
    int? percent,
    String? message,
    String? error,
    bool clearError = false,
    DateTime? updatedAt,
  }) {
    return UploadFileState(
      filePath: filePath ?? this.filePath,
      state: state ?? this.state,
      percent: percent ?? this.percent,
      message: message ?? this.message,
      error: clearError ? null : (error ?? this.error),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class UploadJobState {
  const UploadJobState({
    required this.jobId,
    required this.createdAt,
    required this.isComplete,
    required this.totalFiles,
    required this.finishedFiles,
    required this.overallPercent,
    required this.summaryMessage,
    required this.filesByPath,
    this.completedAt,
  });

  final String jobId;
  final DateTime createdAt;
  final bool isComplete;
  final int totalFiles;
  final int finishedFiles;
  final int overallPercent;
  final String summaryMessage;
  final DateTime? completedAt;
  final Map<String, UploadFileState> filesByPath;

  UnmodifiableListView<UploadFileState> get files =>
      UnmodifiableListView<UploadFileState>(filesByPath.values.toList());

  int get successCount =>
      filesByPath.values.where((UploadFileState item) => item.state == 'success').length;
  int get errorCount =>
      filesByPath.values.where((UploadFileState item) => item.state == 'error').length;
  int get uploadingCount => filesByPath
      .values
      .where((UploadFileState item) => item.state == 'uploading')
      .length;
  int get queuedCount =>
      filesByPath.values.where((UploadFileState item) => item.state == 'queued').length;

  UploadJobState copyWith({
    String? jobId,
    DateTime? createdAt,
    bool? isComplete,
    int? totalFiles,
    int? finishedFiles,
    int? overallPercent,
    String? summaryMessage,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    Map<String, UploadFileState>? filesByPath,
  }) {
    return UploadJobState(
      jobId: jobId ?? this.jobId,
      createdAt: createdAt ?? this.createdAt,
      isComplete: isComplete ?? this.isComplete,
      totalFiles: totalFiles ?? this.totalFiles,
      finishedFiles: finishedFiles ?? this.finishedFiles,
      overallPercent: overallPercent ?? this.overallPercent,
      summaryMessage: summaryMessage ?? this.summaryMessage,
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      filesByPath: filesByPath ?? this.filesByPath,
    );
  }
}
