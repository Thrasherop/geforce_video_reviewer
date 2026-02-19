import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class KeyBindConfig {
  const KeyBindConfig({
    this.rewindSeconds = 10,
    this.forwardSeconds = 3,
  });

  final double rewindSeconds;
  final double forwardSeconds;
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
    this.config = const KeyBindConfig(),
  });

  final KeyBindActions actions;
  final KeyBindConfig config;

  bool _isAttached = false;

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
    if (event is! KeyDownEvent) {
      return false;
    }
    if (_isTypingInInput()) {
      return false;
    }

    final bool ctrlPressed =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final bool shiftPressed = HardwareKeyboard.instance.isShiftPressed;
    final LogicalKeyboardKey key = event.logicalKey;

    if (key == LogicalKeyboardKey.keyK) {
      actions.togglePlayPause();
      return true;
    }
    if (key == LogicalKeyboardKey.keyJ) {
      actions.seekRelative(-config.rewindSeconds);
      return true;
    }
    if (key == LogicalKeyboardKey.keyL) {
      actions.seekRelative(config.forwardSeconds);
      return true;
    }
    if (key == LogicalKeyboardKey.delete && actions.hasSelectedFile()) {
      actions.submitDelete();
      return true;
    }
    if (ctrlPressed && key == LogicalKeyboardKey.keyZ && !shiftPressed) {
      actions.submitUndo();
      return true;
    }
    if (ctrlPressed && shiftPressed && key == LogicalKeyboardKey.keyZ) {
      actions.submitRedo();
      return true;
    }
    return false;
  }

  bool _isTypingInInput() {
    final BuildContext? focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext == null) {
      return false;
    }
    return focusContext.widget is EditableText;
  }
}
