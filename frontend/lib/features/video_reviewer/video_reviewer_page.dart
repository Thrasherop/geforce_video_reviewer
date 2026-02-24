import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'controllers/migration_controller.dart';
import 'controllers/merging_controller.dart';
import 'controllers/video_reviewer_controller.dart';
import 'key_bind_handler.dart';
import 'models/video_reviewer_state.dart';
import 'models/video_reviewer_settings.dart';
import 'services/split_pane_preferences_store.dart';
import 'services/video_reviewer_api_service.dart';
import 'services/video_reviewer_settings_store.dart';
import 'utils/time_format_utils.dart';
import 'utils/trim_utils.dart';
import 'utils/video_path_utils.dart';
import 'widgets/horizontal_split_handle.dart';
import 'widgets/merging_tab.dart';
import 'widgets/migration_tab.dart';
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

class _VideoReviewerPageState extends State<VideoReviewerPage>
    with SingleTickerProviderStateMixin {
  final TextEditingController _directoryController = TextEditingController();
  final TextEditingController _indexController = TextEditingController();
  final TextEditingController _newFileNameController = TextEditingController();

  VideoPlayerController? _videoController;
  Future<void>? _videoInitFuture;
  final GlobalKey<VideoPlayerPaneState> _videoPlayerPaneKey =
      GlobalKey<VideoPlayerPaneState>();
  late final TabController _tabController;
  late final KeyBindHandler _keyBindHandler;
  late final MigrationController _migrationController;
  late final MergingController _mergingController;
  late final VideoReviewerController _reviewerController;
  final VideoReviewerSettingsStore _settingsStore =
      VideoReviewerSettingsStore();
  final VideoReviewerApiService _apiService = VideoReviewerApiService();
  VideoReviewerSettings _settings = VideoReviewerSettings.defaults();
  late final VoidCallback _controllerListener;

  @override
  void initState() {
    super.initState();
    _migrationController = MigrationController();
    _mergingController = MergingController();
    _reviewerController = VideoReviewerController(
      apiService: _apiService,
      splitPanePreferencesStore: SplitPanePreferencesStore(),
      mergingController: _mergingController,
    );
    _controllerListener = () {
      _migrationController.retainOnlyExistingPaths(
        availablePaths: _state.files,
        apiService: _apiService,
        onError: _showSnackBar,
      );
      if (mounted) {
        setState(() {});
      }
    };
    _reviewerController.addListener(_controllerListener);
    _migrationController.addListener(_controllerListener);
    _mergingController.addListener(_controllerListener);

    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(() {
      if (!mounted || _tabController.indexIsChanging) {
        return;
      }
      setState(() {});
    });
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
        hasSelectedFile: () => _reviewerController.currentPath != null,
      ),
      config: _keyBindConfigFromSettings(_settings),
    );
    _keyBindHandler.attach();
    _reviewerController.loadSavedSplitPaneProportion();
    _loadSettings();
  }

  @override
  void dispose() {
    _reviewerController.removeListener(_controllerListener);
    _migrationController.removeListener(_controllerListener);
    _mergingController.removeListener(_controllerListener);
    _tabController.dispose();
    _keyBindHandler.detach();
    _directoryController.dispose();
    _indexController.dispose();
    _newFileNameController.dispose();
    _migrationController.disposeControllers();
    _mergingController.disposeControllers();
    _disposeVideoController();
    super.dispose();
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

  VideoReviewerState get _state => _reviewerController.state;

  double get _videoDurationSeconds {
    final VideoPlayerController? controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return 0;
    }
    final Duration duration = controller.value.duration;
    return duration.inMilliseconds / 1000.0;
  }

  bool get _isMergingTabActive => _tabController.index == 1;
  bool get _isMigrationTabActive => _tabController.index == 2;
  bool get _isMigrationOperationInFlight =>
      _state.isSubmittingAction ||
      _state.isLoadingFiles ||
      _migrationController.isOperationInFlight;

  Future<void> _addPathToMergeAtIndex(int index) async {
    if (index < 0 || index >= _state.files.length) {
      return;
    }
    final String path = _state.files[index];
    final String? error = _mergingController.addPath(
      path,
      isBusy: _state.isSubmittingAction,
    );
    if (error != null) {
      _showSnackBar(error);
    }
  }

  Future<void> _removeMergePathAt(int index) async {
    _mergingController.removeAt(index, isBusy: _state.isSubmittingAction);
  }

  Future<void> _moveMergePathLeft(int index) async {
    _mergingController.moveLeft(index, isBusy: _state.isSubmittingAction);
  }

  Future<void> _moveMergePathRight(int index) async {
    _mergingController.moveRight(index, isBusy: _state.isSubmittingAction);
  }

  Future<void> _submitMerge({required bool archiveOriginals}) async {
    final String? error = _mergingController.validateForSubmit();
    if (error != null) {
      _showSnackBar(error);
      return;
    }
    await _reviewerController.submitActionAndRefresh(
      payload: _mergingController.buildMergePayload(
        archiveOriginals: archiveOriginals,
      ),
      directoryInput: _directoryController.text,
      onError: _showSnackBar,
      onLoadVideoAtIndex: _loadVideoAtIndex,
      onNoSelection: _clearCurrentSelection,
    );
  }

  Future<void> _toggleMigrationPathAtIndex(int index) async {
    await _migrationController.togglePathAtIndex(
      index: index,
      files: _state.files,
      isBusy: _state.isSubmittingAction || _state.isLoadingFiles,
      apiService: _apiService,
      onError: _showSnackBar,
    );
  }

  Future<void> _submitMigrationUpload({
    required bool archiveAfterUpload,
  }) async {
    await _migrationController.submitUpload(
      apiService: _apiService,
      archiveAfterUpload: archiveAfterUpload,
      isBusy: _state.isSubmittingAction || _state.isLoadingFiles,
      onError: _showSnackBar,
      onInfo: _showSnackBar,
    );
  }

  Future<void> _setKeepLocalForSelection(bool designation) async {
    await _migrationController.setKeepLocalForSelection(
      designation: designation,
      apiService: _apiService,
      isBusy: _state.isSubmittingAction || _state.isLoadingFiles,
      onError: _showSnackBar,
    );
  }

  Future<void> _loadDirectory() async {
    await _reviewerController.loadDirectory(
      directory: _directoryController.text,
      onError: _showSnackBar,
      onInfo: _showSnackBar,
      onLoadVideoAtIndex: _loadVideoAtIndex,
      onNoSelection: _clearCurrentSelection,
    );
  }

  Future<void> _loadVideoAtIndex(int index) async {
    if (index < 0 || index >= _state.files.length) {
      return;
    }

    final String path = _state.files[index];
    final String fileName = extractFileName(path);
    final String baseName = fileName.toLowerCase().endsWith('.mp4')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;

    _reviewerController.setCurrentIndex(index);
    _newFileNameController.text = baseName;
    _reviewerController.setTrimRange(const RangeValues(0, 0));

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
          _reviewerController.setTrimRange(
            clampTrimRange(RangeValues(0, duration), duration),
          );
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
    await _reviewerController.jumpToIndex(
      indexInput: _indexController.text,
      onError: _showSnackBar,
      onLoadVideoAtIndex: _loadVideoAtIndex,
      onJumpInputConsumed: _indexController.clear,
    );
  }

  Future<void> _navigate(int delta) async {
    await _reviewerController.navigate(
      delta,
      onLoadVideoAtIndex: _loadVideoAtIndex,
    );
  }

  Future<void> _submitRenameOnly() async {
    final String? currentPath = _reviewerController.currentPath;
    final String newName = _newFileNameController.text.trim();
    if (currentPath == null) {
      _showSnackBar('Select a file first.');
      return;
    }
    if (newName.isEmpty) {
      _showSnackBar('Name cannot be empty.');
      return;
    }
    await _reviewerController.submitActionAndRefresh(
      payload: <String, dynamic>{
        'action': 'rename',
        'path': currentPath,
        'new_name': newName,
      },
      directoryInput: _directoryController.text,
      onError: _showSnackBar,
      onLoadVideoAtIndex: _loadVideoAtIndex,
      onNoSelection: _clearCurrentSelection,
    );
  }

  Future<void> _submitTrim() async {
    final String? currentPath = _reviewerController.currentPath;
    final String newName = _newFileNameController.text.trim();
    if (currentPath == null) {
      _showSnackBar('Select a file first.');
      return;
    }
    if (newName.isEmpty) {
      _showSnackBar('Name cannot be empty.');
      return;
    }
    if (_state.trimRange.end <= _state.trimRange.start) {
      _showSnackBar('Trim range is invalid.');
      return;
    }
    await _reviewerController.submitActionAndRefresh(
      payload: <String, dynamic>{
        'action': 'trim',
        'path': currentPath,
        'new_name': newName,
        'start': formatSeconds(_state.trimRange.start),
        'end': formatSeconds(_state.trimRange.end),
      },
      directoryInput: _directoryController.text,
      onError: _showSnackBar,
      onLoadVideoAtIndex: _loadVideoAtIndex,
      onNoSelection: _clearCurrentSelection,
    );
  }

  Future<void> _submitDelete() async {
    final String? currentPath = _reviewerController.currentPath;
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

    // Release the current player before delete so backend can rename safely.
    _disposeVideoController();

    await _reviewerController.submitActionAndRefresh(
      payload: <String, dynamic>{'action': 'delete', 'path': currentPath},
      directoryInput: _directoryController.text,
      onError: _showSnackBar,
      onLoadVideoAtIndex: _loadVideoAtIndex,
      onNoSelection: _clearCurrentSelection,
    );
  }

  Future<void> _submitUndo() async {
    await _reviewerController.submitHistoryAction(
      endpoint: '/api/undo',
      includeNewPathFallback: false,
      directoryInput: _directoryController.text,
      onError: _showSnackBar,
      onLoadVideoAtIndex: _loadVideoAtIndex,
      onNoSelection: _clearCurrentSelection,
    );
  }

  Future<void> _submitRedo() async {
    await _reviewerController.submitHistoryAction(
      endpoint: '/api/redo',
      includeNewPathFallback: true,
      directoryInput: _directoryController.text,
      onError: _showSnackBar,
      onLoadVideoAtIndex: _loadVideoAtIndex,
      onNoSelection: _clearCurrentSelection,
    );
  }

  void _clearCurrentSelection() {
    _newFileNameController.clear();
    _reviewerController.setTrimRange(const RangeValues(0, 0));
    _disposeVideoController();
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
    final String indexText = _state.files.isEmpty
        ? '0/0'
        : '${_state.currentIndex + 1}/${_state.files.length}';

    return Scaffold(
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
                    includeReviewed: _state.includeReviewed,
                    isLoading: _state.isLoadingFiles,
                    indexText: indexText,
                    indexController: _indexController,
                    onIncludeReviewedChanged: _reviewerController.setIncludeReviewed,
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
                                    TabBar(
                                      controller: _tabController,
                                      tabs: const <Widget>[
                                        Tab(text: 'Trimming'),
                                        Tab(text: 'Merging'),
                                        Tab(text: 'Migration'),
                                      ],
                                    ),
                                    Expanded(
                                      child: TabBarView(
                                        controller: _tabController,
                                        children: <Widget>[
                                          TrimmingTab(
                                            newFileNameController:
                                                _newFileNameController,
                                            trimRange: _state.trimRange,
                                            maxTrimEnd: _videoDurationSeconds,
                                            isBusy: _state.isSubmittingAction,
                                            onTrimRangeChanged:
                                                (RangeValues values) async {
                                                  final RangeValues previousRange =
                                                      _state.trimRange;
                                                  final RangeValues clamped =
                                                      clampTrimRange(
                                                        values,
                                                        _videoDurationSeconds,
                                                      );
                                                  _reviewerController.setTrimRange(
                                                    clamped,
                                                  );

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
                                          MergingTab(
                                            selectedPaths:
                                                _mergingController.selectedPaths,
                                            titleForPath: extractTitle,
                                            thumbnailUriForPath:
                                                _apiService.thumbnailUri,
                                            outputNameController:
                                                _mergingController
                                                    .outputNameController,
                                            isBusy: _state.isSubmittingAction,
                                            onMoveLeftPressed:
                                                _moveMergePathLeft,
                                            onMoveRightPressed:
                                                _moveMergePathRight,
                                            onRemovePressed:
                                                _removeMergePathAt,
                                            onMergeKeepPressed: () =>
                                                _submitMerge(
                                                  archiveOriginals: false,
                                                ),
                                            onMergeArchivePressed: () =>
                                                _submitMerge(
                                                  archiveOriginals: true,
                                                ),
                                          ),
                                          MigrationTab(
                                            selectedPaths:
                                                _migrationController.selectedPaths,
                                            uploadNameController:
                                                _migrationController
                                                    .uploadNameController,
                                            uploadNameEnabled: _migrationController
                                                .uploadNameEnabled,
                                            visibilitySetting:
                                                _migrationController
                                                    .visibilitySetting,
                                            onVisibilityChanged: (String? value) {
                                              if (value == null) {
                                                return;
                                              }
                                              _migrationController
                                                  .setVisibilitySetting(value);
                                            },
                                            madeForKids:
                                                _migrationController.madeForKids,
                                            onMadeForKidsChanged: (bool? value) {
                                              if (value == null) {
                                                return;
                                              }
                                              _migrationController
                                                  .setMadeForKids(value);
                                            },
                                            isKeepLocalLoading:
                                                _migrationController
                                                    .isKeepLocalLoading,
                                            isKeepLocalAvailable:
                                                _migrationController
                                                    .isKeepLocalAvailable,
                                            keepLocalValue:
                                                _migrationController.keepLocalValue,
                                            onKeepLocalChanged:
                                                _setKeepLocalForSelection,
                                            isBusy:
                                                _isMigrationOperationInFlight,
                                            onUploadPressed: () =>
                                                _submitMigrationUpload(
                                                  archiveAfterUpload: false,
                                                ),
                                            onUploadArchivePressed: () =>
                                                _submitMigrationUpload(
                                                  archiveAfterUpload: true,
                                                ),
                                            isActivityPanelExpanded:
                                                _migrationController
                                                    .isActivityPanelExpanded,
                                            onToggleActivityPanel:
                                                _migrationController
                                                    .toggleActivityPanelExpanded,
                                            uploadJobs:
                                                _migrationController.uploadJobs,
                                            isJobExpanded:
                                                _migrationController
                                                    .isJobExpanded,
                                            onToggleJobExpanded:
                                                _migrationController
                                                    .toggleJobExpanded,
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
                                  files: _state.files,
                                  selectedIndex: _state.currentIndex,
                                  titleForPath: extractTitle,
                                  thumbnailUriForPath: _apiService.thumbnailUri,
                                  onItemSelected: _loadVideoAtIndex,
                                  onOverlayIconPressed: _isMergingTabActive
                                      ? _addPathToMergeAtIndex
                                      : (_isMigrationTabActive
                                            ? _toggleMigrationPathAtIndex
                                            : null),
                                  overlayEnabledForPath: _isMergingTabActive
                                      ? (String path) =>
                                            _mergingController.canAddPath(
                                              path,
                                              isBusy:
                                                  _state.isSubmittingAction,
                                            )
                                      : (_isMigrationTabActive
                                            ? (String path) =>
                                                  !_isMigrationOperationInFlight
                                            : null),
                                  overlayIconForPath: _isMigrationTabActive
                                      ? (String path) =>
                                            _migrationController.isPathSelected(
                                              path,
                                            )
                                            ? Icons.check_box
                                            : Icons.check_box_outline_blank
                                      : null,
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
                                  constraints.maxWidth * _state.leftPaneProportion,
                              child: VideoListPane(
                                files: _state.files,
                                selectedIndex: _state.currentIndex,
                                titleForPath: extractTitle,
                                thumbnailUriForPath: _apiService.thumbnailUri,
                                onItemSelected: _loadVideoAtIndex,
                                onOverlayIconPressed: _isMergingTabActive
                                    ? _addPathToMergeAtIndex
                                    : (_isMigrationTabActive
                                          ? _toggleMigrationPathAtIndex
                                          : null),
                                overlayEnabledForPath: _isMergingTabActive
                                    ? (String path) =>
                                          _mergingController.canAddPath(
                                            path,
                                            isBusy:
                                                _state.isSubmittingAction,
                                          )
                                    : (_isMigrationTabActive
                                          ? (String path) =>
                                                !_isMigrationOperationInFlight
                                          : null),
                                overlayIconForPath: _isMigrationTabActive
                                    ? (String path) =>
                                          _migrationController.isPathSelected(
                                            path,
                                          )
                                          ? Icons.check_box
                                          : Icons.check_box_outline_blank
                                    : null,
                              ),
                            ),
                            HorizontalSplitHandle(
                              onDragDelta: (double deltaX) {
                                final double nextValue =
                                    _state.leftPaneProportion +
                                    (deltaX / constraints.maxWidth);
                                _reviewerController.updateLeftPaneProportion(
                                  nextValue.toDouble(),
                                );
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
    );
  }
}
