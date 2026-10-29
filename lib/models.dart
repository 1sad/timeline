import 'dart:math' as math;

import 'package:flutter/material.dart';

const int kHourMs = 60 * 60 * 1000;
const int kDayMs = 24 * kHourMs;
const int kTimelineDays = 8;
const List<double> kZoomSteps = <double>[1, 3, 6, 12, 24, 72];

/// Zoom stops for a timeline whose full range is [maxHours] wide. The actual
/// range is always the final stop. Fixed stops within an hour of it are
/// dropped so daylight-saving changes cannot produce a duplicate 8d step.
List<double> zoomPresetsFor(double maxHours) {
  final List<double> presets = kZoomSteps
      .where((double value) => value < maxHours - 1)
      .toList();
  presets.add(maxHours);
  return presets;
}

/// All calendar maths in the app is done with local [DateTime] objects.
/// Building the next midnight explicitly (instead of adding 24h) keeps day
/// boundaries and ruler ticks correct across daylight-saving changes.
DateTime startOfLocalDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);

DateTime addLocalDays(DateTime value, int days) => DateTime(
  value.year,
  value.month,
  value.day + days,
  value.hour,
  value.minute,
  value.second,
  value.millisecond,
  value.microsecond,
);

DateTime atLocalTime(DateTime day, int hour, int minute) =>
    DateTime(day.year, day.month, day.day, hour, minute);

String _pad2(int n) => n.toString().padLeft(2, '0');
const List<String> _weekdays = <String>[
  'Sun',
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
];
const List<String> _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String fmtTime(DateTime value) => '${_pad2(value.hour)}:${_pad2(value.minute)}';

String fmtClock(DateTime value) =>
    '${_pad2(value.hour)}:${_pad2(value.minute)}:${_pad2(value.second)}';

String fmtDay(DateTime value) => '${_weekdays[value.weekday % 7]} ${value.day}';

String fmtDayTight(DateTime value) =>
    '${_weekdays[value.weekday % 7].substring(0, 2)} ${value.day}';

String fmtDayLong(DateTime value) =>
    '${_weekdays[value.weekday % 7]} ${value.day} ${_months[value.month - 1]}';

String fmtDateInput(DateTime value) =>
    '${value.year}-${_pad2(value.month)}-${_pad2(value.day)}';

String fmtDuration(Duration duration) {
  final int minutes = math.max(1, (duration.inMilliseconds / 60000).round());
  if (minutes < 60) return '${minutes}m';
  final int hours = minutes ~/ 60;
  final int rest = minutes % 60;
  return rest == 0 ? '${hours}h' : '${hours}h ${_pad2(rest)}m';
}

/// Live metadata for a block. Deliberately describes how far away or how
/// long rather than repeating the start/end clock times shown in the header.
String blockMeta(Block block, DateTime now) {
  if (!now.isBefore(block.start) && now.isBefore(block.end)) {
    return '${fmtDuration(now.difference(block.start))} in · '
        '${fmtDuration(block.end.difference(now))} left';
  }
  if (now.isBefore(block.start)) {
    return 'in ${fmtDuration(block.start.difference(now))}';
  }
  return fmtDuration(block.end.difference(block.start));
}

/// Just the moving part of a block's timing: "in 20m", "35m left" or nothing
/// once the block has finished.
String blockRelativeMeta(Block block, DateTime now) {
  if (!now.isBefore(block.start) && now.isBefore(block.end)) {
    return '${fmtDuration(block.end.difference(now))} left';
  }
  if (now.isBefore(block.start)) {
    return 'in ${fmtDuration(block.start.difference(now))}';
  }
  return '';
}

/// Total length plus how far away or how much is left. Used by headers where
/// the total duration should always be visible exactly once.
String blockTiming(Block block, DateTime now) {
  final String total = fmtDuration(block.end.difference(block.start));
  final String relative = blockRelativeMeta(block, now);
  return relative.isEmpty ? total : '$total · $relative';
}

