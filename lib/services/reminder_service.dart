import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';

class ReminderService {
  static const String _reminderKey = 'isReminderEnabled';
  static const String _reminderHourKey = 'reminderHour';
  static const String _reminderMinuteKey = 'reminderMinute';
  static const String _windowsScheduledThroughKey = 'windowsReminderThrough';
  static const String _windowsScheduleTimezoneKey = 'windowsReminderTimezone';
  static const int _windowsScheduleHorizonDays = 365;
  static const int _windowsScheduleRefreshDays = 30;
  static const _secureStorage = FlutterSecureStorage();

  static final FlutterLocalNotificationsPlugin
      _flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
  static Timer? _linuxReminderTimer;

  static bool get supportsDailyReminders =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows);

  Future<void> initNotifications() async {
    if (!supportsDailyReminders) return;

    tz.initializeTimeZones();
    final timezoneInfo = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(timezoneInfo.identifier));

    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    final initializationSettings = InitializationSettings(
      android: defaultTargetPlatform == TargetPlatform.android
          ? androidSettings
          : null,
      iOS: defaultTargetPlatform == TargetPlatform.iOS ? darwinSettings : null,
      macOS:
          defaultTargetPlatform == TargetPlatform.macOS ? darwinSettings : null,
      linux: defaultTargetPlatform == TargetPlatform.linux
          ? const LinuxInitializationSettings(
              defaultActionName: 'Open notification',
            )
          : null,
      windows: defaultTargetPlatform == TargetPlatform.windows
          ? const WindowsInitializationSettings(
              appName: 'Sunrise Signal',
              appUserModelId: 'Asv2e.SunriseSignal',
              guid: '7b951a74-18d2-4ee1-8aa5-4ff170954772',
            )
          : null,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      settings: initializationSettings,
    );
    unawaited(
      _restoreReminder().catchError((Object error, StackTrace stackTrace) {
        FlutterError.reportError(
          FlutterErrorDetails(
            exception: error,
            stack: stackTrace,
            library: 'reminder service',
            context: ErrorDescription('while restoring scheduled reminders'),
          ),
        );
      }),
    );
  }

  Future<bool> requestNotificationPermission() async {
    if (!supportsDailyReminders) return false;

    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return await _flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation<
                    AndroidFlutterLocalNotificationsPlugin>()
                ?.requestNotificationsPermission() ??
            false;
      case TargetPlatform.iOS:
        return await _flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      case TargetPlatform.macOS:
        return await _flutterLocalNotificationsPlugin
                .resolvePlatformSpecificImplementation<
                    MacOSFlutterLocalNotificationsPlugin>()
                ?.requestPermissions(alert: true, badge: true, sound: true) ??
            false;
      case TargetPlatform.linux:
      case TargetPlatform.windows:
        return true;
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  NotificationDetails notificationDetails() {
    return const NotificationDetails(
      android: AndroidNotificationDetails(
        'daily_reminder_channel',
        'Daily Reminder',
        channelDescription: 'Daily reminder notifications',
        importance: Importance.low,
        priority: Priority.low,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
      linux: LinuxNotificationDetails(),
      windows: WindowsNotificationDetails(),
    );
  }

  Future<void> scheduleDailyReminder({
    required int hour,
    required int minute,
  }) async {
    if (!supportsDailyReminders) {
      throw UnsupportedError(
        'Daily reminders are not supported on this platform.',
      );
    }

    switch (defaultTargetPlatform) {
      case TargetPlatform.linux:
        _scheduleNextLinuxReminder(hour: hour, minute: minute);
      case TargetPlatform.windows:
        await _scheduleWindowsReminders(hour: hour, minute: minute);
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
        await _scheduleNativeDailyReminder(hour: hour, minute: minute);
      case TargetPlatform.fuchsia:
        throw UnsupportedError(
          'Daily reminders are not supported on this platform.',
        );
    }

    await _saveReminderTime(hour, minute);
    await _saveReminderState(true);
  }

  Future<void> _scheduleNativeDailyReminder({
    required int hour,
    required int minute,
  }) async {
    final now = tz.TZDateTime.now(tz.local);
    final scheduledDate = _nextOccurrence(now, hour, minute);
    await _flutterLocalNotificationsPlugin.zonedSchedule(
      0,
      'Did you wake up with morning wood?',
      null,
      scheduledDate,
      notificationDetails(),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  Future<void> _scheduleWindowsReminders({
    required int hour,
    required int minute,
  }) async {
    await _secureStorage.delete(key: _windowsScheduledThroughKey);
    await _flutterLocalNotificationsPlugin.cancelAll();
    final now = tz.TZDateTime.now(tz.local);
    final firstOccurrence = _nextOccurrence(now, hour, minute);

    for (var day = 0; day < _windowsScheduleHorizonDays; day++) {
      final scheduledDate = tz.TZDateTime(
        tz.local,
        firstOccurrence.year,
        firstOccurrence.month,
        firstOccurrence.day + day,
        hour,
        minute,
      );
      await _flutterLocalNotificationsPlugin.zonedSchedule(
        day,
        'Did you wake up with morning wood?',
        null,
        scheduledDate,
        notificationDetails(),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
      if (day % 25 == 24) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    final scheduledThrough = tz.TZDateTime(
      tz.local,
      firstOccurrence.year,
      firstOccurrence.month,
      firstOccurrence.day + _windowsScheduleHorizonDays - 1,
    );
    await _secureStorage.write(
      key: _windowsScheduledThroughKey,
      value: '${scheduledThrough.year.toString().padLeft(4, '0')}-'
          '${scheduledThrough.month.toString().padLeft(2, '0')}-'
          '${scheduledThrough.day.toString().padLeft(2, '0')}',
    );
    await _secureStorage.write(
      key: _windowsScheduleTimezoneKey,
      value: tz.local.name,
    );
  }

  static void _scheduleNextLinuxReminder({
    required int hour,
    required int minute,
  }) {
    _linuxReminderTimer?.cancel();
    final now = tz.TZDateTime.now(tz.local);
    final next = _nextOccurrence(now, hour, minute);
    _linuxReminderTimer = Timer(next.difference(now), () {
      _scheduleNextLinuxReminder(hour: hour, minute: minute);
      unawaited(
        _flutterLocalNotificationsPlugin.show(
          0,
          'Did you wake up with morning wood?',
          null,
          const NotificationDetails(
            linux: LinuxNotificationDetails(),
          ),
        ),
      );
    });
  }

  static tz.TZDateTime _nextOccurrence(
    tz.TZDateTime now,
    int hour,
    int minute,
  ) {
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!next.isAfter(now)) {
      next = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
        hour,
        minute,
      );
    }
    return next;
  }

  Future<void> _restoreReminder() async {
    if (!await isReminderEnabled()) return;
    final time = await getReminderTime();
    if (time == null) return;

    switch (defaultTargetPlatform) {
      case TargetPlatform.linux:
        _scheduleNextLinuxReminder(hour: time.hour, minute: time.minute);
      case TargetPlatform.windows:
        if (!await _windowsQueueNeedsRefresh()) return;
        await _scheduleWindowsReminders(hour: time.hour, minute: time.minute);
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.macOS:
      case TargetPlatform.fuchsia:
        break;
    }
  }

  Future<bool> _windowsQueueNeedsRefresh() async {
    final scheduledThrough =
        await _secureStorage.read(key: _windowsScheduledThroughKey);
    final scheduledTimezone =
        await _secureStorage.read(key: _windowsScheduleTimezoneKey);
    if (scheduledThrough == null || scheduledTimezone != tz.local.name) {
      return true;
    }

    final throughDate = DateTime.tryParse(scheduledThrough);
    if (throughDate == null) return true;
    final through = tz.TZDateTime(
      tz.local,
      throughDate.year,
      throughDate.month,
      throughDate.day,
    );
    final refreshAfter = tz.TZDateTime.now(tz.local).add(
      const Duration(days: _windowsScheduleRefreshDays),
    );
    return !through.isAfter(refreshAfter);
  }

  static Future<void> cancelReminders() async {
    _linuxReminderTimer?.cancel();
    _linuxReminderTimer = null;
    if (supportsDailyReminders) {
      await _flutterLocalNotificationsPlugin.cancelAll();
    }
    await _saveReminderState(false);
    await _deleteReminderTime();
  }

  static Future<void> _saveReminderState(bool isEnabled) async {
    await _secureStorage.write(
      key: _reminderKey,
      value: isEnabled.toString(),
    );
  }

  static Future<void> _saveReminderTime(int hour, int minute) async {
    await _secureStorage.write(key: _reminderHourKey, value: hour.toString());
    await _secureStorage.write(
        key: _reminderMinuteKey, value: minute.toString());
  }

  static Future<void> _deleteReminderTime() async {
    await _secureStorage.delete(key: _reminderHourKey);
    await _secureStorage.delete(key: _reminderMinuteKey);
  }

  static Future<bool> isReminderEnabled() async {
    final state = await _secureStorage.read(key: _reminderKey);
    return state == 'true';
  }

  static Future<TimeOfDay?> getReminderTime() async {
    final hourStr = await _secureStorage.read(key: _reminderHourKey);
    final minuteStr = await _secureStorage.read(key: _reminderMinuteKey);

    if (hourStr != null && minuteStr != null) {
      return TimeOfDay(
        hour: int.parse(hourStr),
        minute: int.parse(minuteStr),
      );
    }
    return null;
  }
}
