import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

const String timelineStorageKey = 'timeline_data_v1';

abstract class TimelineStorage {
  Future<String?> read();
  Future<void> write(String value);
}

class SharedPreferencesTimelineStorage implements TimelineStorage {
  SharedPreferencesTimelineStorage();

  SharedPreferences? _preferences;

  Future<SharedPreferences> _getPreferences() async =>
      _preferences ??= await SharedPreferences.getInstance();

  @override
  Future<String?> read() async =>
      (await _getPreferences()).getString(timelineStorageKey);

  @override
  Future<void> write(String value) async {
    final SharedPreferences preferences = await _getPreferences();
    await preferences.setString(timelineStorageKey, value);
  }
}

class FileTimelineStorage implements TimelineStorage {
  FileTimelineStorage(this.file);

  final File file;

  Future<bool> ensureWritable() async {
    try {
      await file.parent.create(recursive: true);
      final File probe = File('${file.path}.probe');
      await probe.writeAsString('', flush: true);
      await probe.delete();
      return true;
    } on FileSystemException {
      return false;
    }
  }

  @override
  Future<String?> read() async {
    try {
      File source = file;
      if (!await source.exists()) {
        source = File('${file.path}.tmp');
      }
      if (!await source.exists()) return null;
      return await source.readAsString();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Future<void> write(String value) async {
    await file.parent.create(recursive: true);
    final File temp = File('${file.path}.tmp');
    await temp.writeAsString(value, flush: true);
    if (await file.exists()) await file.delete();
    await temp.rename(file.path);
  }
}

/// Windows portable builds keep their data beside the executable. If that
/// location is not writable, fall back to the per-user preferences store.
Future<TimelineStorage> createDefaultTimelineStorage() async {
  if (!Platform.isWindows) return SharedPreferencesTimelineStorage();

  final Directory executableDir = File(Platform.resolvedExecutable).parent;
  final String separator = Platform.pathSeparator;
  final File dataFile = File(
    '${executableDir.path}${separator}timeline-data'
    '${separator}timeline_data.json',
  );
  final FileTimelineStorage portable = FileTimelineStorage(dataFile);
  if (!await portable.ensureWritable()) {
    return SharedPreferencesTimelineStorage();
  }

  if (!await dataFile.exists()) {
    final String? legacy = await SharedPreferencesTimelineStorage().read();
    if (legacy != null) {
      try {
        await portable.write(legacy);
      } on FileSystemException {
        return SharedPreferencesTimelineStorage();
      }
    }
  }
  return portable;
}
