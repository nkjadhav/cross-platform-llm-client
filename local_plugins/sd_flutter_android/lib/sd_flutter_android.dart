import 'dart:async';
import 'package:flutter/services.dart';

class SdFlutterAndroid {
  static const MethodChannel _channel = MethodChannel('sd_flutter_android');

  static StreamController<Map<String, int>>? _progressController;

  Future<String?> getPlatformVersion() {
    return _channel.invokeMethod<String>('getPlatformVersion');
  }

  static Future<dynamic> initModelRaw(String path, {String? controlNetPath}) async {
    final result = await _channel.invokeMethod<dynamic>('initModel', {
      'path': path,
      'controlNetPath': controlNetPath ?? '',
    });
    return result;
  }

  static Future<bool> initModel(String path, {String? controlNetPath}) async {
    final result = await initModelRaw(path, controlNetPath: controlNetPath);
    if (result is bool) {
      return result;
    }
    if (result is String && result == 'true') {
      return true;
    }
    return false;
  }

  static Function(int step, int total)? _onProgress;

  static void _ensureInitialized() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onProgress') {
        final step = call.arguments['step'] as int;
        final total = call.arguments['total'] as int;
        _onProgress?.call(step, total);
      }
    });
  }

  static Future<Uint8List?> generateImage(
    String prompt, {
    int steps = 20,
    Function(int step, int total)? onProgress,
    Uint8List? referenceImage,
    int referenceWidth = 0,
    int referenceHeight = 0,
    double strength = 0.75,
    Uint8List? controlImage,
    int controlWidth = 0,
    int controlHeight = 0,
    double controlStrength = 1.0,
  }) async {
    _ensureInitialized();
    _onProgress = onProgress;

    final bytes = await _channel.invokeMethod<Uint8List>('generateImage', {
      'prompt': prompt,
      'steps': steps,
      'referenceImage': referenceImage,
      'referenceWidth': referenceWidth,
      'referenceHeight': referenceHeight,
      'strength': strength,
      'controlImage': controlImage,
      'controlWidth': controlWidth,
      'controlHeight': controlHeight,
      'controlStrength': controlStrength,
    });
    return bytes;
  }

  static Future<void> unloadModel() async {
    await _channel.invokeMethod('unloadModel');
  }
}
