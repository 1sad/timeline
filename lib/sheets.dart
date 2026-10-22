import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'models.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

Future<void> showCategoriesSheet(BuildContext context, TimelineStore store) {
  return showAppSheet<void>(
    context: context,
    child: _CategoriesSheet(store: store),
  );
}

class _CategoriesSheet extends StatefulWidget {
  const _CategoriesSheet({required this.store});

  final TimelineStore store;

  @override
  State<_CategoriesSheet> createState() => _CategoriesSheetState();
}

class _CategoriesSheetState extends State<_CategoriesSheet> {
  String? _paletteFor;
  String? _confirmDelete;
  bool _busy = false;

  TimelineStore get store => widget.store;

  void _close() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (BuildContext context, Widget? child) {
        final List<Track> editable = store.tracks
            .where((Track track) => !track.fixed)
            .toList();
        final Track? uncat = store.trackById('uncat');
        return SheetFrame(
          kicker: 'Categories',
          title: 'Your tracks',
          subtitle:
              'Rename, recolour, add or delete. Zero categories is allowed.',
          onClose: _close,
          footer: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${store.tracks.length} ${store.tracks.length == 1 ? 'category' : 'categories'} · '
                  '${store.blocks.length} ${store.blocks.length == 1 ? 'block' : 'blocks'}',
                  style: const TextStyle(fontSize: 10, color: AppColors.faint),
                ),
              ),
              ToastButton(
                label: 'New category',
                icon: Icons.add,
                onPressed: () => store.addTrack(),
                primary: true,
              ),
            ],
          ),
          body: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _SheetTip(
                text:
                    'Blocks keep their times if you delete a category. '
                    'They move to Uncategorized instead.',
              ),
              const SizedBox(height: 12),
              if (editable.isEmpty && uncat == null)
                const _EmptyCategories()
              else ...<Widget>[
                for (final Track track in editable)
                  _CategoryRow(
                    key: ValueKey<String>(track.id),
                    store: store,
                    track: track,
                    count: store.blockCountForTrack(track.id),
                    paletteOpen: _paletteFor == track.id,
                    confirmOpen: _confirmDelete == track.id,
                    onPalette: () => setState(() {
                      _paletteFor = _paletteFor == track.id ? null : track.id;
                      _confirmDelete = null;
                    }),
                    onAskDelete: () => setState(() {
                      _paletteFor = null;
                      _confirmDelete = _confirmDelete == track.id
                          ? null
                          : track.id;
                    }),
                    onDelete: () {
                      store.deleteTrack(track.id);
                      setState(() => _confirmDelete = null);
                    },
                  ),
                if (uncat != null)
                  _CategoryRow(
                    key: const ValueKey<String>('uncat'),
                    store: store,
                    track: uncat,
                    count: store.blockCountForTrack('uncat'),
                    paletteOpen: false,
                    confirmOpen: false,
                    fixed: true,
                    onPalette: () {},
                    onAskDelete: () {},
                    onDelete: () {},
                  ),
              ],
              if (store.templates.isNotEmpty) ...<Widget>[
                const SizedBox(height: 22),
                const _SectionLabel('Templates'),
                const SizedBox(height: 7),
                _TemplateList(store: store),
              ],
              const SizedBox(height: 22),
              const _SectionLabel('Sync'),
              const SizedBox(height: 6),
              _SyncBox(busy: _busy, onExport: _export, onImport: _import),
            ],
          ),
        );
      },
    );
  }

  Future<void> _export() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final String date = DateTime.now().toIso8601String().substring(0, 10);
      final Uint8List bytes = Uint8List.fromList(
        utf8.encode(store.exportJsonString()),
      );
      final Uri? uri = await FilePicker.saveFile(
        fileName: 'timeline-sync-$date.json',
        bytes: bytes,
        mimeType: 'application/json',
        type: FileType.custom,
        allowedExtensions: const <String>['json'],
        dialogTitle: 'Export Timeline JSON',
      );
      if (uri != null && mounted) {
        await showAppToast(
          context,
          'Exported categories, blocks and templates',
        );
      }
    } catch (error) {
      if (mounted) {
        await showAppToast(context, 'Export failed: $error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final PlatformFile? file = await FilePicker.pickFile(
        dialogTitle: 'Import Timeline JSON',
        type: FileType.custom,
        allowedExtensions: const <String>['json'],
      );
      if (file == null) return;
      final Uint8List bytes = await file.xFile.readAsBytes();
      final ImportResult result = store.importJsonString(utf8.decode(bytes));
      if (mounted) {
        await showAppToast(
          context,
          'Imported ${result.blocks} blocks · ${result.tracks} categories',
          actionLabel: 'Undo',
          onAction: () => store.undo(),
        );
      }
    } catch (error) {
      if (mounted) {
        final String message = error is FormatException
            ? error.message
            : 'Could not import that file.';
        await showAppToast(context, message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SheetTip extends StatelessWidget {
  const _SheetTip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: AppColors.alpha(AppColors.accent, .07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.alpha(AppColors.accent, .16)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10,
          height: 1.4,
          color: Color(0xFFAAB7CF),
        ),
      ),
    );
  }
}

class _EmptyCategories extends StatelessWidget {
  const _EmptyCategories();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 18),
      decoration: BoxDecoration(
        color: const Color(0xFF11151B),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.line),
      ),
      child: const Column(
        children: <Widget>[
          Icon(Icons.category_outlined, size: 24, color: AppColors.faint),
          SizedBox(height: 8),
          Text(
            'No categories yet',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          SizedBox(height: 3),
          Text(
            'Every block is Uncategorized. Add a category whenever you want one.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.4,
              color: AppColors.muted,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 8.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 1,
        color: AppColors.muted,
      ),
    );
  }
}

