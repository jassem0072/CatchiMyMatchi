import 'package:flutter/material.dart';

/// App-wide theme mode notifier. Wrap MaterialApp in a
/// ValueListenableBuilder to react to changes.
class ThemeNotifier extends ValueNotifier<ThemeMode> {
  ThemeNotifier._() : super(ThemeMode.dark);

  static final ThemeNotifier instance = ThemeNotifier._();

  bool get isDark => value == ThemeMode.dark;

  void toggle() {
    value = isDark ? ThemeMode.light : ThemeMode.dark;
  }

  void setDark(bool dark) {
    value = dark ? ThemeMode.dark : ThemeMode.light;
  }
}
