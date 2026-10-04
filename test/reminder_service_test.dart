import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sunrise_signal/services/reminder_service.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('daily reminders are supported on Android, iOS, and macOS', () {
    for (final platform in [
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    ]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(ReminderService.supportsDailyReminders, isTrue);
    }
  });

  test('daily reminders are supported on Linux and Windows', () {
    for (final platform in [TargetPlatform.linux, TargetPlatform.windows]) {
      debugDefaultTargetPlatformOverride = platform;
      expect(ReminderService.supportsDailyReminders, isTrue);
    }
  });

  test('daily reminders are unsupported on Fuchsia', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.fuchsia;
    expect(ReminderService.supportsDailyReminders, isFalse);
  });
}
