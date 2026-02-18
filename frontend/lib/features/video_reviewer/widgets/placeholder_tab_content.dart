import 'package:flutter/material.dart';

class PlaceholderTabContent extends StatelessWidget {
  const PlaceholderTabContent({
    required this.title,
    required this.subtitle,
    super.key,
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: Color(0xFFB0B0B0))),
        ],
      ),
    );
  }
}
