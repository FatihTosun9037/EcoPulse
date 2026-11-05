import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class Alerts {
  static const MethodChannel _channel = MethodChannel('ecopulse/alerts');
  static bool ready = false;

  static Future<void> init() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      ready = true;
      return;
    }
    try {
      await _channel.invokeMethod<void>('init');
      ready = true;
    } on PlatformException {
      ready = false;
    }
  }

  static Future<void> show(int id, String title, String body) async {
    if (!ready || kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    try {
      await _channel.invokeMethod<void>('show', {'id': id, 'title': title, 'body': body});
    } on PlatformException {
      return;
    }
  }
}
