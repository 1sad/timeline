// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tray_manager/legacy.dart';
import 'package:window_manager/window_manager.dart';

import 'models.dart';
import 'platform_services.dart';
import 'store.dart';
import 'theme.dart';
import 'timeline_page.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final TimelineStore store = TimelineStore();
  try {
    await store.load();
  } catch (error, stack) {
    debugPrint('Timeline startup failed: $error\n$stack');
    runApp(TimelineStartupError(error: error));
    return;
  }

  final NotificationService notifications = NotificationService();
  await notifications.initialize();

  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const WindowOptions options = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(760, 480),
      center: true,
      title: 'Timeline',
      backgroundColor: AppColors.bg,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(TimelineApp(store: store, notifications: notifications));
}

class TimelineApp extends StatelessWidget {
  const TimelineApp({
    super.key,
    required this.store,
    required this.notifications,
  });

  final TimelineStore store;
  final NotificationService notifications;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timeline',
      debugShowCheckedModeBanner: false,
      theme: buildTimelineTheme(),
      home: AppShell(store: store, notifications: notifications),
    );
  }
}

class TimelineStartupError extends StatelessWidget {
  const TimelineStartupError({super.key, required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Timeline',
      debugShowCheckedModeBanner: false,
      theme: buildTimelineTheme(),
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    const Icon(
                      Icons.error_outline,
                      size: 36,
                      color: AppColors.danger,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Timeline could not start',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 7),
                    const Text(
                      'Your data has not been changed. Please restart the app. '
                      'If this keeps happening, reinstall the latest build.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        color: AppColors.muted,
                      ),
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      '$error',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        height: 1.35,
                        color: AppColors.faint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store, required this.notifications});

  final TimelineStore store;
  final NotificationService notifications;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell>
    with WindowListener, TrayListener, WidgetsBindingObserver {
  final GlobalKey<TimelinePageState> _timelineKey =
      GlobalKey<TimelinePageState>();

  late final AlarmWatcher _alarmWatcher;
  bool _trayMode = false;
  bool _quitting = false;
  bool _switching = false;
  bool _isMaximized = false;
  Rect? _mainBounds;
  bool _mainWasMaximized = false;
  DateTime _ignoreBlurUntil = DateTime.fromMillisecondsSinceEpoch(0);

  TimelineStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _alarmWatcher = AlarmWatcher(
      store: widget.store,
      notifications: widget.notifications,
      onAlarm: _onAlarm,
    )..start();

    if (Platform.isWindows) {
      windowManager.addListener(this);
      unawaited(windowManager.setPreventClose(true));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_setupTray());
      });
    }
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(widget.notifications.requestPermission());
      });
    }
    if (Platform.isWindows) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          _isMaximized = await windowManager.isMaximized();
          if (mounted) setState(() {});
        } catch (_) {}
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _alarmWatcher.dispose();
    if (Platform.isWindows) {
      windowManager.removeListener(this);
      trayManager.removeListener(this);
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(store.flush());
    }
  }

  Future<void> _setupTray() async {
    if (!Platform.isWindows) return;
    try {
      await trayManager.setIcon('assets/tray_icon.png');
      await trayManager.setToolTip('Timeline');
      await trayManager.setContextMenu(
        Menu(
          items: <MenuItem>[
            MenuItem(
              key: 'open',
              label: 'Open timeline',
              onClick: (_) => unawaited(_showMain()),
            ),
            MenuItem(
              key: 'quick',
              label: 'Quick add',
              onClick: (_) => unawaited(_quickAdd()),
            ),
            MenuItem.separator(),
            MenuItem(
              key: 'quit',
              label: 'Quit Timeline',
              onClick: (_) => unawaited(_quit()),
            ),
          ],
        ),
      );
      trayManager.addListener(this);
    } catch (error) {
      debugPrint('Timeline tray unavailable: $error');
    }
  }

  Future<void> _toggleTrayPopup() async {
    if (!Platform.isWindows || _quitting || _switching) return;
    if (_trayMode) {
      final bool visible = await windowManager.isVisible();
      if (visible) {
        await windowManager.hide();
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
      return;
    }
    await _showTrayPopup();
  }

  Future<void> _showTrayPopup() async {
    if (!Platform.isWindows) return;
    _switching = true;
    try {
      _mainBounds = await windowManager.getBounds();
      _mainWasMaximized = await windowManager.isMaximized();
      if (_mainWasMaximized) {
        await windowManager.unmaximize();
      }
      await windowManager.setResizable(false);
      await windowManager.setMinimumSize(const Size(320, 260));
      await windowManager.setMaximumSize(const Size(600, 600));
      await windowManager.setAlwaysOnTop(true);
      await windowManager.setSkipTaskbar(true);
      await windowManager.setSize(const Size(380, 360));
      await windowManager.setAlignment(Alignment.bottomRight);
      final Offset position = await windowManager.getPosition();
      await windowManager.setPosition(position - const Offset(12, 12));
      if (mounted) setState(() => _trayMode = true);
      await windowManager.show();
      await windowManager.focus();
    } catch (error) {
      debugPrint('Timeline tray popup failed: $error');
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 220));
      _switching = false;
    }
  }

  Future<void> _showMain() async {
    if (!Platform.isWindows) return;
    if (_quitting) return;
    _switching = true;
    try {
      if (_trayMode) {
        await windowManager.setAlwaysOnTop(false);
        await windowManager.setSkipTaskbar(false);
        await windowManager.setResizable(true);
        await windowManager.setMaximumSize(const Size(1000000, 1000000));
        await windowManager.setMinimumSize(const Size(760, 480));
        if (_mainBounds != null) {
          await windowManager.setBounds(_mainBounds);
        }
        if (mounted) setState(() => _trayMode = false);
        await windowManager.show();
        await windowManager.focus();
        if (_mainWasMaximized) {
          await windowManager.maximize();
        }
      } else {
        await windowManager.show();
        await windowManager.focus();
      }
    } catch (error) {
      debugPrint('Timeline main window failed: $error');
    } finally {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      _switching = false;
    }
  }

  Future<void> _quickAdd() async {
    await _showMain();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _timelineKey.currentState?.openNewBlock();
  }

  Future<void> _focusBlock(int id) async {
    await _showMain();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    _timelineKey.currentState?.selectBlock(id);
  }

  Future<void> _hideToTray() async {
    if (!Platform.isWindows) return;
    await windowManager.hide();
  }

  Future<void> _quit() async {
    if (_quitting) return;
    _quitting = true;
    _alarmWatcher.dispose();
    try {
      await store.flush();
      if (Platform.isWindows) {
        trayManager.removeListener(this);
        windowManager.removeListener(this);
        await trayManager.destroy();
        await windowManager.setPreventClose(false);
        await windowManager.close();
      }
    } catch (error) {
      debugPrint('Timeline quit failed: $error');
      exit(0);
    }
  }

  @override
  void onWindowClose() {
    if (_quitting) return;
    unawaited(_hideToTray());
  }

  @override
  void onWindowBlur() {
    if (!_trayMode || _switching) return;
    if (DateTime.now().isBefore(_ignoreBlurUntil)) return;
    unawaited(windowManager.hide());
  }

  @override
  void onWindowMaximize() {
    if (!mounted) return;
    setState(() => _isMaximized = true);
  }

  @override
  void onWindowUnmaximize() {
    if (!mounted) return;
    setState(() => _isMaximized = false);
  }

  @override
  void onTrayIconMouseDown() {
    unawaited(_toggleTrayPopup());
  }

  @override
  void onTrayIconMouseUp() {}

  @override
  void onTrayIconRightMouseDown() {
    _ignoreBlurUntil = DateTime.now().add(const Duration(milliseconds: 700));
    unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayIconRightMouseUp() {}

  Future<void> _toggleMaximize() async {
    if (!Platform.isWindows) return;
    try {
      if (await windowManager.isMaximized()) {
        await windowManager.unmaximize();
      } else {
        await windowManager.maximize();
      }
    } catch (_) {}
  }

  void _onAlarm(Block block) {
    if (!mounted) return;
    if (_trayMode) unawaited(_showMain());
    final String message = 'Alarm · ${block.title} · ${fmtTime(block.start)}';
    Future<void>.delayed(const Duration(milliseconds: 230), () {
      if (!mounted) return;
      unawaited(
        showAppToast(
          context,
          message,
          icon: Icons.notifications_active_outlined,
          actionLabel: 'View',
          onAction: () => unawaited(_focusBlock(block.id)),
          duration: const Duration(seconds: 4),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) {
      return TimelinePage(key: _timelineKey, store: store);
    }
    return VirtualWindowFrame(
      child: Material(
        color: AppColors.bg,
        child: Column(
          children: <Widget>[
            if (!_trayMode) _buildTitleBar(),
            Expanded(
              child: _trayMode
                  ? TrayPopupPage(
                      store: store,
                      onClose: _hideToTray,
                      onOpen: _showMain,
                      onQuickAdd: _quickAdd,
                    )
                  : TimelinePage(key: _timelineKey, store: store),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return SizedBox(
      height: 34,
      child: Row(
        children: <Widget>[
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onDoubleTap: _toggleMaximize,
              onPanStart: (_) => unawaited(windowManager.startDragging()),
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: <Widget>[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.asset(
                        'assets/tray_icon.png',
                        width: 18,
                        height: 18,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.view_timeline_outlined,
                          size: 16,
                          color: Color(0xFFAFC6FF),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Timeline',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFFC7CEDB),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      fmtDayLong(DateTime.now()),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF737D8D),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
              ),
            ),
          ),
          _TitleBarButton(
            icon: Icons.remove,
            tooltip: 'Minimize',
            onPressed: () => unawaited(windowManager.minimize()),
          ),
          _TitleBarButton(
            icon: _isMaximized ? Icons.filter_none : Icons.crop_square,
            tooltip: _isMaximized ? 'Restore' : 'Maximize',
            iconSize: 13,
            onPressed: _toggleMaximize,
          ),
          _TitleBarButton(
            icon: Icons.close,
            tooltip: 'Close to tray',
            close: true,
            onPressed: _hideToTray,
          ),
        ],
      ),
    );
  }
}

class _TitleBarButton extends StatefulWidget {
  const _TitleBarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconSize = 15,
    this.close = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final double iconSize;
  final bool close;

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final Color background = _hover
        ? (widget.close ? const Color(0xFFC42B1C) : const Color(0xFF252C36))
        : Colors.transparent;
    final Color foreground = _hover
        ? (widget.close ? Colors.white : const Color(0xFFE1E7F0))
        : const Color(0xFFA3ADBC);
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: InkWell(
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: 34,
            color: background,
            child: Icon(widget.icon, size: widget.iconSize, color: foreground),
          ),
        ),
      ),
    );
  }
}

class TrayPopupPage extends StatefulWidget {
  const TrayPopupPage({
    super.key,
    required this.store,
    required this.onClose,
    required this.onOpen,
    required this.onQuickAdd,
  });

  final TimelineStore store;
  final Future<void> Function() onClose;
  final Future<void> Function() onOpen;
  final Future<void> Function() onQuickAdd;

  @override
  State<TrayPopupPage> createState() => _TrayPopupPageState();
}

class _TrayPopupPageState extends State<TrayPopupPage> {
  late DateTime _now;
  Timer? _timer;

  TimelineStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    store.addListener(_onStore);
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    _timer?.cancel();
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Block? get _currentEvent => store.currentBlock(_now);

  Block? get _currentZone {
    for (final Block block in store.blocks) {
      if (block.isZone &&
          !_now.isBefore(block.start) &&
          _now.isBefore(block.end)) {
        return block;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final Block? event = _currentEvent;
    final Block? zone = _currentZone;
    final Block? current = event ?? zone;
    final Track? currentTrack = current == null
        ? null
        : store.trackOrUncategorized(current.trackId);
    final List<Block> next = store.nextBlocks(_now, limit: 3);

    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF171B22),
          border: Border.all(color: const Color(0xFF333B47)),
        ),
        child: Column(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.fromLTRB(13, 10, 8, 9),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFF282F3A))),
              ),
              child: Row(
                children: <Widget>[
                  const Text(
                    'Timeline',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${fmtTime(_now)} · ${fmtDayLong(_now)}',
                    style: const TextStyle(
                      fontSize: 9.5,
                      color: AppColors.muted,
                      fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Tooltip(
                    message: 'Close',
                    child: InkWell(
                      onTap: () => unawaited(widget.onClose()),
                      borderRadius: BorderRadius.circular(5),
                      child: const SizedBox(
                        width: 25,
                        height: 25,
                        child: Icon(
                          Icons.close,
                          size: 14,
                          color: AppColors.faint,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(13, 11, 13, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    const Text('NOW', style: AppText.kicker),
                    const SizedBox(height: 6),
                    if (current == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 7),
                        child: Text(
                          'Nothing scheduled',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: AppColors.text,
                          ),
                        ),
                      )
                    else
                      _NowCard(
                        block: current,
                        track: currentTrack!,
                        now: _now,
                        zone: event == null,
                      ),
                    const SizedBox(height: 14),
                    const Text('NEXT', style: AppText.kicker),
                    const SizedBox(height: 5),
                    if (next.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 6),
                        child: Text(
                          'Nothing coming up',
                          style: TextStyle(
                            fontSize: 10.5,
                            color: AppColors.muted,
                          ),
                        ),
                      )
                    else
                      for (final Block block in next)
                        _NextRow(
                          block: block,
                          track: store.trackOrUncategorized(block.trackId),
                          now: _now,
                          onTap: () => unawaited(widget.onOpen()),
                        ),
                  ],
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: Color(0xFF282F3A))),
                color: Color(0xFF14181F),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: ToastButton(
                      label: 'Open timeline',
                      icon: Icons.open_in_full,
                      primary: true,
                      onPressed: () => unawaited(widget.onOpen()),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: ToastButton(
                      label: 'Quick add',
                      icon: Icons.add,
                      onPressed: () => unawaited(widget.onQuickAdd()),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NowCard extends StatelessWidget {
  const _NowCard({
    required this.block,
    required this.track,
    required this.now,
    required this.zone,
  });

  final Block block;
  final Track track;
  final DateTime now;
  final bool zone;

  @override
  Widget build(BuildContext context) {
    final double total = math.max(
      1.0,
      (block.end.millisecondsSinceEpoch - block.start.millisecondsSinceEpoch)
          .toDouble(),
    );
    final double progress =
        ((now.millisecondsSinceEpoch - block.start.millisecondsSinceEpoch) /
                total)
            .clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 9, 11, 10),
      decoration: BoxDecoration(
        color: AppColors.alpha(track.color, .08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.alpha(track.color, .25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: track.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  block.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
              if (zone)
                const Text(
                  'ZONE',
                  style: TextStyle(
                    fontSize: 7.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .6,
                    color: AppColors.muted,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${fmtTime(block.start)}–${fmtTime(block.end)} · '
            '${blockMeta(block, now)}',
            style: const TextStyle(
              fontSize: 9.5,
              color: AppColors.muted,
              fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: const Color(0xFF2A303B),
              valueColor: AlwaysStoppedAnimation<Color>(
                zone ? AppColors.alpha(track.color, .42) : track.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NextRow extends StatelessWidget {
  const _NextRow({
    required this.block,
    required this.track,
    required this.now,
    required this.onTap,
  });

  final Block block;
  final Track track;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final bool sameDay = isSameLocalDay(block.start, now);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                color: track.color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                block.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.text),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${sameDay ? '' : '${fmtDay(block.start)} · '}'
              '${fmtTime(block.start)} · ${blockMeta(block, now)}',
              style: const TextStyle(
                fontSize: 9,
                color: AppColors.muted,
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

bool isSameLocalDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
