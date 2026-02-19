import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/video_reviewer_settings.dart';

class VideoReviewerSettingsStore {
  static const String _keyPrefix = 'video_reviewer.settings.';
  static const String _startPercentKey = '${_keyPrefix}default_start_percent';
  static const String _rewindSecondsKey = '${_keyPrefix}rewind_seconds';
  static const String _forwardSecondsKey = '${_keyPrefix}forward_seconds';
  static const String _confirmDeleteKey = '${_keyPrefix}confirm_before_delete';
  static const String _hotkeysJsonKey = '${_keyPrefix}hotkeys_json';

  Future<VideoReviewerSettings> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final VideoReviewerSettings defaults = VideoReviewerSettings.defaults();
    final String? hotkeysJson = prefs.getString(_hotkeysJsonKey);
    final Map<String, List<LogicalKeyboardKey>> hotkeys = _decodeHotkeys(
      hotkeysJson,
      defaults.hotkeysByAction,
    );

    return VideoReviewerSettings(
      defaultStartPositionPercent:
          prefs.getInt(_startPercentKey) ??
          defaults.defaultStartPositionPercent,
      rewindSeconds:
          prefs.getDouble(_rewindSecondsKey) ?? defaults.rewindSeconds,
      forwardSeconds:
          prefs.getDouble(_forwardSecondsKey) ?? defaults.forwardSeconds,
      confirmBeforeDelete:
          prefs.getBool(_confirmDeleteKey) ?? defaults.confirmBeforeDelete,
      hotkeysByAction: hotkeys,
    ).sanitized();
  }

  Future<void> save(VideoReviewerSettings settings) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final VideoReviewerSettings sanitized = settings.sanitized();

    await prefs.setInt(_startPercentKey, sanitized.defaultStartPositionPercent);
    await prefs.setDouble(_rewindSecondsKey, sanitized.rewindSeconds);
    await prefs.setDouble(_forwardSecondsKey, sanitized.forwardSeconds);
    await prefs.setBool(_confirmDeleteKey, sanitized.confirmBeforeDelete);
    await prefs.setString(
      _hotkeysJsonKey,
      jsonEncode(_encodeHotkeys(sanitized.hotkeysByAction)),
    );
  }

  Map<String, List<int>> _encodeHotkeys(
    Map<String, List<LogicalKeyboardKey>> hotkeysByAction,
  ) {
    final Map<String, List<int>> result = <String, List<int>>{};
    for (final String action in VideoReviewerHotkeyAction.all) {
      final List<LogicalKeyboardKey> keys =
          hotkeysByAction[action] ?? <LogicalKeyboardKey>[];
      final List<int> keyIds = keys
          .map((LogicalKeyboardKey key) => key.keyId)
          .toList();
      result[action] = keyIds;
    }
    return result;
  }

  Map<String, List<LogicalKeyboardKey>> _decodeHotkeys(
    String? sourceJson,
    Map<String, List<LogicalKeyboardKey>> fallback,
  ) {
    if (sourceJson == null || sourceJson.trim().isEmpty) {
      return fallback;
    }
    try {
      final dynamic decoded = jsonDecode(sourceJson);
      if (decoded is! Map<String, dynamic>) {
        return fallback;
      }

      final Map<String, List<LogicalKeyboardKey>> mapped =
          <String, List<LogicalKeyboardKey>>{};
      for (final String action in VideoReviewerHotkeyAction.all) {
        final dynamic rawList = decoded[action];
        if (rawList is! List<dynamic>) {
          mapped[action] = fallback[action] ?? <LogicalKeyboardKey>[];
          continue;
        }
        final List<LogicalKeyboardKey> keys = <LogicalKeyboardKey>[];
        for (final dynamic rawValue in rawList) {
          if (rawValue is! num) {
            continue;
          }
          final LogicalKeyboardKey? known = LogicalKeyboardKey.findKeyByKeyId(
            rawValue.toInt(),
          );
          if (known != null) {
            keys.add(known);
          }
        }
        mapped[action] = keys.isEmpty
            ? (fallback[action] ?? <LogicalKeyboardKey>[])
            : keys;
      }
      return mapped;
    } catch (_) {
      return fallback;
    }
  }
}
