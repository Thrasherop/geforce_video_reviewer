import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerPane extends StatefulWidget {
  const VideoPlayerPane({
    required this.controller,
    required this.initializeFuture,
    super.key,
  });

  final VideoPlayerController? controller;
  final Future<void>? initializeFuture;  

  @override
  State<VideoPlayerPane> createState() => VideoPlayerPaneState();
}

class VideoPlayerPaneState extends State<VideoPlayerPane> {
  VideoPlayerController? _listeningController;

  @override
  void initState() {
    super.initState();
    _attachControllerListener();
  }


  @override
  void didUpdateWidget(covariant VideoPlayerPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _detachControllerListener();
      _attachControllerListener();
    }
  }

  @override
  void dispose() {
    _detachControllerListener();
    super.dispose();
  }

  void _attachControllerListener() {
    final VideoPlayerController? controller = widget.controller;
    if (controller == null) {
      _listeningController = null;
      return;
    }
    _listeningController = controller;
    controller.addListener(_handleControllerUpdate);
  }

  void _detachControllerListener() {
    _listeningController?.removeListener(_handleControllerUpdate);
    _listeningController = null;
  }

  void _handleControllerUpdate() {
    if (!mounted) {
      return;
    }
    setState(() {});
  }

  Future<void> togglePlayPause() async {
    final VideoPlayerController? controller = widget.controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (controller.value.isPlaying) {
      await controller.pause();
      return;
    }
    await controller.play();
  }

  Future<void> seekRelative(double seconds) async {
    final VideoPlayerController? controller = widget.controller;
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    final Duration current = controller.value.position;
    final Duration duration = controller.value.duration;
    final int targetMs = current.inMilliseconds + (seconds * 1000).round();
    final int boundedMs = targetMs.clamp(0, duration.inMilliseconds).toInt();
    await controller.seekTo(Duration(milliseconds: boundedMs));
  }

  String _formatDuration(Duration duration) {
    final int totalSeconds = duration.inSeconds;
    final int hours = totalSeconds ~/ 3600;
    final int minutes = (totalSeconds % 3600) ~/ 60;
    final int seconds = totalSeconds % 60;
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final VideoPlayerController? controller = widget.controller;
    final Future<void>? initializeFuture = widget.initializeFuture;

    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF202020),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: controller == null || initializeFuture == null
            ? const Center(
                child: Text(
                  'Select a video to preview',
                  style: TextStyle(color: Color(0xFFB0B0B0)),
                ),
              )
            : FutureBuilder<void>(
                future: initializeFuture,
                builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!controller.value.isInitialized) {
                    return const Center(child: Text('Unable to initialize video.'));
                  }
                  final Duration position = controller.value.position;
                  final Duration duration = controller.value.duration;
                  final bool isPlaying = controller.value.isPlaying;

                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: <Widget>[
                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: controller.value.aspectRatio,
                              child: VideoPlayer(controller),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: <Widget>[
                            IconButton(
                              onPressed: () => seekRelative(-10),
                              icon: const Icon(Icons.replay_10),
                              tooltip: 'Rewind 10s (J)',
                            ),
                            IconButton(
                              onPressed: togglePlayPause,
                              icon: Icon(
                                isPlaying ? Icons.pause_circle : Icons.play_circle,
                              ),
                              tooltip: isPlaying ? 'Pause (K)' : 'Play (K)',
                            ),
                            IconButton(
                              onPressed: () => seekRelative(3),
                              icon: const Icon(Icons.forward_5),
                              tooltip: 'Forward 3s (L)',
                            ),
                            Expanded(
                              child: VideoProgressIndicator(
                                controller,
                                allowScrubbing: true,
                                colors: const VideoProgressColors(
                                  playedColor: Color(0xFF4C8DFF),
                                  bufferedColor: Color(0xFF666666),
                                  backgroundColor: Color(0xFF2D2D2D),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${_formatDuration(position)} / ${_formatDuration(duration)}',
                              style: const TextStyle(color: Color(0xFFB0B0B0)),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
      ),
    );
  }
}
