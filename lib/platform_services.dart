import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import 'models.dart';
import 'store.dart';

/// Shows immediate notifications on Windows and schedules real OS alarms on
/// Android. Android alarms survive the app going to the background (and the
/// process being killed) because the system owns the schedule.
class NotificationService {
  NotificationService();

  static const String _channelId = 'timeline_alarms_v2';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _exactAllowed = false;
  Timer? _syncTimer;

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

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
      if (Platform.isAndroid) {
        _exactAllowed =
            await _android?.canScheduleExactNotifications() ?? false;
      }
    } catch (error) {
      debugPrint('Timeline notifications unavailable: $error');
    }
  }

  Future<void> requestPermission() async {
    if (!Platform.isAndroid || !_initialized) return;
    try {
      await _android?.requestNotificationsPermission();
      if (await _android?.canScheduleExactNotifications() != true) {
        await _android?.requestExactAlarmsPermission();
      }
      _exactAllowed = await _android?.canScheduleExactNotifications() ?? false;
    } catch (error) {
      debugPrint('Timeline notification permission request failed: $error');
    }
  }

  /// Re-reads the exact-alarm grant. Android sends the user to Settings for
  /// this permission, so the grant can change while the app is paused.
  Future<void> refreshPermissions() async {
    if (!Platform.isAndroid || !_initialized) return;
    try {
      _exactAllowed = await _android?.canScheduleExactNotifications() ?? false;
    } catch (error) {
      debugPrint('Timeline notification permission check failed: $error');
    }
  }

  /// Immediately presents an alarm. Used on Windows, where Timeline owns the
  /// timer, and as a fallback when scheduling is unavailable.
  Future<void> showAlarm(
    Block block,
    Track? track, [
    AlarmOffset offset = AlarmOffset.start,
  ]) async {
    if (!_initialized) return;
    try {
      final DateTime? at = offset.timeFor(block);
      await _plugin.show(
        id: _notificationId(block.id, offset),
        title: block.title,
        body:
            '${offset.label} · ${fmtTime(at ?? block.start)} · '
            '${track?.name ?? 'Timeline'}',
        notificationDetails: _details,
        payload: 'block:${block.id}',
      );
    } catch (error) {
      debugPrint('Timeline notification failed: $error');
    }
  }

  /// Replaces every pending Android alarm with the current block list.
  Future<void> sync(TimelineStore store) async {
    if (!Platform.isAndroid || !_initialized) return;
    try {
      await _plugin.cancelAllPendingNotifications();
      final DateTime now = DateTime.now();
      final List<({Block block, Track? track, AlarmOffset offset, DateTime at})>
      pending =
          <({Block block, Track? track, AlarmOffset offset, DateTime at})>[];
      for (final Block block in store.blocks) {
        if (block.alarms.isEmpty) continue;
        final Track? track = store.trackById(block.trackId);
        for (final AlarmOffset offset in block.alarms) {
          final DateTime? at = offset.timeFor(block);
          if (at == null || !at.isAfter(now)) continue;
          pending.add((block: block, track: track, offset: offset, at: at));
        }
      }
      // Android caps the number of exact alarms per app, and a long hourly
      // series can generate a lot of them. The nearest ones matter most.
      pending.sort((a, b) => a.at.compareTo(b.at));
      for (final ({Block block, Track? track, AlarmOffset offset, DateTime at})
          item
          in pending.take(400)) {
        try {
          await _schedule(item.block, item.track, item.offset, item.at);
        } catch (error) {
          debugPrint('Timeline could not schedule an alarm: $error');
        }
      }
    } catch (error) {
      debugPrint('Timeline alarm sync failed: $error');
    }
  }

  /// Store notifications arrive on every drag frame, so scheduling is
  /// coalesced until the user pauses.
  void syncDebounced(TimelineStore store) {
    if (!Platform.isAndroid || !_initialized) return;
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(milliseconds: 700), () {
      _syncTimer = null;
      unawaited(sync(store));
    });
  }

  Future<void> _schedule(
    Block block,
    Track? track,
    AlarmOffset offset,
    DateTime at,
  ) async {
    Future<void> send(AndroidScheduleMode mode) => _plugin.zonedSchedule(
      id: _notificationId(block.id, offset),
      scheduledDate: tz.TZDateTime.from(at, tz.UTC),
      title: block.title,
      body:
          '${offset.label} · ${fmtTime(at)} · '
          '${track?.name ?? 'Timeline'}',
      notificationDetails: _details,
      androidScheduleMode: mode,
      payload: 'block:${block.id}',
    );

    if (_exactAllowed) {
      try {
        await send(AndroidScheduleMode.exactAllowWhileIdle);
        return;
      } catch (error) {
        // Some devices report that exact alarms are allowed but still reject
        // them. Fall back to an inexact alarm instead of dropping the alert.
        _exactAllowed = false;
        debugPrint('Timeline exact alarm rejected: $error');
      }
    }
    await send(AndroidScheduleMode.inexactAllowWhileIdle);
  }

  int _notificationId(int blockId, AlarmOffset offset) =>
      blockId * AlarmOffset.values.length + offset.index;

  NotificationDetails get _details => const NotificationDetails(
    android: AndroidNotificationDetails(
      _channelId,
      'Timeline alarms',
      channelDescription: 'Start, middle and end alerts for blocks in Timeline',
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      category: AndroidNotificationCategory.alarm,
      visibility: NotificationVisibility.public,
    ),
    windows: WindowsNotificationDetails(
      duration: WindowsNotificationDuration.short,
    ),
  );

  void dispose() {
    _syncTimer?.cancel();
    _syncTimer = null;
  }
}

/// In-process watcher used for the in-app toast. Android alerts are also
/// scheduled with the OS, so this only presents a banner while the app is
/// running; Windows relies on it for the system notification too.
class AlarmWatcher {
  AlarmWatcher({
    required this.store,
    required this.notifications,
    required this.onAlarm,
  });

  final TimelineStore store;
  final NotificationService notifications;
  final void Function(Block block, AlarmOffset offset) onAlarm;

  Timer? _timer;
  final Set<String> _handled = <String>{};

  void start() {
    if (_timer != null) return;
    final DateTime now = DateTime.now();
    for (final Block block in store.blocks) {
      for (final AlarmOffset offset in block.alarms) {
        final DateTime? at = offset.timeFor(block);
        if (at != null && !at.isAfter(now)) _handled.add(_key(block, offset));
      }
    }
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => check());
  }

  void check() {
    final DateTime now = DateTime.now();
    for (final Block block in List<Block>.of(store.blocks)) {
      for (final AlarmOffset offset in block.alarms) {
        final String key = _key(block, offset);
        if (_handled.contains(key)) continue;
        final DateTime? at = offset.timeFor(block);
        if (at == null || at.isAfter(now)) continue;
        if (now.difference(at) > const Duration(seconds: 90)) {
          _handled.add(key);
          continue;
        }
        _handled.add(key);
        if (!Platform.isAndroid) {
          final Track? track = store.trackById(block.trackId);
          unawaited(notifications.showAlarm(block, track, offset));
        }
        onAlarm(block, offset);
      }
    }
  }

  String _key(Block block, AlarmOffset offset) => '${block.id}:${offset.name}';

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
