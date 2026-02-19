import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'key_bind_handler.dart';
import 'models/video_reviewer_settings.dart';
import 'services/split_pane_preferences_store.dart';
import 'services/video_reviewer_api_service.dart';
import 'services/video_reviewer_settings_store.dart';
import 'utils/time_format_utils.dart';
import 'utils/trim_utils.dart';
import 'utils/video_path_utils.dart';
import 'widgets/horizontal_split_handle.dart';
import 'widgets/placeholder_tab_content.dart';
import 'widgets/settings_dialog.dart';
import 'widgets/top_controls_bar.dart';
import 'widgets/trimming_tab.dart';
import 'widgets/video_list_pane.dart';
import 'widgets/video_player_pane.dart';

class VideoReviewerPage extends StatefulWidget {
  const VideoReviewerPage({super.key});

  @override
  State<VideoReviewerPage> createState() => _VideoReviewerPageState();
}

class _VideoReviewerPageState extends State<VideoReviewerPage> {
  final TextEditingController _directoryController = TextEditingController();
  final TextEditingController _indexController = TextEditingController();
  final TextEditingController _newFileNameController = TextEditingController();

  bool _includeReviewed = false;
  bool _isLoadingFiles = false;
  bool _isSubmittingAction = false;
  double _leftPaneProportion = 0.42;

  List<String> _files = <String>[];
  int _currentIndex = -1;
  RangeValues _trimRange = const RangeValues(0, 0);

  VideoPlayerController? _videoController;
  Future<void>? _videoInitFuture;
  final GlobalKey<VideoPlayerPaneState> _videoPlayerPaneKey =
      GlobalKey<VideoPlayerPaneState>();
  late final KeyBindHandler _keyBindHandler;
  final VideoReviewerSettingsStore _settingsStore =
      VideoReviewerSettingsStore();
  final SplitPanePreferencesStore _splitPanePrefsStore =
      SplitPanePreferencesStore();
  final VideoReviewerApiService _apiService = VideoReviewerApiService();
  VideoReviewerSettings _settings = VideoReviewerSettings.defaults();

  @override
  void initState() {
    super.initState();
    _keyBindHandler = KeyBindHandler(
      actions: KeyBindActions(
        togglePlayPause: () async {
          await _videoPlayerPaneKey.currentState?.togglePlayPause();
        },
        seekRelative: (double deltaSeconds) async {
          await _videoPlayerPaneKey.currentState?.seekRelative(deltaSeconds);
        },
        submitDelete: _submitDelete,
        submitUndo: _submitUndo,
        submitRedo: _submitRedo,
        hasSelectedFile: () => _currentPath != null,
      ),
      config: _keyBindConfigFromSettings(_settings),
    );
    _keyBindHandler.attach();
    _loadSavedSplitPaneProportion();
    _loadSettings();
  }

  @override
  void dispose() {
    _keyBindHandler.detach();
    _directoryController.dispose();
    _indexController.dispose();
    _newFileNameController.dispose();
    _disposeVideoController();
    super.dispose();
  }

