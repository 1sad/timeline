import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:timeline/storage.dart';

void main() {
  test('file storage creates its folder and round-trips data', () async {
    final Directory directory = await Directory.systemTemp.createTemp(
      'timeline-storage-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final String separator = Platform.pathSeparator;
    final FileTimelineStorage storage = FileTimelineStorage(
      File(
        '${directory.path}${separator}nested'
        '${separator}timeline_data.json',
      ),
    );

    expect(await storage.read(), isNull);
    expect(await storage.ensureWritable(), isTrue);
    await storage.write('{"blocks":[]}');
    expect(await storage.read(), '{"blocks":[]}');
    await storage.write('{"blocks":[1]}');
    expect(await storage.read(), '{"blocks":[1]}');

    await storage.file.delete();
    await File('${storage.file.path}.tmp').writeAsString('{"blocks":[2]}');
    expect(await storage.read(), '{"blocks":[2]}');
  });
}
