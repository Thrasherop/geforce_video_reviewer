import 'package:shared_preferences/shared_preferences.dart';

class SplitPanePreferencesStore {
  static const String _leftPanePrefKey = 'video_reviewer.left_pane_proportion';

  Future<double?> loadLeftPaneProportion() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getDouble(_leftPanePrefKey);
  }

  Future<void> saveLeftPaneProportion(double value) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_leftPanePrefKey, value);
  }
}
