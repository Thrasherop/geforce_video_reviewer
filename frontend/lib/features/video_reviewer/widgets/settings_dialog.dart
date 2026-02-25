import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/video_reviewer_settings.dart';

Future<VideoReviewerSettings?> showVideoReviewerSettingsDialog(
  BuildContext context, {
  required VideoReviewerSettings initialSettings,
}) {
  return showDialog<VideoReviewerSettings>(
    context: context,
    builder: (BuildContext dialogContext) {
      return SettingsDialog(initialSettings: initialSettings);
    },
  );
}

class SettingsDialog extends StatefulWidget {
  const SettingsDialog({required this.initialSettings, super.key});

  final VideoReviewerSettings initialSettings;

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late final TextEditingController _defaultStartPercentController;
  late final TextEditingController _rewindSecondsController;
  late final TextEditingController _forwardSecondsController;
  late bool _confirmBeforeDelete;
  late bool _seekOnStartSliderChange;
  late Map<String, List<LogicalKeyboardKey>> _hotkeysByAction;

  final FocusNode _captureFocusNode = FocusNode();
  String? _recordingAction;
  String? _validationError;

  static const Map<String, String> _actionLabels = <String, String>{
    VideoReviewerHotkeyAction.togglePlayPause: 'Toggle play/pause',
    VideoReviewerHotkeyAction.seekBackward: 'Seek backward',
    VideoReviewerHotkeyAction.seekForward: 'Seek forward',
    VideoReviewerHotkeyAction.deleteClip: 'Delete clip',
    VideoReviewerHotkeyAction.undo: 'Undo',
    VideoReviewerHotkeyAction.redo: 'Redo',
    VideoReviewerHotkeyAction.switchToTrimmingTab: 'Switch to Trimming tab',
    VideoReviewerHotkeyAction.switchToMergingTab: 'Switch to Merging tab',
    VideoReviewerHotkeyAction.switchToMigrationTab: 'Switch to Migration tab',
    VideoReviewerHotkeyAction.previousFile: 'Previous file (Trimming tab)',
    VideoReviewerHotkeyAction.nextFile: 'Next file (Trimming tab)',
  };

  @override
  void initState() {
    super.initState();
    _defaultStartPercentController = TextEditingController(
      text: widget.initialSettings.defaultStartPositionPercent.toString(),
    );
    _rewindSecondsController = TextEditingController(
      text: _formatNumber(widget.initialSettings.rewindSeconds),
    );
    _forwardSecondsController = TextEditingController(
      text: _formatNumber(widget.initialSettings.forwardSeconds),
    );
    _confirmBeforeDelete = widget.initialSettings.confirmBeforeDelete;
    _seekOnStartSliderChange = widget.initialSettings.seekOnStartSliderChange;
    _hotkeysByAction = <String, List<LogicalKeyboardKey>>{
      for (final String action in VideoReviewerHotkeyAction.all)
        action: List<LogicalKeyboardKey>.from(
          widget.initialSettings.hotkeysByAction[action] ??
              <LogicalKeyboardKey>[],
        ),
    };
  }

