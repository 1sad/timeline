import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

const String _storageKey = 'timeline_data_v1';
const String _uncatId = 'uncat';
const int _uncatColor = 0xFF7C8698;

const List<int> _palette = <int>[
  0xFFD9A05B,
  0xFF6F9DF0,
  0xFF72C39A,
  0xFF5FC2C9,
  0xFFB489E6,
  0xFFE08AA0,
  0xFF6270C9,
  0xFFE3B341,
  0xFF7BD88F,
  0xFFFF8FAB,
  0xFFA78BFA,
  0xFFF0876A,
];

class UndoState {
  UndoState({
    required this.tracks,
    required this.blocks,
    required this.templates,
    required this.trackOpen,
    required this.showNames,
    required this.locked,
  });

  final List<Track> tracks;
  final List<Block> blocks;
  final List<Template> templates;
  final Map<String, bool> trackOpen;
  final bool showNames;
  final bool locked;
}

class UndoEntry {
  UndoEntry({required this.state, required this.label});

  final UndoState state;
  final String label;
}

class ImportResult {
  const ImportResult({required this.tracks, required this.blocks});

  final int tracks;
  final int blocks;
}

class TimelineStore extends ChangeNotifier {
  TimelineStore() {
    final DateTime now = DateTime.now();
    timelineStart = DateTime(now.year, now.month, now.day - 4);
    timelineEnd = DateTime(now.year, now.month, now.day + 4);
  }

  late final DateTime timelineStart;
  late final DateTime timelineEnd;

  final List<Track> tracks = <Track>[];
  final List<Block> blocks = <Block>[];
  final List<Template> templates = <Template>[];
  final Map<String, bool> trackOpen = <String, bool>{};
  final List<UndoEntry> undoStack = <UndoEntry>[];

  bool showNames = true;
  bool locked = false;

  int _nextBlockId = 1;
  int _nextTrackId = 1;
  int _nextTemplateId = 1;
  Timer? _saveTimer;
  SharedPreferences? _prefs;

  bool get hasUndo => undoStack.isNotEmpty;
  int get maxUndo => 30;

  Track? trackById(String id) {
    for (final Track track in tracks) {
      if (track.id == id) return track;
    }
    return null;
  }

  Track get uncategorized => Track(
    id: _uncatId,
    name: 'Uncategorized',
    colorValue: _uncatColor,
    fixed: true,
  );

  Track trackOrUncategorized(String id) => trackById(id) ?? uncategorized;

  bool hasBlocksInTrack(String trackId) =>
      blocks.any((Block block) => block.trackId == trackId);

  int blockCountForTrack(String trackId) =>
      blocks.where((Block block) => block.trackId == trackId).length;

  Block? blockById(int id) {
    for (final Block block in blocks) {
      if (block.id == id) return block;
    }
    return null;
  }

  Block? currentBlock(DateTime now) {
    final List<Block> current =
        blocks
            .where(
              (Block block) =>
                  !block.isZone &&
                  !now.isBefore(block.start) &&
                  now.isBefore(block.end),
            )
            .toList()
          ..sort((Block a, Block b) => a.end.compareTo(b.end));
    return current.isEmpty ? null : current.first;
  }

  List<Block> nextBlocks(DateTime now, {int limit = 3}) {
    final List<Block> upcoming =
        blocks
            .where((Block block) => !block.isZone && block.start.isAfter(now))
            .toList()
          ..sort((Block a, Block b) => a.start.compareTo(b.start));
    return upcoming.take(limit).toList(growable: false);
  }

