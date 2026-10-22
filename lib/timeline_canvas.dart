import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'models.dart';
import 'store.dart';
import 'theme.dart';
import 'timeline_painters.dart';

class TimelineCanvas extends StatefulWidget {
  const TimelineCanvas({
    super.key,
    required this.layout,
    required this.contentHeight,
    required this.store,
    required this.selectedId,
    required this.now,
    required this.showNames,
    required this.scrollController,
    required this.onSelect,
    required this.onEdit,
    required this.onViewport,
    required this.onToast,
  });

  final TimelineLayout layout;
  final double contentHeight;
  final TimelineStore store;
  final int? selectedId;
  final DateTime now;
  final bool showNames;
  final ScrollController scrollController;
  final ValueChanged<int?> onSelect;
  final ValueChanged<Block> onEdit;
  final void Function(DateTime start, double hours) onViewport;
  final ValueChanged<String> onToast;

  @override
  State<TimelineCanvas> createState() => _TimelineCanvasState();
}

enum _Interaction {
  none,
  pendingBlock,
  move,
  resizeLeft,
  resizeRight,
  pan,
  pinch,
}

class _TimelineCanvasState extends State<TimelineCanvas> {
  final Map<int, Offset> _pointers = <int, Offset>{};
  _Interaction _mode = _Interaction.none;
  Offset? _down;
  bool _moved = false;
  bool _downWasEmpty = false;
  int? _lastTapId;
  DateTime? _lastTapAt;

  Block? _dragBlock;
  UndoState? _before;
  DateTime? _originalStart;
  DateTime? _originalEnd;
  double _dragPxPerHour = 1;

  DateTime? _panStartView;
  double _panStartHours = 24;
  double _panPxPerHour = 1;
  double _panScrollStart = 0;
  int _panAxis = 0;

  double _pinchStartDistance = 1;
  double _pinchStartHours = 24;
  DateTime? _pinchAnchorTime;

  double get _maxHours => math.max(
    1,
    (widget.layout.rangeEnd.millisecondsSinceEpoch -
            widget.layout.rangeStart.millisecondsSinceEpoch) /
        kHourMs,
  );

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[
      Positioned.fill(
        child: CustomPaint(
          painter: TimelineBackgroundPainter(
            layout: widget.layout,
            height: widget.contentHeight,
          ),
        ),
      ),
    ];

    if (!widget.showNames) {
      for (final Track track in widget.layout.tracks) {
        final TrackMetrics? metric = widget.layout.metrics[track.id];
        if (metric == null) continue;
        children.add(
          Positioned(
            left: 0,
            top: metric.rowTop,
            width: 3,
            height: metric.height,
            child: IgnorePointer(
              child: ColoredBox(color: AppColors.alpha(track.color, .9)),
            ),
          ),
        );
      }
    }

    if (widget.showNames) {
      for (final Track track in widget.layout.tracks) {
        if (widget.store.blockCountForTrack(track.id) > 0) continue;
        final TrackMetrics? metric = widget.layout.metrics[track.id];
        if (metric == null) continue;
        children.add(
          Positioned(
            left: 8,
            top: metric.rowTop + metric.height / 2 - 7,
            child: IgnorePointer(
              child: Text(
                'empty category',
                style: TextStyle(
                  fontSize: 9.5,
                  fontStyle: FontStyle.italic,
                  color: AppColors.faint.withValues(alpha: .65),
                ),
              ),
            ),
          ),
        );
      }
    }

