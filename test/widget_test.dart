import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeline/models.dart';
import 'package:timeline/store.dart';
import 'package:timeline/theme.dart';
import 'package:timeline/timeline_page.dart';

Future<TimelineStore> emptyStore() async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'timeline_data_v1':
        '{"tracks":[],"blocks":[],"templates":[],"trackOpen":{}}',
  });
  final TimelineStore store = TimelineStore();
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

    test('keeps a cross-midnight lane stable when another block overlaps', () {
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
      expect(overnight.single.lane, 1);
    });

    test('packs overlapping events and leaves free events in lane zero', () {
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
      expect(lanes[2], 1);
      expect(lanes[3], 0);
      expect(layout.metrics[track.id]!.events, 2);
      expect(layout.metrics[track.id]!.height, 8 + 2 * 42);
    });

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
            repeat: Recurrence.daily,
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
          repeat: Recurrence.daily,
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
