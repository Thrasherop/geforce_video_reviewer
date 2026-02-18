import 'package:flutter/material.dart';

import '../features/video_reviewer/video_reviewer_page.dart';

class VideoReviewerApp extends StatelessWidget {
  const VideoReviewerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Video Reviewer',
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF4C8DFF),
          brightness: Brightness.dark,
        ),
        scaffoldBackgroundColor: const Color(0xFF121212),
        inputDecorationTheme: const InputDecorationTheme(
          filled: true,
          fillColor: Color(0xFF232323),
          border: OutlineInputBorder(),
        ),
        useMaterial3: true,
      ),
      home: const VideoReviewerPage(),
    );
  }
}
