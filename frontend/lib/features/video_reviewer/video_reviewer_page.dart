import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';

import 'widgets/placeholder_tab_content.dart';
import 'widgets/top_controls_bar.dart';
import 'widgets/trimming_tab.dart';
import 'widgets/video_list_pane.dart';
import 'widgets/video_player_pane.dart';

class VideoReviewerPage extends StatefulWidget {
  const VideoReviewerPage({super.key});

  @override
  State<VideoReviewerPage> createState() => _VideoReviewerPageState();
}

const String _splitPanePrefKey = 'video_reviewer.left_pane_proportion';

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

  @override
  void initState() {
    super.initState();
    _loadSavedSplitPaneProportion();
  }

  @override
  void dispose() {
    _directoryController.dispose();
    _indexController.dispose();
    _newFileNameController.dispose();
    _disposeVideoController();
    super.dispose();
  }

  Future<void> _loadSavedSplitPaneProportion() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final double? savedValue = prefs.getDouble(_splitPanePrefKey);
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

  Future<void> _saveSplitPaneProportion() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_splitPanePrefKey, _leftPaneProportion);
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
    final Duration? duration = _videoController?.value.duration;
    if (duration == null) {
      return 0;
    }
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
      final Uri uri = Uri(
        path: '/api/files',
        queryParameters: <String, String>{
          'dir': dir,
          'include_reviewed': _includeReviewed.toString(),
        },
      );
      final http.Response response = await http.get(uri);
      final Map<String, dynamic> json =
          jsonDecode(response.body) as Map<String, dynamic>;

      if (!mounted) {
        return;
      }

      if (response.statusCode >= 400 || json['error'] != null) {
        _showSnackBar((json['error'] ?? 'Failed to load files').toString());
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
    final String fileName = _extractFileName(path);
    final String baseName = fileName.toLowerCase().endsWith('.mp4')
        ? fileName.substring(0, fileName.length - 4)
        : fileName;

    setState(() {
      _currentIndex = index;
      _newFileNameController.text = baseName;
    });

    _disposeVideoController();

    final Uri source = Uri(
      path: '/api/video',
      queryParameters: <String, String>{'path': path},
    );

    final VideoPlayerController controller = VideoPlayerController.networkUrl(
      source,
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
            _trimRange = RangeValues(0, duration);
          });
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
      'start': _formatSeconds(_trimRange.start),
      'end': _formatSeconds(_trimRange.end),
    });
  }

  Future<void> _submitDelete() async {
    final String? currentPath = _currentPath;
    if (currentPath == null) {
      _showSnackBar('Select a file first.');
      return;
    }

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

    await _callActionAndRefresh(<String, dynamic>{
      'action': 'delete',
      'path': currentPath,
    });
  }

  Future<void> _callActionAndRefresh(Map<String, dynamic> payload) async {
    final String dir = _directoryController.text.trim();
    if (dir.isEmpty) {
      _showSnackBar('Directory is required for refresh.');
      return;
    }

    setState(() {
      _isSubmittingAction = true;
    });

    try {
      final http.Response response = await http.post(
        Uri(path: '/api/action'),
        headers: <String, String>{'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );
      final Map<String, dynamic> json =
          jsonDecode(response.body) as Map<String, dynamic>;

      if (!mounted) {
        return;
      }
      if (response.statusCode >= 400 || json['error'] != null) {
        _showSnackBar((json['error'] ?? 'Action failed').toString());
        setState(() {
          _isSubmittingAction = false;
        });
        return;
      }

      final String? preferredPath = (json['new_path'] ?? json['current_path'])
          ?.toString();
      await _reloadFilesAndPreserveSelection(preferredPath);
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

  Future<void> _reloadFilesAndPreserveSelection(String? preferredPath) async {
    final Uri uri = Uri(
      path: '/api/files',
      queryParameters: <String, String>{
        'dir': _directoryController.text.trim(),
        'include_reviewed': _includeReviewed.toString(),
      },
    );
    final http.Response response = await http.get(uri);
    final Map<String, dynamic> json =
        jsonDecode(response.body) as Map<String, dynamic>;

    if (!mounted) {
      return;
    }

    if (response.statusCode >= 400 || json['error'] != null) {
      _showSnackBar((json['error'] ?? 'Reload failed').toString());
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
      _newFileNameController.clear();
      _disposeVideoController();
    }
  }

  void _disposeVideoController() {
    final VideoPlayerController? oldController = _videoController;
    _videoController = null;
    _videoInitFuture = null;
    oldController?.dispose();
  }

  String _extractFileName(String fullPath) {
    final String normalized = fullPath.replaceAll('\\', '/');
    final int index = normalized.lastIndexOf('/');
    if (index < 0 || index + 1 >= normalized.length) {
      return normalized;
    }
    return normalized.substring(index + 1);
  }

  String _extractTitle(String fullPath) {
    final String fileName = _extractFileName(fullPath);
    if (!fileName.toLowerCase().endsWith('.mp4')) {
      return fileName;
    }
    return fileName.substring(0, fileName.length - 4);
  }

  String _formatSeconds(double seconds) {
    final int totalMs = (seconds * 1000).round();
    final int hours = totalMs ~/ 3600000;
    final int minutes = (totalMs % 3600000) ~/ 60000;
    final int secs = (totalMs % 60000) ~/ 1000;
    final int millis = totalMs % 1000;
    final String hh = hours.toString().padLeft(2, '0');
    final String mm = minutes.toString().padLeft(2, '0');
    final String ss = secs.toString().padLeft(2, '0');
    final String mmm = millis.toString().padLeft(3, '0');
    return '$hh:$mm:$ss.$mmm';
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
                      onSettingsPressed: () {
                        _showSnackBar('Settings screen coming soon.');
                      },
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (BuildContext context, BoxConstraints constraints) {
                          final Widget rightPane = Column(
                            children: <Widget>[
                              VideoPlayerPane(
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
                                                  (RangeValues values) {
                                                    setState(() {
                                                      _trimRange = values;
                                                    });
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
                                    titleForPath: _extractTitle,
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
                                  titleForPath: _extractTitle,
                                  onItemSelected: _loadVideoAtIndex,
                                ),
                              ),
                              _HorizontalSplitHandle(
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

class _HorizontalSplitHandle extends StatelessWidget {
  const _HorizontalSplitHandle({required this.onDragDelta});

  final ValueChanged<double> onDragDelta;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (DragUpdateDetails details) {
          onDragDelta(details.delta.dx);
        },
        child: SizedBox(
          width: 14,
          child: Center(
            child: Container(
              width: 3,
              decoration: BoxDecoration(
                color: const Color(0xFF4A4A4A),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