  @override
  void dispose() {
    _defaultStartPercentController.dispose();
    _rewindSecondsController.dispose();
    _forwardSecondsController.dispose();
    _captureFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _captureFocusNode,
      onKeyEvent: _onCaptureKeyEvent,
      child: AlertDialog(
        title: const Text('Settings'),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: _defaultStartPercentController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Default start position percent',
                    helperText: 'Integer from 0 to 100',
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: _rewindSecondsController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Backward skip seconds',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _forwardSecondsController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Forward skip seconds',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _confirmBeforeDelete,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Confirm before deleting'),
                  onChanged: (bool value) {
                    setState(() {
                      _confirmBeforeDelete = value;
                    });
                  },
                ),
                SwitchListTile(
                  value: _seekOnStartSliderChange,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Seek when start trim slider changes'),
                  onChanged: (bool value) {
                    setState(() {
                      _seekOnStartSliderChange = value;
                    });
                  },
                ),
                const SizedBox(height: 8),
                const Divider(height: 1),
                const SizedBox(height: 12),
                const Text(
                  'Hotkey rebinding',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...VideoReviewerHotkeyAction.all.map(_buildHotkeyRow),
                if (_recordingAction != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Recording "${_actionLabels[_recordingAction] ?? _recordingAction}" - press the desired keys together.',
                      style: const TextStyle(
                        color: Color(0xFFE7CC67),
                        fontSize: 12,
                      ),
                    ),
                  ),
                if (_validationError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      _validationError!,
                      style: const TextStyle(color: Color(0xFFE57373)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(onPressed: _saveAndClose, child: const Text('Save')),
        ],
      ),
    );
  }

  Widget _buildHotkeyRow(String action) {
    final List<LogicalKeyboardKey> combo =
        _hotkeysByAction[action] ?? <LogicalKeyboardKey>[];
    final bool isRecording = _recordingAction == action;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: <Widget>[
          SizedBox(width: 170, child: Text(_actionLabels[action] ?? action)),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF505050)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(_formatCombo(combo), overflow: TextOverflow.ellipsis),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: () {
              setState(() {
                _recordingAction = action;
                _validationError = null;
              });
              _captureFocusNode.requestFocus();
            },
            child: Text(isRecording ? 'Press keys...' : 'Rebind'),
          ),
          const SizedBox(width: 6),
          IconButton(
            onPressed: () {
              setState(() {
                _hotkeysByAction[action] = List<LogicalKeyboardKey>.from(
                  widget.initialSettings.hotkeysByAction[action] ??
                      <LogicalKeyboardKey>[],
                );
              });
            },
            tooltip: 'Reset to initial',
            icon: const Icon(Icons.replay),
          ),
        ],
      ),
    );
  }

  void _onCaptureKeyEvent(KeyEvent event) {
    if (_recordingAction == null || event is! KeyDownEvent) {
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      setState(() {
        _recordingAction = null;
      });
      return;
    }

    final Set<LogicalKeyboardKey> pressed = HardwareKeyboard
        .instance
        .logicalKeysPressed
        .map(_normalizeKey)
        .toSet();
    pressed.add(_normalizeKey(event.logicalKey));
    final List<LogicalKeyboardKey> normalized = _normalizeCombo(
      pressed.toList(),
    );
    if (normalized.isEmpty) {
      return;
    }

    setState(() {
      _hotkeysByAction[_recordingAction!] = normalized;
      _recordingAction = null;
      _validationError = null;
    });
  }

  void _saveAndClose() {
    final int? percent = int.tryParse(
      _defaultStartPercentController.text.trim(),
    );
    if (percent == null) {
      setState(() {
        _validationError = 'Default start position percent must be an integer.';
      });
      return;
    }
    final double? rewind = double.tryParse(
      _rewindSecondsController.text.trim(),
    );
    if (rewind == null) {
      setState(() {
        _validationError = 'Backward skip seconds must be a valid number.';
      });
      return;
    }
    final double? forward = double.tryParse(
      _forwardSecondsController.text.trim(),
    );
    if (forward == null) {
      setState(() {
        _validationError = 'Forward skip seconds must be a valid number.';
      });
      return;
    }

    final VideoReviewerSettings settings = VideoReviewerSettings(
      defaultStartPositionPercent: percent,
      rewindSeconds: rewind,
      forwardSeconds: forward,
      confirmBeforeDelete: _confirmBeforeDelete,
      seekOnStartSliderChange: _seekOnStartSliderChange,
      hotkeysByAction: _hotkeysByAction,
    ).sanitized();
    Navigator.of(context).pop(settings);
  }

  static List<LogicalKeyboardKey> _normalizeCombo(
    List<LogicalKeyboardKey> keys,
  ) {
    final Map<int, LogicalKeyboardKey> dedupedById =
        <int, LogicalKeyboardKey>{};
    for (final LogicalKeyboardKey key in keys) {
      final LogicalKeyboardKey normalized = _normalizeKey(key);
      dedupedById[normalized.keyId] = normalized;
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

  String _formatCombo(List<LogicalKeyboardKey> keys) {
    if (keys.isEmpty) {
      return 'Not set';
    }
    return _normalizeCombo(keys).map(_displayNameForKey).join(' + ');
  }

  String _displayNameForKey(LogicalKeyboardKey key) {
    if (key == LogicalKeyboardKey.control) {
      return 'Ctrl';
    }
    if (key == LogicalKeyboardKey.shift) {
      return 'Shift';
    }
    if (key == LogicalKeyboardKey.alt) {
      return 'Alt';
    }
    if (key == LogicalKeyboardKey.meta) {
      return 'Meta';
    }
    if ((key.keyLabel).trim().isNotEmpty) {
      return key.keyLabel.toUpperCase();
    }
    return key.debugName ?? 'Key ${key.keyId}';
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toString();
  }
}
