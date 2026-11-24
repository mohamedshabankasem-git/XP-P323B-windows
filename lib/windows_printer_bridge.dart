import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Windows-only bridge for the native XP-P323B transport layer.
///
/// USB uses the Windows printer queue in RAW mode. Bluetooth uses an
/// outgoing Windows virtual COM port created by Windows when the printer
/// is paired. Pair the printer in Windows Settings before scanning.
class WindowsPrinterBridge {
  WindowsPrinterBridge._();

  static const MethodChannel _channel =
      MethodChannel('xp_p323b/windows_printer');

  static Future<List<Map<String, dynamic>>> listUsbPrinters() async {
    _requireWindows();
    final result = await _channel.invokeListMethod<Object?>('listUsbPrinters');
    return _asMaps(result);
  }

  static Future<List<Map<String, dynamic>>> listBluetoothPorts() async {
    _requireWindows();
    final result =
        await _channel.invokeListMethod<Object?>('listBluetoothPorts');
    return _asMaps(result);
  }

  static Future<void> connectUsb(String printerName) async {
    _requireWindows();
    await _channel.invokeMethod<void>(
      'connectUsb',
      <String, Object?>{'name': printerName},
    );
  }

  static Future<void> connectBluetooth(String port) async {
    _requireWindows();
    await _channel.invokeMethod<void>(
      'connectBluetooth',
      <String, Object?>{'port': port},
    );
  }

  static Future<int> write(List<int> bytes) async {
    _requireWindows();
    final written = await _channel.invokeMethod<int>(
      'write',
      <String, Object?>{'bytes': Uint8List.fromList(bytes)},
    );
    return written ?? 0;
  }

  static Future<void> disconnect() async {
    _requireWindows();
    await _channel.invokeMethod<void>('disconnect');
  }

  static void _requireWindows() {
    if (!Platform.isWindows) {
      throw UnsupportedError('The native printer bridge is available on Windows only.');
    }
  }

  static List<Map<String, dynamic>> _asMaps(List<Object?>? values) {
    return (values ?? const <Object?>[])
        .whereType<Map<Object?, Object?>>()
        .map((value) => value.map(
              (key, item) => MapEntry(key.toString(), item),
            ))
        .toList(growable: false);
  }
}
