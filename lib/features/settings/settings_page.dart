import 'dart:convert';
import 'package:flutter/foundation.dart'
  show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_auth/local_auth.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:sunrise_signal/services/theme_service.dart';
import '../../services/auth_service.dart';
import '../../services/reminder_service.dart';
import '../../services/secure_storage_service.dart';
import '../../models/log_model.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _isPasscodeSet = false;
  bool _hasDeviceAuthentication = false;
  bool _isBiometricEnabled = false;
  bool _isReminderEnabled = false;
  TimeOfDay? _reminderTime;
  bool _isAuthenticating = false;

  final AuthService _authService = AuthService();
  final SecureStorageService _storageService = SecureStorageService();
  final LocalAuthentication _localAuth = LocalAuthentication();
  Map<DateTime, LogModel> _logs = {};

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkDeviceAuthentication();
    _loadLogs();
  }

  Future<void> _loadSettings() async {
    final passcodeSet = await _authService.isPasscodeSet();
    final biometricEnabled = await _authService.isBiometricEnabled();
    final reminderEnabled = await ReminderService.isReminderEnabled();
    final reminderTime = await ReminderService.getReminderTime();
    setState(() {
      _isPasscodeSet = passcodeSet;
      _isBiometricEnabled = biometricEnabled;
      _isReminderEnabled = reminderEnabled;
      _reminderTime = reminderTime;
    });
  }

  Future<void> _checkDeviceAuthentication() async {
    try {
      final isDeviceSupported = await _localAuth.isDeviceSupported();
      if (!mounted) return;
      setState(() {
        _hasDeviceAuthentication = isDeviceSupported;
      });
    } catch (error) {
      debugPrint('Device authentication check failed: $error');
      if (mounted) {
        setState(() {
          _hasDeviceAuthentication = false;
        });
      }
    }
  }

  Future<void> _loadLogs() async {
    final logs = await _storageService.loadLogs();
    setState(() {
      _logs = logs;
    });
  }

  Future<void> _togglePasscode(bool value) async {
    if (value) {
      await showSetPasscodeDialog(context);
      if (!mounted) return;
    } else {
      await _authService.removePasscode();
      if (!mounted) return;
      setState(() {
        _isPasscodeSet = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passcode removed successfully!')),
      );
    }
  }

  Future<void> _toggleBiometric(bool value) async {
    if (_isAuthenticating) return;
    setState(() {
      _isAuthenticating = true;
    });

    bool authenticated = false;
    try {
      authenticated = await _localAuth.authenticate(
        localizedReason: 'Authenticate with your device to continue',
        options: const AuthenticationOptions(biometricOnly: false),
      );
    } catch (error) {
      debugPrint('Authentication error: $error');
    }

    if (!mounted) return;

    if (authenticated) {
      if (value) {
        await _enableBiometricLock();
        if (!mounted) return;
        setState(() {
          _isAuthenticating = false;
        });
      } else {
        await _authService.disableBiometricLock();
        if (!mounted) return;
        setState(() {
          _isBiometricEnabled = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disabled Biometric/Device Lock!')),
        );
        setState(() {
          _isAuthenticating = false;
        });
      }
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Authentication failed')),
      );
      setState(() {
        _isAuthenticating = false;
      });
    }
  }

  Future<bool> _requestNotificationPermission() async {
    FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
        FlutterLocalNotificationsPlugin();

    bool? notificationPermission = await flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();

    if (notificationPermission == null || !notificationPermission) {
      if (!mounted) return false;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:
              Text('Notification permission is required to enable reminders.'),
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _toggleReminder(bool value) async {
    if (value) {
      await _pickTimeAndSetReminder();
      if (!mounted) return;
      return;
    }

    await ReminderService.cancelReminders();
    if (!mounted) return;
    setState(() {
      _isReminderEnabled = false;
      _reminderTime = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Daily reminder disabled.')),
    );
  }

  Future<void> _pickTimeAndSetReminder() async {
    bool permissionGranted = await _requestNotificationPermission();
    if (!permissionGranted) return; // Stop if no permission

    final TimeOfDay? pickedTime = await showTimePicker(
      context: context,
      initialTime: _reminderTime ?? TimeOfDay.now(),
    );

    if (pickedTime != null) {
      if (!mounted) return;
      setState(() {
        _reminderTime = pickedTime;
      });
      await ReminderService().scheduleDailyReminder(
        hour: pickedTime.hour,
        minute: pickedTime.minute,
      );
      if (!mounted) return;
      setState(() {
        _isReminderEnabled = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Daily reminder set!')),
      );
    }
  }

  Future<void> showSetPasscodeDialog(BuildContext context) async {
    final TextEditingController passcodeController = TextEditingController();
    final TextEditingController confirmPasscodeController =
        TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set Passcode'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passcodeController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Enter Passcode',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmPasscodeController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm Passcode',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final String passcode = passcodeController.text.trim();
                final String confirmPasscode =
                    confirmPasscodeController.text.trim();

                if (passcode.isEmpty || confirmPasscode.isEmpty) {
                  _showErrorDialog(context, 'Passcode cannot be blank.');
                  return;
                }

                if (passcode != confirmPasscode) {
                  _showErrorDialog(context, 'Passcodes do not match.');
                  return;
                }

                final dialogContext = context;
                final messenger = ScaffoldMessenger.maybeOf(dialogContext);
                await _authService.setPasscode(passcode);
                if (!mounted) return;
                setState(() {
                  _isPasscodeSet = true;
                });

                if (Navigator.of(dialogContext).canPop()) {
                  Navigator.pop(dialogContext);
                }

                messenger?.showSnackBar(
                  const SnackBar(content: Text('Passcode set successfully!')),
                );
              },
              child: const Text('Set Passcode'),
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _enableBiometricLock() async {
    await _authService.enableBiometricLock();
    if (!mounted) return;
    setState(() {
      _isBiometricEnabled = true;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Enabled Biometric/Device Lock!')),
    );
  }

  Future<void> _exportLogs() async {
    try {
      final logsBytes = Uint8List.fromList(
        utf8.encode(_storageService.exportLogsJson(_logs)),
      );
      final path = await FilePicker.platform.saveFile(
        allowedExtensions: ['json'],
        type: FileType.custom,
        dialogTitle: 'Export your data',
        fileName: 'sunrise_signal_data_export.json',
        bytes: logsBytes,
      );
      if (!mounted || (path == null && !kIsWeb)) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data exported successfully.')),
      );
    } on PlatformException catch (error) {
      _logException('Unsupported operation: $error');
      _showDataError('Could not export data on this device.');
    } catch (e) {
      _logException('Error: $e');
      _showDataError('Could not export data.');
    }
  }

  void _logException(String message) {
    debugPrint('Exception: $message');
  }

  Future<void> _importLogs() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (result == null) return;

      final bytes = result.files.single.bytes;
      if (bytes == null) {
        throw const FormatException('The selected file could not be read.');
      }
      final importedLogs = _storageService.parseLogsJson(utf8.decode(bytes));
      if (!mounted) return;

      final shouldReplace = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Replace current data?'),
          content: Text(
            'Import ${importedLogs.length} log entries and replace your current logs? Passcode and biometric settings are not included.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (shouldReplace != true || !mounted) return;

      await _storageService.saveLogs(importedLogs);
      if (!mounted) return;
      setState(() {
        _logs = importedLogs;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Data imported successfully.')),
      );
    } on FormatException {
      _showDataError('This file is not a valid Sunrise Signal data export.');
    } on PlatformException catch (error) {
      _logException('Unsupported operation: $error');
      _showDataError('Could not import data on this device.');
    } catch (error) {
      _logException('Error: $error');
      _showDataError('Could not import data.');
    }
  }

  void _showDataError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    int flag = 0;
    bool locked = true;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          ListTile(
            title: const Text('Daily Reminder'),
            subtitle: Text(
              _isReminderEnabled && _reminderTime != null
                  ? _reminderTime!.format(context)
                  : 'Off',
            ),
            trailing: Switch(
              value: _isReminderEnabled,
              onChanged: (value) async {
                if (value) {
                  await _pickTimeAndSetReminder();
                } else {
                  await _toggleReminder(false);
                }
              },
            ),
            onTap: () async {
              if (!_isReminderEnabled) {
                await _pickTimeAndSetReminder();
              }
            },
          ),
          const Divider(),
          ListTile(
            title: const Text('Enable Passcode Lock'),
            trailing: Switch(
              value: _isPasscodeSet,
              onChanged: _togglePasscode,
            ),
          ),
          if (_hasDeviceAuthentication)
            ListTile(
              title: const Text('Enable Biometric/Device Lock'),
              trailing: Switch(
                value: _isBiometricEnabled,
                onChanged: _toggleBiometric,
              ),
            ),
          if (!_hasDeviceAuthentication)
            ListTile(
              title: const Text('Biometric/Device Lock Unavailable'),
              subtitle: Text(
                kIsWeb || defaultTargetPlatform == TargetPlatform.linux
                    ? 'System authentication is not supported on Web or Linux. Use the passcode lock instead.'
                    : 'This device does not provide system authentication. Use the passcode lock instead.',
              ),
            ),
          const Divider(),
          ListTile(
            title: const Text('Dark Theme'),
            trailing: Consumer<ThemeService>(
              builder: (context, themeService, _) => Switch(
                value: themeService.isDarkMode,
                onChanged: (value) {
                  themeService.toggleDarkMode(value);
                },
              ),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Export Data'),
            trailing: IconButton(
              icon: const Icon(Icons.download),
              onPressed: _exportLogs,
            ),
            onTap: _exportLogs,
          ),
          ListTile(
            title: const Text('Import Data'),
            trailing: IconButton(
              icon: const Icon(Icons.upload),
              onPressed: _importLogs,
            ),
            onTap: _importLogs,
          ),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () {
              if (flag > 8) {
                locked = false;
              }
              flag++;
            },
            onLongPress: () {
              if (!locked) {
                showDialog<String>(
                  context: context,
                  builder: (BuildContext context) => AlertDialog(
                    content: Padding(
                      padding: const EdgeInsets.all(15.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Developed by Avizit Roy\nWebsite: avizitRX.com',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge,
                          ),
                        ],
                      ),
                    ),
                    actions: <Widget>[
                      TextButton(
                        onPressed: () => Navigator.pop(context, 'Close'),
                        child: const Text('Close'),
                      ),
                    ],
                  ),
                );
              }
            },
            child: const Center(
              child: Text('Sunrise Signal v2.0.0'),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
