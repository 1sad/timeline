import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'models.dart';
import 'theme.dart';

class RulerSpec {
  const RulerSpec({
    required this.labelMinutes,
    required this.minorMinutes,
    required this.clockLabels,
    required this.clockText,
  });

  final int labelMinutes;
  final int minorMinutes;
  final bool clockLabels;
  final bool clockText;
}

RulerSpec rulerSpecFor(double hours) {
  if (hours <= 1.6) {
    return const RulerSpec(
      labelMinutes: 15,
      minorMinutes: 5,
      clockLabels: true,
      clockText: true,
    );
  }
  if (hours <= 4) {
    return const RulerSpec(
      labelMinutes: 30,
      minorMinutes: 10,
      clockLabels: true,
      clockText: true,
    );
  }
  if (hours <= 18) {
    return const RulerSpec(
      labelMinutes: 60,
      minorMinutes: 30,
      clockLabels: true,
      clockText: false,
    );
  }
  if (hours <= 36) {
    return const RulerSpec(
      labelMinutes: 120,
      minorMinutes: 60,
      clockLabels: true,
      clockText: false,
    );
  }
  if (hours <= 100) {
    return const RulerSpec(
      labelMinutes: 360,
      minorMinutes: 360,
      clockLabels: true,
      clockText: false,
    );
  }
  return const RulerSpec(
    labelMinutes: 1440,
    minorMinutes: 1440,
    clockLabels: false,
    clockText: false,
  );
}

class RulerPainter extends CustomPainter {
  RulerPainter({
    required this.viewStart,
    required this.hours,
    required this.width,
    required this.now,
  });

  final DateTime viewStart;
  final double hours;
  final double width;
  final DateTime now;

  double get _pxPerHour => width / math.max(.001, hours);
  DateTime get _viewEnd =>
      viewStart.add(Duration(milliseconds: (hours * kHourMs).round()));

  double _xOf(DateTime value) =>
      value.difference(viewStart).inMilliseconds / kHourMs * _pxPerHour;

