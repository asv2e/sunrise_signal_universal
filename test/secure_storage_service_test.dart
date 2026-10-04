import 'package:flutter_test/flutter_test.dart';
import 'package:sunrise_signal/services/secure_storage_service.dart';

void main() {
  final storageService = SecureStorageService();

  test('parses versioned data exports', () {
    final logs = storageService.parseLogsJson('''
      {
        "format": "sunrise_signal_data",
        "version": 1,
        "logs": {
          "2026-10-04T00:00:00.000": {
            "emoji": "🙂",
            "sleepHours": 7.5
          }
        }
      }
    ''');

    expect(logs.length, 1);
    expect(logs.values.single.sleepHours, 7.5);
  });

  test('continues to parse legacy log exports', () {
    final logs = storageService.parseLogsJson('''
      {
        "2026-10-04T00:00:00.000": {
          "emoji": "🙂",
          "sleepHours": 7
        }
      }
    ''');

    expect(logs.values.single.sleepHours, 7);
  });

  test('rejects unsupported export versions', () {
    expect(
      () => storageService.parseLogsJson(
        '{"format":"sunrise_signal_data","version":2,"logs":{}}',
      ),
      throwsFormatException,
    );
  });
}