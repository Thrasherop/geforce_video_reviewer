import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models/video_reviewer_settings.dart';

class KeyBindConfig {
  const KeyBindConfig({
    this.rewindSeconds = 10,
    this.forwardSeconds = 3,
    this.hotkeysByAction = const <String, List<LogicalKeyboardKey>>{
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
  });

  final double rewindSeconds;
  final double forwardSeconds;
  final Map<String, List<LogicalKeyboardKey>> hotkeysByAction;
}

class KeyBindActions {
  const KeyBindActions({
    required this.togglePlayPause,
    required this.seekRelative,
    required this.submitDelete,
    required this.submitUndo,
    required this.submitRedo,
    required this.hasSelectedFile,
  });

  final Future<void> Function() togglePlayPause;
  final Future<void> Function(double deltaSeconds) seekRelative;
  final Future<void> Function() submitDelete;
  final Future<void> Function() submitUndo;
  final Future<void> Function() submitRedo;
  final bool Function() hasSelectedFile;
}

class KeyBindHandler {
  KeyBindHandler({
    required this.actions,
    KeyBindConfig config = const KeyBindConfig(),
  }) : _config = config;

  final KeyBindActions actions;
  KeyBindConfig _config;
  KeyBindConfig get config => _config;

  bool _isAttached = false;
  bool _isEnabled = true;

  void updateConfig(KeyBindConfig config) {
    _config = config;
  }

  void setEnabled(bool value) {
    _isEnabled = value;
  }

  void attach() {
    if (_isAttached) {
      return;
    }
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvent);
    _isAttached = true;
  }

  void detach() {
    if (!_isAttached) {
      return;
    }
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvent);
    _isAttached = false;
  }

  bool _handleGlobalKeyEvent(KeyEvent event) {
    if (!_isEnabled) {
      return false;
    }
    if (event is! KeyDownEvent) {
      return false;
    }
    if (_isTypingInInput()) {
      return false;
    }

    final Set<LogicalKeyboardKey> pressed = HardwareKeyboard
        .instance
        .logicalKeysPressed
        .map(_normalizeKey)
        .toSet();
    pressed.add(_normalizeKey(event.logicalKey));

    if (_matchesAction(VideoReviewerHotkeyAction.togglePlayPause, pressed)) {
      actions.togglePlayPause();
      return true;
    }
    if (_matchesAction(VideoReviewerHotkeyAction.seekBackward, pressed)) {
      actions.seekRelative(-_config.rewindSeconds);
      return true;
    }
    if (_matchesAction(VideoReviewerHotkeyAction.seekForward, pressed)) {
      actions.seekRelative(_config.forwardSeconds);
      return true;
    }
    if (_matchesAction(VideoReviewerHotkeyAction.deleteClip, pressed) &&
        actions.hasSelectedFile()) {
      actions.submitDelete();
      return true;
    }
    if (_matchesAction(VideoReviewerHotkeyAction.undo, pressed)) {
      actions.submitUndo();
      return true;
    }
    if (_matchesAction(VideoReviewerHotkeyAction.redo, pressed)) {
      actions.submitRedo();
      return true;
    }
    return false;
  }

  bool _isTypingInInput() {
    final FocusNode? primaryFocus = FocusManager.instance.primaryFocus;
    final BuildContext? focusContext = primaryFocus?.context;
    if (focusContext == null) {
      return false;
    }
    return focusContext.widget is EditableText ||
        focusContext.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  bool _matchesAction(String action, Set<LogicalKeyboardKey> pressedKeys) {
    final List<LogicalKeyboardKey> binding =
        _config.hotkeysByAction[action] ?? const <LogicalKeyboardKey>[];
    if (binding.isEmpty) {
      return false;
    }
    final Set<int> normalizedPressedIds = pressedKeys.map((
      LogicalKeyboardKey key,
    ) {
      return _normalizeKey(key).keyId;
    }).toSet();
    final Set<int> normalizedBindingIds = binding.map((LogicalKeyboardKey key) {
      return _normalizeKey(key).keyId;
    }).toSet();
    if (normalizedBindingIds.length != normalizedPressedIds.length) {
      return false;
    }
    return normalizedBindingIds.every(normalizedPressedIds.contains);
  }

  LogicalKeyboardKey _normalizeKey(LogicalKeyboardKey key) {
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