  @override
  void paint(Canvas canvas, Size size) {
    if (width <= 0 || size.height <= 0) return;
    final Paint linePaint = Paint()
      ..color = AppColors.alpha(Colors.white, .055)
      ..strokeWidth = 1;
    final Paint dayPaint = Paint()
      ..color = AppColors.alpha(Colors.white, .16)
      ..strokeWidth = 1;

    final DateTime firstDay = startOfLocalDay(viewStart);
    final DateTime lastDay = startOfLocalDay(_viewEnd);
    DateTime day = firstDay;
    while (!day.isAfter(lastDay)) {
      final double x = _xOf(day);
      if (x >= -1 && x <= width + 1) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), dayPaint);
        _paintDayLabel(canvas, day, x, size);
      }
      day = addLocalDays(day, 1);
    }

    final RulerSpec spec = rulerSpecFor(hours);
    if (hours < 160) {
      _paintTicks(canvas, size, spec, linePaint);
    }

    final double nowX = _xOf(now);
    if (nowX >= 0 && nowX <= width) {
      _paintNowPill(canvas, size, nowX);
    }
  }

  void _paintDayLabel(Canvas canvas, DateTime day, double x, Size size) {
    final double dayWidth = _pxPerHour * 24;
    final bool tight = dayWidth < 54 || hours > 100;
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: tight ? fmtDayTight(day) : fmtDay(day),
        style: TextStyle(
          fontSize: tight ? 9 : 9.5,
          height: 1,
          fontWeight: FontWeight.w600,
          color: tight ? const Color(0xFFA8B2C2) : const Color(0xFFB9C4D3),
          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(16, dayWidth - 8));
    // Start clear of the midnight tick and keep the whole label in the top
    // band so it cannot collide with the clock text underneath.
    final double left = math.max(2, x + 6);
    if (left + painter.width > width) {
      return;
    }
    painter.paint(canvas, Offset(left, 1.5));
  }

  void _paintTicks(Canvas canvas, Size size, RulerSpec spec, Paint linePaint) {
    final Set<int> seen = <int>{};
    DateTime day = startOfLocalDay(viewStart);
    final DateTime end = _viewEnd;
    while (!day.isAfter(end)) {
      for (int minute = 0; minute < 1440; minute += spec.minorMinutes) {
        final DateTime tick = DateTime(
          day.year,
          day.month,
          day.day,
          minute ~/ 60,
          minute % 60,
        );
        if (!seen.add(tick.millisecondsSinceEpoch)) continue;
        if (tick.isBefore(viewStart) || !tick.isBefore(end)) continue;
        final double x = _xOf(tick);
        if (x < 0 || x > width) continue;
        final bool labelled = minute % spec.labelMinutes == 0;
        if (labelled) {
          canvas.drawLine(
            Offset(x, size.height - 11),
            Offset(x, size.height - 1),
            linePaint,
          );
          _paintTickLabel(canvas, size, tick, x, spec);
        } else {
          canvas.drawLine(
            Offset(x, size.height - 5),
            Offset(x, size.height - 1),
            linePaint,
          );
        }
      }
      day = addLocalDays(day, 1);
    }
  }

  void _paintTickLabel(
    Canvas canvas,
    Size size,
    DateTime tick,
    double x,
    RulerSpec spec,
  ) {
    if (hours >= 160) return;
    final String text = spec.clockText
        ? fmtTime(tick)
        : tick.hour.toString().padLeft(2, '0');
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 9,
          height: 1,
          color: Color(0xFF7F8A9B),
          fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final double left = (x - painter.width / 2).clamp(
      1.0,
      math.max(1.0, width - painter.width - 1),
    );
    painter.paint(canvas, Offset(left, size.height - 23));
  }

  void _paintNowPill(Canvas canvas, Size size, double x) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: fmtTime(now),
        style: const TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w700,
          color: Color(0xFF23100E),
          fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double pillWidth = painter.width + 10;
    final double left = (x - pillWidth / 2).clamp(
      2.0,
      math.max(2, width - pillWidth - 2),
    );
    final Rect rect = Rect.fromLTWH(left, size.height - 17, pillWidth, 14);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = AppColors.now,
    );
    painter.paint(canvas, Offset(left + 5, size.height - 14.5));
  }

  @override
  bool shouldRepaint(covariant RulerPainter oldDelegate) =>
      oldDelegate.viewStart != viewStart ||
      oldDelegate.hours != hours ||
      oldDelegate.width != width ||
      oldDelegate.now != now;
}

class TimelineBackgroundPainter extends CustomPainter {
  TimelineBackgroundPainter({required this.layout, required this.height});

  final TimelineLayout layout;
  final double height;

