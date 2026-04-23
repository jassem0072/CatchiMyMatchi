import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/locale_notifier.dart';
import '../../theme/theme_notifier.dart';

class ThemeModeController extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    final notifier = ThemeNotifier.instance;

    void listener() {
      state = notifier.value;
    }

    notifier.addListener(listener);
    ref.onDispose(() => notifier.removeListener(listener));

    return notifier.value;
  }

  void toggle() {
    ThemeNotifier.instance.toggle();
    state = ThemeNotifier.instance.value;
  }

  void setDark(bool dark) {
    ThemeNotifier.instance.setDark(dark);
    state = ThemeNotifier.instance.value;
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(
  ThemeModeController.new,
);

class AppLocaleController extends Notifier<Locale> {
  @override
  Locale build() {
    final notifier = LocaleNotifier.instance;
    var disposed = false;

    void listener() {
      state = notifier.value;
    }

    notifier.addListener(listener);
    ref.onDispose(() {
      disposed = true;
      notifier.removeListener(listener);
    });

    Future<void>(() async {
      await notifier.load();
      if (!disposed) {
        state = notifier.value;
      }
    });

    return notifier.value;
  }

  void setLocale(String code) {
    LocaleNotifier.instance.setLocale(code);
    state = LocaleNotifier.instance.value;
  }
}

final appLocaleProvider = NotifierProvider<AppLocaleController, Locale>(
  AppLocaleController.new,
);