String zoomLabel(double hours) {
  if ((hours - 24).abs() < .01) return '1d';
  if ((hours - 72).abs() < .01) return '3d';
  if ((hours - 192).abs() < .01) return '8d';
  if (hours < 24) {
    final double rounded = (hours * 10).round() / 10;
    return '${rounded == rounded.roundToDouble() ? rounded.toInt() : rounded}h';
  }
  final double days = hours / 24;
  final double rounded = (days * 10).round() / 10;
  return '${rounded == rounded.roundToDouble() ? rounded.toInt() : rounded}d';
}

int colorFromHex(String? value, {int fallback = 0xFF7C8698}) {
  if (value == null) return fallback;
  final String raw = value.trim().replaceFirst('#', '');
  if (raw.length == 6) {
    return int.tryParse('FF$raw', radix: 16) ?? fallback;
  }
  if (raw.length == 8) {
    return int.tryParse(raw, radix: 16) ?? fallback;
  }
  return fallback;
}

String hexFromColor(int value) {
  final int rgb = value & 0xFFFFFF;
  return '#${rgb.toRadixString(16).padLeft(6, '0')}';
}

enum BlockKind { event, zone }

/// Points inside a block where a notification can fire.
enum AlarmOffset { start, middle, end }

extension AlarmOffsetLabel on AlarmOffset {
  String get label {
    switch (this) {
      case AlarmOffset.start:
        return 'Start';
      case AlarmOffset.middle:
        return 'Middle';
      case AlarmOffset.end:
        return 'End';
    }
  }

  /// The exact instant this offset points at, or null for a block that has no
  /// length.
  DateTime? timeFor(Block block) {
    final Duration span = block.end.difference(block.start);
    if (span <= Duration.zero) return null;
    switch (this) {
      case AlarmOffset.start:
        return block.start;
      case AlarmOffset.middle:
        return block.start.add(
          Duration(milliseconds: span.inMilliseconds ~/ 2),
        );
      case AlarmOffset.end:
        return block.end;
    }
  }

  static AlarmOffset? parse(Object? value) {
    for (final AlarmOffset offset in AlarmOffset.values) {
      if (offset.name == value) return offset;
    }
    return null;
  }
}

enum RepeatCadence { none, daily, hourly }

/// How a block repeats.
///
/// Daily repeats use ISO weekdays (Mon = 1 … Sun = 7). Hourly repeats use
/// 24-hour clock hours and keep the block's start minute. An empty selection
/// means the block does not repeat.
class RepeatSpec {
  const RepeatSpec({
    this.mode = RepeatCadence.none,
    this.days = const <int>{},
    this.hours = const <int>{},
  });

  const RepeatSpec.daily([this.days = allDays])
    : mode = RepeatCadence.daily,
      hours = const <int>{};

  const RepeatSpec.hourly([this.hours = const <int>{}])
    : mode = RepeatCadence.hourly,
      days = const <int>{};

  static const Set<int> allDays = <int>{1, 2, 3, 4, 5, 6, 7};
  static const Set<int> weekdays = <int>{1, 2, 3, 4, 5};
  static const Set<int> allHours = <int>{
    0,
    1,
    2,
    3,
    4,
    5,
    6,
    7,
    8,
    9,
    10,
    11,
    12,
    13,
    14,
    15,
    16,
    17,
    18,
    19,
    20,
    21,
    22,
    23,
  };

  static const RepeatSpec none = RepeatSpec();

  final RepeatCadence mode;
  final Set<int> days;
  final Set<int> hours;

  bool get active => mode != RepeatCadence.none;
  bool get isDaily => mode == RepeatCadence.daily;
  bool get isHourly => mode == RepeatCadence.hourly;

  bool get isValid {
    switch (mode) {
      case RepeatCadence.none:
        return true;
      case RepeatCadence.daily:
        return days.isNotEmpty;
      case RepeatCadence.hourly:
        return hours.isNotEmpty;
    }
  }

  List<int> get sortedDays => days.toList(growable: false)..sort();
  List<int> get sortedHours => hours.toList(growable: false)..sort();

  String get label {
    switch (mode) {
      case RepeatCadence.none:
        return 'Does not repeat';
      case RepeatCadence.daily:
        return 'Daily';
      case RepeatCadence.hourly:
        return 'Hourly';
    }
  }