  static const Color _weekendTint = Color(0x07FFFFFF);
  static const Color _nightTint = Color(0x1A000000);
  static const Color _hourLine = Color(0x0BFFFFFF);
  static const Color _majorLine = Color(0x14FFFFFF);
  static const Color _midnightLine = Color(0x24FFFFFF);
  static const Color _rowLine = Color(0x10FFFFFF);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Rect.fromLTWH(0, 0, layout.width, height),
      Paint()..color = AppColors.canvas,
    );
    if (layout.metrics.isEmpty) return;

    // Day fills are drawn edge-to-edge with anti-aliasing off so neighbouring
    // days cannot double-blend into a seam or a soft gradient.
    final Paint fill = Paint()..isAntiAlias = false;
    DateTime day = startOfLocalDay(layout.viewStart);
    final DateTime lastDay = startOfLocalDay(layout.viewEnd);
    while (!day.isAfter(lastDay)) {
      final DateTime nextDay = addLocalDays(day, 1);
      final double left = math.max(0, layout.xOf(day));
      final double right = math.min(layout.width, layout.xOf(nextDay));
      if (right > left) {
        final bool weekend =
            day.weekday == DateTime.saturday || day.weekday == DateTime.sunday;
        if (weekend) {
          canvas.drawRect(
            Rect.fromLTRB(left, 0, right, height),
            fill..color = _weekendTint,
          );
        }
        final double morningEnd = layout
            .xOf(atLocalTime(day, 7, 0))
            .clamp(left, right)
            .toDouble();
        if (morningEnd > left) {
          canvas.drawRect(
            Rect.fromLTRB(left, 0, morningEnd, height),
            fill..color = _nightTint,
          );
        }
        final double eveningStart = layout
            .xOf(atLocalTime(day, 20, 0))
            .clamp(left, right)
            .toDouble();
        if (right > eveningStart) {
          canvas.drawRect(
            Rect.fromLTRB(eveningStart, 0, right, height),
            fill..color = _nightTint,
          );
        }
      }
      day = addLocalDays(day, 1);
    }

    final double pxPerHour = layout.pxPerHour;
    final int step = pxPerHour >= 34
        ? 1
        : pxPerHour >= 13
        ? 2
        : pxPerHour >= 4.5
        ? 6
        : 12;
    final Paint hourPaint = Paint()
      ..color = _hourLine
      ..strokeWidth = 1;
    final Paint majorPaint = Paint()
      ..color = _majorLine
      ..strokeWidth = 1;

    day = startOfLocalDay(layout.viewStart);
    while (!day.isAfter(lastDay)) {
      for (int hour = 0; hour < 24; hour += step) {
        if (hour == 0) continue;
        final DateTime tick = atLocalTime(day, hour, 0);
        if (tick.isBefore(layout.viewStart) || !tick.isBefore(layout.viewEnd)) {
          continue;
        }
        final double x = layout.xOf(tick);
        canvas.drawLine(
          Offset(x, 0),
          Offset(x, height),
          hour % 6 == 0 ? majorPaint : hourPaint,
        );
      }
      day = addLocalDays(day, 1);
    }

    // Midnight is the only line that separates days, so it gets one extra
    // step of contrast without turning into a bright column.
    final Paint midnightPaint = Paint()
      ..color = _midnightLine
      ..strokeWidth = 1;
    day = startOfLocalDay(layout.viewStart);
    while (!day.isAfter(lastDay)) {
      final double x = layout.xOf(day);
      if (x >= 0 && x <= layout.width) {
        canvas.drawLine(Offset(x, 0), Offset(x, height), midnightPaint);
      }
      day = addLocalDays(day, 1);
    }

    final Paint separator = Paint()
      ..color = _rowLine
      ..strokeWidth = 1;
    for (final TrackMetrics metric in layout.metrics.values) {
      canvas.drawLine(
        Offset(0, metric.rowTop + metric.height - .5),
        Offset(layout.width, metric.rowTop + metric.height - .5),
        separator,
      );
    }
  }

  @override
  bool shouldRepaint(covariant TimelineBackgroundPainter oldDelegate) =>
      oldDelegate.layout.viewStart != layout.viewStart ||
      oldDelegate.layout.hours != layout.hours ||
      oldDelegate.layout.width != layout.width ||
      oldDelegate.layout.totalHeight != layout.totalHeight ||
      oldDelegate.height != height;
}

class TimelineOverlayPainter extends CustomPainter {
  TimelineOverlayPainter({required this.layout, required this.now});

  final TimelineLayout layout;
  final DateTime now;

  @override
  void paint(Canvas canvas, Size size) {
    final double nowX = layout.xOf(now);
    if (nowX > 0) {
      final double right = math.min(layout.width, nowX);
      if (right > 0) {
        canvas.drawRect(
          Rect.fromLTWH(0, 0, right, size.height),
          Paint()..color = const Color(0x38000000),
        );
      }
    }
    if (nowX >= 0 && nowX <= layout.width) {
      final Paint glow = Paint()
        ..color = AppColors.alpha(AppColors.now, .16)
        ..strokeWidth = 6;
      final Paint line = Paint()
        ..color = AppColors.now
        ..strokeWidth = 1.5;
      canvas.drawLine(Offset(nowX, 0), Offset(nowX, size.height), glow);
      canvas.drawLine(Offset(nowX, 0), Offset(nowX, size.height), line);
      canvas.drawCircle(Offset(nowX, 0), 3, Paint()..color = AppColors.now);
    }
  }

  @override
  bool shouldRepaint(covariant TimelineOverlayPainter oldDelegate) =>
      oldDelegate.layout.viewStart != layout.viewStart ||
      oldDelegate.layout.hours != layout.hours ||
      oldDelegate.layout.width != layout.width ||
      oldDelegate.now != now;
}

