import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'sheets.dart';
import 'store.dart';
import 'theme.dart';
import 'timeline_canvas.dart';
import 'timeline_painters.dart';
import 'widgets.dart';

class TimelinePage extends StatefulWidget {
  const TimelinePage({super.key, required this.store});

  final TimelineStore store;

  @override
  State<TimelinePage> createState() => TimelinePageState();
}

class TimelinePageState extends State<TimelinePage> {
  late DateTime _now;
  late DateTime _viewStart;
  double _hours = 24;
  bool _didInitView = false;
  final Set<int> _selectedIds = <int>{};
  bool _selecting = false;
  Timer? _clock;
  final ScrollController _vertical = ScrollController();

  TimelineStore get store => widget.store;
  int? get _primarySelectedId =>
      _selectedIds.length == 1 ? _selectedIds.single : null;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _viewStart = _now;
    store.addListener(_onStoreChanged);
    HardwareKeyboard.instance.addHandler(_handleKey);
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    store.removeListener(_onStoreChanged);
    _clock?.cancel();
    _vertical.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (!mounted) return;
    _selectedIds.removeWhere((int id) => store.blockById(id) == null);
    if (_selectedIds.isEmpty) _selecting = false;
    setState(() {});
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    final BuildContext? focusContext =
        FocusManager.instance.primaryFocus?.context;
    final bool editingText =
        focusContext != null &&
        (focusContext.widget is EditableText ||
            focusContext.findAncestorWidgetOfExactType<EditableText>() !=
                null ||
            focusContext.findAncestorStateOfType<EditableTextState>() != null);
    if (editingText) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape &&
        _selectedIds.isNotEmpty) {
      _clearSelection();
      return true;
    }
    if (!HardwareKeyboard.instance.isControlPressed ||
        event.logicalKey != LogicalKeyboardKey.keyZ) {
      return false;
    }
    unawaited(_undo());
    return true;
  }

  void selectBlock(int id) {
    if (store.blockById(id) == null) return;
    setState(() {
      _selectedIds
        ..clear()
        ..add(id);
      _selecting = false;
    });
  }

  void _selectBlock(int id, {required bool toggle}) {
    if (store.blockById(id) == null) return;
    setState(() {
      if (toggle) {
        if (!_selectedIds.add(id)) _selectedIds.remove(id);
      } else {
        _selectedIds
          ..clear()
          ..add(id);
      }
      if (_selectedIds.isEmpty) _selecting = false;
    });
  }

  void _clearSelection() {
    if (_selectedIds.isEmpty && !_selecting) return;
    setState(() {
      _selectedIds.clear();
      _selecting = false;
    });
  }

  void _marqueeSelect(Set<int> ids, {required bool additive}) {
    setState(() {
      if (!additive) _selectedIds.clear();
      _selectedIds.addAll(ids);
      _selecting = _selectedIds.length > 1;
    });
  }

  void _longPressSelect(int id) {
    if (store.blockById(id) == null) return;
    setState(() {
      _selectedIds.add(id);
      _selecting = true;
    });
    unawaited(HapticFeedback.selectionClick());
  }

  void _initViewport(double width) {
    final double hours = width < 700 ? 8 : 24;
    _hours = hours;
    final int span = (hours * kHourMs).round();
    final DateTime approximate = _now.subtract(
      Duration(milliseconds: (span * .3).round()),
    );
    _viewStart = _clampViewStart(approximate, hours);
    _didInitView = true;
  }

  double get _maxHours => math.max(
    1,
    (store.timelineEnd.millisecondsSinceEpoch -
            store.timelineStart.millisecondsSinceEpoch) /
        kHourMs,
  );

  List<double> get _zoomPresets => zoomPresetsFor(_maxHours);

  DateTime _clampViewStart(DateTime start, double hours) {
    final int rangeMs =
        store.timelineEnd.millisecondsSinceEpoch -
        store.timelineStart.millisecondsSinceEpoch;
    final int spanMs = math.max(1, (hours * kHourMs).round());
    final int startMs = store.timelineStart.millisecondsSinceEpoch;
    if (spanMs >= rangeMs) return store.timelineStart;
    final int target = start.millisecondsSinceEpoch.clamp(
      startMs,
      startMs + rangeMs - spanMs,
    );
    return DateTime.fromMillisecondsSinceEpoch(target);
  }

  void _setViewport(DateTime start, double hours) {
    final double clampedHours = hours.clamp(1.0, _maxHours).toDouble();
    final DateTime clampedStart = _clampViewStart(start, clampedHours);
    if ((clampedHours - _hours).abs() < .0001 &&
        clampedStart.isAtSameMomentAs(_viewStart)) {
      return;
    }
    setState(() {
      _hours = clampedHours;
      _viewStart = clampedStart;
      _didInitView = true;
    });
  }

  void _goNow() {
    final int span = (_hours * kHourMs).round();
    final DateTime start = _now.subtract(
      Duration(milliseconds: (span * .3).round()),
    );
    setState(() {
      _selectedIds.clear();
      _selecting = false;
      _viewStart = _clampViewStart(start, _hours);
    });
  }

  Future<void> openNewBlock({Block? initial}) async {
    if (!mounted) return;
    if (store.locked) {
      await showAppToast(context, 'Layout is locked — unlock to edit times');
      return;
    }
    final DateTime now = DateTime.now();
    final int minutesToNextFive = 5 - (now.minute % 5);
    DateTime start = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      now.minute,
    ).add(Duration(minutes: minutesToNextFive == 5 ? 5 : minutesToNextFive));
    if (start.add(const Duration(hours: 1)).isAfter(store.timelineEnd)) {
      start = store.timelineEnd.subtract(const Duration(hours: 1));
    }
    if (start.isBefore(store.timelineStart)) start = store.timelineStart;
    final Block draft =
        initial ??
        Block(
          id: 0,
          trackId: store.tracks.firstOrNull?.id ?? 'uncat',
          title: '',
          start: start,
          end: start.add(const Duration(hours: 1)),
        );
    final Block? saved = await showBlockEditor(
      context,
      store,
      block: draft,
      isNew: true,
    );
    if (!mounted || saved == null) return;
    setState(() {
      _selectedIds
        ..clear()
        ..add(saved.id);
      _selecting = false;
    });
    _ensureVisible(saved);
    await showAppToast(
      context,
      'Added “${saved.title}” · ${fmtTime(saved.start)}–${fmtTime(saved.end)}',
    );
  }

  Future<void> _editBlock(Block block) async {
    if (!mounted) return;
    if (store.locked) {
      await showAppToast(context, 'Layout is locked — unlock to edit times');
      return;
    }
    final Block? saved = await showBlockEditor(
      context,
      store,
      block: block,
      isNew: false,
    );
    if (!mounted || saved == null) return;
    setState(() {
      _selectedIds
        ..clear()
        ..add(saved.id);
      _selecting = false;
    });
    _ensureVisible(saved);
  }

  void _ensureVisible(Block block) {
    final int span = (_hours * kHourMs).round();
    final DateTime viewEnd = _viewStart.add(Duration(milliseconds: span));
    if (block.start.isBefore(_viewStart) ||
        block.end.isAfter(viewEnd) ||
        block.start.isAfter(viewEnd)) {
      final int middle =
          block.start.millisecondsSinceEpoch +
          block.end.difference(block.start).inMilliseconds ~/ 2;
      final DateTime start = DateTime.fromMillisecondsSinceEpoch(
        middle - span ~/ 2,
      );
      setState(() => _viewStart = _clampViewStart(start, _hours));
    }
  }

  Future<void> _undo() async {
    final String? label = store.undo();
    if (!mounted) return;
    if (label == null) {
      await showAppToast(context, 'Nothing to undo');
    } else {
      await showAppToast(context, 'Undid: $label');
    }
  }

  Future<void> _toggleLock() async {
    store.toggleLock();
    if (!mounted) return;
    await showAppToast(
      context,
      store.locked ? 'Layout locked' : 'Layout unlocked',
    );
  }

  Future<void> _openCategories() async {
    await showCategoriesSheet(context, store);
  }

  void _openEditSelected() {
    final int? id = _primarySelectedId;
    if (id != null) {
      final Block? block = store.blockById(id);
      if (block != null) {
        _editBlock(block);
        return;
      }
    }
    if (_selectedIds.length > 1) {
      _editSelection();
    }
  }

  Future<void> _editSelection() async {
    if (store.locked) {
      await showAppToast(context, 'Layout is locked — unlock to edit blocks');
      return;
    }
    final List<Block> selected = store.blocks
        .where((Block block) => _selectedIds.contains(block.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final bool changed = await showBatchEditor(context, store, selected);
    if (!mounted) return;
    _onStoreChanged();
    if (changed) {
      await showAppToast(
        context,
        'Updated ${selected.length} ${selected.length == 1 ? 'block' : 'blocks'}',
      );
    }
  }

  Future<void> _deleteSelection() async {
    final List<Block> selected = store.blocks
        .where((Block block) => _selectedIds.contains(block.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final bool hasRepeat = selected.any((Block block) => block.repeats);
    bool wholeSeries = false;
    if (hasRepeat) {
      final String? result = await showDialog<String>(
        context: context,
        builder: (BuildContext context) => AlertDialog(
          title: Text(
            'Delete ${selected.length} blocks?',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          content: const Text(
            'Some selected blocks repeat. Delete only the selected occurrences, '
            'or remove every occurrence in their series.',
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppColors.muted,
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop('cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('one'),
              child: const Text('Selected only'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop('series'),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
              child: const Text('Whole series'),
            ),
          ],
        ),
      );
      if (result == null || result == 'cancel') return;
      wholeSeries = result == 'series';
    } else {
      final bool yes = await showConfirm(
        context,
        title: 'Delete ${selected.length} blocks?',
        message:
            '${selected.length} selected ${selected.length == 1 ? 'block' : 'blocks'} will be removed from the timeline.',
      );
      if (!yes) return;
    }
    final int count = selected.length;
    store.deleteBlocks(_selectedIds, wholeSeries: wholeSeries);
    _clearSelection();
    if (mounted) {
      await showAppToast(
        context,
        'Deleted $count ${count == 1 ? 'block' : 'blocks'}',
      );
    }
  }

  Future<void> _saveSelectionAsTemplate() async {
    final List<Block> selected = store.blocks
        .where((Block block) => _selectedIds.contains(block.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    store.addTemplateFromBlocks(selected);
    if (mounted) {
      await showAppToast(
        context,
        'Saved ${selected.length} ${selected.length == 1 ? 'block' : 'blocks'} as a template',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool windows = Platform.isWindows;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        top: !windows,
        bottom: false,
        child: Column(
          children: <Widget>[
            _buildHeader(context),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  return _buildViewport(context, constraints);
                },
              ),
            ),
            _buildBottomBar(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final Block? selected = _primarySelectedId == null
        ? null
        : store.blockById(_primarySelectedId!);
    final Track? track = selected == null
        ? null
        : store.trackOrUncategorized(selected.trackId);
    final bool multi = _selectedIds.length > 1;
    final bool selectingOne = _selecting && selected != null && !multi;
    final bool windows = Platform.isWindows;
    return Container(
      height: windows ? 58 : 56,
      padding: EdgeInsets.symmetric(horizontal: windows ? 16 : 12),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: multi
                ? _multiHeader(_selectedIds.length)
                : selected == null
                ? _fallbackHeader()
                : selectingOne
                ? _selectingOneHeader(selected, track!)
                : _selectedHeader(selected, track!),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (_selectedIds.isNotEmpty) ...<Widget>[
                AppIconButton(
                  icon: Icons.edit_outlined,
                  tooltip: store.locked
                      ? 'Layout is locked'
                      : multi
                      ? 'Edit selected blocks'
                      : 'Edit exact times',
                  onPressed: _openEditSelected,
                  size: 32,
                ),
                const SizedBox(width: 5),
                if (multi) ...<Widget>[
                  AppIconButton(
                    icon: Icons.bookmark_add_outlined,
                    tooltip: 'Save selection as template',
                    onPressed: _saveSelectionAsTemplate,
                    size: 32,
                  ),
                  const SizedBox(width: 5),
                  AppIconButton(
                    icon: Icons.close,
                    tooltip: 'Delete selected blocks',
                    foreground: AppColors.danger,
                    onPressed: _deleteSelection,
                    size: 32,
                  ),
                  const SizedBox(width: 5),
                ],
              ],
              AppIconButton(
                icon: Icons.undo,
                tooltip: 'Undo (Ctrl+Z)',
                onPressed: store.hasUndo ? _undo : null,
                size: 32,
              ),
              const SizedBox(width: 5),
              AppIconButton(
                icon: store.locked
                    ? Icons.lock_outline
                    : Icons.lock_open_outlined,
                tooltip: store.locked ? 'Unlock layout' : 'Lock layout',
                onPressed: _toggleLock,
                active: store.locked,
                size: 32,
              ),
              const SizedBox(width: 6),
              _NowButton(onPressed: _goNow),
            ],
          ),
        ],
      ),
    );
  }

  Widget _multiHeader(int count) {
    return Row(
      children: <Widget>[
        Container(
          width: 3,
          height: 32,
          decoration: BoxDecoration(
            color: AppColors.accent,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                '$count blocks selected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  letterSpacing: .1,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                Platform.isAndroid
                    ? 'Tap blocks to add or remove · tap empty space to clear'
                    : 'Ctrl+click to add · Shift+drag to box select · Esc clears',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _selectingOneHeader(Block block, Track track) {
    return Row(
      children: <Widget>[
        Container(
          width: 3,
          height: 32,
          decoration: BoxDecoration(
            color: track.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      block.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const _HeaderTag('SELECTING'),
                ],
              ),
              const SizedBox(height: 2),
              const Text(
                'Tap more blocks to add them · tap empty space to clear',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 10.5, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _selectedHeader(Block block, Track track) {
    final String subtitle =
        '${fmtTime(block.start)}–${fmtTime(block.end)} · '
        '${blockMeta(block, _now)} · ${track.name}';
    return Row(
      children: <Widget>[
        Container(
          width: 3,
          height: 32,
          decoration: BoxDecoration(
            color: track.color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Flexible(
                    child: Text(
                      block.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .1,
                        color: AppColors.text,
                      ),
                    ),
                  ),
                  if (block.isZone) ...<Widget>[
                    const SizedBox(width: 6),
                    const _HeaderTag('ZONE'),
                  ],
                  if (block.repeats) ...<Widget>[
                    const SizedBox(width: 5),
                    const Icon(Icons.repeat, size: 12, color: AppColors.muted),
                  ],
                  if (block.alarm) ...<Widget>[
                    const SizedBox(width: 5),
                    const Icon(
                      Icons.notifications_none,
                      size: 13,
                      color: AppColors.muted,
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  color: AppColors.muted,
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _fallbackHeader() {
    return Row(
      children: <Widget>[
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: AppColors.alpha(AppColors.accent, .1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.alpha(AppColors.accent, .22)),
          ),
          child: const Icon(
            Icons.view_timeline_outlined,
            size: 17,
            color: AppColors.accent,
          ),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'Timeline',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                fmtDayLong(_now),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10.5, color: AppColors.muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildViewport(BuildContext context, BoxConstraints constraints) {
    final double totalWidth = constraints.maxWidth;
    if (!_didInitView) _initViewport(totalWidth);
    final double gutter = store.showNames ? (totalWidth < 480 ? 72 : 84) : 0;
    final double timelineWidth = math.max(1, totalWidth - gutter);
    final TimelineLayout layout = buildTimelineLayout(
      tracks: store.tracks,
      blocks: store.blocks,
      rangeStart: store.timelineStart,
      rangeEnd: store.timelineEnd,
      viewStart: _viewStart,
      hours: _hours,
      width: timelineWidth,
      trackOpen: store.trackOpen,
    );

    return Column(
      children: <Widget>[
        SizedBox(
          height: 36,
          child: Row(
            children: <Widget>[
              if (gutter > 0)
                Container(
                  width: gutter,
                  height: 36,
                  decoration: const BoxDecoration(
                    color: Color(0xFF141820),
                    border: Border(
                      right: BorderSide(color: AppColors.line),
                      bottom: BorderSide(color: AppColors.line),
                    ),
                  ),
                ),
              SizedBox(
                width: timelineWidth,
                height: 36,
                child: DecoratedBox(
                  decoration: const BoxDecoration(
                    color: Color(0xFF151A21),
                    border: Border(bottom: BorderSide(color: AppColors.line)),
                  ),
                  child: CustomPaint(
                    painter: RulerPainter(
                      viewStart: _viewStart,
                      hours: _hours,
                      width: timelineWidth,
                      now: _now,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints bodyConstraints) {
              final double contentHeight = math.max(
                layout.totalHeight,
                math.max(1, bodyConstraints.maxHeight),
              );
              return Scrollbar(
                controller: _vertical,
                thumbVisibility: Platform.isWindows,
                thickness: 7,
                radius: const Radius.circular(4),
                child: SingleChildScrollView(
                  controller: _vertical,
                  physics: const NeverScrollableScrollPhysics(),
                  child: SizedBox(
                    width: totalWidth,
                    height: contentHeight,
                    child: Row(
                      children: <Widget>[
                        if (gutter > 0)
                          SizedBox(
                            width: gutter,
                            height: contentHeight,
                            child: _buildTrackLabels(
                              layout,
                              contentHeight,
                              gutter,
                            ),
                          ),
                        SizedBox(
                          width: timelineWidth,
                          height: contentHeight,
                          child: TimelineCanvas(
                            layout: layout,
                            contentHeight: contentHeight,
                            store: store,
                            selectedIds: _selectedIds,
                            primarySelectedId: _primarySelectedId,
                            selectionMode: _selecting,
                            now: _now,
                            showNames: store.showNames,
                            scrollController: _vertical,
                            onSelect: _selectBlock,
                            onClearSelection: _clearSelection,
                            onMarqueeSelect: _marqueeSelect,
                            onLongPressSelect: _longPressSelect,
                            onEdit: _editBlock,
                            onViewport: _setViewport,
                            onToast: (String message) {
                              if (mounted) showAppToast(context, message);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          height: 44,
          child: Row(
            children: <Widget>[
              if (gutter > 0) _buildMinimapGutter(context, gutter),
              SizedBox(
                width: timelineWidth,
                height: 44,
                child: _buildMinimap(timelineWidth),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTrackLabels(
    TimelineLayout layout,
    double contentHeight,
    double gutter,
  ) {
    return SizedBox(
      width: gutter,
      height: contentHeight,
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: const BoxDecoration(
                color: Color(0xFF141820),
                border: Border(right: BorderSide(color: AppColors.line)),
              ),
            ),
          ),
          for (final Track track in layout.tracks)
            Positioned(
              left: 0,
              right: 0,
              top: layout.metrics[track.id]!.rowTop,
              height: layout.metrics[track.id]!.height,
              child: _TrackLabel(
                track: track,
                collapsed: layout.metrics[track.id]!.collapsed,
                onTap: () => store.toggleTrackOpen(track.id),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMinimapGutter(BuildContext context, double gutter) {
    return Container(
      width: gutter,
      height: 44,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(
          top: BorderSide(color: AppColors.line),
          right: BorderSide(color: AppColors.line),
        ),
      ),
      alignment: Alignment.center,
      child: Tooltip(
        message: 'Edit categories',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openCategories,
            borderRadius: BorderRadius.circular(7),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(Icons.edit_outlined, size: 13, color: Color(0xFF9EABBE)),
                  SizedBox(width: 5),
                  Text(
                    'Edit',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF9EABBE),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMinimap(double width) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (TapDownDetails details) =>
            _navigateMinimap(details.localPosition.dx, width),
        onHorizontalDragStart: (DragStartDetails details) =>
            _navigateMinimap(details.localPosition.dx, width),
        onHorizontalDragUpdate: (DragUpdateDetails details) =>
            _navigateMinimap(details.localPosition.dx, width),
        child: CustomPaint(
          size: Size(width, 44),
          painter: MinimapPainter(
            tracks: store.tracks,
            blocks: store.blocks,
            rangeStart: store.timelineStart,
            rangeEnd: store.timelineEnd,
            viewStart: _viewStart,
            hours: _hours,
            now: _now,
            selectedIds: _selectedIds,
          ),
        ),
      ),
    );
  }

  void _navigateMinimap(double dx, double width) {
    if (width <= 0) return;
    final int rangeMs =
        store.timelineEnd.millisecondsSinceEpoch -
        store.timelineStart.millisecondsSinceEpoch;
    final int target =
        store.timelineStart.millisecondsSinceEpoch +
        (dx / width * rangeMs).round();
    final int span = (_hours * kHourMs).round();
    _setViewport(
      DateTime.fromMillisecondsSinceEpoch(target - span ~/ 2),
      _hours,
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    final double inset = Platform.isWindows
        ? 0
        : MediaQuery.paddingOf(context).bottom;
    final double side = Platform.isWindows ? 18 : 10;
    return Container(
      padding: EdgeInsets.fromLTRB(side, 10, side, 10 + inset),
      decoration: const BoxDecoration(
        color: AppColors.panel,
        border: Border(top: BorderSide(color: AppColors.line)),
      ),
      child: SizedBox(
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: <Widget>[
            Row(
              children: <Widget>[
                _buildSegmentGroup(),
                const Spacer(),
                _buildNewButton(context),
              ],
            ),
            _buildZoomControl(),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentGroup() {
    final bool allCollapsed =
        store.tracks.isNotEmpty &&
        store.tracks.every((Track track) => store.trackOpen[track.id] == false);
    return Container(
      width: 78,
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2B323D)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: <Widget>[
          Expanded(
            child: _BottomIconButton(
              icon: Icons.vertical_split_outlined,
              tooltip: store.showNames
                  ? 'Hide category names'
                  : 'Show category names',
              active: !store.showNames,
              onPressed: store.toggleShowNames,
              showDivider: true,
            ),
          ),
          Expanded(
            child: _BottomIconButton(
              icon: Icons.keyboard_arrow_down,
              tooltip: allCollapsed ? 'Open all tracks' : 'Collapse all tracks',
              active: allCollapsed,
              rotate: allCollapsed,
              onPressed: store.toggleCollapseAll,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewButton(BuildContext context) {
    return SizedBox(
      width: 78,
      height: 36,
      child: Material(
        color: AppColors.alpha(AppColors.accent, .15),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: AppColors.alpha(AppColors.accent, .4)),
        ),
        child: InkWell(
          onTap: () => openNewBlock(),
          borderRadius: BorderRadius.circular(10),
          child: const Center(
            child: Text(
              'NEW',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: .6,
                color: Color(0xFFC1D3FF),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildZoomControl() {
    return Container(
      height: 34,
      decoration: BoxDecoration(
        color: AppColors.panel2,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF2B323D)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          _ZoomStepButton(
            icon: Icons.remove,
            tooltip: 'Zoom out',
            onPressed: () => _stepZoom(1),
          ),
          PopupMenuButton<double>(
            tooltip: 'Choose zoom',
            onSelected: (double value) => _setPresetZoom(value),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<double>>[
              for (final double value in _zoomPresets)
                PopupMenuItem<double>(
                  value: value,
                  child: Row(
                    children: <Widget>[
                      SizedBox(
                        width: 34,
                        child: Text(
                          zoomLabel(value),
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                      Text(
                        _presetDescription(value),
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.faint,
                        ),
                      ),
                      const Spacer(),
                      if ((_hours - value).abs() < .02)
                        const Icon(
                          Icons.check,
                          size: 14,
                          color: AppColors.accent,
                        ),
                    ],
                  ),
                ),
            ],
            child: SizedBox(
              width: 46,
              height: 32,
              child: Center(
                child: Text(
                  zoomLabel(_hours),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                  ),
                ),
              ),
            ),
          ),
          _ZoomStepButton(
            icon: Icons.add,
            tooltip: 'Zoom in',
            onPressed: () => _stepZoom(-1),
          ),
        ],
      ),
    );
  }

  String _presetDescription(double hours) {
    if ((hours - _maxHours).abs() < .01) return 'whole range';
    if (hours == 1) return 'one hour';
    if (hours == 24) return 'one day';
    if (hours == 72) return 'three days';
    return '$hours hours';
  }

  void _stepZoom(int direction) {
    final List<double> presets = _zoomPresets;
    double target;
    if (direction < 0) {
      target = presets.first;
      for (final double preset in presets) {
        if (preset < _hours - .01) target = preset;
      }
    } else {
      target = presets.last;
      for (final double preset in presets.reversed) {
        if (preset > _hours + .01) target = preset;
      }
    }
    _setPresetZoom(target);
  }

  void _setPresetZoom(double hours) {
    final double newHours = hours.clamp(1.0, _maxHours).toDouble();
    final int span = (_hours * kHourMs).round();
    final int newSpan = (newHours * kHourMs).round();
    final int anchor = _viewStart.millisecondsSinceEpoch + (span * .5).round();
    _setViewport(
      DateTime.fromMillisecondsSinceEpoch(anchor - newSpan ~/ 2),
      newHours,
    );
  }
}

class _TrackLabel extends StatelessWidget {
  const _TrackLabel({
    required this.track,
    required this.collapsed,
    required this.onTap,
  });

  final Track track;
  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.alpha(track.color, .025),
      child: InkWell(
        onTap: onTap,
        child: Semantics(
          button: true,
          label: collapsed
              ? 'Open ${track.name} track'
              : 'Collapse ${track.name} track',
          child: DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0x10FFFFFF))),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 3,
                  height: double.infinity,
                  color: AppColors.alpha(track.color, .9),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    track.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: collapsed ? FontWeight.w500 : FontWeight.w600,
                      color: collapsed
                          ? AppColors.muted
                          : const Color(0xFFCFD6E2),
                    ),
                  ),
                ),
                Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 14,
                  color: AppColors.faint,
                ),
                const SizedBox(width: 3),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomIconButton extends StatelessWidget {
  const _BottomIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
    this.rotate = false,
    this.showDivider = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool active;
  final bool rotate;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active
            ? AppColors.alpha(AppColors.accent, .16)
            : Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            decoration: BoxDecoration(
              border: showDivider
                  ? const Border(right: BorderSide(color: Color(0xFF2B323D)))
                  : null,
            ),
            child: Center(
              child: Transform.rotate(
                angle: rotate ? math.pi : 0,
                child: Icon(
                  icon,
                  size: 17,
                  color: active
                      ? const Color(0xFFC8D8FF)
                      : const Color(0xFFAAB4C4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ZoomStepButton extends StatelessWidget {
  const _ZoomStepButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 28,
            height: 32,
            child: Icon(icon, size: 15, color: const Color(0xFFAAB4C4)),
          ),
        ),
      ),
    );
  }
}

class _HeaderTag extends StatelessWidget {
  const _HeaderTag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(5, 2, 5, 2),
      decoration: BoxDecoration(
        color: AppColors.alpha(AppColors.accent, .13),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.alpha(AppColors.accent, .25)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 7.5,
          fontWeight: FontWeight.w700,
          letterSpacing: .7,
          color: Color(0xFFAFC6FF),
        ),
      ),
    );
  }
}

class _NowButton extends StatelessWidget {
  const _NowButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Jump to now',
      child: Material(
        color: AppColors.panel2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(9),
          side: const BorderSide(color: Color(0xFF2B323D)),
        ),
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(9),
          child: const SizedBox(
            height: 32,
            width: 48,
            child: Center(
              child: Text(
                'Now',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFFBBD0FF),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