  String get summary {
    switch (mode) {
      case RepeatCadence.none:
        return 'Does not repeat';
      case RepeatCadence.daily:
        if (days.length == allDays.length) return 'Every day';
        return sortedDays.map(shortWeekday).join(', ');
      case RepeatCadence.hourly:
        if (hours.length == allHours.length) return 'Every hour';
        return sortedHours.map(hourLabel).join(', ');
    }
  }

  static String shortWeekday(int day) => _weekdays[day % 7];
  static String hourLabel(int hour) => '${_pad2(hour)}:00';

  RepeatSpec copyWith({RepeatCadence? mode, Set<int>? days, Set<int>? hours}) =>
      RepeatSpec(
        mode: mode ?? this.mode,
        days: days ?? this.days,
        hours: hours ?? this.hours,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'mode': mode.name,
    if (mode == RepeatCadence.daily) 'days': sortedDays,
    if (mode == RepeatCadence.hourly) 'hours': sortedHours,
  };

  /// Accepts the current object shape and the older string values written by
  /// Timeline 1.1 and earlier.
  static RepeatSpec parse(Object? value, {DateTime? anchor}) {
    if (value is Map) {
      final Object? rawMode = value['mode'];
      final RepeatCadence mode = RepeatCadence.values.firstWhere(
        (RepeatCadence item) => item.name == rawMode,
        orElse: () => RepeatCadence.none,
      );
      final Set<int> days = _intSet(value['days'])
          .where((int day) => day >= 1 && day <= 7)
          .toSet();
      final Set<int> hours = _intSet(value['hours'])
          .where((int hour) => hour >= 0 && hour <= 23)
          .toSet();
      if (mode == RepeatCadence.daily) {
        return RepeatSpec(mode: mode, days: days);
      }
      if (mode == RepeatCadence.hourly) {
        return RepeatSpec(mode: mode, hours: hours);
      }
      return RepeatSpec.none;
    }
    switch (value) {
      case 'daily':
        return const RepeatSpec.daily();
      case 'weekdays':
        return const RepeatSpec(mode: RepeatCadence.daily, days: weekdays);
      case 'weekly':
        return RepeatSpec(
          mode: RepeatCadence.daily,
          days: <int>{anchor?.weekday ?? DateTime.monday},
        );
      default:
        return RepeatSpec.none;
    }
  }

  static Set<int> _intSet(Object? value) {
    if (value is! List) return <int>{};
    return value
        .map((Object? item) => item is num ? item.toInt() : null)
        .whereType<int>()
        .toSet();
  }

  @override
  bool operator ==(Object other) =>
      other is RepeatSpec &&
      other.mode == mode &&
      _sameInts(other.days, days) &&
      _sameInts(other.hours, hours);

  @override
  int get hashCode => Object.hash(
    mode,
    Object.hashAll(sortedDays),
    Object.hashAll(sortedHours),
  );

  static bool _sameInts(Set<int> a, Set<int> b) =>
      a.length == b.length && a.containsAll(b);
}

extension BlockKindJson on BlockKind {
  String get value => this == BlockKind.zone ? 'zone' : 'event';

  static BlockKind parse(Object? value) =>
      value == 'zone' ? BlockKind.zone : BlockKind.event;
}

class Track {
  Track({
    required this.id,
    required this.name,
    required this.colorValue,
    this.fixed = false,
  });

  final String id;
  final String name;
  final int colorValue;
  final bool fixed;

  Color get color => Color(colorValue);

  Track copyWith({String? name, int? colorValue}) => Track(
    id: id,
    name: name ?? this.name,
    colorValue: colorValue ?? this.colorValue,
    fixed: fixed,
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'name': name,
    'color': hexFromColor(colorValue),
    if (fixed) 'fixed': true,
  };

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    id: (json['id'] ?? '').toString(),
    name: (json['name'] ?? 'Untitled').toString(),
    colorValue: colorFromHex(json['color'] as String?),
    fixed: json['fixed'] == true,
  );
}

class Block {
  Block({
    required this.id,
    required this.trackId,
    required this.title,
    required this.start,
    required this.end,
    this.kind = BlockKind.event,
    Set<AlarmOffset> alarms = const <AlarmOffset>{},
    this.repeat = RepeatSpec.none,
    this.seriesId,
    this.lane,
  }) : alarms = Set<AlarmOffset>.of(alarms);