class _CategoryRow extends StatefulWidget {
  const _CategoryRow({
    super.key,
    required this.store,
    required this.track,
    required this.count,
    required this.paletteOpen,
    required this.confirmOpen,
    required this.onPalette,
    required this.onAskDelete,
    required this.onDelete,
    this.fixed = false,
  });

  final TimelineStore store;
  final Track track;
  final int count;
  final bool paletteOpen;
  final bool confirmOpen;
  final VoidCallback onPalette;
  final VoidCallback onAskDelete;
  final VoidCallback onDelete;
  final bool fixed;

  @override
  State<_CategoryRow> createState() => _CategoryRowState();
}

class _CategoryRowState extends State<_CategoryRow> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.track.name,
  );
  late final FocusNode _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _CategoryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focus.hasFocus && _controller.text != widget.track.name) {
      _controller.text = widget.track.name;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _commit() {
    if (widget.fixed) return;
    final bool changed = widget.store.renameTrack(
      widget.track.id,
      _controller.text,
    );
    if (!changed && mounted) {
      _controller.text = widget.track.name;
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color color = widget.track.color;
    return Container(
      margin: const EdgeInsets.only(bottom: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF11151B),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 6, 6),
            child: Row(
              children: <Widget>[
                Tooltip(
                  message: widget.fixed ? 'Built-in category' : 'Change colour',
                  child: InkWell(
                    onTap: widget.fixed ? null : widget.onPalette,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 25,
                      height: 25,
                      decoration: BoxDecoration(
                        color: AppColors.alpha(color, .2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.alpha(color, .65)),
                      ),
                      child: Center(
                        child: Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: widget.fixed
                      ? Text(
                          widget.track.name,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.muted,
                          ),
                        )
                      : TextField(
                          controller: _controller,
                          focusNode: _focus,
                          maxLength: 40,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            counterText: '',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 7,
                            ),
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            filled: false,
                          ),
                          onSubmitted: (_) => _focus.unfocus(),
                          textInputAction: TextInputAction.done,
                        ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${widget.count} ${widget.count == 1 ? 'block' : 'blocks'}',
                  style: const TextStyle(fontSize: 9.5, color: AppColors.faint),
                ),
                if (!widget.fixed)
                  IconButton(
                    tooltip: 'Delete category',
                    onPressed: widget.onAskDelete,
                    icon: const Icon(
                      Icons.close,
                      size: 14,
                      color: AppColors.faint,
                    ),
                    splashRadius: 16,
                    constraints: const BoxConstraints.tightFor(
                      width: 28,
                      height: 28,
                    ),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          if (widget.paletteOpen)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
              child: Wrap(
                spacing: 7,
                runSpacing: 7,
                children: <Widget>[
                  for (final int value in const <int>[
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
                  ])
                    InkWell(
                      onTap: () {
                        widget.store.setTrackColor(widget.track.id, value);
                        widget.onPalette();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 23,
                        height: 23,
                        decoration: BoxDecoration(
                          color: Color(value),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: value == widget.track.colorValue
                                ? Colors.white
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          if (widget.confirmOpen)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(11, 8, 9, 8),
              decoration: const BoxDecoration(
                color: Color(0xFF21191B),
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(9)),
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: <Widget>[
                  Text(
                    'Delete “${widget.track.name}”? ${widget.count} '
                    '${widget.count == 1 ? 'block moves' : 'blocks move'} to Uncategorized.',
                    style: const TextStyle(
                      fontSize: 10,
                      height: 1.35,
                      color: Color(0xFFD4B7B7),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      ToastButton(
                        label: 'Cancel',
                        height: 28,
                        onPressed: widget.onAskDelete,
                      ),
                      const SizedBox(width: 6),
                      ToastButton(
                        label: 'Delete',
                        height: 28,
                        danger: true,
                        onPressed: widget.onDelete,
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TemplateList extends StatelessWidget {
  const _TemplateList({required this.store});

  final TimelineStore store;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: <Widget>[
        for (final Template template in store.templates)
          Container(
            padding: const EdgeInsets.fromLTRB(9, 5, 4, 5),
            decoration: BoxDecoration(
              color: AppColors.panel2,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    color: store.trackOrUncategorized(template.trackId).color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${template.title} · ${fmtDuration(Duration(minutes: template.durationMinutes))}',
                  style: const TextStyle(fontSize: 10.5),
                ),
                const SizedBox(width: 3),
                InkWell(
                  onTap: () => store.deleteTemplate(template.id),
                  borderRadius: BorderRadius.circular(5),
                  child: const Padding(
                    padding: EdgeInsets.all(3),
                    child: Icon(Icons.close, size: 12, color: AppColors.faint),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _SyncBox extends StatelessWidget {
  const _SyncBox({
    required this.busy,
    required this.onExport,
    required this.onImport,
  });

  final bool busy;
  final Future<void> Function() onExport;
  final Future<void> Function() onImport;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
      decoration: BoxDecoration(
        color: const Color(0xFF11151B),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'Write categories, blocks, templates and settings to a portable JSON file, '
            'or import one from another device.',
            style: TextStyle(fontSize: 10, height: 1.4, color: AppColors.faint),
          ),
          const SizedBox(height: 9),
          Row(
            children: <Widget>[
              Expanded(
                child: ToastButton(
                  label: busy ? 'Working…' : 'Export .json',
                  icon: Icons.file_download_outlined,
                  onPressed: busy ? null : onExport,
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: ToastButton(
                  label: busy ? 'Working…' : 'Import .json',
                  icon: Icons.file_upload_outlined,
                  onPressed: busy ? null : onImport,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<Block?> showBlockEditor(
  BuildContext context,
  TimelineStore store, {
  Block? block,
  required bool isNew,
}) {
  return showAppSheet<Block>(
    context: context,
    child: _BlockEditorSheet(store: store, block: block, isNew: isNew),
  );
}

class _BlockEditorSheet extends StatefulWidget {
  const _BlockEditorSheet({
    required this.store,
    required this.block,
    required this.isNew,
  });

  final TimelineStore store;
  final Block? block;
  final bool isNew;

  @override
  State<_BlockEditorSheet> createState() => _BlockEditorSheetState();
}

class _BlockEditorSheetState extends State<_BlockEditorSheet> {
  late final TextEditingController _title;
  late String _trackId;
  late DateTime _start;
  late DateTime _end;
  late BlockKind _kind;
  late bool _alarm;
  late Recurrence _repeat;
  String? _error;

  TimelineStore get store => widget.store;
  Block? get original => widget.block;

  @override
  void initState() {
    super.initState();
    final Block? source = widget.block;
    final DateTime now = DateTime.now();
    final DateTime roundedStart = DateTime(
      now.year,
      now.month,
      now.day,
      now.hour,
      (now.minute ~/ 5) * 5,
    );
    _title = TextEditingController(text: source?.title ?? '');
    _start =
        source?.start ??
        (roundedStart.isBefore(store.timelineStart)
            ? store.timelineStart.add(const Duration(hours: 1))
            : roundedStart);
    _end = source?.end ?? _start.add(const Duration(hours: 1));
    _kind = source?.kind ?? BlockKind.event;
    _alarm = source?.alarm ?? false;
    _repeat = source?.repeat ?? Recurrence.none;
    _trackId = source?.trackId ?? store.tracks.firstOrNull?.id ?? 'uncat';
    if (store.trackById(_trackId) == null) _trackId = 'uncat';
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      kicker: widget.isNew ? 'New block' : 'Exact times',
      title: widget.isNew
          ? 'Add to the timeline'
          : (original?.title ?? 'Block'),
      subtitle: widget.isNew
          ? 'Pick a category, exact times, and whether this is a zone.'
          : '${store.trackOrUncategorized(_trackId).name} · '
                '${fmtTime(_start)}–${fmtTime(_end)}',
      onClose: () => Navigator.of(context).pop(),
      footer: Row(
        children: <Widget>[
          if (!widget.isNew)
            TextButton.icon(
              onPressed: _delete,
              icon: const Icon(Icons.delete_outline, size: 16),
              label: const Text('Delete'),
              style: TextButton.styleFrom(foregroundColor: AppColors.danger),
            ),
          const Spacer(),
          ToastButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(),
          ),
          const SizedBox(width: 7),
          ToastButton(label: 'Save', primary: true, onPressed: _save),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (store.templates.isNotEmpty) ...<Widget>[
            const _SectionLabel('Start from a template'),
            const SizedBox(height: 7),
            SizedBox(
              height: 34,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: store.templates.length,
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (BuildContext context, int index) {
                  final Template template = store.templates[index];
                  return ToastButton(
                    label:
                        '${template.title} · ${fmtDuration(Duration(minutes: template.durationMinutes))}',
                    icon: Icons.bolt_outlined,
                    height: 30,
                    onPressed: () => _applyTemplate(template),
                  );
                },
              ),
            ),
            const SizedBox(height: 13),
          ],
          SheetField(
            label: 'Title',
            child: TextField(
              controller: _title,
              maxLength: 80,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                counterText: '',
                hintText: 'What are you doing?',
              ),
            ),
          ),
          const SizedBox(height: 11),
          SheetField(
            label: 'Category',
            child: _DropdownBox<String>(
              value: _trackId,
              items: <DropdownMenuItem<String>>[
                for (final Track track in store.tracks)
                  DropdownMenuItem<String>(
                    value: track.id,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        _ColorDot(track.color),
                        const SizedBox(width: 7),
                        Text(track.name),
                      ],
                    ),
                  ),
                DropdownMenuItem<String>(
                  value: 'uncat',
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      _ColorDot(store.uncategorized.color),
                      const SizedBox(width: 7),
                      const Text('Uncategorized'),
                    ],
                  ),
                ),
              ],
              onChanged: (String? value) {
                if (value != null) setState(() => _trackId = value);
              },
            ),
          ),
          const SizedBox(height: 11),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: _PickerField(
                  label: 'Start date',
                  value: fmtDayLong(_start),
                  icon: Icons.calendar_today_outlined,
                  onTap: _pickStartDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _PickerField(
                  label: 'Start time',
                  value: fmtTime(_start),
                  icon: Icons.schedule,
                  onTap: () => _pickTime(isStart: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Expanded(
                flex: 3,
                child: _PickerField(
                  label: 'End date',
                  value: fmtDayLong(_end),
                  icon: Icons.calendar_today_outlined,
                  onTap: _pickEndDate,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: _PickerField(
                  label: 'End time',
                  value: fmtTime(_end),
                  icon: Icons.schedule,
                  onTap: () => _pickTime(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Text(
                'Duration',
                style: const TextStyle(fontSize: 10.5, color: AppColors.faint),
              ),
              const Spacer(),
              Text(
                _end.isAfter(_start)
                    ? fmtDuration(_end.difference(_start))
                    : '—',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppColors.text,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final int minutes in <int>[15, 30, 60, 120])
                ToastButton(
                  label: '+${fmtDuration(Duration(minutes: minutes))}',
                  height: 27,
                  onPressed: () {
                    setState(() {
                      _end = _start.add(Duration(minutes: minutes));
                      _error = null;
                    });
                  },
                ),
            ],
          ),
          const SizedBox(height: 15),
          const _SectionLabel('Behaviour'),
          const SizedBox(height: 7),
          SheetToggleRow(
            label: 'Zone',
            description:
                'A quiet background ribbon for sleep, travel or digestion.',
            value: _kind == BlockKind.zone,
            onChanged: (bool value) => setState(
              () => _kind = value ? BlockKind.zone : BlockKind.event,
            ),
          ),
          const SizedBox(height: 7),
          SheetToggleRow(
            label: 'Alarm',
            description: 'Notify at the start time while Timeline is running.',
            value: _alarm,
            onChanged: (bool value) => setState(() => _alarm = value),
          ),
          const SizedBox(height: 11),
          SheetField(
            label: 'Repeat',
            child: _DropdownBox<Recurrence>(
              value: _repeat,
              items: <DropdownMenuItem<Recurrence>>[
                for (final Recurrence value in Recurrence.values)
                  DropdownMenuItem<Recurrence>(
                    value: value,
                    child: Text(value.label),
                  ),
              ],
              onChanged: (Recurrence? value) {
                if (value != null) setState(() => _repeat = value);
              },
            ),
          ),
          if (_repeat != Recurrence.none) ...<Widget>[
            const SizedBox(height: 6),
            const Text(
              'Saving a repeating block updates the occurrences visible in the eight-day timeline.',
              style: TextStyle(
                fontSize: 9.5,
                height: 1.35,
                color: AppColors.faint,
              ),
            ),
          ],
          const SizedBox(height: 13),
          Row(
            children: <Widget>[
              Expanded(
                child: ToastButton(
                  label: 'Save as template',
                  icon: Icons.bookmark_add_outlined,
                  onPressed: _saveTemplate,
                ),
              ),
            ],
          ),
          if (_error != null) ...<Widget>[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(fontSize: 10.5, color: AppColors.danger),
            ),
          ],
        ],
      ),
    );
  }

  void _applyTemplate(Template template) {
    setState(() {
      _title.text = template.title;
      _trackId = template.trackId;
      if (store.trackById(_trackId) == null) _trackId = 'uncat';
      _kind = template.kind;
      _alarm = template.alarm;
      _repeat = template.repeat;
      _end = _start.add(Duration(minutes: template.durationMinutes));
      _error = null;
    });
  }

  Future<void> _pickStartDate() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _start,
      firstDate: store.timelineStart,
      lastDate: store.timelineEnd,
      helpText: 'Start date',
    );
    if (date == null) return;
    setState(() {
      _start = DateTime(
        date.year,
        date.month,
        date.day,
        _start.hour,
        _start.minute,
      );
      if (!_end.isAfter(_start)) {
        _end = _start.add(const Duration(hours: 1));
      }
      _error = null;
    });
  }

  Future<void> _pickEndDate() async {
    final DateTime? date = await showDatePicker(
      context: context,
      initialDate: _end,
      firstDate: store.timelineStart,
      lastDate: store.timelineEnd,
      helpText: 'End date',
    );
    if (date == null) return;
    setState(() {
      _end = DateTime(date.year, date.month, date.day, _end.hour, _end.minute);
      _error = null;
    });
  }

  Future<void> _pickTime({required bool isStart}) async {
    final DateTime current = isStart ? _start : _end;
    final TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
      helpText: isStart ? 'Start time' : 'End time',
    );
    if (time == null) return;
    setState(() {
      final DateTime value = DateTime(
        current.year,
        current.month,
        current.day,
        time.hour,
        time.minute,
      );
      if (isStart) {
        _start = value;
        if (!_end.isAfter(_start)) {
          _end = _start.add(const Duration(hours: 1));
        }
      } else {
        _end = value;
      }
      _error = null;
    });
  }

  void _saveTemplate() {
    final String title = _title.text.trim().isEmpty
        ? 'Untitled'
        : _title.text.trim();
    final Block draft = Block(
      id: 0,
      trackId: _trackId,
      title: title,
      start: _start,
      end: _end,
      kind: _kind,
      alarm: _alarm,
      repeat: _repeat,
    );
    store.addTemplateFromBlock(draft);
    setState(() {});
    showAppToast(context, 'Saved “$title” as a template');
  }

  Future<void> _delete() async {
    final Block? block = original;
    if (block == null) return;
    if (block.repeat == Recurrence.none) {
      final bool yes = await showConfirm(
        context,
        title: 'Delete block?',
        message: '“${block.title}” will be removed from the timeline.',
      );
      if (!yes) return;
      store.deleteBlock(block.id);
      if (mounted) Navigator.of(context).pop();
      return;
    }

    final String? result = await showDialog<String>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text(
          'Delete repeating block?',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: const Text(
          'Choose whether to remove only this occurrence or every occurrence in the series.',
          style: TextStyle(fontSize: 12, height: 1.45, color: AppColors.muted),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop('cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop('one'),
            child: const Text('This block'),
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
    store.deleteBlock(block.id, wholeSeries: result == 'series');
    if (mounted) Navigator.of(context).pop();
  }

  void _save() {
    if (!_end.isAfter(_start)) {
      setState(() => _error = 'End must be after start.');
      return;
    }
    final String title = _title.text.trim().isEmpty
        ? 'Untitled'
        : _title.text.trim();
    final Block draft = Block(
      id: widget.isNew ? 0 : (original?.id ?? 0),
      trackId: _trackId,
      title: title,
      start: _start,
      end: _end,
      kind: _kind,
      alarm: _alarm,
      repeat: _repeat,
      seriesId: original?.seriesId,
    );
    final Block? saved = store.saveBlock(draft, isNew: widget.isNew);
    if (saved == null) {
      setState(() => _error = 'End must be after start.');
      return;
    }
    Navigator.of(context).pop(saved);
  }
}

class _DropdownBox<T> extends StatelessWidget {
  const _DropdownBox({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final T value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF11151B),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          icon: const Icon(Icons.expand_more, size: 17, color: AppColors.muted),
          dropdownColor: AppColors.panel2,
          borderRadius: BorderRadius.circular(8),
          style: const TextStyle(fontSize: 12, color: AppColors.text),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SheetField(
      label: label,
      child: Material(
        color: const Color(0xFF11151B),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.line),
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5),
                  ),
                ),
                Icon(icon, size: 14, color: AppColors.faint),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot(this.color);

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );
  }
}
