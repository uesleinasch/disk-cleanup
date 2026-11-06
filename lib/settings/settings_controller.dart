import 'package:flutter/foundation.dart';

import 'settings.dart';
import 'settings_store.dart';

class SettingsController extends ChangeNotifier {
  SettingsController(this.store, this.home) : _value = Settings.defaults(home);

  final SettingsStore store;
  final String home;
  Settings _value;

  Settings get value => _value;

  Future<void> load() async {
    _value = await store.load(home);
    notifyListeners();
  }

  Future<void> update(Settings Function(Settings) change) async {
    _value = change(_value);
    notifyListeners();
    try {
      await store.save(_value);
    } on Object catch (e) {
      debugPrint('Falha ao salvar configurações: $e');
    }
  }
}