  Future<void> load({SharedPreferences? preferences}) async {
    _prefs = preferences ?? await SharedPreferences.getInstance();
    final String? raw = _prefs!.getString(_storageKey);
    if (raw != null) {
      try {
        final Object? decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic> && _restoreFromMap(decoded)) {
          _scheduleSave();
          return;
        }
      } catch (_) {
        // A damaged preference bundle must never make the app unusable.
      }
    }
    _seedSampleData();
    _ensureUncategorized();
    _scheduleSave();
  }

  bool _restoreFromMap(Map<String, dynamic> map) {
    final Object? rawTracks = map['tracks'];
    final Object? rawBlocks = map['blocks'];
    if (rawTracks is! List || rawBlocks is! List) return false;

    final List<Track> restoredTracks = <Track>[];
    for (final Object? item in rawTracks) {
      if (item is! Map) continue;
      final Track track = Track.fromJson(Map<String, dynamic>.from(item));
      if (track.id.isEmpty ||
          track.id == _uncatId ||
          restoredTracks.any((Track t) => t.id == track.id)) {
        continue;
      }
      restoredTracks.add(track);
    }

    final Set<String> ids = restoredTracks
        .map((Track track) => track.id)
        .toSet();
    final List<Block> restoredBlocks = <Block>[];
    final Set<int> usedIds = <int>{};
    int nextId = 1;
    for (final Object? item in rawBlocks) {
      if (item is! Map) continue;
      try {
        final Map<String, dynamic> json = Map<String, dynamic>.from(item);
        int id = (json['id'] is num)
            ? (json['id'] as num).toInt()
            : int.tryParse('${json['id'] ?? ''}') ?? 0;
        if (id <= 0 || usedIds.contains(id)) {
          while (usedIds.contains(nextId)) {
            nextId++;
          }
          id = nextId;
        }
        usedIds.add(id);
        nextId = math.max(nextId, id + 1);
        final Block block = Block.fromJson(json, fallbackId: id);
        block.id = id;
        if (!ids.contains(block.trackId)) block.trackId = _uncatId;
        restoredBlocks.add(block);
      } catch (_) {
        // Skip malformed blocks instead of rejecting the whole file.
      }
    }

    final List<Template> restoredTemplates = <Template>[];
    final Object? rawTemplates = map['templates'];
    if (rawTemplates is List) {
      final Set<int> usedTemplateIds = <int>{};
      int nextTemplateId = 1;
      for (final Object? item in rawTemplates) {
        if (item is! Map) continue;
        try {
          final Map<String, dynamic> json = Map<String, dynamic>.from(item);
          int id = (json['id'] is num)
              ? (json['id'] as num).toInt()
              : int.tryParse('${json['id'] ?? ''}') ?? 0;
          if (id <= 0 || usedTemplateIds.contains(id)) {
            while (usedTemplateIds.contains(nextTemplateId)) {
              nextTemplateId++;
            }
            id = nextTemplateId;
          }
          usedTemplateIds.add(id);
          nextTemplateId = math.max(nextTemplateId, id + 1);
          restoredTemplates.add(Template.fromJson(json, fallbackId: id));
        } catch (_) {}
      }
      _nextTemplateId = nextTemplateId;
    }

    tracks
      ..clear()
      ..addAll(restoredTracks);
    blocks
      ..clear()
      ..addAll(restoredBlocks);
    templates
      ..clear()
      ..addAll(restoredTemplates);
    _nextBlockId = nextId;
    _nextTrackId = _nextAvailableTrackNumber();
    undoStack.clear();
    showNames = map['namesHidden'] != true;
    locked = map['locked'] == true;

    trackOpen.clear();
    final Object? rawOpen = map['trackOpen'];
    if (rawOpen is Map) {
      rawOpen.forEach((Object? key, Object? value) {
        if (key is String) trackOpen[key] = value != false;
      });
    }
    for (final Track track in tracks) {
      trackOpen.putIfAbsent(track.id, () => true);
    }
    _ensureUncategorized();
    return true;
  }

  int _nextAvailableTrackNumber() {
    int result = 1;
    for (final Track track in tracks) {
      final Match? match = RegExp(r'^cat-(\d+)$').firstMatch(track.id);
      if (match != null) {
        result = math.max(result, int.parse(match.group(1)!) + 1);
      }
    }
    return result;
  }

  void _ensureUncategorized() {
    final Set<String> known = tracks.map((Track track) => track.id).toSet();
    bool needsUncat = blocks.any(
      (Block block) => !known.contains(block.trackId),
    );
    needsUncat =
        needsUncat || blocks.any((Block block) => block.trackId == _uncatId);
    if (needsUncat) {
      if (!known.contains(_uncatId)) {
        tracks.add(uncategorized);
        trackOpen[_uncatId] = true;
      }
      for (final Block block in blocks) {
        if (!known.contains(block.trackId)) block.trackId = _uncatId;
      }
    } else {
      tracks.removeWhere((Track track) => track.id == _uncatId);
      trackOpen.remove(_uncatId);
    }
    for (final Block block in blocks) {
      if (block.trackId == _uncatId &&
          !tracks.any((Track t) => t.id == _uncatId)) {
        // This can only happen if a caller changed the block list directly.
        // Keeping the invariant in one place avoids an invisible block.
        tracks.add(uncategorized);
        trackOpen[_uncatId] = true;
      }
    }
  }

  UndoState captureState() => UndoState(
    tracks: tracks.map((Track track) => track.copyWith()).toList(),
    blocks: blocks
        .map(
          (Block block) =>
              block.copyWith(clearSeriesId: block.seriesId == null),
        )
        .toList(),
    templates: templates
        .map(
          (Template template) => Template(
            id: template.id,
            title: template.title,
            trackId: template.trackId,
            durationMinutes: template.durationMinutes,
            kind: template.kind,
            alarm: template.alarm,
            repeat: template.repeat,
          ),
        )
        .toList(),
    trackOpen: Map<String, bool>.from(trackOpen),
    showNames: showNames,
    locked: locked,
  );

  void recordUndoState(UndoState state, String label) {
    undoStack.add(UndoEntry(state: state, label: label));
    if (undoStack.length > maxUndo) undoStack.removeAt(0);
    notifyListeners();
  }

  void _pushUndo(String label) => recordUndoState(captureState(), label);

  String? undo() {
    if (undoStack.isEmpty) return null;
    final UndoEntry entry = undoStack.removeLast();
    final UndoState state = entry.state;
    tracks
      ..clear()
      ..addAll(state.tracks.map((Track track) => track.copyWith()));
    blocks
      ..clear()
      ..addAll(
        state.blocks.map(
          (Block block) =>
              block.copyWith(clearSeriesId: block.seriesId == null),
        ),
      );
    templates
      ..clear()
      ..addAll(
        state.templates.map(
          (Template template) => Template(
            id: template.id,
            title: template.title,
            trackId: template.trackId,
            durationMinutes: template.durationMinutes,
            kind: template.kind,
            alarm: template.alarm,
            repeat: template.repeat,
          ),
        ),
      );
    trackOpen
      ..clear()
      ..addAll(state.trackOpen);
    showNames = state.showNames;
    locked = state.locked;
    _nextBlockId = _maxBlockId() + 1;
    _nextTrackId = _nextAvailableTrackNumber();
    _nextTemplateId = _maxTemplateId() + 1;
    _ensureUncategorized();
    notifyListeners();
    _scheduleSave();
    return entry.label;
  }

  int _maxBlockId() => blocks.fold<int>(
    0,
    (int value, Block block) => math.max(value, block.id),
  );

  int _maxTemplateId() => templates.fold<int>(
    0,
    (int value, Template template) => math.max(value, template.id),
  );

  void toggleTrackOpen(String trackId) {
    trackOpen[trackId] = trackOpen[trackId] == false;
    notifyListeners();
    _scheduleSave();
  }

  void toggleCollapseAll() {
    final bool anyOpen = tracks.any(
      (Track track) => trackOpen[track.id] != false,
    );
    for (final Track track in tracks) {
      trackOpen[track.id] = !anyOpen;
    }
    notifyListeners();
    _scheduleSave();
  }

  void toggleShowNames() {
    showNames = !showNames;
    notifyListeners();
    _scheduleSave();
  }

  void toggleLock() {
    locked = !locked;
    notifyListeners();
    _scheduleSave();
  }

  Track addTrack({String? name, int? colorValue}) {
    _pushUndo('Added category');
    final int index = _nextTrackId++;
    final Track track = Track(
      id: 'cat-$index',
      name: name?.trim().isNotEmpty == true ? name!.trim() : 'New category',
      colorValue: colorValue ?? _palette[(index - 1) % _palette.length],
    );
    tracks.add(track);
    trackOpen[track.id] = true;
    notifyListeners();
    _scheduleSave();
    return track;
  }

  bool renameTrack(String trackId, String name) {
    final Track? track = trackById(trackId);
    if (track == null || track.fixed) return false;
    final String cleaned = name.trim();
    final String next = cleaned.isEmpty ? 'Untitled' : cleaned;
    if (next == track.name) return false;
    _pushUndo('Renamed category');
    final Track updated = track.copyWith(name: next);
    final int index = tracks.indexWhere((Track item) => item.id == trackId);
    if (index >= 0) tracks[index] = updated;
    notifyListeners();
    _scheduleSave();
    return true;
  }

  void setTrackColor(String trackId, int colorValue) {
    final Track? track = trackById(trackId);
    if (track == null || track.fixed || track.colorValue == colorValue) return;
    _pushUndo('Changed category colour');
    final int index = tracks.indexWhere((Track item) => item.id == trackId);
    if (index >= 0) {
      tracks[index] = track.copyWith(colorValue: colorValue);
      notifyListeners();
      _scheduleSave();
    }
  }

  void deleteTrack(String trackId) {
    final Track? track = trackById(trackId);
    if (track == null || track.fixed) return;
    _pushUndo('Deleted category');
    tracks.removeWhere((Track item) => item.id == trackId);
    trackOpen.remove(trackId);
    for (final Block block in blocks) {
      if (block.trackId == trackId) block.trackId = _uncatId;
    }
    _ensureUncategorized();
    notifyListeners();
    _scheduleSave();
  }

  Block? saveBlock(Block draft, {required bool isNew}) {
    final Block? existing = isNew ? null : blockById(draft.id);
    final Duration duration = draft.end.difference(draft.start);
    if (duration <= Duration.zero) return null;

    _pushUndo(isNew ? 'Added ${draft.title}' : 'Edited ${draft.title}');

    if (existing != null) {
      if (existing.seriesId != null) {
        blocks.removeWhere(
          (Block block) => block.seriesId == existing.seriesId,
        );
      } else {
        blocks.removeWhere((Block block) => block.id == existing.id);
      }
    }

    int primaryId = existing?.id ?? _nextBlockId++;
    if (isNew) {
      _nextBlockId = math.max(_nextBlockId, primaryId + 1);
    }
    draft.id = primaryId;

    if (draft.repeat == Recurrence.none) {
      draft.seriesId = null;
      final Block saved = draft.copyWith(
        id: primaryId,
        seriesId: null,
        clearSeriesId: true,
      );
      blocks.add(saved);
      _sortBlocks();
      _ensureUncategorized();
      notifyListeners();
      _scheduleSave();
      return saved;
    }

    final int? oldSeriesId = existing?.seriesId;
    final int seriesId = oldSeriesId ?? primaryId;
    draft.seriesId = seriesId;
    final List<Block> generated = _expandRecurringBlock(draft, seriesId);
    Block? primary;
    for (final Block block in generated) {
      blocks.add(block);
      if (block.start.isAtSameMomentAs(draft.start)) primary = block;
    }
    if (primary == null) {
      primary = draft.copyWith(seriesId: seriesId);
      blocks.add(primary);
    }
    _sortBlocks();
    _ensureUncategorized();
    notifyListeners();
    _scheduleSave();
    return primary;
  }

  List<Block> _expandRecurringBlock(Block draft, int seriesId) {
    final List<DateTime> starts = <DateTime>[];
    final DateTime base = draft.start;
    final Duration duration = draft.duration;
    final int stepDays = draft.repeat == Recurrence.weekly ? 7 : 1;
    final int span = draft.repeat == Recurrence.weekly ? 5 : 20;
    for (int offset = -span; offset <= span; offset++) {
      final DateTime candidate = addLocalDays(base, offset * stepDays);
      if (draft.repeat == Recurrence.weekdays &&
          (candidate.weekday == DateTime.saturday ||
              candidate.weekday == DateTime.sunday)) {
        continue;
      }
      final DateTime candidateEnd = candidate.add(duration);
      if (candidateEnd.isAfter(timelineStart) &&
          candidate.isBefore(timelineEnd)) {
        starts.add(candidate);
      }
    }
    if (!starts.any((DateTime start) => start.isAtSameMomentAs(base))) {
      starts.add(base);
    }
    starts.sort();
    final List<Block> result = <Block>[];
    for (final DateTime start in starts) {
      final bool isPrimary = start.isAtSameMomentAs(base);
      final int id = isPrimary ? draft.id : _nextBlockId++;
      result.add(
        draft.copyWith(
          id: id,
          start: start,
          end: start.add(duration),
          seriesId: seriesId,
          clearSeriesId: false,
        ),
      );
      _nextBlockId = math.max(_nextBlockId, id + 1);
    }
    return result;
  }

  void _sortBlocks() {
    blocks.sort((Block a, Block b) {
      final int byStart = a.start.compareTo(b.start);
      if (byStart != 0) return byStart;
      return a.id.compareTo(b.id);
    });
  }

  void moveBlockLive(
    int blockId,
    DateTime start,
    DateTime end, {
    bool resize = false,
  }) {
    final Block? block = blockById(blockId);
    if (block == null) return;
    final DateTime oldStart = block.start;
    final Duration newDuration = end.difference(start);
    if (newDuration <= Duration.zero) return;

    if (block.seriesId == null) {
      block.start = start;
      block.end = end;
    } else {
      final int deltaMs = start.difference(oldStart).inMilliseconds;
      final List<({Block block, Duration duration})> series = blocks
          .where((Block item) => item.seriesId == block.seriesId)
          .map((Block item) => (block: item, duration: item.duration))
          .toList(growable: false);
      for (final ({Block block, Duration duration}) item in series) {
        item.block.start = item.block.start.add(
          Duration(milliseconds: deltaMs),
        );
        item.block.end = item.block.start.add(
          resize ? newDuration : item.duration,
        );
      }
    }
    notifyListeners();
  }

  void finishLiveChange() {
    notifyListeners();
    _scheduleSave();
  }

  void deleteBlock(int blockId, {bool wholeSeries = false}) {
    final Block? block = blockById(blockId);
    if (block == null) return;
    _pushUndo('Deleted ${block.title}');
    if (wholeSeries && block.seriesId != null) {
      blocks.removeWhere((Block item) => item.seriesId == block.seriesId);
    } else {
      blocks.removeWhere((Block item) => item.id == blockId);
    }
    _ensureUncategorized();
    notifyListeners();
    _scheduleSave();
  }

  void addTemplateFromBlock(Block block) {
    final int duration = math.max(1, block.duration.inMinutes);
    final Template template = Template(
      id: _nextTemplateId++,
      title: block.title.trim().isEmpty ? 'Untitled' : block.title.trim(),
      trackId: block.trackId,
      durationMinutes: duration,
      kind: block.kind,
      alarm: block.alarm,
      repeat: block.repeat,
    );
    templates.add(template);
    notifyListeners();
    _scheduleSave();
  }

  void deleteTemplate(int id) {
    templates.removeWhere((Template template) => template.id == id);
    notifyListeners();
    _scheduleSave();
  }

  void addTemplate(Template template) {
    templates.add(
      Template(
        id: _nextTemplateId++,
        title: template.title,
        trackId: template.trackId,
        durationMinutes: template.durationMinutes,
        kind: template.kind,
        alarm: template.alarm,
        repeat: template.repeat,
      ),
    );
    notifyListeners();
    _scheduleSave();
  }

  Map<String, dynamic> toJsonMap() => <String, dynamic>{
    'format': 'timeline-sync-v1',
    'app': 'Timeline',
    'exportedAt': DateTime.now().toUtc().toIso8601String(),
    'tracks': tracks.map((Track track) => track.toJson()).toList(),
    'blocks': blocks.map((Block block) => block.toJson()).toList(),
    'templates': templates
        .map((Template template) => template.toJson())
        .toList(),
    'trackOpen': Map<String, bool>.from(trackOpen),
    'namesHidden': !showNames,
    'locked': locked,
  };

  String exportJsonString({bool pretty = true}) {
    if (pretty) {
      return const JsonEncoder.withIndent('  ').convert(toJsonMap());
    }
    return jsonEncode(toJsonMap());
  }

  ImportResult importJsonString(String raw) {
    final Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } catch (_) {
      throw const FormatException('That file is not valid JSON.');
    }
    if (decoded is! Map) {
      throw const FormatException('Not a Timeline sync file.');
    }
    final Map<String, dynamic> map = Map<String, dynamic>.from(decoded);
    final Object? rawTracks = map['tracks'];
    final Object? rawBlocks = map['blocks'];
    if (rawTracks is! List || rawBlocks is! List) {
      throw const FormatException('Not a Timeline sync file.');
    }

    final UndoState before = captureState();
    final List<Track> nextTracks = <Track>[];
    final Set<String> trackIds = <String>{};
    for (final Object? item in rawTracks) {
      if (item is! Map) continue;
      final Track track = Track.fromJson(Map<String, dynamic>.from(item));
      if (track.id.isEmpty || track.id == _uncatId || !trackIds.add(track.id)) {
        continue;
      }
      nextTracks.add(track);
    }

    final List<Block> nextBlocks = <Block>[];
    final Set<int> blockIds = <int>{};
    int nextBlockId = 1;
    for (final Object? item in rawBlocks) {
      if (item is! Map) continue;
      try {
        final Map<String, dynamic> json = Map<String, dynamic>.from(item);
        int id = (json['id'] is num)
            ? (json['id'] as num).toInt()
            : int.tryParse('${json['id'] ?? ''}') ?? 0;
        if (id <= 0 || blockIds.contains(id)) {
          while (blockIds.contains(nextBlockId)) {
            nextBlockId++;
          }
          id = nextBlockId;
        }
        blockIds.add(id);
        nextBlockId = math.max(nextBlockId, id + 1);
        final Block block = Block.fromJson(json, fallbackId: id);
        block.id = id;
        if (!trackIds.contains(block.trackId)) block.trackId = _uncatId;
        nextBlocks.add(block);
      } catch (_) {
        // Ignore individually invalid blocks.
      }
    }

    final List<Template> nextTemplates = <Template>[];
    int nextTemplateId = 1;
    final Object? rawTemplates = map['templates'];
    if (rawTemplates is List) {
      for (final Object? item in rawTemplates) {
        if (item is! Map) continue;
        try {
          final Map<String, dynamic> json = Map<String, dynamic>.from(item);
          int id = (json['id'] is num)
              ? (json['id'] as num).toInt()
              : int.tryParse('${json['id'] ?? ''}') ?? 0;
          if (id <= 0) id = nextTemplateId++;
          nextTemplateId = math.max(nextTemplateId, id + 1);
          nextTemplates.add(Template.fromJson(json, fallbackId: id));
        } catch (_) {}
      }
    }

    tracks
      ..clear()
      ..addAll(nextTracks);
    blocks
      ..clear()
      ..addAll(nextBlocks);
    templates
      ..clear()
      ..addAll(nextTemplates);
    _nextBlockId = nextBlockId;
    _nextTrackId = _nextAvailableTrackNumber();
    _nextTemplateId = math.max(nextTemplateId, _maxTemplateId() + 1);
    trackOpen.clear();
    final Object? rawOpen = map['trackOpen'];
    if (rawOpen is Map) {
      rawOpen.forEach((Object? key, Object? value) {
        if (key is String) trackOpen[key] = value != false;
      });
    }
    for (final Track track in tracks) {
      trackOpen.putIfAbsent(track.id, () => true);
    }
    if (map.containsKey('namesHidden')) showNames = map['namesHidden'] != true;
    if (map.containsKey('locked')) locked = map['locked'] == true;
    _ensureUncategorized();
    undoStack.add(UndoEntry(state: before, label: 'Imported sync file'));
    if (undoStack.length > maxUndo) undoStack.removeAt(0);
    notifyListeners();
    _scheduleSave();
    return ImportResult(tracks: tracks.length, blocks: blocks.length);
  }

  Future<void> flush() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    final SharedPreferences prefs =
        _prefs ?? await SharedPreferences.getInstance();
    _prefs = prefs;
    await prefs.setString(
      _storageKey,
      jsonEncode(<String, dynamic>{
        'tracks': tracks.map((Track track) => track.toJson()).toList(),
        'blocks': blocks.map((Block block) => block.toJson()).toList(),
        'templates': templates
            .map((Template template) => template.toJson())
            .toList(),
        'trackOpen': Map<String, bool>.from(trackOpen),
        'namesHidden': !showNames,
        'locked': locked,
      }),
    );
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), () {
      _saveTimer = null;
      unawaited(flush());
    });
  }

  void _seedSampleData() {
    tracks
      ..clear()
      ..addAll(<Track>[
        Track(id: 'food', name: 'Food', colorValue: 0xFFD9A05B),
        Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0),
        Track(id: 'personal', name: 'Personal', colorValue: 0xFF72C39A),
        Track(id: 'learning', name: 'Learning', colorValue: 0xFF5FC2C9),
        Track(id: 'health', name: 'Health', colorValue: 0xFFB489E6),
        Track(id: 'media', name: 'Media', colorValue: 0xFFE08AA0),
        Track(id: 'rest', name: 'Rest', colorValue: 0xFF6270C9),
      ]);
    blocks.clear();
    templates.clear();
    trackOpen.clear();
    for (final Track track in tracks) {
      trackOpen[track.id] = true;
    }
    _nextBlockId = 1;
    _nextTrackId = 1;

    final DateTime now = DateTime.now();
    final DateTime today = startOfLocalDay(now);

    for (int dayOffset = -5; dayOffset <= 4; dayOffset++) {
      final DateTime base = DateTime(
        today.year,
        today.month,
        today.day + dayOffset,
      );
      final int weekday = base.weekday;
      final _Rng rng = _Rng(9000 + dayOffset.abs() * 137 + 11);
      int jitter(int minutes) => ((rng.next() * 2 - 1) * minutes).round();

      DateTime local(double hour) {
        final int h = hour.floor();
        final int m = ((hour - h) * 60).round();
        return atLocalTime(base, h, m);
      }

      final DateTime breakfast = local(8).add(Duration(minutes: jitter(22)));
      final DateTime lunch = local(13).add(Duration(minutes: jitter(28)));
      final DateTime dinner = local(19.5).add(Duration(minutes: jitter(30)));

      _sampleBlock(
        'food',
        'Breakfast',
        breakfast,
        breakfast.add(const Duration(minutes: 25)),
      );
      _sampleBlock(
        'food',
        'Lunch',
        lunch,
        lunch.add(const Duration(minutes: 35)),
      );
      _sampleBlock(
        'food',
        'Dinner',
        dinner,
        dinner.add(const Duration(minutes: 45)),
      );
      _sampleBlock(
        'food',
        'Digestion',
        breakfast,
        breakfast.add(const Duration(hours: 12)),
        BlockKind.zone,
      );
      _sampleBlock(
        'food',
        'Digestion',
        lunch,
        lunch.add(const Duration(hours: 12)),
        BlockKind.zone,
      );
      _sampleBlock(
        'food',
        'Digestion',
        dinner,
        dinner.add(const Duration(hours: 12)),
        BlockKind.zone,
      );

      if (weekday >= DateTime.monday && weekday <= DateTime.friday) {
        _sampleBlock('work', 'Deep work', local(9.5), local(12.5));
        _sampleBlock('work', 'Admin', local(14), local(19));
      } else {
        _sampleBlock('work', 'Side project', local(11), local(13));
      }

      if (rng.next() > 0.3) {
        _sampleBlock('personal', 'Walk', local(18), local(18.75));
      }
      if (rng.next() > 0.55) {
        _sampleBlock('personal', 'Chores', local(17), local(17.5));
      }
      _sampleBlock('learning', 'Reading', local(20), local(20.75));
      if (rng.next() > 0.45) {
        _sampleBlock('health', 'Medication', local(21), local(21.08));
      }
      _sampleBlock('media', 'Wind down', local(21.5), local(22.5));
      _sampleBlock(
        'rest',
        'Sleep',
        local(23.5),
        local(23.5).add(const Duration(hours: 8)),
        BlockKind.zone,
      );
    }

    _sampleBlock(
      'health',
      'Dentist',
      atLocalTime(addLocalDays(today, 1), 11, 0),
      atLocalTime(addLocalDays(today, 1), 12, 0),
    );
    _sampleBlock(
      'personal',
      'Call family',
      atLocalTime(today, 18, 30),
      atLocalTime(today, 19, 0),
    );

    templates.addAll(<Template>[
      Template(
        id: _nextTemplateId++,
        title: 'Deep work',
        trackId: 'work',
        durationMinutes: 180,
      ),
      Template(
        id: _nextTemplateId++,
        title: 'Walk',
        trackId: 'personal',
        durationMinutes: 45,
      ),
      Template(
        id: _nextTemplateId++,
        title: 'Focus',
        trackId: 'learning',
        durationMinutes: 90,
      ),
    ]);
  }

  void _sampleBlock(
    String trackId,
    String title,
    DateTime start,
    DateTime end, [
    BlockKind kind = BlockKind.event,
  ]) {
    blocks.add(
      Block(
        id: _nextBlockId++,
        trackId: trackId,
        title: title,
        start: start,
        end: end,
        kind: kind,
      ),
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    super.dispose();
  }
}

class _Rng {
  _Rng(this._state);

  int _state;

  double next() {
    _state = (_state + 0x6D2B79F5) & 0x7FFFFFFF;
    int t = _state;
    t = (t ^ (t >> 15)) * (t | 1) & 0x7FFFFFFF;
    t ^= t + ((t ^ (t >> 7)) * (t | 61) & 0x7FFFFFFF);
    return ((t ^ (t >> 14)) & 0x7FFFFFFF) / 0x80000000;
  }
}