  Future<void> _loadSavedSplitPaneProportion() async {
    try {
      final double? savedValue = await _splitPanePrefsStore
          .loadLeftPaneProportion();
      if (!mounted || savedValue == null || !savedValue.isFinite) {
        return;
      }
      setState(() {
        _leftPaneProportion = savedValue.clamp(0.22, 0.72).toDouble();
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load split pane preference: $error\n$stackTrace');
    }
  }

  Future<void> _loadSettings() async {
    try {
      final VideoReviewerSettings loaded = await _settingsStore.load();
      if (!mounted) {
        return;
      }
      setState(() {
        _settings = loaded;
      });
      _keyBindHandler.updateConfig(_keyBindConfigFromSettings(_settings));
    } catch (error, stackTrace) {
      debugPrint('Failed to load settings: $error\n$stackTrace');
    }
  }

  Future<void> _saveSettings(VideoReviewerSettings settings) async {
    try {
      await _settingsStore.save(settings);
    } catch (error, stackTrace) {
      debugPrint('Failed to save settings: $error\n$stackTrace');
    }
  }

  Future<void> _openSettingsDialog() async {
    _keyBindHandler.setEnabled(false);
    try {
      final VideoReviewerSettings? updated =
          await showVideoReviewerSettingsDialog(
            context,
            initialSettings: _settings,
          );
      if (updated == null || !mounted) {
        return;
      }
      final VideoReviewerSettings sanitized = updated.sanitized();
      setState(() {
        _settings = sanitized;
      });
      _keyBindHandler.updateConfig(_keyBindConfigFromSettings(_settings));
      await _saveSettings(sanitized);
    } finally {
      _keyBindHandler.setEnabled(true);
    }
  }

  KeyBindConfig _keyBindConfigFromSettings(VideoReviewerSettings settings) {
    return KeyBindConfig(
      rewindSeconds: settings.rewindSeconds,
      forwardSeconds: settings.forwardSeconds,
      hotkeysByAction: <String, List<LogicalKeyboardKey>>{
        for (final String action in VideoReviewerHotkeyAction.all)
          action: List<LogicalKeyboardKey>.from(
            settings.hotkeysByAction[action] ?? <LogicalKeyboardKey>[],
          ),
      },
    );
  }

  Future<void> _saveSplitPaneProportion() async {
    try {
      await _splitPanePrefsStore.saveLeftPaneProportion(_leftPaneProportion);
    } catch (error, stackTrace) {
      debugPrint('Failed to save split pane preference: $error\n$stackTrace');
    }
  }

  String? get _currentPath {
    if (_currentIndex < 0 || _currentIndex >= _files.length) {
      return null;
    }
    return _files[_currentIndex];
  }

  double get _videoDurationSeconds {
    final VideoPlayerController? controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return 0;
    }
    final Duration duration = controller.value.duration;
    return duration.inMilliseconds / 1000.0;
  }

  Future<void> _loadDirectory() async {
    final String dir = _directoryController.text.trim();
    if (dir.isEmpty) {
      _showSnackBar('Please enter a directory.');
      return;
    }

    setState(() {
      _isLoadingFiles = true;
    });

    try {
      final VideoReviewerApiResult result = await _apiService.loadFiles(
        directory: dir,
        includeReviewed: _includeReviewed,
      );
      final Map<String, dynamic> json = result.json;

      if (!mounted) {
        return;
      }

      if (result.hasError) {
        _showSnackBar(result.errorOr('Failed to load files'));
        setState(() {
          _isLoadingFiles = false;
        });
        return;
      }

      final List<String> nextFiles =
          ((json['files'] ?? <dynamic>[]) as List<dynamic>)
              .map((dynamic file) => file.toString())
              .toList();

      if (nextFiles.isEmpty) {
        _showSnackBar('No videos found in this directory.');
      }

      setState(() {
        _files = nextFiles;
        _currentIndex = nextFiles.isEmpty ? -1 : 0;
        _isLoadingFiles = false;
      });

      if (_currentIndex >= 0) {
        await _loadVideoAtIndex(_currentIndex);
      } else {
        _newFileNameController.clear();
        _disposeVideoController();
      }
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoadingFiles = false;
      });
      _showSnackBar('Error loading files.');
    }
  }

  Future<void> _loadVideoAtIndex(int index) async {
    if (index < 0 || index >= _files.length) {
      return;
    }

    final String path = _files[index];
    final String fileName = extractFileName(path);
    final String baseName = fileName.toLowerCase().endsWith('.mp4')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;

    setState(() {
      _currentIndex = index;
      _newFileNameController.text = baseName;
      _trimRange = const RangeValues(0, 0);
    });

    _disposeVideoController();

    final VideoPlayerController controller = VideoPlayerController.networkUrl(
      _apiService.videoUri(path),
    );
    _videoController = controller;
    _videoInitFuture = controller
        .initialize()
        .then((_) {
          if (!mounted || _videoController != controller) {
            return;
          }
          final double duration = _videoDurationSeconds;
          setState(() {
            _trimRange = clampTrimRange(RangeValues(0, duration), duration);
          });
          final Duration initialPosition = defaultStartPositionForDuration(
            duration,
            _settings.defaultStartPositionPercent.toDouble(),
          );
          controller.seekTo(initialPosition);
        })
        .catchError((_) {
          if (mounted) {
            _showSnackBar('Could not load this video.');
          }
        });

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _jumpToIndex() async {
    if (_files.isEmpty) {
      _showSnackBar('Load a directory first.');
      return;
    }
    final int? parsed = int.tryParse(_indexController.text.trim());
    if (parsed == null || parsed < 1 || parsed > _files.length) {
      _showSnackBar('Enter a number from 1 to ${_files.length}.');
      return;
    }
    _indexController.clear();
    await _loadVideoAtIndex(parsed - 1);
  }

  Future<void> _navigate(int delta) async {
    if (_files.isEmpty) {
      return;
    }
    final int target = _currentIndex + delta;
    if (target < 0 || target >= _files.length) {
      return;
    }
    await _loadVideoAtIndex(target);
  }

  Future<void> _submitRenameOnly() async {
    final String? currentPath = _currentPath;
    final String newName = _newFileNameController.text.trim();
    if (currentPath == null) {
      _showSnackBar('Select a file first.');
      return;
    }
    if (newName.isEmpty) {
      _showSnackBar('Name cannot be empty.');
      return;
    }
    await _callActionAndRefresh(<String, dynamic>{
      'action': 'rename',
      'path': currentPath,
      'new_name': newName,
    });
  }

  Future<void> _submitTrim() async {
    final String? currentPath = _currentPath;
    final String newName = _newFileNameController.text.trim();
    if (currentPath == null) {
      _showSnackBar('Select a file first.');
      return;
    }
    if (newName.isEmpty) {
      _showSnackBar('Name cannot be empty.');
      return;
    }
    if (_trimRange.end <= _trimRange.start) {
      _showSnackBar('Trim range is invalid.');
      return;
    }
    await _callActionAndRefresh(<String, dynamic>{
      'action': 'trim',
      'path': currentPath,
      'new_name': newName,
      'start': formatSeconds(_trimRange.start),
      'end': formatSeconds(_trimRange.end),
    });
  }

  Future<void> _submitDelete() async {
    final String? currentPath = _currentPath;
    if (currentPath == null) {
      _showSnackBar('Select a file first.');
      return;
    }

    if (_settings.confirmBeforeDelete) {
      final bool? confirmed = await showDialog<bool>(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Delete clip'),
            content: const Text('Are you sure you want to delete this clip?'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        return;
      }
    }

    await _callActionAndRefresh(<String, dynamic>{
      'action': 'delete',
      'path': currentPath,
    });
  }

  Future<void> _submitUndo() async {
    await _submitHistoryAction('/api/undo', includeNewPathFallback: false);
  }

  Future<void> _submitRedo() async {
    await _submitHistoryAction('/api/redo', includeNewPathFallback: true);
  }

  Future<void> _submitHistoryAction(
    String endpoint, {
    required bool includeNewPathFallback,
  }) async {
    final String fallbackPath = _currentPath ?? '';
    final String folderPath = extractDirectoryPath(fallbackPath).isNotEmpty
        ? extractDirectoryPath(fallbackPath)
        : _directoryController.text.trim();

    if (folderPath.isEmpty) {
      _showSnackBar('Load a directory before using this action.');
      return;
    }

    setState(() {
      _isSubmittingAction = true;
    });

    try {
      final VideoReviewerApiResult result = await _apiService.submitHistoryAction(
        endpoint: endpoint,
        directory: folderPath,
        path: fallbackPath,
      );
      final Map<String, dynamic> json = result.json;

      if (!mounted) {
        return;
      }

      if (result.hasError) {
        _showSnackBar(result.errorOr('History action failed'));
        setState(() {
          _isSubmittingAction = false;
        });
        return;
      }

      final String? preferredPath =
          (json['current_path'] ??
                  (includeNewPathFallback ? json['new_path'] : null) ??
                  (fallbackPath.isEmpty ? null : fallbackPath))
              ?.toString();
      await _reloadFilesAndPreserveSelection(
        preferredPath,
        directoryOverride: folderPath,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar('History action failed.');
      setState(() {
        _isSubmittingAction = false;
      });
    }
  }

  Future<void> _callActionAndRefresh(Map<String, dynamic> payload) async {
    setState(() {
      _isSubmittingAction = true;
    });

    try {
      final VideoReviewerApiResult result = await _apiService.submitAction(
        payload,
      );
      final Map<String, dynamic> json = result.json;

      if (!mounted) {
        return;
      }
      if (result.hasError) {
        _showSnackBar(result.errorOr('Action failed'));
        setState(() {
          _isSubmittingAction = false;
        });
        return;
      }

      final String? preferredPath = (json['new_path'] ?? json['current_path'])
          ?.toString();
      final String pathForReload =
          preferredPath ?? payload['path']?.toString() ?? _currentPath ?? '';
      final String directoryOverride = extractDirectoryPath(pathForReload);
      await _reloadFilesAndPreserveSelection(
        preferredPath,
        directoryOverride: directoryOverride.isEmpty ? null : directoryOverride,
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      _showSnackBar('Action failed.');
      setState(() {
        _isSubmittingAction = false;
      });
    }
  }

  Future<void> _reloadFilesAndPreserveSelection(
    String? preferredPath, {
    String? directoryOverride,
  }) async {
    final String directory = (directoryOverride ?? _directoryController.text)
        .trim();
    if (directory.isEmpty) {
      _showSnackBar('Directory is required for refresh.');
      setState(() {
        _isSubmittingAction = false;
      });
      return;
    }
    _directoryController.text = directory;

    final VideoReviewerApiResult result = await _apiService.loadFiles(
      directory: directory,
      includeReviewed: _includeReviewed,
    );
    final Map<String, dynamic> json = result.json;

    if (!mounted) {
      return;
    }

    if (result.hasError) {
      _showSnackBar(result.errorOr('Reload failed'));
      setState(() {
        _isSubmittingAction = false;
      });
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
        nextIndex = _currentIndex.clamp(0, nextFiles.length - 1);
      }
    }

    setState(() {
      _files = nextFiles;
      _currentIndex = nextIndex;
      _isSubmittingAction = false;
    });

    if (nextIndex >= 0) {
      await _loadVideoAtIndex(nextIndex);
    } else {
      setState(() {
        _newFileNameController.clear();
        _trimRange = const RangeValues(0, 0);
      });
      _disposeVideoController();
    }
  }

  void _disposeVideoController() {
    final VideoPlayerController? oldController = _videoController;
    _videoController = null;
    _videoInitFuture = null;
    oldController?.dispose();
  }

  void _showSnackBar(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final String indexText = _files.isEmpty
        ? '0/0'
        : '${_currentIndex + 1}/${_files.length}';

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E1E),
                border: Border.all(color: const Color(0xFF3A3A3A)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: <Widget>[
                    TopControlsBar(
                      directoryController: _directoryController,
                      includeReviewed: _includeReviewed,
                      isLoading: _isLoadingFiles,
                      indexText: indexText,
                      indexController: _indexController,
                      onIncludeReviewedChanged: (bool value) {
                        setState(() {
                          _includeReviewed = value;
                        });
                      },
                      onLoadPressed: _loadDirectory,
                      onGoPressed: _jumpToIndex,
                      onUndoPressed: _submitUndo,
                      onRedoPressed: _submitRedo,
                      onSettingsPressed: _openSettingsDialog,
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints constraints) {
                          final Widget rightPane = Column(
                            children: <Widget>[
                              VideoPlayerPane(
                                key: _videoPlayerPaneKey,
                                controller: _videoController,
                                initializeFuture: _videoInitFuture,
                              ),
                              const SizedBox(height: 14),
                              Expanded(
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF232323),
                                    border: Border.all(
                                      color: const Color(0xFF3A3A3A),
                                    ),
                                  ),
                                  child: Column(
                                    children: <Widget>[
                                      const TabBar(
                                        tabs: <Widget>[
                                          Tab(text: 'Trimming'),
                                          Tab(text: 'Merging'),
                                          Tab(text: 'Migration'),
                                        ],
                                      ),
                                      Expanded(
                                        child: TabBarView(
                                          children: <Widget>[
                                            TrimmingTab(
                                              newFileNameController:
                                                  _newFileNameController,
                                              trimRange: _trimRange,
                                              maxTrimEnd: _videoDurationSeconds,
                                              isBusy: _isSubmittingAction,
                                              onTrimRangeChanged:
                                                  (RangeValues values) async {
                                                    final RangeValues previousRange =
                                                        _trimRange;
                                                    final RangeValues clamped =
                                                        clampTrimRange(
                                                          values,
                                                          _videoDurationSeconds,
                                                        );
                                                    setState(() {
                                                      _trimRange = clamped;
                                                    });

                                                    if (!_settings
                                                            .seekOnStartSliderChange ||
                                                        clamped.start ==
                                                            previousRange.start) {
                                                      return;
                                                    }

                                                    final VideoPlayerController?
                                                    controller = _videoController;
                                                    if (controller == null ||
                                                        !controller
                                                            .value
                                                            .isInitialized) {
                                                      return;
                                                    }

                                                    final int targetMs =
                                                        (clamped.start * 1000)
                                                            .round()
                                                            .clamp(
                                                              0,
                                                              controller
                                                                  .value
                                                                  .duration
                                                                  .inMilliseconds,
                                                            )
                                                            .toInt();
                                                    await controller.seekTo(
                                                      Duration(
                                                        milliseconds: targetMs,
                                                      ),
                                                    );
                                                  },
                                              onRenamePressed:
                                                  _submitRenameOnly,
                                              onRenameTrimPressed: _submitTrim,
                                              onDeletePressed: _submitDelete,
                                              onPreviousPressed: () =>
                                                  _navigate(-1),
                                              onNextPressed: () => _navigate(1),
                                            ),
                                            const PlaceholderTabContent(
                                              title: 'Merging',
                                              subtitle:
                                                  'Merge workflow will be implemented here.',
                                            ),
                                            const PlaceholderTabContent(
                                              title: 'Migration',
                                              subtitle:
                                                  'Migration workflow will be implemented here.',
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );

                          if (constraints.maxWidth < 1100) {
                            return Column(
                              children: <Widget>[
                                SizedBox(
                                  height: 240,
                                  child: VideoListPane(
                                    files: _files,
                                    selectedIndex: _currentIndex,
                                    titleForPath: extractTitle,
                                    thumbnailUriForPath: _apiService.thumbnailUri,
                                    onItemSelected: _loadVideoAtIndex,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Expanded(child: rightPane),
                              ],
                            );
                          }

                          return Row(
                            children: <Widget>[
                              SizedBox(
                                width:
                                    constraints.maxWidth * _leftPaneProportion,
                                child: VideoListPane(
                                  files: _files,
                                  selectedIndex: _currentIndex,
                                  titleForPath: extractTitle,
                                  thumbnailUriForPath: _apiService.thumbnailUri,
                                  onItemSelected: _loadVideoAtIndex,
                                ),
                              ),
                              HorizontalSplitHandle(
                                onDragDelta: (double deltaX) {
                                  setState(() {
                                    final double nextValue =
                                        _leftPaneProportion +
                                        (deltaX / constraints.maxWidth);
                                    _leftPaneProportion = nextValue
                                        .clamp(0.22, 0.72)
                                        .toDouble();
                                  });
                                  _saveSplitPaneProportion();
                                },
                              ),
                              Expanded(child: rightPane),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
