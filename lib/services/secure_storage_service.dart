import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sunrise_signal/models/log_model.dart';

class SecureStorageService {
  static const _exportFormat = 'sunrise_signal_data';
  static const _exportVersion = 1;

  final FlutterSecureStorage _storage = const FlutterSecureStorage();

  // Load logs from secure storage
  Future<Map<DateTime, LogModel>> loadLogs() async {
    final logsJson = await _storage.read(key: 'logs');
    if (logsJson == null || logsJson.isEmpty) {
      return {}; // No logs stored
    }

    final Map<String, dynamic> decodedLogs = jsonDecode(logsJson);
    return decodedLogs.map((key, value) {
      final date = DateTime.parse(key);
      final logModel = LogModel.fromMap(Map<String, dynamic>.from(value));
      return MapEntry(date, logModel);
    });
  }

  // Save logs to secure storage
  Future<void> saveLogs(Map<DateTime, LogModel> logs) async {
    final logsJson = jsonEncode(
      logs.map((key, value) => MapEntry(key.toIso8601String(), value.toMap())),
    );
    await _storage.write(key: 'logs', value: logsJson);
  }

  String exportLogsJson(Map<DateTime, LogModel> logs) {
    return jsonEncode({
      'format': _exportFormat,
      'version': _exportVersion,
      'exportedAt': DateTime.now().toIso8601String(),
      'logs': logs.map(
        (key, value) => MapEntry(key.toIso8601String(), value.toMap()),
      ),
    });
  }

  Map<DateTime, LogModel> parseLogsJson(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object.');
    }

    late final dynamic logsData;
    if (decoded.containsKey('format')) {
      if (decoded['format'] != _exportFormat ||
          decoded['version'] != _exportVersion) {
        throw const FormatException('Unsupported export format or version.');
      }
      logsData = decoded['logs'];
    } else {
      logsData = decoded;
    }

    if (logsData is! Map<String, dynamic>) {
      throw const FormatException('Expected log entries.');
    }

    return logsData.map((key, value) {
      final date = DateTime.tryParse(key);
      if (date == null || value is! Map<String, dynamic>) {
        throw const FormatException('Invalid log entry.');
      }

      final sleepHours = value['sleepHours'];
      if (value['emoji'] is! String || sleepHours is! num) {
        throw const FormatException('Invalid log entry.');
      }
      for (final field in [
        'stressLevel',
        'exercise',
        'alcoholIntake',
        'caffeineIntake',
      ]) {
        if (value[field] != null && value[field] is! String) {
          throw const FormatException('Invalid log entry.');
        }
      }

      return MapEntry(date, LogModel.fromMap(value));
    });
  }

  Future<void> write({required String key, required String value}) async {
    await _storage.write(key: key, value: value);
  }

  Future<String?> read({required String key}) async {
    return await _storage.read(key: key);
  }

  Future<void> delete({required String key}) async {
    await _storage.delete(key: key);
  }
}
