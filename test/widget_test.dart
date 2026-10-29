import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeline/models.dart';
import 'package:timeline/sheets.dart';
import 'package:timeline/storage.dart';
import 'package:timeline/store.dart';
import 'package:timeline/theme.dart';
import 'package:timeline/timeline_canvas.dart';
import 'package:timeline/timeline_page.dart';

Future<TimelineStore> emptyStore() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'timeline_data_v1':
        '{"tracks":[],"blocks":[],"templates":[],"trackOpen":{}}',
  });
  final TimelineStore store = TimelineStore(
    storage: SharedPreferencesTimelineStorage(),
  );
  await store.load();
  return store;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('layout', () {
    final DateTime today = startOfLocalDay(DateTime.now());
    final Track track = Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0);

    test('keeps a block crossing midnight in one segment', () {
      final DateTime rangeStart = DateTime(
        today.year,
        today.month,
        today.day - 4,
      );
      final DateTime rangeEnd = DateTime(
        today.year,
        today.month,
        today.day + 4,
      );
      final Block block = Block(
        id: 1,
        trackId: track.id,
        title: 'Night shift',
        start: atLocalTime(today, 23, 0),
        end: atLocalTime(addLocalDays(today, 1), 1, 0),
      );
      final TimelineLayout layout = buildTimelineLayout(
        tracks: <Track>[track],
        blocks: <Block>[block],
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        viewStart: today,
        hours: 24,
        width: 720,
        trackOpen: <String, bool>{track.id: true},
      );
      expect(layout.segments, hasLength(1));
      final TimelineSegment segment = layout.segments.single;
      expect(segment.start, atLocalTime(today, 23, 0));
      expect(segment.end, atLocalTime(addLocalDays(today, 1), 1, 0));
      expect(segment.lane, 0);
    });

    test('overlapping blocks stay in the first lane', () {
      final DateTime rangeStart = DateTime(
        today.year,
        today.month,
        today.day - 4,
      );
      final DateTime rangeEnd = DateTime(
        today.year,
        today.month,
        today.day + 4,
      );
      final List<Block> blocks = <Block>[
        Block(
          id: 1,
          trackId: track.id,
          title: 'Evening',
          start: atLocalTime(today, 23, 0),
          end: atLocalTime(today, 23, 50),
        ),
        Block(
          id: 2,
          trackId: track.id,
          title: 'Overnight',
          start: atLocalTime(today, 23, 45),
          end: atLocalTime(addLocalDays(today, 1), 1, 0),
        ),
      ];
      final TimelineLayout layout = buildTimelineLayout(
        tracks: <Track>[track],
        blocks: blocks,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        viewStart: today,
        hours: 24,
        width: 720,
        trackOpen: <String, bool>{track.id: true},
      );
      final List<TimelineSegment> evening = layout.segments
          .where((TimelineSegment segment) => segment.block.id == 1)
          .toList();
      final List<TimelineSegment> overnight = layout.segments
          .where((TimelineSegment segment) => segment.block.id == 2)
          .toList();
      expect(evening, hasLength(1));
      expect(overnight, hasLength(1));
      expect(evening.single.lane, 0);
      expect(overnight.single.lane, 0);
      expect(layout.metrics[track.id]!.events, 1);
      expect(layout.metrics[track.id]!.height, 8 + 42);
    });

    test('rows are one lane tall unless a block has an explicit lane', () {
      final DateTime rangeStart = DateTime(
        today.year,
        today.month,
        today.day - 4,
      );
      final DateTime rangeEnd = DateTime(
        today.year,
        today.month,
        today.day + 4,
      );
      final List<Block> blocks = <Block>[
        Block(
          id: 1,
          trackId: track.id,
          title: 'A',
          start: atLocalTime(today, 9, 0),
          end: atLocalTime(today, 10, 0),
        ),
        Block(
          id: 2,
          trackId: track.id,
          title: 'B',
          start: atLocalTime(today, 9, 30),
          end: atLocalTime(today, 10, 30),
        ),
        Block(
          id: 3,
          trackId: track.id,
          title: 'C',
          start: atLocalTime(today, 11, 0),
          end: atLocalTime(today, 12, 0),
        ),
      ];
      final TimelineLayout layout = buildTimelineLayout(
        tracks: <Track>[track],
        blocks: blocks,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        viewStart: today,
        hours: 24,
        width: 720,
        trackOpen: <String, bool>{track.id: true},
      );
      final Map<int, int> lanes = <int, int>{
        for (final TimelineSegment segment in layout.segments)
          segment.block.id: segment.lane,
      };
      expect(lanes[1], 0);
      expect(lanes[2], 0);
      expect(lanes[3], 0);
      expect(layout.metrics[track.id]!.events, 1);
      expect(layout.metrics[track.id]!.height, 8 + 42);
    });

    test(
      'layout keeps raw lanes and zone-only rows skip empty event lanes',
      () {
        final Track rest = Track(
          id: 'rest',
          name: 'Rest',
          colorValue: 0xFF6270C9,
        );
        final List<Block> blocks = <Block>[
          Block(
            id: 1,
            trackId: track.id,
            title: 'A',
            start: atLocalTime(today, 9, 0),
            end: atLocalTime(today, 10, 0),
          ),
          Block(
            id: 2,
            trackId: track.id,
            title: 'B',
            start: atLocalTime(today, 11, 0),
            end: atLocalTime(today, 12, 0),
            lane: 1,
          ),
          Block(
            id: 3,
            trackId: rest.id,
            title: 'Sleep',
            start: atLocalTime(today, 23, 30),
            end: atLocalTime(addLocalDays(today, 1), 7, 30),
            kind: BlockKind.zone,
          ),
        ];
        final TimelineLayout layout = buildTimelineLayout(
          tracks: <Track>[track, rest],
          blocks: blocks,
          rangeStart: DateTime(today.year, today.month, today.day - 4),
          rangeEnd: DateTime(today.year, today.month, today.day + 4),
          viewStart: today,
          hours: 24,
          width: 720,
          trackOpen: <String, bool>{track.id: true, rest.id: true},
        );
        final Map<int, int> lanes = <int, int>{
          for (final TimelineSegment segment in layout.segments)
            segment.block.id: segment.lane,
        };
        // Layout never moves a block on its own: the drag must stay under the
        // pointer and the store normalizes empty leading lanes after the drop.
        expect(lanes[1], 0);
        expect(lanes[2], 1);
        expect(lanes[3], 0);

        final TrackMetrics work = layout.metrics[track.id]!;
        expect(work.events, 2);
        expect(work.zones, 0);
        expect(work.height, 8 + 2 * 42);

        // A category that only contains a zone must not reserve an event lane.
        final TrackMetrics sleep = layout.metrics[rest.id]!;
        expect(sleep.events, 0);
        expect(sleep.zones, 1);
        expect(sleep.height, 8 + 18 + 6);
      },
    );

    test('row height does not change while panning', () {
      final DateTime rangeStart = DateTime(
        today.year,
        today.month,
        today.day - 4,
      );
      final DateTime rangeEnd = DateTime(
        today.year,
        today.month,
        today.day + 4,
      );
      final List<Block> blocks = <Block>[
        Block(
          id: 1,
          trackId: track.id,
          title: 'A',
          start: atLocalTime(today, 9, 0),
          end: atLocalTime(today, 10, 0),
        ),
        Block(
          id: 2,
          trackId: track.id,
          title: 'Zone',
          start: atLocalTime(today, 8, 0),
          end: atLocalTime(today, 20, 0),
          kind: BlockKind.zone,
        ),
      ];
      final TimelineLayout first = buildTimelineLayout(
        tracks: <Track>[track],
        blocks: blocks,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        viewStart: today,
        hours: 6,
        width: 720,
        trackOpen: <String, bool>{track.id: true},
      );
      final TimelineLayout second = buildTimelineLayout(
        tracks: <Track>[track],
        blocks: blocks,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
        viewStart: addLocalDays(today, 2),
        hours: 72,
        width: 720,
        trackOpen: <String, bool>{track.id: true},
      );
      expect(first.metrics[track.id]!.height, second.metrics[track.id]!.height);
      expect(first.totalHeight, second.totalHeight);
    });
  });

  group('zoom', () {
    test('uses the actual range as a single final step', () {
      for (final double maxHours in <double>[191, 192, 193, 194]) {
        final List<double> presets = zoomPresetsFor(maxHours);
        expect(presets.last, maxHours);
        expect(
          presets.where((double value) => (value - maxHours).abs() < .001),
          hasLength(1),
        );
        expect(presets.toSet(), hasLength(presets.length));
      }
      expect(
        zoomPresetsFor(192),
        orderedEquals(<double>[1, 3, 6, 12, 24, 72, 192]),
      );
      expect(
        zoomPresetsFor(193),
        orderedEquals(<double>[1, 3, 6, 12, 24, 72, 193]),
      );
      expect(zoomPresetsFor(72), orderedEquals(<double>[1, 3, 6, 12, 24, 72]));
    });
  });

  group('store', () {
    test('untouched 1.1 sample data is regenerated once', () async {
      final DateTime today = startOfLocalDay(DateTime.now());
      SharedPreferences.setMockInitialValues(<String, Object>{
        'timeline_data_v1': jsonEncode(<String, dynamic>{
          'tracks': <Map<String, Object>>[
            <String, Object>{'id': 'food', 'name': 'Food', 'color': '#d9a05b'},
            <String, Object>{'id': 'work', 'name': 'Work', 'color': '#6f9df0'},
            <String, Object>{
              'id': 'personal',
              'name': 'Personal',
              'color': '#72c39a',
            },
            <String, Object>{
              'id': 'learning',
              'name': 'Learning',
              'color': '#5fc2c9',
            },
            <String, Object>{
              'id': 'health',
              'name': 'Health',
              'color': '#b489e6',
            },
            <String, Object>{
              'id': 'media',
              'name': 'Media',
              'color': '#e08aa0',
            },
            <String, Object>{'id': 'rest', 'name': 'Rest', 'color': '#6270c9'},
          ],
          'blocks': <Map<String, Object>>[
            <String, Object>{
              'id': 1,
              'track': 'food',
              'title': 'Breakfast',
              'start': atLocalTime(today, 8, 0).millisecondsSinceEpoch,
              'end': atLocalTime(today, 8, 30).millisecondsSinceEpoch,
            },
          ],
          'templates': <Object>[],
        }),
      });
      final TimelineStore store = TimelineStore(
        storage: SharedPreferencesTimelineStorage(),
      );
      addTearDown(store.dispose);
      await store.load();

      final List<Block> digestion =
          store.blocks
              .where((Block block) => block.title == 'Digestion')
              .toList()
            ..sort((Block a, Block b) => a.start.compareTo(b.start));
      // One digestion zone per sample day, not three overlapping ones.
      expect(digestion, hasLength(10));
      for (int i = 1; i < digestion.length; i++) {
        expect(
          digestion[i].start.isBefore(digestion[i - 1].end),
          isFalse,
          reason: 'sample digestion zones should not overlap',
        );
      }

      final Block call = store.blocks.singleWhere(
        (Block block) => block.title == 'Call family',
      );
      expect(call.start.hour, 19);
      expect(call.start.minute, 15);
    });

    test('releasing collapses only the empty top rows', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      final DateTime today = startOfLocalDay(DateTime.now());
      final Block top = Block(
        id: 1,
        trackId: 'work',
        title: 'Top',
        start: atLocalTime(today, 9, 0),
        end: atLocalTime(today, 10, 0),
      );
      final Block second = Block(
        id: 2,
        trackId: 'work',
        title: 'Second',
        start: atLocalTime(today, 11, 0),
        end: atLocalTime(today, 12, 0),
        lane: 1,
      );
      store.blocks.addAll(<Block>[top, second]);

      store.beginGroupMove(
        <int>{1},
        lanes: <int, int>{1: 0, 2: 1},
        allowVertical: true,
      );
      store.updateGroupMove(deltaMs: 0, laneDelta: 2);
      // While dragging, the block must stay exactly where the pointer put it.
      expect(top.lane, 2);
      expect(second.lane, 1);

      store.finishLiveChange();
      // The empty row above Second collapses; the spacing between the two
      // events is preserved.
      expect(second.lane, 0);
      expect(top.lane, 1);
    });

    test('a single block snaps back to the top boundary on release', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      final DateTime today = startOfLocalDay(DateTime.now());
      final Block only = Block(
        id: 1,
        trackId: 'work',
        title: 'Only',
        start: atLocalTime(today, 9, 0),
        end: atLocalTime(today, 10, 0),
      );
      store.blocks.add(only);

      store.beginGroupMove(
        <int>{1},
        lanes: <int, int>{1: 0},
        allowVertical: true,
      );
      store.updateGroupMove(deltaMs: 0, laneDelta: 3);
      expect(only.lane, 3);
      store.finishLiveChange();
      // An empty top boundary is removed, so a lone block returns to lane 0.
      expect(only.lane, 0);
    });

    test('multi-selection collapses only the empty boundary rows', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      final DateTime today = startOfLocalDay(DateTime.now());
      final Block first = Block(
        id: 1,
        trackId: 'work',
        title: 'First',
        start: atLocalTime(today, 9, 0),
        end: atLocalTime(today, 10, 0),
      );
      final Block second = Block(
        id: 2,
        trackId: 'work',
        title: 'Second',
        start: atLocalTime(today, 11, 0),
        end: atLocalTime(today, 12, 0),
        lane: 1,
      );
      store.blocks.addAll(<Block>[first, second]);

      store.beginGroupMove(
        <int>{1, 2},
        lanes: <int, int>{1: 0, 2: 1},
        allowVertical: true,
      );
      store.updateGroupMove(deltaMs: 0, laneDelta: 3);
      expect(first.lane, 3);
      expect(second.lane, 4);

      store.finishLiveChange();
      // The group keeps its one-row spacing, but the empty rows above it go.
      expect(first.lane, 0);
      expect(second.lane, 1);
    });

    test(
      'horizontal overlap bumps above or below the blocking event',
      () async {
        Future<TimelineStore> setup() async {
          final TimelineStore store = await emptyStore();
          store.tracks.add(
            Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0),
          );
          final DateTime today = startOfLocalDay(DateTime.now());
          store.blocks.addAll(<Block>[
            Block(
              id: 1,
              trackId: 'work',
              title: 'Moved',
              start: atLocalTime(today, 9, 0),
              end: atLocalTime(today, 10, 0),
              lane: 1,
            ),
            Block(
              id: 2,
              trackId: 'work',
              title: 'Blocker',
              start: atLocalTime(today, 11, 0),
              end: atLocalTime(today, 12, 0),
              lane: 1,
            ),
          ]);
          store.beginGroupMove(
            <int>{1},
            lanes: <int, int>{1: 1, 2: 1},
            allowVertical: true,
          );
          return store;
        }

        final TimelineStore above = await setup();
        addTearDown(above.dispose);
        above.updateGroupMove(
          deltaMs: 2 * 60 * 60 * 1000,
          laneDelta: 0,
          preferAbove: true,
        );
        expect(above.blocks.firstWhere((Block b) => b.id == 1).lane, 0);
        above.finishLiveChange();
        expect(above.blocks.firstWhere((Block b) => b.id == 1).lane, 0);
        expect(above.blocks.firstWhere((Block b) => b.id == 2).lane, 1);

        final TimelineStore below = await setup();
        addTearDown(below.dispose);
        below.updateGroupMove(
          deltaMs: 2 * 60 * 60 * 1000,
          laneDelta: 0,
          preferAbove: false,
        );
        expect(below.blocks.firstWhere((Block b) => b.id == 1).lane, 2);
        // Moving away from the blocker restores the original lane.
        below.updateGroupMove(deltaMs: 0, laneDelta: 0, preferAbove: false);
        expect(below.blocks.firstWhere((Block b) => b.id == 1).lane, 1);
        below.updateGroupMove(
          deltaMs: 2 * 60 * 60 * 1000,
          laneDelta: 0,
          preferAbove: false,
        );
        expect(below.blocks.firstWhere((Block b) => b.id == 1).lane, 2);
        below.finishLiveChange();
        // The empty top boundary collapses; Moved stays below Blocker.
        expect(below.blocks.firstWhere((Block b) => b.id == 1).lane, 1);
        expect(below.blocks.firstWhere((Block b) => b.id == 2).lane, 0);
      },
    );

    test('vertical drag moves a selection from multiple categories', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      store.tracks.add(
        Track(id: 'personal', name: 'Personal', colorValue: 0xFF72C39A),
      );
      final DateTime today = startOfLocalDay(DateTime.now());
      final Block work = Block(
        id: 1,
        trackId: 'work',
        title: 'Work',
        start: atLocalTime(today, 9, 0),
        end: atLocalTime(today, 10, 0),
      );
      final Block personal = Block(
        id: 2,
        trackId: 'personal',
        title: 'Personal',
        start: atLocalTime(today, 9, 0),
        end: atLocalTime(today, 10, 0),
      );
      store.blocks.addAll(<Block>[work, personal]);

      store.beginGroupMove(
        <int>{1, 2},
        lanes: <int, int>{1: 0, 2: 0},
        allowVertical: true,
      );
      store.updateGroupMove(deltaMs: 0, laneDelta: 2);
      expect(work.lane, 2);
      expect(personal.lane, 2);
      store.finishLiveChange();
      // Each category collapses its own empty top boundary.
      expect(work.lane, 0);
      expect(personal.lane, 0);
    });

    test(
      'multi-selection keeps relative rows when clamped at the top',
      () async {
        final TimelineStore store = await emptyStore();
        addTearDown(store.dispose);
        store.tracks.add(
          Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0),
        );
        final DateTime today = startOfLocalDay(DateTime.now());
        final Block first = Block(
          id: 1,
          trackId: 'work',
          title: 'First',
          start: atLocalTime(today, 9, 0),
          end: atLocalTime(today, 10, 0),
          lane: 2,
        );
        final Block second = Block(
          id: 2,
          trackId: 'work',
          title: 'Second',
          start: atLocalTime(today, 9, 0),
          end: atLocalTime(today, 10, 0),
          lane: 3,
        );
        store.blocks.addAll(<Block>[first, second]);

        store.beginGroupMove(
          <int>{1, 2},
          lanes: <int, int>{1: 2, 2: 3},
          allowVertical: true,
        );
        store.updateGroupMove(deltaMs: 0, laneDelta: -5);
        // Both hit the top together but keep one row between them.
        expect(first.lane, 0);
        expect(second.lane, 1);
        store.finishLiveChange();
        expect(first.lane, 0);
        expect(second.lane, 1);
      },
    );

    test('dragging above the top event pushes the stack down', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      final DateTime today = startOfLocalDay(DateTime.now());
      final Block top = Block(
        id: 1,
        trackId: 'work',
        title: 'Top',
        start: atLocalTime(today, 9, 0),
        end: atLocalTime(today, 10, 0),
      );
      final Block lower = Block(
        id: 2,
        trackId: 'work',
        title: 'Lower',
        start: atLocalTime(today, 9, 0),
        end: atLocalTime(today, 10, 0),
        lane: 1,
      );
      store.blocks.addAll(<Block>[top, lower]);

      store.beginGroupMove(
        <int>{2},
        lanes: <int, int>{1: 0, 2: 1},
        allowVertical: true,
      );
      store.updateGroupMove(deltaMs: 0, laneDelta: -1, preferAbove: true);
      expect(lower.lane, 0);
      expect(top.lane, 1);
      store.finishLiveChange();
      expect(lower.lane, 0);
      expect(top.lane, 1);
    });

    test('dragging far above the top inserts without skipping rows', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      final DateTime today = startOfLocalDay(DateTime.now());
      final Block top = Block(
        id: 1,
        trackId: 'work',
        title: 'Top',
        start: atLocalTime(today, 9, 0),
        end: atLocalTime(today, 10, 0),
      );
      final Block lower = Block(
        id: 2,
        trackId: 'work',
        title: 'Lower',
        start: atLocalTime(today, 9, 0),
        end: atLocalTime(today, 10, 0),
        lane: 1,
      );
      store.blocks.addAll(<Block>[top, lower]);

      store.beginGroupMove(
        <int>{2},
        lanes: <int, int>{1: 0, 2: 1},
        allowVertical: true,
      );
      // Three lanes of upward drag: the top event is pushed far enough down to
      // leave the requested separation above it.
      store.updateGroupMove(deltaMs: 0, laneDelta: -3, preferAbove: true);
      expect(lower.lane, 0);
      expect(top.lane, 3);
      store.finishLiveChange();
      expect(lower.lane, 0);
      expect(top.lane, 3);
    });

    test(
      'dragging up into the top row inserts above a non-overlapping event',
      () async {
        final TimelineStore store = await emptyStore();
        addTearDown(store.dispose);
        store.tracks.add(
          Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0),
        );
        final DateTime today = startOfLocalDay(DateTime.now());
        final Block top = Block(
          id: 1,
          trackId: 'work',
          title: 'Top',
          start: atLocalTime(today, 9, 0),
          end: atLocalTime(today, 10, 0),
          lane: 0,
        );
        final Block lower = Block(
          id: 2,
          trackId: 'work',
          title: 'Lower',
          start: atLocalTime(today, 15, 0),
          end: atLocalTime(today, 16, 0),
          lane: 1,
        );
        store.blocks.addAll(<Block>[top, lower]);

        store.beginGroupMove(
          <int>{2},
          lanes: <int, int>{1: 0, 2: 1},
          allowVertical: true,
        );
        store.updateGroupMove(deltaMs: 0, laneDelta: -1, preferAbove: true);
        // Upward dragging at the top inserts above the existing first row even
        // when the clock times do not overlap.
        expect(lower.lane, 0);
        expect(top.lane, 1);
        store.finishLiveChange();
        expect(lower.lane, 0);
        expect(top.lane, 1);
      },
    );

    test('non-overlapping events on another day do not skip rows', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      final DateTime today = startOfLocalDay(DateTime.now());
      final Block visibleTop = Block(
        id: 1,
        trackId: 'work',
        title: 'Visible top',
        start: atLocalTime(today, 9, 0),
        end: atLocalTime(today, 10, 0),
      );
      final Block dragged = Block(
        id: 2,
        trackId: 'work',
        title: 'Dragged',
        start: atLocalTime(today, 11, 0),
        end: atLocalTime(today, 12, 0),
        lane: 1,
      );
      final Block offScreen = Block(
        id: 3,
        trackId: 'work',
        title: 'Next day',
        start: atLocalTime(addLocalDays(today, 1), 9, 0),
        end: atLocalTime(addLocalDays(today, 1), 10, 0),
        lane: 2,
      );
      store.blocks.addAll(<Block>[visibleTop, dragged, offScreen]);

      store.beginGroupMove(
        <int>{2},
        lanes: <int, int>{1: 0, 2: 1, 3: 2},
        allowVertical: true,
      );
      store.updateGroupMove(deltaMs: 0, laneDelta: 1);
      // The block on another day does not overlap in time, so it does not
      // bump the drag or make it skip a row.
      expect(dragged.lane, 2);
      expect(offScreen.lane, 2);
      store.finishLiveChange();
      expect(dragged.lane, 2);
    });

    test('boundary collapse keeps gaps between events', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      final DateTime today = startOfLocalDay(DateTime.now());
      store.blocks.addAll(<Block>[
        Block(
          id: 1,
          trackId: 'work',
          title: 'A',
          start: atLocalTime(today, 9, 0),
          end: atLocalTime(today, 10, 0),
          lane: 2,
        ),
        Block(
          id: 2,
          trackId: 'work',
          title: 'B',
          start: atLocalTime(today, 11, 0),
          end: atLocalTime(today, 12, 0),
          lane: 4,
        ),
      ]);
      store.normalizeLanes();
      expect(store.blocks.firstWhere((Block b) => b.id == 1).lane, 0);
      // The internal one-row gap is user positioning and stays intact.
      expect(store.blocks.firstWhere((Block b) => b.id == 2).lane, 2);
    });

    test(
      'pushing down moves every block in the category, not just visible ones',
      () async {
        final TimelineStore store = await emptyStore();
        addTearDown(store.dispose);
        store.tracks.add(
          Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0),
        );
        final DateTime today = startOfLocalDay(DateTime.now());
        final Block visibleTop = Block(
          id: 1,
          trackId: 'work',
          title: 'Today',
          start: atLocalTime(today, 9, 0),
          end: atLocalTime(today, 10, 0),
        );
        final Block dragged = Block(
          id: 2,
          trackId: 'work',
          title: 'Dragged',
          start: atLocalTime(today, 9, 0),
          end: atLocalTime(today, 10, 0),
          lane: 1,
        );
        final Block nextDay = Block(
          id: 3,
          trackId: 'work',
          title: 'Tomorrow',
          start: atLocalTime(addLocalDays(today, 1), 9, 0),
          end: atLocalTime(addLocalDays(today, 1), 10, 0),
        );
        store.blocks.addAll(<Block>[visibleTop, dragged, nextDay]);

        store.beginGroupMove(
          <int>{2},
          lanes: <int, int>{1: 0, 2: 1, 3: 0},
          allowVertical: true,
        );
        store.updateGroupMove(deltaMs: 0, laneDelta: -1, preferAbove: true);
        // The whole row stack moves down, so zooming out shows a consistent
        // layout instead of only the visible blocks having shifted.
        expect(dragged.lane, 0);
        expect(visibleTop.lane, 1);
        expect(nextDay.lane, 1);
        store.finishLiveChange();
        expect(dragged.lane, 0);
        expect(visibleTop.lane, 1);
        expect(nextDay.lane, 1);
      },
    );

    test('horizontal overlap at the top pushes the blocker down', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      final DateTime today = startOfLocalDay(DateTime.now());
      final Block top = Block(
        id: 1,
        trackId: 'work',
        title: 'Top',
        start: atLocalTime(today, 9, 0),
        end: atLocalTime(today, 10, 0),
      );
      final Block mover = Block(
        id: 2,
        trackId: 'work',
        title: 'Mover',
        start: atLocalTime(today, 11, 0),
        end: atLocalTime(today, 12, 0),
      );
      store.blocks.addAll(<Block>[top, mover]);

      store.beginGroupMove(
        <int>{2},
        lanes: <int, int>{1: 0, 2: 0},
        allowVertical: true,
      );
      store.updateGroupMove(
        deltaMs: -2 * 60 * 60 * 1000,
        laneDelta: 0,
        preferAbove: true,
      );
      expect(mover.lane, 0);
      expect(top.lane, 1);
      store.finishLiveChange();
      expect(mover.lane, 0);
      expect(top.lane, 1);
    });

    test(
      'recurrence is materialized and edits keep series semantics',
      () async {
        final TimelineStore store = await emptyStore();
        addTearDown(store.dispose);
        store.tracks.add(
          Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0),
        );
        final DateTime today = startOfLocalDay(DateTime.now());
        final Block primary = store.saveBlock(
          Block(
            id: 0,
            trackId: 'work',
            title: 'Standup',
            start: atLocalTime(today, 10, 0),
            end: atLocalTime(today, 10, 30),
            repeat: RepeatSpec.daily(),
          ),
          isNew: true,
        )!;
        expect(primary.seriesId, isNotNull);
        final int count = store.blocks.length;
        expect(count, greaterThan(1));
        expect(
          store.blocks.every(
            (Block block) => block.seriesId == primary.seriesId,
          ),
          isTrue,
        );

        primary.title = 'Standup edited';
        final Block? saved = store.saveBlock(primary, isNew: false);
        expect(saved, isNotNull);
        expect(store.blocks.length, count);
        expect(
          store.blocks.every((Block block) => block.title == 'Standup edited'),
          isTrue,
        );
      },
    );

    test('daily repeat keeps only the ticked weekdays', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      final DateTime today = startOfLocalDay(DateTime.now());
      final Block primary = store.saveBlock(
        Block(
          id: 0,
          trackId: 'work',
          title: 'Tuesday standup',
          start: atLocalTime(today, 10, 0),
          end: atLocalTime(today, 10, 30),
          repeat: const RepeatSpec(
            mode: RepeatCadence.daily,
            days: <int>{DateTime.tuesday, DateTime.thursday},
          ),
        ),
        isNew: true,
      )!;
      expect(primary.seriesId, isNotNull);
      expect(store.blocks.length, greaterThanOrEqualTo(2));
      for (final Block block in store.blocks) {
        if (block.id == primary.id) continue;
        expect(<int>{
          DateTime.tuesday,
          DateTime.thursday,
        }, contains(block.start.weekday));
      }
    });

    test('hourly repeat uses the ticked hours', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      final DateTime today = startOfLocalDay(DateTime.now());
      final Block primary = store.saveBlock(
        Block(
          id: 0,
          trackId: 'work',
          title: 'Hydrate',
          start: atLocalTime(today, 10, 0),
          end: atLocalTime(today, 10, 10),
          repeat: const RepeatSpec.hourly(<int>{8, 20}),
        ),
        isNew: true,
      )!;
      expect(primary.seriesId, isNotNull);
      final Set<int> hours = store.blocks
          .map((Block block) => block.start.hour)
          .toSet();
      expect(hours, <int>{8, 10, 20});
      expect(
        store.blocks.every((Block block) => block.start.minute == 0),
        isTrue,
      );
    });

    test('legacy repeat strings migrate to day selections', () {
      expect(RepeatSpec.parse('weekdays').days, RepeatSpec.weekdays);
      final DateTime monday = DateTime(2026, 10, 26);
      expect(
        RepeatSpec.parse('weekly', anchor: monday),
        const RepeatSpec(
          mode: RepeatCadence.daily,
          days: <int>{DateTime.monday},
        ),
      );
      expect(RepeatSpec.parse('daily'), const RepeatSpec.daily());
      expect(RepeatSpec.parse(null), RepeatSpec.none);

      final Block decoded = Block.fromJson(<String, dynamic>{
        'id': 1,
        'track': 'work',
        'title': 'Old',
        'start': DateTime(2026, 10, 26, 10).millisecondsSinceEpoch,
        'end': DateTime(2026, 10, 26, 11).millisecondsSinceEpoch,
        'alarm': true,
        'repeat': 'weekdays',
      }, fallbackId: 1);
      expect(decoded.repeat.days, RepeatSpec.weekdays);
      expect(decoded.alarms, <AlarmOffset>{AlarmOffset.start});
    });

    test('combine spans the selection and undo restores every block', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      final DateTime today = startOfLocalDay(DateTime.now());
      store.blocks.addAll(<Block>[
        Block(
          id: 1,
          trackId: 'work',
          title: 'First',
          start: atLocalTime(today, 9, 0),
          end: atLocalTime(today, 10, 0),
        ),
        Block(
          id: 2,
          trackId: 'work',
          title: 'Second',
          start: atLocalTime(today, 11, 0),
          end: atLocalTime(today, 12, 0),
        ),
        Block(
          id: 3,
          trackId: 'work',
          title: 'Third',
          start: atLocalTime(today, 13, 0),
          end: atLocalTime(today, 14, 0),
        ),
      ]);

      final Block combined = store.combineBlocks(<int>{1, 3})!;
      expect(combined.title, 'First');
      expect(combined.start, atLocalTime(today, 9, 0));
      expect(combined.end, atLocalTime(today, 14, 0));
      expect(store.blocks, hasLength(2));
      expect(store.undo(), contains('Combined'));
      expect(store.blocks, hasLength(3));

      final Block joined = store.combineBlocks(<int>{1, 2}, joinTitles: true)!;
      expect(joined.title, 'First + Second');
      expect(joined.duration, const Duration(hours: 3));
    });

    test('alarm offsets point at the start, middle and end', () {
      final Block block = Block(
        id: 1,
        trackId: 'work',
        title: 'Long',
        start: DateTime(2026, 10, 28, 10),
        end: DateTime(2026, 10, 28, 12),
      );
      expect(AlarmOffset.start.timeFor(block), DateTime(2026, 10, 28, 10));
      expect(AlarmOffset.middle.timeFor(block), DateTime(2026, 10, 28, 11));
      expect(AlarmOffset.end.timeFor(block), DateTime(2026, 10, 28, 12));

      final DateTime now = DateTime(2026, 10, 28, 9, 30);
      expect(blockTiming(block, now), '2h · in 30m');
      expect(blockTiming(block, DateTime(2026, 10, 28, 13)), '2h');
    });

    test('moving a recurring block moves the whole series', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      final DateTime today = startOfLocalDay(DateTime.now());
      final Block primary = store.saveBlock(
        Block(
          id: 0,
          trackId: 'work',
          title: 'Standup',
          start: atLocalTime(today, 10, 0),
          end: atLocalTime(today, 10, 30),
          repeat: RepeatSpec.daily(),
        ),
        isNew: true,
      )!;
      final List<DateTime> starts = store.blocks
          .map((Block block) => block.start)
          .toList(growable: false);
      store.moveBlockLive(
        primary.id,
        primary.start.add(const Duration(hours: 2)),
        primary.end.add(const Duration(hours: 2)),
      );
      expect(store.blocks.length, starts.length);
      for (int i = 0; i < starts.length; i++) {
        expect(store.blocks[i].start, starts[i].add(const Duration(hours: 2)));
        expect(store.blocks[i].duration, const Duration(minutes: 30));
      }
    });

    test('save and undo round trip', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      final DateTime today = startOfLocalDay(DateTime.now());
      store.saveBlock(
        Block(
          id: 0,
          trackId: 'work',
          title: 'Temporary',
          start: atLocalTime(today, 14, 0),
          end: atLocalTime(today, 15, 0),
        ),
        isNew: true,
      );
      expect(store.blocks.length, 1);
      expect(store.hasUndo, isTrue);
      final String? label = store.undo();
      expect(label, contains('Temporary'));
      expect(store.blocks, isEmpty);
    });

    test('explicit lanes survive layout and JSON round trips', () {
      final Block block = Block(
        id: 7,
        trackId: 'work',
        title: 'Pinned',
        start: DateTime(2026, 10, 23, 9),
        end: DateTime(2026, 10, 23, 10),
        lane: 3,
      );
      expect(block.toJson()['lane'], 3);
      expect(Block.fromJson(block.toJson(), fallbackId: 99).lane, 3);

      final DateTime today = startOfLocalDay(DateTime.now());
      final Track work = Track(
        id: 'work',
        name: 'Work',
        colorValue: 0xFF6F9DF0,
      );
      final TimelineLayout layout = buildTimelineLayout(
        tracks: <Track>[work],
        blocks: <Block>[
          block.copyWith(
            start: atLocalTime(today, 9, 0),
            end: atLocalTime(today, 10, 0),
          ),
          Block(
            id: 8,
            trackId: 'work',
            title: 'Packed',
            start: atLocalTime(today, 9, 30),
            end: atLocalTime(today, 10, 30),
          ),
        ],
        rangeStart: DateTime(today.year, today.month, today.day - 1),
        rangeEnd: DateTime(today.year, today.month, today.day + 1),
        viewStart: today,
        hours: 24,
        width: 720,
        trackOpen: <String, bool>{'work': true},
      );
      final Map<int, int> lanes = <int, int>{
        for (final TimelineSegment segment in layout.segments)
          segment.block.id: segment.lane,
      };
      expect(lanes[7], 3);
      expect(lanes[8], 0);
    });

    test('category order keeps Uncategorized draggable when empty', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'a', name: 'A', colorValue: 0xFFD9A05B));
      store.tracks.add(Track(id: 'b', name: 'B', colorValue: 0xFF6F9DF0));
      final DateTime today = startOfLocalDay(DateTime.now());
      store.saveBlock(
        Block(
          id: 0,
          trackId: 'uncat',
          title: 'Loose',
          start: atLocalTime(today, 9, 0),
          end: atLocalTime(today, 10, 0),
        ),
        isNew: true,
      );
      List<String> ids() =>
          store.displayTracks.map((Track track) => track.id).toList();
      expect(ids(), <String>['a', 'b', 'uncat']);

      store.reorderCategory('uncat', 0);
      expect(ids(), <String>['uncat', 'a', 'b']);
      expect(store.tracks.map((Track track) => track.id), <String>[
        'uncat',
        'a',
        'b',
      ]);

      store.clearTrack('uncat');
      expect(store.blocks, isEmpty);
      expect(ids(), <String>['uncat', 'a', 'b']);
      expect(store.tracks.map((Track track) => track.id), <String>['a', 'b']);

      expect(store.undo(), contains('Uncategorized'));
      expect(store.blocks, hasLength(1));
      expect(ids(), <String>['uncat', 'a', 'b']);

      store.reorderCategory('uncat', 2);
      expect(ids(), <String>['a', 'b', 'uncat']);
    });

    test('group vertical movement is rigid and avoids fixed blocks', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      final DateTime today = startOfLocalDay(DateTime.now());
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      final Block first = Block(
        id: 1,
        trackId: 'work',
        title: 'First',
        start: atLocalTime(today, 9, 0),
        end: atLocalTime(today, 10, 0),
        lane: 0,
      );
      final Block second = Block(
        id: 2,
        trackId: 'work',
        title: 'Second',
        start: atLocalTime(today, 10, 0),
        end: atLocalTime(today, 11, 0),
        lane: 1,
      );
      final Block fixed = Block(
        id: 3,
        trackId: 'work',
        title: 'Fixed',
        start: atLocalTime(today, 10, 30),
        end: atLocalTime(today, 11, 30),
        lane: 1,
      );
      store.blocks.addAll(<Block>[first, second, fixed]);
      const int hour = 60 * 60 * 1000;
      store.beginGroupMove(
        <int>{1, 2},
        lanes: <int, int>{1: 0, 2: 1, 3: 1},
        allowVertical: true,
      );
      store.updateGroupMove(deltaMs: hour, laneDelta: 1);
      // Both blocks shift by one hour. Their requested lanes are 1 and 2;
      // lane 1 is occupied by the fixed 10:30 block after the shift, so the
      // whole group moves down together to lanes 2 and 3.
      expect(first.start, atLocalTime(today, 10, 0));
      expect(second.start, atLocalTime(today, 11, 0));
      expect(first.lane, 2);
      expect(second.lane, 3);
      expect(fixed.lane, 1);
      store.finishLiveChange();
    });

    test('batch edit updates fields and one undo restores all', () async {
      final TimelineStore store = await emptyStore();
      addTearDown(store.dispose);
      store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
      store.tracks.add(
        Track(id: 'personal', name: 'Personal', colorValue: 0xFF72C39A),
      );
      final DateTime today = startOfLocalDay(DateTime.now());
      store.blocks.addAll(<Block>[
        Block(
          id: 1,
          trackId: 'work',
          title: 'One',
          start: atLocalTime(today, 9, 0),
          end: atLocalTime(today, 10, 0),
          lane: 2,
        ),
        Block(
          id: 2,
          trackId: 'work',
          title: 'Two',
          start: atLocalTime(today, 11, 0),
          end: atLocalTime(today, 12, 0),
          lane: 3,
        ),
      ]);
      store.batchEditBlocks(
        <int>{1, 2},
        trackId: 'personal',
        title: 'Renamed',
        kind: BlockKind.zone,
        alarms: <AlarmOffset>{AlarmOffset.start},
        durationDeltaMinutes: 30,
      );
      for (final Block block in store.blocks) {
        expect(block.trackId, 'personal');
        expect(block.title, 'Renamed');
        expect(block.kind, BlockKind.zone);
        expect(block.alarm, isTrue);
        expect(block.duration, const Duration(minutes: 90));
        expect(block.lane, isNull);
      }
      expect(store.undo(), 'Edited 2 blocks');
      expect(store.blocks, hasLength(2));
      expect(
        store.blocks.every((Block block) => block.trackId == 'work'),
        isTrue,
      );
      expect(
        store.blocks.every(
          (Block block) => block.duration == const Duration(hours: 1),
        ),
        isTrue,
      );
      expect(
        store.blocks.map((Block block) => block.title),
        unorderedEquals(<String>['One', 'Two']),
      );
    });

    test(
      'multi-block templates keep relative offsets and can be added',
      () async {
        final TimelineStore store = await emptyStore();
        addTearDown(store.dispose);
        store.tracks.add(
          Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0),
        );
        final DateTime today = startOfLocalDay(DateTime.now());
        store.addTemplateFromBlocks(<Block>[
          Block(
            id: 1,
            trackId: 'work',
            title: 'First',
            start: atLocalTime(today, 9, 0),
            end: atLocalTime(today, 10, 0),
          ),
          Block(
            id: 2,
            trackId: 'work',
            title: 'Second',
            start: atLocalTime(today, 9, 45),
            end: atLocalTime(today, 10, 15),
          ),
        ]);
        final Template template = store.templates.single;
        expect(template.isMulti, isTrue);
        expect(template.blockCount, 2);
        expect(
          template.parts.map((TemplatePart part) => part.offsetMinutes),
          <int>[0, 45],
        );
        final Template decoded = Template.fromJson(
          template.toJson(),
          fallbackId: 99,
        );
        expect(decoded.isMulti, isTrue);
        expect(decoded.parts, hasLength(2));

        final List<Block> added = store.addBlocksFromTemplate(
          template,
          atLocalTime(today, 13, 0),
        );
        expect(added, hasLength(2));
        expect(added[0].start, atLocalTime(today, 13, 0));
        expect(added[1].start, atLocalTime(today, 13, 45));
        expect(added[1].duration, const Duration(minutes: 30));
      },
    );
  });

  testWidgets('categories and batch editor sheets build without errors', (
    tester,
  ) async {
    final TimelineStore store = await emptyStore();
    addTearDown(store.dispose);
    store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
    final DateTime today = startOfLocalDay(DateTime.now());
    store.blocks.addAll(<Block>[
      Block(
        id: 1,
        trackId: 'work',
        title: 'One',
        start: atLocalTime(today, 9, 0),
        end: atLocalTime(today, 10, 0),
      ),
      Block(
        id: 2,
        trackId: 'work',
        title: 'Two',
        start: atLocalTime(today, 11, 0),
        end: atLocalTime(today, 12, 0),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTimelineTheme(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ElevatedButton(
                    onPressed: () => showCategoriesSheet(context, store),
                    child: const Text('Open categories'),
                  ),
                  ElevatedButton(
                    onPressed: () =>
                        showBatchEditor(context, store, store.blocks),
                    child: const Text('Open batch'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open categories'));
    await tester.pumpAndSettle();
    expect(find.text('Your tracks'), findsOneWidget);
    expect(find.text('Uncategorized'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open batch'));
    await tester.pumpAndSettle();
    expect(find.text('2 blocks selected'), findsOneWidget);
    await tester.tap(find.text('Duration'));
    await tester.pumpAndSettle();
    expect(find.text('-1h'), findsOneWidget);
    expect(find.text('+1h'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('blocks only move after a tap selects them', (tester) async {
    final TimelineStore store = await emptyStore();
    addTearDown(store.dispose);
    store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
    final DateTime today = startOfLocalDay(DateTime.now());
    final Block block = Block(
      id: 1,
      trackId: 'work',
      title: 'Focus',
      start: atLocalTime(today, 10, 0),
      end: atLocalTime(today, 11, 0),
    );
    store.blocks.add(block);
    final TimelineLayout layout = buildTimelineLayout(
      tracks: store.tracks,
      blocks: store.blocks,
      rangeStart: today,
      rangeEnd: addLocalDays(today, 1),
      viewStart: atLocalTime(today, 9, 0),
      hours: 4,
      width: 800,
      trackOpen: <String, bool>{'work': true},
    );

    int? selected;
    DateTime? viewportStart;
    Set<int> selection = <int>{};
    final ScrollController controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => MaterialApp(
          theme: buildTimelineTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: TimelineCanvas(
                layout: layout,
                contentHeight: 400,
                store: store,
                selectedIds: selection,
                primarySelectedId: selection.length == 1
                    ? selection.first
                    : null,
                selectionMode: false,
                now: DateTime.now(),
                showNames: true,
                scrollController: controller,
                onSelect: (int id, {required bool toggle}) {
                  selected = id;
                  setState(() => selection = <int>{id});
                },
                onClearSelection: () {},
                onMarqueeSelect: (Set<int> ids, {required bool additive}) {},
                onLongPressSelect: (int id) {},
                onEdit: (Block value) {},
                onViewport: (DateTime start, double hours) {
                  viewportStart = start;
                },
                onToast: (String message) {},
              ),
            ),
          ),
        ),
      ),
    );

    // Dragging an unselected block pans; it neither selects nor moves it.
    final TestGesture first = await tester.startGesture(const Offset(300, 25));
    await first.moveBy(const Offset(80, 0));
    await first.up();
    await tester.pumpAndSettle();
    expect(selected, isNull);
    expect(viewportStart, isNotNull);
    expect(block.start, atLocalTime(today, 10, 0));

    // A plain tap selects it.
    await tester.tapAt(const Offset(300, 25));
    await tester.pumpAndSettle();
    expect(selected, 1);
    expect(block.start, atLocalTime(today, 10, 0));

    // The same drag now moves the block because it is selected.
    final TestGesture second = await tester.startGesture(const Offset(300, 25));
    await second.moveBy(const Offset(80, 0));
    await second.up();
    await tester.pumpAndSettle();
    await store.flush();
    expect(block.start.isAfter(atLocalTime(today, 10, 0)), isTrue);
    expect(store.hasUndo, isTrue);
  });

  testWidgets('tapping an overlap cycles to the buried block', (tester) async {
    final TimelineStore store = await emptyStore();
    addTearDown(store.dispose);
    store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
    final DateTime today = startOfLocalDay(DateTime.now());
    store.blocks.addAll(<Block>[
      Block(
        id: 1,
        trackId: 'work',
        title: 'Long',
        start: atLocalTime(today, 10, 0),
        end: atLocalTime(today, 11, 30),
      ),
      Block(
        id: 2,
        trackId: 'work',
        title: 'Short',
        start: atLocalTime(today, 10, 30),
        end: atLocalTime(today, 11, 0),
      ),
    ]);
    final TimelineLayout layout = buildTimelineLayout(
      tracks: store.tracks,
      blocks: store.blocks,
      rangeStart: today,
      rangeEnd: addLocalDays(today, 1),
      viewStart: atLocalTime(today, 9, 0),
      hours: 4,
      width: 800,
      trackOpen: <String, bool>{'work': true},
    );

    int? selected;
    Set<int> selection = <int>{};
    final ScrollController controller = ScrollController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) => MaterialApp(
          theme: buildTimelineTheme(),
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 400,
              child: TimelineCanvas(
                layout: layout,
                contentHeight: 400,
                store: store,
                selectedIds: selection,
                primarySelectedId: selection.length == 1
                    ? selection.first
                    : null,
                selectionMode: false,
                now: DateTime.now(),
                showNames: true,
                scrollController: controller,
                onSelect: (int id, {required bool toggle}) {
                  selected = id;
                  setState(() => selection = <int>{id});
                },
                onClearSelection: () {},
                onMarqueeSelect: (Set<int> ids, {required bool additive}) {},
                onLongPressSelect: (int id) {},
                onEdit: (Block value) {},
                onViewport: (DateTime start, double hours) {},
                onToast: (String message) {},
              ),
            ),
          ),
        ),
      ),
    );

    const Offset overlap = Offset(350, 25);
    await tester.tapAt(overlap);
    await tester.pumpAndSettle();
    // The later-starting block is drawn on top, so it is selected first.
    expect(selected, 2);

    // Wait out the double-tap window, then tap the same spot again.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 420)),
    );
    await tester.tapAt(overlap);
    await tester.pumpAndSettle();
    expect(selected, 1);
    await store.flush();
  });

  testWidgets('block editor shows duration and repeat pickers', (tester) async {
    final TimelineStore store = await emptyStore();
    addTearDown(store.dispose);
    store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
    final DateTime today = startOfLocalDay(DateTime.now());
    final Block block = Block(
      id: 1,
      trackId: 'work',
      title: 'Standup',
      start: atLocalTime(today, 10, 0),
      end: atLocalTime(today, 11, 0),
      repeat: const RepeatSpec.daily(),
    );
    store.blocks.add(block);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTimelineTheme(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    showBlockEditor(context, store, block: block, isNew: false),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    expect(find.textContaining('10:00–11:00 · 1h'), findsOneWidget);
    expect(find.text('Notify me'), findsOneWidget);

    final Finder body = find.byType(SingleChildScrollView).last;
    await tester.dragUntilVisible(
      find.text('Start'),
      body,
      const Offset(0, -180),
    );
    await tester.tap(find.text('Start'));
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('Mon'),
      body,
      const Offset(0, -180),
    );
    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('Sun'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(
      store.blocks.any((Block item) => item.alarms.contains(AlarmOffset.start)),
      isTrue,
    );
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('block editor can switch to hourly repeat', (tester) async {
    final TimelineStore store = await emptyStore();
    addTearDown(store.dispose);
    store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
    final DateTime today = startOfLocalDay(DateTime.now());
    final Block block = Block(
      id: 1,
      trackId: 'work',
      title: 'Hydrate',
      start: atLocalTime(today, 10, 0),
      end: atLocalTime(today, 10, 10),
    );
    store.blocks.add(block);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTimelineTheme(),
        home: Builder(
          builder: (BuildContext context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    showBlockEditor(context, store, block: block, isNew: false),
                child: const Text('Open editor'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open editor'));
    await tester.pumpAndSettle();

    final Finder body = find.byType(SingleChildScrollView).last;
    await tester.dragUntilVisible(
      find.text('Does not repeat'),
      body,
      const Offset(0, -180),
    );
    await tester.tap(find.text('Does not repeat'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hourly').last);
    await tester.pumpAndSettle();
    await tester.dragUntilVisible(
      find.text('23:00'),
      body,
      const Offset(0, -180),
    );
    expect(find.text('10:00'), findsWidgets);
    expect(find.text('23:00'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('timeline page renders categories and blocks', (tester) async {
    final TimelineStore store = await emptyStore();
    addTearDown(store.dispose);
    store.tracks.add(Track(id: 'work', name: 'Work', colorValue: 0xFF6F9DF0));
    store.trackOpen['work'] = true;
    final DateTime now = DateTime.now();
    final DateTime start = now.subtract(const Duration(minutes: 30));
    final Block block = Block(
      id: store.blocks.length + 1,
      trackId: 'work',
      title: 'Smoke block',
      start: start,
      end: start.add(const Duration(hours: 1)),
    );
    store.blocks.add(block);

    await tester.pumpWidget(
      MaterialApp(
        theme: buildTimelineTheme(),
        home: TimelinePage(store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Smoke block'), findsWidgets);
    expect(find.text('NEW'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
