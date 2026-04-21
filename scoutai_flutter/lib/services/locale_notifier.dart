import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Simple app-wide locale notifier (EN / FR).
class LocaleNotifier extends ValueNotifier<Locale> {
  LocaleNotifier._() : super(const Locale('en'));
  static final instance = LocaleNotifier._();

  bool get isFrench => value.languageCode == 'fr';
  String get code => value.languageCode;

  void setLocale(String code) {
    value = Locale(code);
    SharedPreferences.getInstance().then((p) => p.setString('app_locale', code));
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('app_locale');
    if (saved != null && saved.isNotEmpty) {
      value = Locale(saved);
    }
  }
}