  int id;
  String trackId;
  String title;
  DateTime start;
  DateTime end;
  BlockKind kind;
  Set<AlarmOffset> alarms;
  RepeatSpec repeat;
  int? seriesId;

  /// Explicit vertical lane. Null means the block sits in the first lane and
  /// the row only grows when a block is dragged into a lower lane.
  int? lane;

  bool get isZone => kind == BlockKind.zone;
  Duration get duration => end.difference(start);
  bool get repeats => repeat.active;
  bool get alarm => alarms.isNotEmpty;

  Block copyWith({
    int? id,
    String? trackId,
    String? title,
    DateTime? start,
    DateTime? end,
    BlockKind? kind,
    Set<AlarmOffset>? alarms,
    RepeatSpec? repeat,
    int? seriesId,
    bool clearSeriesId = false,
    int? lane,
    bool clearLane = false,
  }) => Block(
    id: id ?? this.id,
    trackId: trackId ?? this.trackId,
    title: title ?? this.title,
    start: start ?? this.start,
    end: end ?? this.end,
    kind: kind ?? this.kind,
    alarms: alarms ?? this.alarms,
    repeat: repeat ?? this.repeat,
    seriesId: clearSeriesId ? null : (seriesId ?? this.seriesId),
    lane: clearLane ? null : (lane ?? this.lane),
  );

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'track': trackId,
    'title': title,
    'start': start.millisecondsSinceEpoch,
    'end': end.millisecondsSinceEpoch,
    if (kind == BlockKind.zone) 'type': 'zone',
    if (alarms.isNotEmpty)
      'alarm': alarms.map((AlarmOffset offset) => offset.name).toList(),
    if (repeat.active) 'repeat': repeat.toJson(),
    if (seriesId != null) 'seriesId': seriesId,
    if (lane != null) 'lane': lane,
  };

  /// Tolerant parser used by JSON import. It intentionally accepts both the
  /// compact sync shape (`track`) and a slightly more explicit shape
  /// (`trackId`, ISO timestamps).
  factory Block.fromJson(Map<String, dynamic> json, {required int fallbackId}) {
    final DateTime? parsedStart = parseJsonTime(json['start']);
    final DateTime? parsedEnd = parseJsonTime(json['end']);
    if (parsedStart == null ||
        parsedEnd == null ||
        !parsedEnd.isAfter(parsedStart)) {
      throw const FormatException('Block has an invalid start or end time');
    }
    return Block(
      id: _jsonInt(json['id'], fallbackId),
      trackId: (json['track'] ?? json['trackId'] ?? 'uncat').toString(),
      title: (json['title'] ?? 'Untitled').toString(),
      start: parsedStart,
      end: parsedEnd,
      kind: BlockKindJson.parse(json['type'] ?? json['kind']),
      alarms: parseAlarms(json['alarm'] ?? json['alarms']),
      repeat: RepeatSpec.parse(json['repeat'], anchor: parsedStart),
      seriesId: json['seriesId'] is num
          ? (json['seriesId'] as num).toInt()
          : int.tryParse('${json['seriesId'] ?? ''}'),
      lane: json['lane'] is num
          ? math.max(0, (json['lane'] as num).toInt())
          : int.tryParse('${json['lane'] ?? ''}'),
    );
  }
}

/// Reads both the current list shape and the older boolean `alarm` flag.
Set<AlarmOffset> parseAlarms(Object? value) {
  if (value == true) return <AlarmOffset>{AlarmOffset.start};
  if (value is List) {
    return value.map(AlarmOffsetLabel.parse).whereType<AlarmOffset>().toSet();
  }
  if (value is String) {
    final AlarmOffset? offset = AlarmOffsetLabel.parse(value);
    if (offset != null) return <AlarmOffset>{offset};
  }
  return <AlarmOffset>{};
}

DateTime? parseJsonTime(Object? value) {
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt());
  }
  if (value is String) {
    final int? numeric = int.tryParse(value);
    if (numeric != null) return DateTime.fromMillisecondsSinceEpoch(numeric);
    return DateTime.tryParse(value)?.toLocal();
  }
  return null;
}