class MinimapPainter extends CustomPainter {
  MinimapPainter({
    required this.tracks,
    required this.blocks,
    required this.rangeStart,
    required this.rangeEnd,
    required this.viewStart,
    required this.hours,
    required this.now,
    required this.selectedIds,
  });

  final List<Track> tracks;
  final List<Block> blocks;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final DateTime viewStart;
  final double hours;
  final DateTime now;
  final Set<int> selectedIds;

  double _xOf(DateTime value, double width) {
    final int range = math.max(
      1,
      rangeEnd.millisecondsSinceEpoch - rangeStart.millisecondsSinceEpoch,
    );
    final int offset =
        value.millisecondsSinceEpoch - rangeStart.millisecondsSinceEpoch;
    return (offset / range) * width;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final Paint dayPaint = Paint()
      ..color = const Color(0x20FFFFFF)
      ..strokeWidth = 1;

    DateTime day = startOfLocalDay(rangeStart);
    while (!day.isAfter(rangeEnd)) {
      final double x = _xOf(day, size.width);
      if (x >= 0 && x <= size.width) {
        if (day.weekday == DateTime.saturday ||
            day.weekday == DateTime.sunday) {
          final double next = _xOf(addLocalDays(day, 1), size.width);
          canvas.drawRect(
            Rect.fromLTWH(x, 0, math.max(0, next - x), size.height),
            Paint()..color = const Color(0x07FFFFFF),
          );
        }
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), dayPaint);
      }
      day = addLocalDays(day, 1);
    }

    final int count = math.max(1, tracks.length);
    final double rowHeight = math.min(
      7.0,
      math.max(3.0, (size.height - 8) / count),
    );
    final double totalRows = rowHeight * count;
    final double top = (size.height - totalRows) / 2;
    for (int i = 0; i < tracks.length; i++) {
      final Track track = tracks[i];
      final double y = top + i * rowHeight;
      final double barHeight = math.max(2, math.min(4, rowHeight - 1.5));
      for (final Block block in blocks) {
        if (block.trackId != track.id) continue;
        final DateTime start = block.start.isBefore(rangeStart)
            ? rangeStart
            : block.start;
        final DateTime end = block.end.isAfter(rangeEnd) ? rangeEnd : block.end;
        if (!end.isAfter(start)) continue;
        final double x1 = _xOf(start, size.width);
        final double x2 = _xOf(end, size.width);
        if (x2 < 0 || x1 > size.width) continue;
        final double left = math.max(0, x1);
        final double width = math.max(1, math.min(size.width, x2) - left);
        final Color color = track.color;
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(
              left,
              y + (rowHeight - barHeight) / 2,
              width,
              barHeight,
            ),
            const Radius.circular(1.5),
          ),
          Paint()..color = AppColors.alpha(color, block.isZone ? .45 : .86),
        );
        if (selectedIds.contains(block.id)) {
          canvas.drawLine(
            Offset(left, y + (rowHeight - barHeight) / 2),
            Offset(left + width, y + (rowHeight - barHeight) / 2),
            Paint()..color = Colors.white.withValues(alpha: .8),
          );
        }
      }
    }

    final double nowX = _xOf(now, size.width);
    if (nowX >= 0 && nowX <= size.width) {
      canvas.drawLine(
        Offset(nowX, 0),
        Offset(nowX, size.height),
        Paint()
          ..color = AppColors.alpha(AppColors.now, .8)
          ..strokeWidth = 1,
      );
    }

    final double viewLeft = _xOf(viewStart, size.width);
    final double viewRight = _xOf(
      viewStart.add(Duration(milliseconds: (hours * kHourMs).round())),
      size.width,
    );
    final Rect viewRect = Rect.fromLTWH(
      viewLeft.clamp(0, size.width),
      1,
      (viewRight - viewLeft).clamp(0, size.width),
      size.height - 2,
    );
    if (viewRect.width > 1) {
      canvas.drawRect(viewRect, Paint()..color = const Color(0x14FFFFFF));
      canvas.drawRRect(
        RRect.fromRectAndRadius(viewRect.deflate(.5), const Radius.circular(2)),
        Paint()
          ..color = Colors.white.withValues(alpha: .5)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant MinimapPainter oldDelegate) => true;
}
