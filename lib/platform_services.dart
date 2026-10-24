import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'models.dart';
import 'store.dart';

/// Immediate, in-process notifications. No alarms are scheduled with the OS:
/// if Timeline is not running, it stays quiet, which is the intended rule.
class NotificationService {
  NotificationService();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> initialize() async {
    if (!Platform.isWindows && !Platform.isAndroid) return;
    try {
      const InitializationSettings settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        windows: WindowsInitializationSettings(
          appName: 'Timeline',
          appUserModelId: '1sad.Timeline',
          guid: '7d3e7a2c-9f6a-4c1e-9b4e-3f6b0a4a2c91',
        ),
      );
      await _plugin.initialize(settings: settings);
      _initialized = true;
    } catch (error) {
      debugPrint('Timeline notifications unavailable: $error');
    }
  }

  Future<void> requestPermission() async {
    if (!Platform.isAndroid || !_initialized) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
    } catch (error) {
      debugPrint('Timeline notification permission request failed: $error');
    }
  }

  Future<void> showAlarm(Block block, Track? track) async {
    if (!_initialized) return;
    try {
      await _plugin.show(
        id: block.id,
        title: block.title,
        body: '${fmtTime(block.start)} · ${track?.name ?? 'Timeline'}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'timeline_alarms',
            'Timeline alarms',
            channelDescription: 'Alarms attached to blocks in Timeline',
            importance: Importance.high,
            priority: Priority.high,
            playSound: true,
          ),
          windows: WindowsNotificationDetails(
            duration: WindowsNotificationDuration.short,
          ),
        ),
        payload: 'block:${block.id}',
      );
    } catch (error) {
      debugPrint('Timeline notification failed: $error');
    }
  }
}

class AlarmWatcher {
  AlarmWatcher({
    required this.store,
    required this.notifications,
    required this.onAlarm,
  });

  final TimelineStore store;
  final NotificationService notifications;
  final void Function(Block block) onAlarm;

  Timer? _timer;
  final Set<int> _handled = <int>{};

  void start() {
    if (_timer != null) return;
    final DateTime now = DateTime.now();
    for (final Block block in store.blocks) {
      if (block.alarm && !block.start.isAfter(now)) _handled.add(block.id);
    }
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => check());
  }

  void check() {
    final DateTime now = DateTime.now();
    for (final Block block in List<Block>.of(store.blocks)) {
      if (!block.alarm || _handled.contains(block.id)) continue;
      if (block.start.isAfter(now)) continue;
      if (now.difference(block.start) > const Duration(seconds: 60)) {
        _handled.add(block.id);
        continue;
      }
      _handled.add(block.id);
      final Track? track = store.trackById(block.trackId);
      unawaited(notifications.showAlarm(block, track));
      onAlarm(block);
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