int _jsonInt(Object? value, int fallback) {
  if (value is num) return value.toInt();
  return int.tryParse('${value ?? ''}') ?? fallback;
}

class TemplatePart {
  TemplatePart({
    required this.title,
    required this.trackId,
    required this.offsetMinutes,
    required this.durationMinutes,
    this.kind = BlockKind.event,
    Set<AlarmOffset> alarms = const <AlarmOffset>{},
    this.repeat = RepeatSpec.none,
  }) : alarms = Set<AlarmOffset>.of(alarms);

  final String title;
  final String trackId;
  final int offsetMinutes;
  final int durationMinutes;
  final BlockKind kind;
  final Set<AlarmOffset> alarms;
  final RepeatSpec repeat;

  bool get alarm => alarms.isNotEmpty;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'title': title,
    'track': trackId,
    'offsetMinutes': offsetMinutes,
    'durationMinutes': durationMinutes,
    if (kind == BlockKind.zone) 'type': 'zone',
    if (alarms.isNotEmpty)
      'alarm': alarms.map((AlarmOffset offset) => offset.name).toList(),
    if (repeat.active) 'repeat': repeat.toJson(),
  };

  factory TemplatePart.fromJson(Map<String, dynamic> json) => TemplatePart(
    title: (json['title'] ?? 'Untitled').toString(),
    trackId: (json['track'] ?? json['trackId'] ?? 'uncat').toString(),
    offsetMinutes: _jsonInt(json['offsetMinutes'], 0),
    durationMinutes: math.max(
      1,
      _jsonInt(json['durationMinutes'] ?? json['minutes'], 60),
    ),
    kind: BlockKindJson.parse(json['type'] ?? json['kind']),
    alarms: parseAlarms(json['alarm'] ?? json['alarms']),
    repeat: RepeatSpec.parse(json['repeat']),
  );
}

class Template {
  Template({
    required this.id,
    required this.title,
    required this.trackId,
    required this.durationMinutes,
    this.kind = BlockKind.event,
    Set<AlarmOffset> alarms = const <AlarmOffset>{},
    this.repeat = RepeatSpec.none,
    this.parts = const <TemplatePart>[],
  }) : alarms = Set<AlarmOffset>.of(alarms);

  final int id;
  final String title;
  final String trackId;
  final int durationMinutes;
  final BlockKind kind;
  final Set<AlarmOffset> alarms;
  final RepeatSpec repeat;

  bool get alarm => alarms.isNotEmpty;

  /// Empty for a legacy single-block template. A multi-block selection has one
  /// part per block, with offsets measured from the earliest selected start.
  final List<TemplatePart> parts;

  bool get isMulti => parts.length > 1;
  int get blockCount => parts.isEmpty ? 1 : parts.length;

  Map<String, dynamic> toJson() => <String, dynamic>{
    'id': id,
    'title': title,
    'track': trackId,
    'durationMinutes': durationMinutes,
    if (kind == BlockKind.zone) 'type': 'zone',
    if (alarms.isNotEmpty)
      'alarm': alarms.map((AlarmOffset offset) => offset.name).toList(),
    if (repeat.active) 'repeat': repeat.toJson(),
    if (parts.isNotEmpty)
      'parts': parts.map((TemplatePart part) => part.toJson()).toList(),
  };

  factory Template.fromJson(
    Map<String, dynamic> json, {
    required int fallbackId,
  }) {
    final List<TemplatePart> parts = <TemplatePart>[];
    final Object? rawParts = json['parts'];
    if (rawParts is List) {
      for (final Object? item in rawParts) {
        if (item is Map) {
          try {
            parts.add(TemplatePart.fromJson(Map<String, dynamic>.from(item)));
          } catch (_) {}
        }
      }
    }
    return Template(
      id: _jsonInt(json['id'], fallbackId),
      title: (json['title'] ?? 'Untitled').toString(),
      trackId: (json['track'] ?? json['trackId'] ?? 'uncat').toString(),
      durationMinutes: math.max(
        1,
        _jsonInt(json['durationMinutes'] ?? json['minutes'], 60),
      ),
      kind: BlockKindJson.parse(json['type'] ?? json['kind']),
      alarms: parseAlarms(json['alarm'] ?? json['alarms']),
      repeat: RepeatSpec.parse(json['repeat']),
      parts: parts,
    );
  }
}

