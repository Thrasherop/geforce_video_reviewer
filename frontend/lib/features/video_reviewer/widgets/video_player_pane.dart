import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class VideoPlayerPane extends StatelessWidget {
  const VideoPlayerPane({
    required this.controller,
    required this.initializeFuture,
    super.key,
  });

  final VideoPlayerController? controller;
  final Future<void>? initializeFuture;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF202020),
          border: Border.all(color: const Color(0xFF3A3A3A)),
        ),
        child: Center(
          child: controller == null || initializeFuture == null
              ? const Text(
                  'Select a video to preview',
                  style: TextStyle(color: Color(0xFFB0B0B0)),
                )
              : FutureBuilder<void>(
                  future: initializeFuture,
                  builder:
                      (BuildContext context, AsyncSnapshot<void> snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const CircularProgressIndicator();
                        }
                        if (!(controller?.value.isInitialized ?? false)) {
                          return const Text('Unable to initialize video.');
                        }
                        return AspectRatio(
                          aspectRatio: controller!.value.aspectRatio,
                          child: VideoPlayer(controller!),
                        );
                      },
                ),
        ),
      ),
    );
  }
}
