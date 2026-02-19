import 'package:flutter/services.dart';

class VideoReviewerHotkeyAction {
  static const String togglePlayPause = 'togglePlayPause';
  static const String seekBackward = 'seekBackward';
  static const String seekForward = 'seekForward';
  static const String deleteClip = 'deleteClip';
  static const String undo = 'undo';
  static const String redo = 'redo';

  static const List<String> all = <String>[
    togglePlayPause,
    seekBackward,
    seekForward,
    deleteClip,
    undo,
    redo,
  ];
}

class VideoReviewerSettings {
  const VideoReviewerSettings({
    required this.defaultStartPositionPercent,
    required this.rewindSeconds,
    required this.forwardSeconds,
    required this.confirmBeforeDelete,
    required this.hotkeysByAction,
  });

  final int defaultStartPositionPercent;
  final double rewindSeconds;
  final double forwardSeconds;
  final bool confirmBeforeDelete;
  final Map<String, List<LogicalKeyboardKey>> hotkeysByAction;

  factory VideoReviewerSettings.defaults() {
    return VideoReviewerSettings(
      defaultStartPositionPercent: 70,
      rewindSeconds: 10,
      forwardSeconds: 3,
      confirmBeforeDelete: true,
      hotkeysByAction: <String, List<LogicalKeyboardKey>>{
        VideoReviewerHotkeyAction.togglePlayPause: <LogicalKeyboardKey>[
          LogicalKeyboardKey.keyK,
        ],
        VideoReviewerHotkeyAction.seekBackward: <LogicalKeyboardKey>[
          LogicalKeyboardKey.keyJ,
        ],
        VideoReviewerHotkeyAction.seekForward: <LogicalKeyboardKey>[
          LogicalKeyboardKey.keyL,
        ],
        VideoReviewerHotkeyAction.deleteClip: <LogicalKeyboardKey>[
          LogicalKeyboardKey.delete,
        ],
        VideoReviewerHotkeyAction.undo: <LogicalKeyboardKey>[
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyZ,
        ],
        VideoReviewerHotkeyAction.redo: <LogicalKeyboardKey>[
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyZ,
        ],
      },
    ).sanitized();
  }

  VideoReviewerSettings copyWith({
    int? defaultStartPositionPercent,
    double? rewindSeconds,
    double? forwardSeconds,
    bool? confirmBeforeDelete,
    Map<String, List<LogicalKeyboardKey>>? hotkeysByAction,
  }) {
    return VideoReviewerSettings(
      defaultStartPositionPercent:
          defaultStartPositionPercent ?? this.defaultStartPositionPercent,
      rewindSeconds: rewindSeconds ?? this.rewindSeconds,
      forwardSeconds: forwardSeconds ?? this.forwardSeconds,
      confirmBeforeDelete: confirmBeforeDelete ?? this.confirmBeforeDelete,
      hotkeysByAction: hotkeysByAction ?? this.hotkeysByAction,
    ).sanitized();
  }

  VideoReviewerSettings sanitized() {
    final VideoReviewerSettings defaults = VideoReviewerSettings.defaultsRaw();
    final Map<String, List<LogicalKeyboardKey>> normalized =
        <String, List<LogicalKeyboardKey>>{};
    for (final String action in VideoReviewerHotkeyAction.all) {
      normalized[action] = _normalizeCombo(
        hotkeysByAction[action] ?? defaults.hotkeysByAction[action]!,
      );
    }
    return VideoReviewerSettings.defaultsRaw().copyWithRaw(
      defaultStartPositionPercent: defaultStartPositionPercent.clamp(0, 100),
      rewindSeconds: _sanitizeSeconds(rewindSeconds, defaults.rewindSeconds),
      forwardSeconds: _sanitizeSeconds(forwardSeconds, defaults.forwardSeconds),
      confirmBeforeDelete: confirmBeforeDelete,
      hotkeysByAction: normalized,
    );
  }

  List<int> hotkeyIdsForAction(String action) {
    return _normalizeCombo(
      hotkeysByAction[action] ?? const <LogicalKeyboardKey>[],
    ).map((LogicalKeyboardKey key) => key.keyId).toList();
  }

  static VideoReviewerSettings defaultsRaw() {
    return VideoReviewerSettings(
      defaultStartPositionPercent: 70,
      rewindSeconds: 10,
      forwardSeconds: 3,
      confirmBeforeDelete: true,
      hotkeysByAction: <String, List<LogicalKeyboardKey>>{
        VideoReviewerHotkeyAction.togglePlayPause: <LogicalKeyboardKey>[
          LogicalKeyboardKey.keyK,
        ],
        VideoReviewerHotkeyAction.seekBackward: <LogicalKeyboardKey>[
          LogicalKeyboardKey.keyJ,
        ],
        VideoReviewerHotkeyAction.seekForward: <LogicalKeyboardKey>[
          LogicalKeyboardKey.keyL,
        ],
        VideoReviewerHotkeyAction.deleteClip: <LogicalKeyboardKey>[
          LogicalKeyboardKey.delete,
        ],
        VideoReviewerHotkeyAction.undo: <LogicalKeyboardKey>[
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.keyZ,
        ],
        VideoReviewerHotkeyAction.redo: <LogicalKeyboardKey>[
          LogicalKeyboardKey.control,
          LogicalKeyboardKey.shift,
          LogicalKeyboardKey.keyZ,
        ],
      },
    );
  }

  VideoReviewerSettings copyWithRaw({
    required int defaultStartPositionPercent,
    required double rewindSeconds,
    required double forwardSeconds,
    required bool confirmBeforeDelete,
    required Map<String, List<LogicalKeyboardKey>> hotkeysByAction,
  }) {
    return VideoReviewerSettings(
      defaultStartPositionPercent: defaultStartPositionPercent,
      rewindSeconds: rewindSeconds,
      forwardSeconds: forwardSeconds,
      confirmBeforeDelete: confirmBeforeDelete,
      hotkeysByAction: hotkeysByAction,
    );
  }

  static double _sanitizeSeconds(double value, double fallback) {
    if (!value.isFinite || value < 0) {
      return fallback;
    }
    return value;
  }

  static List<LogicalKeyboardKey> _normalizeCombo(
    List<LogicalKeyboardKey> keys,
  ) {
    final Map<int, LogicalKeyboardKey> dedupedById =
        <int, LogicalKeyboardKey>{};
    for (final LogicalKeyboardKey key in keys) {
      dedupedById[_normalizeKey(key).keyId] = _normalizeKey(key);
    }
    final List<LogicalKeyboardKey> sorted = dedupedById.values.toList()
      ..sort(
        (LogicalKeyboardKey a, LogicalKeyboardKey b) =>
            a.keyId.compareTo(b.keyId),
      );
    return sorted;
  }

  static LogicalKeyboardKey _normalizeKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight) {
      return LogicalKeyboardKey.shift;
    }
    if (key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight) {
      return LogicalKeyboardKey.control;
    }
    if (key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight) {
      return LogicalKeyboardKey.alt;
    }
    if (key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight) {
      return LogicalKeyboardKey.meta;
    }
    return key;
  }
}