/// A block clipped to the timeline range. Blocks crossing midnight remain a
/// single segment so their lane and geometry stay stable across day changes.
class TimelineSegment {
  TimelineSegment({
    required this.block,
    required this.trackId,
    required this.start,
    required this.end,
    required this.isZone,
    this.lane = 0,
  });

  final Block block;
  final String trackId;
  final DateTime start;
  final DateTime end;
  final bool isZone;
  int lane;
}

class TrackMetrics {
  TrackMetrics({
    required this.zones,
    required this.events,
    required this.collapsed,
    required this.height,
    required this.rowTop,
  });

  final int zones;
  final int events;
  final bool collapsed;
  final double height;
  final double rowTop;

  double get zoneTop => rowTop + 8;
  double get eventTop => rowTop + 8 + zones * 18 + (zones > 0 ? 6 : 0);
}

class TimelineLayout {
  TimelineLayout({
    required this.tracks,
    required this.segments,
    required this.metrics,
    required this.totalHeight,
    required this.rangeStart,
    required this.rangeEnd,
    required this.viewStart,
    required this.hours,
    required this.width,
  });

  final List<Track> tracks;
  final List<TimelineSegment> segments;
  final Map<String, TrackMetrics> metrics;
  final double totalHeight;
  final DateTime rangeStart;
  final DateTime rangeEnd;
  final DateTime viewStart;
  final double hours;
  final double width;

  double get pxPerHour => width / hours;

  DateTime get viewEnd =>
      viewStart.add(Duration(milliseconds: (hours * kHourMs).round()));

  double xOf(DateTime time) =>
      time.difference(viewStart).inMilliseconds / kHourMs * pxPerHour;

  DateTime timeAtX(double x) =>
      viewStart.add(Duration(milliseconds: (x / pxPerHour * kHourMs).round()));

  bool isVisible(DateTime start, DateTime end) =>
      end.isAfter(viewStart) && start.isBefore(viewEnd);

  double segmentTop(TimelineSegment segment) {
    final TrackMetrics metric = metrics[segment.trackId]!;
    if (metric.collapsed) {
      // Collapsed rows show one shared lane. Center each bar in the row so
      // zones and events overlap cleanly instead of hanging below the rail.
      final double barHeight = segment.isZone ? 4 : 6;
      return metric.rowTop + (metric.height - barHeight) / 2;
    }
    return segment.isZone
        ? metric.zoneTop + segment.lane * 18
        : metric.eventTop + segment.lane * 42;
  }

  double segmentHeight(TimelineSegment segment) {
    final TrackMetrics metric = metrics[segment.trackId]!;
    if (metric.collapsed) return segment.isZone ? 4 : 6;
    return segment.isZone ? 16 : 34;
  }

  Rect segmentRect(TimelineSegment segment) {
    final double x1 = xOf(segment.start);
    final double x2 = xOf(segment.end);
    final double left = math.max(0, x1);
    final double right = math.min(width, x2);
    return Rect.fromLTWH(
      left,
      segmentTop(segment),
      math.max(2, right - left),
      segmentHeight(segment),
    );
  }

  TimelineSegment? hitTest(Offset point) {
    for (final TimelineSegment segment in segments.reversed) {
      final Rect rect = segmentRect(segment);
      if (rect.contains(point)) return segment;
    }
    return null;
  }

  /// Every block under [point], topmost first. Tapping again on an overlap
  /// cycles through the stack so a buried block can still be selected.
  List<TimelineSegment> hitTestAll(Offset point) {
    final List<TimelineSegment> hits = <TimelineSegment>[];
    for (final TimelineSegment segment in segments.reversed) {
      if (segmentRect(segment).contains(point)) hits.add(segment);
    }
    return hits;
  }

