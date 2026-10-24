import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timeline/models.dart';
import 'package:timeline/sheets.dart';
import 'package:timeline/storage.dart';
import 'package:timeline/store.dart';
import 'package:timeline/theme.dart';
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
        alarm: true,
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