    for (final TimelineSegment segment in widget.layout.segments) {
      if (!widget.layout.isVisible(segment.start, segment.end)) continue;
      final Rect rect = widget.layout.segmentRect(segment);
      if (rect.width <= 0) continue;
      final Track track = widget.store.trackOrUncategorized(segment.trackId);
      final TrackMetrics metric = widget.layout.metrics[segment.trackId]!;
      children.add(
        Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: _BlockChip(
            segment: segment,
            rect: rect,
            track: track,
            now: widget.now,
            selected: widget.selectedId == segment.block.id,
            collapsed: metric.collapsed,
          ),
        ),
      );
    }

    final int? selectedId = widget.selectedId;
    if (selectedId != null) {
      final Block? block = widget.store.blockById(selectedId);
      if (block != null) {
        final List<TimelineSegment> parts = widget.layout.segments
            .where((TimelineSegment segment) => segment.block.id == selectedId)
            .toList(growable: false);
        if (parts.isNotEmpty) {
          final TimelineSegment first = parts.first;
          final TimelineSegment last = parts.last;
          final double leftX = widget.layout.xOf(block.start);
          final double rightX = widget.layout.xOf(block.end);
          final Rect firstRect = widget.layout.segmentRect(first);
          final Rect lastRect = widget.layout.segmentRect(last);
          if (leftX >= 0 && leftX <= widget.layout.width) {
            children.add(
              Positioned(
                left: leftX - 5,
                top: firstRect.center.dy - 13,
                width: 10,
                height: 26,
                child: IgnorePointer(
                  child: _Handle(active: _mode == _Interaction.resizeLeft),
                ),
              ),
            );
          }
          if (rightX >= 0 && rightX <= widget.layout.width) {
            children.add(
              Positioned(
                left: rightX - 5,
                top: lastRect.center.dy - 13,
                width: 10,
                height: 26,
                child: IgnorePointer(
                  child: _Handle(active: _mode == _Interaction.resizeRight),
                ),
              ),
            );
          }
        }
      }
    }

    children.add(
      Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: TimelineOverlayPainter(
              layout: widget.layout,
              now: widget.now,
            ),
          ),
        ),
      ),
    );

    if (widget.layout.tracks.isEmpty && widget.store.blocks.isEmpty) {
      children.add(
        Positioned.fill(
          child: IgnorePointer(
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 18,
                ),
                decoration: BoxDecoration(
                  color: AppColors.panel.withValues(alpha: .82),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.line),
                ),
                child: const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(
                      Icons.view_timeline_outlined,
                      size: 24,
                      color: AppColors.faint,
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Your timeline is quiet',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Press NEW to add a block. Categories are optional.',
                      style: TextStyle(fontSize: 10.5, color: AppColors.muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    children.add(
      Positioned.fill(
        child: MouseRegion(
          cursor: SystemMouseCursors.basic,
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerCancel,
            onPointerSignal: _onPointerSignal,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );

    return SizedBox(
      width: widget.layout.width,
      height: widget.contentHeight,
      child: Stack(children: children),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons & kSecondaryMouseButton != 0) {
      return;
    }
    _pointers[event.pointer] = event.localPosition;
    if (_pointers.length >= 2) {
      _startPinch();
      return;
    }

    _mode = _Interaction.none;
    _moved = false;
    _down = event.localPosition;
    _downWasEmpty = false;
    _dragBlock = null;
    _before = null;
    _panAxis = 0;

    final Offset position = event.localPosition;
    final ({TimelineSegment segment, bool left})? handle = widget.store.locked
        ? null
        : widget.layout.hitHandle(position, widget.selectedId);
    if (handle != null) {
      final Block block = handle.segment.block;
      _dragBlock = block;
      _originalStart = block.start;
      _originalEnd = block.end;
      _dragPxPerHour = widget.layout.pxPerHour;
      _before = widget.store.captureState();
      _mode = handle.left ? _Interaction.resizeLeft : _Interaction.resizeRight;
      widget.onSelect(block.id);
      return;
    }

    final TimelineSegment? segment = widget.layout.hitTest(position);
    if (segment != null) {
      final Block block = segment.block;
      _dragBlock = block;
      _originalStart = block.start;
      _originalEnd = block.end;
      _dragPxPerHour = widget.layout.pxPerHour;
      widget.onSelect(block.id);

      final DateTime now = DateTime.now();
      final bool doubleTap =
          _lastTapId == block.id &&
          _lastTapAt != null &&
          now.difference(_lastTapAt!) < const Duration(milliseconds: 360);
      _lastTapId = block.id;
      _lastTapAt = now;
      if (doubleTap) {
        _mode = _Interaction.none;
        widget.onEdit(block);
        return;
      }
      if (!widget.store.locked) {
        _mode = _Interaction.pendingBlock;
      }
      return;
    }

    _downWasEmpty = true;
    _mode = _Interaction.pan;
    _panStartView = widget.layout.viewStart;
    _panStartHours = widget.layout.hours;
    _panPxPerHour = widget.layout.pxPerHour;
    _panScrollStart = widget.scrollController.hasClients
        ? widget.scrollController.offset
        : 0;
  }

  void _startPinch() {
    if (_mode == _Interaction.move ||
        _mode == _Interaction.resizeLeft ||
        _mode == _Interaction.resizeRight) {
      if (_moved) _commitLiveChange();
    }
    final List<Offset> points = _pointers.values
        .take(2)
        .toList(growable: false);
    if (points.length < 2) return;
    final Offset mid = Offset(
      (points[0].dx + points[1].dx) / 2,
      (points[0].dy + points[1].dy) / 2,
    );
    _pinchStartDistance = math.max(1, (points[1] - points[0]).distance);
    _pinchStartHours = widget.layout.hours;
    _pinchAnchorTime = widget.layout.timeAtX(mid.dx);
    _mode = _Interaction.pinch;
    _moved = false;
    _downWasEmpty = false;
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (!_pointers.containsKey(event.pointer)) return;
    _pointers[event.pointer] = event.localPosition;

    if (_mode == _Interaction.pinch) {
      _updatePinch();
      return;
    }
    if (_pointers.length != 1 || _down == null) return;

    final Offset delta = event.localPosition - _down!;
    final double distance = delta.distance;
    final double threshold = event.kind == PointerDeviceKind.mouse ? 4 : 8;

    if (_mode == _Interaction.pendingBlock) {
      if (distance < threshold) return;
      _mode = _Interaction.move;
      _moved = true;
      _before ??= widget.store.captureState();
    }

    if (_mode == _Interaction.move) {
      _moved = true;
      _moveBlock(delta.dx);
      return;
    }
    if (_mode == _Interaction.resizeLeft) {
      if (distance < threshold && !_moved) return;
      _moved = true;
      _resizeLeft(delta.dx);
      return;
    }
    if (_mode == _Interaction.resizeRight) {
      if (distance < threshold && !_moved) return;
      _moved = true;
      _resizeRight(delta.dx);
      return;
    }
    if (_mode != _Interaction.pan) return;
    if (distance < threshold) return;

    if (_panAxis == 0) {
      final bool canScroll =
          widget.scrollController.hasClients &&
          widget.scrollController.position.maxScrollExtent > 0;
      _panAxis = canScroll && delta.dy.abs() > delta.dx.abs() * 1.12 ? 2 : 1;
    }
    _moved = true;
    if (_panAxis == 2) {
      _scrollVertically(delta.dy);
    } else {
      final int millis = (delta.dx / math.max(.001, _panPxPerHour) * kHourMs)
          .round();
      final DateTime start = _panStartView!.subtract(
        Duration(milliseconds: millis),
      );
      widget.onViewport(start, _panStartHours);
    }
  }

  void _updatePinch() {
    final List<Offset> points = _pointers.values
        .take(2)
        .toList(growable: false);
    if (points.length < 2 || _pinchAnchorTime == null) return;
    final Offset mid = Offset(
      (points[0].dx + points[1].dx) / 2,
      (points[0].dy + points[1].dy) / 2,
    );
    final double distance = math.max(1, (points[1] - points[0]).distance);
    final double hours = (_pinchStartHours * (_pinchStartDistance / distance))
        .clamp(1.0, _maxHours);
    final double pxPerHour = widget.layout.width / math.max(.001, hours);
    final int millis = (mid.dx / math.max(.001, pxPerHour) * kHourMs).round();
    final DateTime start = _pinchAnchorTime!.subtract(
      Duration(milliseconds: millis),
    );
    widget.onViewport(start, hours);
  }

  void _scrollVertically(double deltaY) {
    if (!widget.scrollController.hasClients) return;
    final double max = widget.scrollController.position.maxScrollExtent;
    widget.scrollController.jumpTo(
      (_panScrollStart - deltaY).clamp(0.0, math.max(0.0, max)),
    );
  }

  void _moveBlock(double dx) {
    final Block? block = _dragBlock;
    if (block == null || _originalStart == null || _originalEnd == null) return;
    final Duration duration = _originalEnd!.difference(_originalStart!);
    final int millis =
        _originalStart!.millisecondsSinceEpoch +
        (dx / math.max(.001, _dragPxPerHour) * kHourMs).round();
    DateTime start = _snap(DateTime.fromMillisecondsSinceEpoch(millis));
    final DateTime rangeStart = widget.layout.rangeStart;
    final DateTime rangeEnd = widget.layout.rangeEnd;
    if (start.isBefore(rangeStart)) start = rangeStart;
    if (start.add(duration).isAfter(rangeEnd)) {
      start = rangeEnd.subtract(duration);
    }
    if (start.isBefore(rangeStart)) start = rangeStart;
    widget.store.moveBlockLive(
      block.id,
      start,
      start.add(duration),
      resize: false,
    );
  }

  void _resizeLeft(double dx) {
    final Block? block = _dragBlock;
    if (block == null || _originalStart == null || _originalEnd == null) return;
    final int millis =
        _originalStart!.millisecondsSinceEpoch +
        (dx / math.max(.001, _dragPxPerHour) * kHourMs).round();
    DateTime start = _snap(DateTime.fromMillisecondsSinceEpoch(millis));
    if (start.isBefore(widget.layout.rangeStart)) {
      start = widget.layout.rangeStart;
    }
    final DateTime latest = _originalEnd!.subtract(const Duration(minutes: 5));
    if (!start.isBefore(latest)) start = latest;
    widget.store.moveBlockLive(block.id, start, _originalEnd!, resize: true);
  }

  void _resizeRight(double dx) {
    final Block? block = _dragBlock;
    if (block == null || _originalStart == null || _originalEnd == null) return;
    final int millis =
        _originalEnd!.millisecondsSinceEpoch +
        (dx / math.max(.001, _dragPxPerHour) * kHourMs).round();
    DateTime end = _snap(DateTime.fromMillisecondsSinceEpoch(millis));
    if (end.isAfter(widget.layout.rangeEnd)) end = widget.layout.rangeEnd;
    final DateTime earliest = _originalStart!.add(const Duration(minutes: 5));
    if (end.isBefore(earliest)) end = earliest;
    widget.store.moveBlockLive(block.id, _originalStart!, end, resize: true);
  }

  DateTime _snap(DateTime value) {
    final double hours = widget.layout.hours;
    final int minutes = hours >= 72
        ? 30
        : hours >= 24
        ? 15
        : 5;
    final int step = minutes * 60000;
    final int epoch = value.millisecondsSinceEpoch;
    return DateTime.fromMillisecondsSinceEpoch((epoch / step).round() * step);
  }

  void _onPointerUp(PointerUpEvent event) {
    _pointers.remove(event.pointer);
    if (_mode == _Interaction.pinch) {
      if (_pointers.length < 2) {
        _mode = _Interaction.none;
        _moved = false;
      }
      return;
    }
    if (_mode == _Interaction.move ||
        _mode == _Interaction.resizeLeft ||
        _mode == _Interaction.resizeRight) {
      if (_moved) _commitLiveChange();
      _resetInteraction();
      return;
    }
    if (_mode == _Interaction.pan && !_moved && _downWasEmpty) {
      widget.onSelect(null);
    }
    _resetInteraction();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _pointers.remove(event.pointer);
    if (_mode == _Interaction.pinch) {
      _mode = _Interaction.none;
      return;
    }
    if ((_mode == _Interaction.move ||
            _mode == _Interaction.resizeLeft ||
            _mode == _Interaction.resizeRight) &&
        _moved) {
      _commitLiveChange();
    }
    _resetInteraction();
  }

  void _commitLiveChange() {
    final Block? block = _dragBlock;
    final UndoState? before = _before;
    if (block == null || before == null) return;
    final Block? current = widget.store.blockById(block.id);
    if (current == null) return;
    final bool resizing =
        _mode == _Interaction.resizeLeft || _mode == _Interaction.resizeRight;
    final String label = resizing
        ? 'Resized “${current.title}”'
        : 'Moved “${current.title}”';
    widget.store.recordUndoState(before, label);
    widget.store.finishLiveChange();
    widget.onToast(
      '${resizing ? 'Resized' : 'Moved'} “${current.title}” · '
      '${fmtTime(current.start)}–${fmtTime(current.end)}',
    );
  }

  void _resetInteraction() {
    _mode = _Interaction.none;
    _moved = false;
    _down = null;
    _dragBlock = null;
    _before = null;
    _downWasEmpty = false;
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final double dy = event.scrollDelta.dy;
    final double dx = event.scrollDelta.dx;
    if (dy.abs() < .01 && dx.abs() < .01) return;

    if (HardwareKeyboard.instance.isControlPressed) {
      final double anchorX = event.localPosition.dx.clamp(
        0.0,
        widget.layout.width,
      );
      final DateTime anchor = widget.layout.timeAtX(anchorX);
      final double ratioX = widget.layout.width <= 0
          ? .5
          : (anchorX / widget.layout.width).clamp(0.0, 1.0);
      final double factor = math.exp(dy / 560);
      final double hours = (widget.layout.hours * factor).clamp(1.0, _maxHours);
      final DateTime start = anchor.subtract(
        Duration(milliseconds: (ratioX * hours * kHourMs).round()),
      );
      widget.onViewport(start, hours);
      return;
    }

    if (HardwareKeyboard.instance.isShiftPressed) {
      if (widget.scrollController.hasClients) {
        final double max = widget.scrollController.position.maxScrollExtent;
        widget.scrollController.jumpTo(
          (widget.scrollController.offset + dy).clamp(0.0, math.max(0.0, max)),
        );
      }
      return;
    }

    final double hoursToMove = (dy + dx) / 1200 * widget.layout.hours;
    final DateTime start = widget.layout.viewStart.add(
      Duration(milliseconds: (hoursToMove * kHourMs).round()),
    );
    widget.onViewport(start, widget.layout.hours);
  }
}

class _Handle extends StatelessWidget {
  const _Handle({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: active ? 6 : 5,
        height: active ? 24 : 22,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: active ? .98 : .9),
          borderRadius: BorderRadius.circular(3),
          boxShadow: const <BoxShadow>[
            BoxShadow(
              color: Color(0x66000000),
              blurRadius: 4,
              offset: Offset(0, 1),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockChip extends StatelessWidget {
  const _BlockChip({
    required this.segment,
    required this.rect,
    required this.track,
    required this.now,
    required this.selected,
    required this.collapsed,
  });

  final TimelineSegment segment;
  final Rect rect;
  final Track track;
  final DateTime now;
  final bool selected;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final Block block = segment.block;
    final bool isZone = block.isZone;
    final Color color = track.color;
    final double radius = isZone ? 5 : 6;

    if (collapsed) {
      return Container(
        decoration: BoxDecoration(
          color: AppColors.alpha(color, isZone ? .55 : .82),
          borderRadius: BorderRadius.circular(2),
        ),
      );
    }

    final bool active = !now.isBefore(block.start) && now.isBefore(block.end);
    final bool showTitle = rect.width >= (isZone ? 34 : 27);
    final bool showMeta = rect.width >= (isZone ? 108 : 82);
    final String meta = blockMeta(block, now);
    final double horizontal = isZone ? 7 : 8;

    final Widget? content;
    if (!showTitle) {
      content = null;
    } else if (isZone) {
      content = Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(
              text: block.title,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFFE4EBF5),
              ),
            ),
            if (showMeta)
              TextSpan(
                text: '   $meta',
                style: TextStyle(
                  fontSize: 9,
                  color: AppColors.alpha(color, .92),
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
          ],
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        softWrap: false,
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            block.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            softWrap: false,
            style: const TextStyle(
              fontSize: 11.5,
              height: 1.1,
              fontWeight: FontWeight.w600,
              color: Color(0xFFE9EEF7),
            ),
          ),
          if (showMeta) ...<Widget>[
            const SizedBox(height: 1),
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: TextStyle(
                fontSize: 9.5,
                height: 1.1,
                color: AppColors.alpha(color, .95),
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ],
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: active
            ? <BoxShadow>[
                BoxShadow(
                  color: AppColors.alpha(color, .2),
                  blurRadius: 9,
                  spreadRadius: .5,
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      AppColors.alpha(color, isZone ? .17 : .27),
                      AppColors.alpha(color, isZone ? .09 : .15),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: AppColors.alpha(
                      color,
                      selected || active ? .68 : .38,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              width: isZone ? 2 : 3,
              child: ColoredBox(
                color: AppColors.alpha(color, selected || active ? .95 : .8),
              ),
            ),
            if (content != null)
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: horizontal),
                  child: Align(alignment: Alignment.centerLeft, child: content),
                ),
              ),
            if (selected)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: .84),
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