  /// Edge hit areas are deliberately a little larger than the 10px handles.
  ({TimelineSegment segment, bool left})? hitHandle(
    Offset point,
    int? blockId,
  ) {
    if (blockId == null) return null;
    final List<TimelineSegment> selected = segments
        .where((TimelineSegment segment) => segment.block.id == blockId)
        .toList(growable: false);
    if (selected.isEmpty) return null;
    final TimelineSegment first = selected.first;
    final TimelineSegment last = selected.last;
    final Rect firstRect = segmentRect(first);
    final Rect lastRect = segmentRect(last);
    final Rect left = Rect.fromCenter(
      center: Offset(firstRect.left, firstRect.center.dy),
      width: 18,
      height: 36,
    );
    final Rect right = Rect.fromCenter(
      center: Offset(lastRect.right, lastRect.center.dy),
      width: 18,
      height: 36,
    );
    if (left.contains(point)) return (segment: first, left: true);
    if (right.contains(point)) return (segment: last, left: false);
    return null;
  }
}

/// Computes lanes for each track and block shape across the whole range. The
/// row height takes the worst overlap in the range, so rows never grow or
/// shrink while the user pans.
TimelineLayout buildTimelineLayout({
  required List<Track> tracks,
  required List<Block> blocks,
  required DateTime rangeStart,
  required DateTime rangeEnd,
  required DateTime viewStart,
  required double hours,
  required double width,
  required Map<String, bool> trackOpen,
}) {
  final List<TimelineSegment> all = <TimelineSegment>[];

  for (final Block block in blocks) {
    final DateTime clippedStart = block.start.isBefore(rangeStart)
        ? rangeStart
        : block.start;
    final DateTime clippedEnd = block.end.isAfter(rangeEnd)
        ? rangeEnd
        : block.end;
    if (!clippedEnd.isAfter(clippedStart)) continue;
    all.add(
      TimelineSegment(
        block: block,
        trackId: block.trackId,
        start: clippedStart,
        end: clippedEnd,
        isZone: block.isZone,
      ),
    );
  }

  // Rows are one lane tall by default. A block only leaves the first lane when
  // the user drags it into a lower one, so overlaps simply stack in lane 0.
  // Lanes stay exactly as stored while dragging; the store removes empty
  // leading lanes after a drop (see TimelineStore.normalizeLanes).
  for (final TimelineSegment segment in all) {
    segment.lane = math.max(0, segment.block.lane ?? 0);
  }

  final Map<String, int> maxZones = <String, int>{};
  final Map<String, int> maxEvents = <String, int>{};
  for (final TimelineSegment segment in all) {
    if (segment.isZone) {
      maxZones[segment.trackId] = math.max(
        maxZones[segment.trackId] ?? 0,
        segment.lane + 1,
      );
    } else {
      maxEvents[segment.trackId] = math.max(
        maxEvents[segment.trackId] ?? 0,
        segment.lane + 1,
      );
    }
  }

  final Map<String, TrackMetrics> metrics = <String, TrackMetrics>{};
  final List<TimelineSegment> ordered = <TimelineSegment>[];
  double rowTop = 0;
  for (final Track track in tracks) {
    final int zones = maxZones[track.id] ?? 0;
    final int events = maxEvents[track.id] ?? 0;
    final bool collapsed = trackOpen[track.id] == false;
    final double content = 8 + zones * 18 + (zones > 0 ? 6 : 0) + events * 42;
    final double height = collapsed
        ? 28
        : (zones == 0 && events == 0 ? 50 : content);
    metrics[track.id] = TrackMetrics(
      zones: zones,
      events: events,
      collapsed: collapsed,
      height: height,
      rowTop: rowTop,
    );
    rowTop += height;

    final List<TimelineSegment> trackSegments =
        all
            .where((TimelineSegment segment) => segment.trackId == track.id)
            .toList()
          ..sort((TimelineSegment a, TimelineSegment b) {
            final int byZone = (a.isZone ? 0 : 1).compareTo(b.isZone ? 0 : 1);
            if (byZone != 0) return byZone;
            final int byStart = a.start.compareTo(b.start);
            if (byStart != 0) return byStart;
            return a.lane.compareTo(b.lane);
          });
    ordered.addAll(trackSegments);
  }

  return TimelineLayout(
    tracks: tracks,
    segments: ordered,
    metrics: metrics,
    totalHeight: math.max(1, rowTop),
    rangeStart: rangeStart,
    rangeEnd: rangeEnd,
    viewStart: viewStart,
    hours: hours,
    width: width,
  );
}
