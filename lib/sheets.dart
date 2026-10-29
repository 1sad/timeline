import 'dart:convert';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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

Future<bool> showBatchEditor(
  BuildContext context,
  TimelineStore store,
  List<Block> blocks,
) async {
  final bool? changed = await showAppSheet<bool>(
    context: context,
    child: _BatchEditorSheet(store: store, blocks: blocks),
  );
  return changed ?? false;
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
  String? _confirmClear;
  bool _busy = false;

  TimelineStore get store => widget.store;

  void _close() => Navigator.of(context).pop();

  Future<void> _undo() async {
    final String? label = store.undo();
    if (!mounted) return;
    await showAppToast(
      context,
      label == null ? 'Nothing to undo' : 'Undid: $label',
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (BuildContext context, Widget? child) {
        final List<Track> ordered = store.displayTracks;
        final int editableCount = ordered
            .where((Track track) => !track.fixed)
            .length;
        return SheetFrame(
          kicker: 'Categories',
          title: 'Your tracks',
          subtitle: 'Drag to reorder. Rename, recolour, add or delete. Zero categories is allowed.',
          onClose: _close,
          headerTrailing: AppIconButton(
            icon: Icons.undo,
            tooltip: 'Undo',
            onPressed: store.hasUndo ? _undo : null,
            size: 30,
          ),
          footer: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '$editableCount ${editableCount == 1 ? 'category' : 'categories'} · '
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
                    'Drag the dotted handle to reorder. On Android, long-press the handle. '
                    'Blocks keep their times if you delete a category.',
              ),
              const SizedBox(height: 12),
              if (ordered.isEmpty)
                const _EmptyCategories()
              else
                ReorderableListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  buildDefaultDragHandles: false,
                  itemCount: ordered.length,
                  proxyDecorator:
                      (Widget child, int index, Animation<double> animation) {
                        return AnimatedBuilder(
                          animation: animation,
                          builder: (BuildContext context, Widget? _) {
                            final double lift = Curves.easeOut.transform(
                              animation.value,
                            );
                            return Transform.translate(
                              offset: Offset(0, -2 * lift),
                              child: Transform.scale(
                                scale: 1 + 0.008 * lift,
                                child: Material(
                                  color: Colors.transparent,
                                  elevation: 12 * lift,
                                  borderRadius: BorderRadius.circular(9),
                                  child: Stack(
                                    children: <Widget>[
                                      child,
                                      Positioned.fill(
                                        bottom: 7,
                                        child: IgnorePointer(
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              borderRadius:
                                                  BorderRadius.circular(9),
                                              border: Border.all(
                                                color: AppColors.alpha(
                                                  AppColors.accent,
                                                  0.8 * lift,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                  onReorderItem: (int oldIndex, int newIndex) {
                    if (store.locked) return;
                    store.reorderCategory(ordered[oldIndex].id, newIndex);
                    setState(() {
                      _paletteFor = null;
                      _confirmDelete = null;
                      _confirmClear = null;
                    });
                  },
                  itemBuilder: (BuildContext context, int index) {
                    final Track track = ordered[index];
                    final bool fixed = track.fixed;
                    return _CategoryRow(
                      key: ValueKey<String>(track.id),
                      store: store,
                      track: track,
                      count: store.blockCountForTrack(track.id),
                      paletteOpen: _paletteFor == track.id,
                      confirmOpen: _confirmDelete == track.id,
                      clearOpen: _confirmClear == track.id,
                      reorderIndex: index,
                      reorderEnabled: !store.locked,
                      onPalette: fixed
                          ? () {}
                          : () => setState(() {
                              _paletteFor = _paletteFor == track.id
                                  ? null
                                  : track.id;
                              _confirmDelete = null;
                              _confirmClear = null;
                            }),
                      onAskDelete: fixed
                          ? () {}
                          : () => setState(() {
                              _paletteFor = null;
                              _confirmClear = null;
                              _confirmDelete = _confirmDelete == track.id
                                  ? null
                                  : track.id;
                            }),
                      onDelete: fixed
                          ? () {}
                          : () {
                              store.deleteTrack(track.id);
                              setState(() => _confirmDelete = null);
                            },
                      onAskClear: () => setState(() {
                        _paletteFor = null;
                        _confirmDelete = null;
                        _confirmClear = _confirmClear == track.id
                            ? null
                            : track.id;
                      }),
                      onClear: () {
                        store.clearTrack(track.id);
                        setState(() => _confirmClear = null);
                      },
                      fixed: fixed,
                    );
                  },
                ),
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
    required this.clearOpen,
    required this.onPalette,
    required this.onAskDelete,
    required this.onDelete,
    required this.onAskClear,
    required this.onClear,
    required this.reorderIndex,
    required this.reorderEnabled,
    this.fixed = false,
  });

  final TimelineStore store;
  final Track track;
  final int count;
  final bool paletteOpen;
  final bool confirmOpen;
  final bool clearOpen;
  final VoidCallback onPalette;
  final VoidCallback onAskDelete;
  final VoidCallback onDelete;
  final VoidCallback onAskClear;
  final VoidCallback onClear;
  final int reorderIndex;
  final bool reorderEnabled;
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
                if (widget.reorderEnabled)
                  defaultTargetPlatform == TargetPlatform.windows
                      ? Tooltip(
                          message: 'Drag to reorder',
                          child: ReorderableDragStartListener(
                            index: widget.reorderIndex,
                            child: const _DragGrip(),
                          ),
                        )
                      : Semantics(
                          label: 'Long-press to reorder',
                          child: ReorderableDelayedDragStartListener(
                            index: widget.reorderIndex,
                            child: const _DragGrip(),
                          ),
                        )
                else
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      Icons.drag_handle,
                      size: 16,
                      color: AppColors.faint,
                    ),
                  ),
                const SizedBox(width: 2),
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
                const SizedBox(width: 4),
                Tooltip(
                  message: widget.count == 0
                      ? 'No blocks to clear'
                      : 'Remove every block in ${widget.track.name}',
                  child: InkWell(
                    onTap: widget.count == 0 ? null : widget.onAskClear,
                    borderRadius: BorderRadius.circular(5),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 4,
                      ),
                      child: Text(
                        'Clear',
                        style: TextStyle(
                          fontSize: 9.5,
                          fontWeight: FontWeight.w600,
                          color: widget.count == 0
                              ? AppColors.faint.withValues(alpha: .45)
                              : const Color(0xFFD9A5A5),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
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
          if (widget.clearOpen)
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
                    'Clear “${widget.track.name}”? ${widget.count} '
                    '${widget.count == 1 ? 'block' : 'blocks'} will be deleted.',
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
                        onPressed: widget.onAskClear,
                      ),
                      const SizedBox(width: 6),
                      ToastButton(
                        label: 'Clear',
                        height: 28,
                        danger: true,
                        onPressed: widget.onClear,
                      ),
                    ],
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

class _DragGrip extends StatelessWidget {
  const _DragGrip();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      width: 44,
      height: 44,
      child: ColoredBox(
        color: Colors.transparent,
        child: Icon(Icons.drag_indicator, size: 18, color: AppColors.faint),
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
                _TemplateIcon(
                  template: template,
                  color: store.trackOrUncategorized(template.trackId).color,
                ),
                const SizedBox(width: 6),
                Text(
                  '${template.title} · '
                  '${template.isMulti ? '${template.blockCount} blocks' : fmtDuration(Duration(minutes: template.durationMinutes))}',
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

class _TemplateIcon extends StatelessWidget {
  const _TemplateIcon({required this.template, required this.color});

  final Template template;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final int count = template.isMulti ? math.min(3, template.blockCount) : 1;
    if (count == 1) {
      return Container(
        width: 18,
        height: 18,
        alignment: Alignment.center,
        child: Container(
          width: 14,
          height: 7,
          decoration: BoxDecoration(
            color: AppColors.alpha(color, .34),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: AppColors.alpha(color, .8)),
          ),
        ),
      );
    }
    return SizedBox(
      width: 18,
      height: 18,
      child: Stack(
        children: <Widget>[
          for (int index = 0; index < count; index++)
            Positioned(
              left: 1.0 + index * 2,
              top: 1.5 + index * 4.5,
              child: Container(
                width: 13 - index * 1.5,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.alpha(color, .72 - index * .14),
                  borderRadius: BorderRadius.circular(1.5),
                  border: Border.all(
                    color: AppColors.alpha(color, .86),
                    width: .7,
                  ),
                ),
              ),
            ),
        ],
      ),
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
  late Set<AlarmOffset> _alarms;
  late RepeatSpec _repeat;
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
    _alarms = Set<AlarmOffset>.of(source?.alarms ?? const <AlarmOffset>{});
    _repeat = source?.repeat ?? RepeatSpec.none;
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
      subtitle:
          '${store.trackOrUncategorized(_trackId).name} · '
          '${fmtDayLong(_start)} ${fmtTime(_start)}–${fmtTime(_end)} · '
          '${_end.isAfter(_start) ? fmtDuration(_end.difference(_start)) : '—'}',
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
                    label: template.isMulti
                        ? '${template.title} · ${template.blockCount} blocks'
                        : '${template.title} · ${fmtDuration(Duration(minutes: template.durationMinutes))}',
                    icon: template.isMulti
                        ? Icons.view_week_outlined
                        : Icons.view_timeline_outlined,
                    height: 34,
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
          _DurationStepper(
            onDelta: (int minutes) {
              setState(() {
                final int next = _end.difference(_start).inMinutes + minutes;
                _end = _start.add(Duration(minutes: math.max(5, next)));
                _error = null;
              });
            },
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
          _NotificationPicker(
            alarms: _alarms,
            onChanged: (Set<AlarmOffset> value) =>
                setState(() => _alarms = value),
          ),
          const SizedBox(height: 11),
          SheetField(
            label: 'Repeat',
            child: _DropdownBox<RepeatCadence>(
              value: _repeat.mode,
              items: const <DropdownMenuItem<RepeatCadence>>[
                DropdownMenuItem<RepeatCadence>(
                  value: RepeatCadence.none,
                  child: Text('Does not repeat'),
                ),
                DropdownMenuItem<RepeatCadence>(
                  value: RepeatCadence.daily,
                  child: Text('Daily'),
                ),
                DropdownMenuItem<RepeatCadence>(
                  value: RepeatCadence.hourly,
                  child: Text('Hourly'),
                ),
              ],
              onChanged: (RepeatCadence? value) {
                if (value != null) {
                  setState(() {
                    _repeat = _repeatWithMode(value);
                    _error = null;
                  });
                }
              },
            ),
          ),
          if (_repeat.isDaily) ...<Widget>[
            const SizedBox(height: 8),
            const _SectionLabel('Repeat on'),
            const SizedBox(height: 6),
            _WeekdayPicker(
              selected: _repeat.days,
              onChanged: (Set<int> days) =>
                  setState(() => _repeat = _repeat.copyWith(days: days)),
            ),
          ],
          if (_repeat.isHourly) ...<Widget>[
            const SizedBox(height: 8),
            const _SectionLabel('Repeat at'),
            const SizedBox(height: 6),
            _HourPicker(
              selected: _repeat.hours,
              onChanged: (Set<int> hours) =>
                  setState(() => _repeat = _repeat.copyWith(hours: hours)),
            ),
          ],
          if (_repeat.active) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              _repeat.isDaily
                  ? 'Occurrences are created on the ticked weekdays inside the eight-day timeline.'
                  : 'Occurrences are created at the ticked hours inside the eight-day timeline.',
              style: const TextStyle(
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

  RepeatSpec _repeatWithMode(RepeatCadence mode) {
    switch (mode) {
      case RepeatCadence.none:
        return RepeatSpec.none;
      case RepeatCadence.daily:
        return RepeatSpec(
          mode: RepeatCadence.daily,
          days: _repeat.isDaily && _repeat.days.isNotEmpty
              ? _repeat.days
              : RepeatSpec.allDays,
        );
      case RepeatCadence.hourly:
        return RepeatSpec(
          mode: RepeatCadence.hourly,
          hours: _repeat.isHourly && _repeat.hours.isNotEmpty
              ? _repeat.hours
              : <int>{_start.hour},
        );
    }
  }

  Future<void> _applyTemplate(Template template) async {
    if (template.isMulti) {
      if (!widget.isNew) {
        await showAppToast(
          context,
          'Multi-block templates can be added from the NEW block editor',
        );
        return;
      }
      final bool yes = await showConfirm(
        context,
        title: 'Add ${template.blockCount} blocks?',
        message:
            'Add “${template.title}” starting at ${fmtTime(_start)} on ${fmtDayLong(_start)}.',
        confirm: 'Add blocks',
        danger: false,
      );
      if (!yes || !mounted) return;
      final List<Block> added = store.addBlocksFromTemplate(template, _start);
      if (added.isEmpty || !mounted) return;
      Navigator.of(context).pop(added.first);
      return;
    }
    final TemplatePart? part = template.parts.isEmpty
        ? null
        : template.parts.first;
    setState(() {
      _title.text = part?.title ?? template.title;
      _trackId = part?.trackId ?? template.trackId;
      if (store.trackById(_trackId) == null) _trackId = 'uncat';
      _kind = part?.kind ?? template.kind;
      _alarms = Set<AlarmOffset>.of(part?.alarms ?? template.alarms);
      _repeat = part?.repeat ?? template.repeat;
      _end = _start.add(
        Duration(minutes: part?.durationMinutes ?? template.durationMinutes),
      );
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
    if (_repeat.isDaily && _repeat.days.isEmpty) {
      setState(
        () => _error = 'Tick at least one day, or choose Does not repeat.',
      );
      return;
    }
    if (_repeat.isHourly && _repeat.hours.isEmpty) {
      setState(
        () => _error = 'Tick at least one hour, or choose Does not repeat.',
      );
      return;
    }
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
      alarms: _alarms,
      repeat: _repeat,
    );
    store.addTemplateFromBlock(draft);
    setState(() {});
    showAppToast(context, 'Saved “$title” as a template');
  }

  Future<void> _delete() async {
    final Block? block = original;
    if (block == null) return;
    if (!block.repeat.active) {
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
    if (_repeat.isDaily && _repeat.days.isEmpty) {
      setState(
        () => _error = 'Tick at least one day, or choose Does not repeat.',
      );
      return;
    }
    if (_repeat.isHourly && _repeat.hours.isEmpty) {
      setState(
        () => _error = 'Tick at least one hour, or choose Does not repeat.',
      );
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
      alarms: _alarms,
      repeat: _repeat,
      seriesId: original?.seriesId,
      lane: original?.lane,
    );
    final Block? saved = store.saveBlock(draft, isNew: widget.isNew);
    if (saved == null) {
      setState(() => _error = 'End must be after start.');
      return;
    }
    Navigator.of(context).pop(saved);
  }
}

class _BatchEditorSheet extends StatefulWidget {
  const _BatchEditorSheet({required this.store, required this.blocks});

  final TimelineStore store;
  final List<Block> blocks;

  @override
  State<_BatchEditorSheet> createState() => _BatchEditorSheetState();
}

class _BatchEditorSheetState extends State<_BatchEditorSheet> {
  late bool _titleOn = false;
  late bool _trackOn = false;
  late bool _kindOn = false;
  late bool _alarmOn = false;
  late bool _repeatOn = false;
  late bool _durationOn = false;
  late String _trackId;
  late BlockKind _kind;
  late Set<AlarmOffset> _alarms;
  late RepeatSpec _repeat;
  int _durationDelta = 0;
  late final TextEditingController _titleController;

  TimelineStore get store => widget.store;
  Set<int> get _ids => widget.blocks.map((Block block) => block.id).toSet();

  @override
  void initState() {
    super.initState();
    final Block first = widget.blocks.first;
    _trackId = first.trackId;
    _kind = first.kind;
    _alarms =
        widget.blocks.every(
          (Block block) => setEquals(block.alarms, first.alarms),
        )
        ? Set<AlarmOffset>.of(first.alarms)
        : <AlarmOffset>{};
    _repeat = first.repeat;
    final String firstTitle = first.title;
    final bool sameTitle = widget.blocks.every(
      (Block block) => block.title == firstTitle,
    );
    _titleController = TextEditingController(text: sameTitle ? firstTitle : '');
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      kicker: 'Batch edit',
      title: '${widget.blocks.length} blocks selected',
      subtitle: 'Only the fields you switch on are changed. Changes are saved as one undo step.',
      onClose: () => Navigator.of(context).pop(false),
      footer: Row(
        children: <Widget>[
          TextButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: AppColors.danger),
          ),
          const Spacer(),
          ToastButton(
            label: 'Cancel',
            onPressed: () => Navigator.of(context).pop(false),
          ),
          const SizedBox(width: 7),
          ToastButton(label: 'Apply', primary: true, onPressed: _apply),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _SheetTip(
            text:
                'These blocks stay at their current times unless you adjust duration. '
                'Repeating blocks follow the same series rules as the single editor.',
          ),
          const SizedBox(height: 12),
          _BatchFieldCard(
            label: 'Title',
            value: _titleOn,
            onChanged: (bool value) => setState(() => _titleOn = value),
            child: TextField(
              controller: _titleController,
              maxLength: 60,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                counterText: '',
                isDense: true,
                hintText: 'Leave blank to keep current titles',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 8,
                ),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(height: 9),
          _BatchFieldCard(
            label: 'Category',
            value: _trackOn,
            onChanged: (bool value) => setState(() => _trackOn = value),
            child: _DropdownBox<String>(
              value: _trackId,
              items: <DropdownMenuItem<String>>[
                for (final Track track in store.displayTracks)
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
              ],
              onChanged: (String? value) {
                if (value != null) setState(() => _trackId = value);
              },
            ),
          ),
          const SizedBox(height: 9),
          _BatchFieldCard(
            label: 'Type',
            value: _kindOn,
            onChanged: (bool value) => setState(() => _kindOn = value),
            child: _DropdownBox<BlockKind>(
              value: _kind,
              items: const <DropdownMenuItem<BlockKind>>[
                DropdownMenuItem<BlockKind>(
                  value: BlockKind.event,
                  child: Text('Event'),
                ),
                DropdownMenuItem<BlockKind>(
                  value: BlockKind.zone,
                  child: Text('Zone'),
                ),
              ],
              onChanged: (BlockKind? value) {
                if (value != null) setState(() => _kind = value);
              },
            ),
          ),
          const SizedBox(height: 9),
          _BatchFieldCard(
            label: 'Notifications',
            value: _alarmOn,
            onChanged: (bool value) => setState(() => _alarmOn = value),
            child: _NotificationPicker(
              alarms: _alarms,
              onChanged: (Set<AlarmOffset> value) =>
                  setState(() => _alarms = value),
            ),
          ),
          const SizedBox(height: 9),
          _BatchFieldCard(
            label: 'Repeat',
            value: _repeatOn,
            onChanged: (bool value) => setState(() {
              _repeatOn = value;
              if (value && _repeat.mode == RepeatCadence.none) {
                _repeat = const RepeatSpec.daily();
              }
            }),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _DropdownBox<RepeatCadence>(
                  value: _repeat.mode,
                  items: const <DropdownMenuItem<RepeatCadence>>[
                    DropdownMenuItem<RepeatCadence>(
                      value: RepeatCadence.none,
                      child: Text('Does not repeat'),
                    ),
                    DropdownMenuItem<RepeatCadence>(
                      value: RepeatCadence.daily,
                      child: Text('Daily'),
                    ),
                    DropdownMenuItem<RepeatCadence>(
                      value: RepeatCadence.hourly,
                      child: Text('Hourly'),
                    ),
                  ],
                  onChanged: (RepeatCadence? value) {
                    if (value != null) {
                      setState(() => _repeat = _repeatWithMode(value));
                    }
                  },
                ),
                if (_repeat.isDaily) ...<Widget>[
                  const SizedBox(height: 8),
                  _WeekdayPicker(
                    selected: _repeat.days,
                    onChanged: (Set<int> days) =>
                        setState(() => _repeat = _repeat.copyWith(days: days)),
                  ),
                ],
                if (_repeat.isHourly) ...<Widget>[
                  const SizedBox(height: 8),
                  _HourPicker(
                    selected: _repeat.hours,
                    onChanged: (Set<int> hours) => setState(
                      () => _repeat = _repeat.copyWith(hours: hours),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 9),
          _BatchFieldCard(
            label: 'Duration',
            value: _durationOn,
            onChanged: (bool value) => setState(() {
              _durationOn = value;
              if (!value) _durationDelta = 0;
            }),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _durationDelta == 0
                      ? 'Tap a step to adjust every selected block'
                      : '${_durationDelta > 0 ? '+' : ''}${fmtDuration(Duration(minutes: _durationDelta.abs()))} per block',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppColors.faint,
                  ),
                ),
                const SizedBox(height: 7),
                _DurationStepper(
                  onDelta: (int minutes) {
                    setState(() {
                      _durationOn = true;
                      _durationDelta += minutes;
                    });
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 15),
          Row(
            children: <Widget>[
              Expanded(
                child: ToastButton(
                  label: 'Save selection as template',
                  icon: Icons.bookmark_add_outlined,
                  onPressed: _saveTemplate,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  RepeatSpec _repeatWithMode(RepeatCadence mode) {
    final DateTime anchor = widget.blocks.first.start;
    switch (mode) {
      case RepeatCadence.none:
        return RepeatSpec.none;
      case RepeatCadence.daily:
        return RepeatSpec(
          mode: RepeatCadence.daily,
          days: _repeat.isDaily && _repeat.days.isNotEmpty
              ? _repeat.days
              : RepeatSpec.allDays,
        );
      case RepeatCadence.hourly:
        return RepeatSpec(
          mode: RepeatCadence.hourly,
          hours: _repeat.isHourly && _repeat.hours.isNotEmpty
              ? _repeat.hours
              : <int>{anchor.hour},
        );
    }
  }

  RepeatSpec _repeatForApply() {
    if (!_repeat.active) return RepeatSpec.none;
    final DateTime anchor = widget.blocks.first.start;
    if (_repeat.isDaily) {
      return _repeat.days.isEmpty
          ? _repeat.copyWith(days: <int>{anchor.weekday})
          : _repeat;
    }
    return _repeat.hours.isEmpty
        ? _repeat.copyWith(hours: <int>{anchor.hour})
        : _repeat;
  }

  void _apply() {
    store.batchEditBlocks(
      _ids,
      trackId: _trackOn ? _trackId : null,
      title: _titleOn ? _titleController.text : null,
      kind: _kindOn ? _kind : null,
      alarms: _alarmOn ? _alarms : null,
      repeat: _repeatOn ? _repeatForApply() : null,
      durationDeltaMinutes: _durationOn ? _durationDelta : 0,
    );
    Navigator.of(context).pop(true);
  }

  void _saveTemplate() {
    store.addTemplateFromBlocks(widget.blocks);
    showAppToast(
      context,
      'Saved ${widget.blocks.length} ${widget.blocks.length == 1 ? 'block' : 'blocks'} as a template',
    );
    setState(() {});
  }

  Future<void> _delete() async {
    final bool yes = await showConfirm(
      context,
      title: 'Delete ${widget.blocks.length} blocks?',
      message:
          'The selected ${widget.blocks.length == 1 ? 'block' : 'blocks'} will be removed from the timeline.',
    );
    if (!yes || !mounted) return;
    store.deleteBlocks(_ids);
    Navigator.of(context).pop(true);
  }
}

class _BatchFieldCard extends StatelessWidget {
  const _BatchFieldCard({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.child,
  });

  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: const Color(0xFF11151B),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          InkWell(
            onTap: () => onChanged(!value),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: <Widget>[
                  Icon(
                    value ? Icons.check_box : Icons.check_box_outline_blank,
                    size: 17,
                    color: value ? AppColors.accent : AppColors.faint,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (value) ...<Widget>[const SizedBox(height: 8), child],
        ],
      ),
    );
  }
}

class _NotificationPicker extends StatelessWidget {
  const _NotificationPicker({required this.alarms, required this.onChanged});

  final Set<AlarmOffset> alarms;
  final ValueChanged<Set<AlarmOffset>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFF11151B),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          const Row(
            children: <Widget>[
              Icon(Icons.notifications_none, size: 15, color: AppColors.muted),
              SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Notify me',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                'Default sound',
                style: TextStyle(fontSize: 9, color: AppColors.faint),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final AlarmOffset offset in AlarmOffset.values)
                _TickChip(
                  label: offset.label,
                  selected: alarms.contains(offset),
                  onTap: () {
                    final Set<AlarmOffset> next = Set<AlarmOffset>.of(alarms);
                    if (!next.add(offset)) next.remove(offset);
                    onChanged(next);
                  },
                ),
            ],
          ),
          const SizedBox(height: 7),
          const Text(
            'Uses the device notification sound. Alerts fire while Timeline is '
            'open or running in the background.',
            style: TextStyle(
              fontSize: 9.5,
              height: 1.35,
              color: AppColors.faint,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekdayPicker extends StatelessWidget {
  const _WeekdayPicker({required this.selected, required this.onChanged});

  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: <Widget>[
        for (int day = DateTime.monday; day <= DateTime.sunday; day++)
          _TickChip(
            label: RepeatSpec.shortWeekday(day),
            selected: selected.contains(day),
            onTap: () {
              final Set<int> next = Set<int>.of(selected);
              if (!next.add(day)) next.remove(day);
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class _HourPicker extends StatelessWidget {
  const _HourPicker({required this.selected, required this.onChanged});

  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      children: <Widget>[
        for (int hour = 0; hour < 24; hour++)
          _TickChip(
            label: RepeatSpec.hourLabel(hour),
            selected: selected.contains(hour),
            onTap: () {
              final Set<int> next = Set<int>.of(selected);
              if (!next.add(hour)) next.remove(hour);
              onChanged(next);
            },
          ),
      ],
    );
  }
}

class _TickChip extends StatelessWidget {
  const _TickChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? AppColors.alpha(AppColors.accent, .16)
          : const Color(0xFF151A21),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(7),
        side: BorderSide(
          color: selected
              ? AppColors.alpha(AppColors.accent, .55)
              : AppColors.line,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(7),
        child: SizedBox(
          height: 30,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 13,
                  child: selected
                      ? const Icon(
                          Icons.check,
                          size: 12,
                          color: AppColors.accent,
                        )
                      : null,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: selected ? AppColors.text : AppColors.muted,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DurationStepper extends StatelessWidget {
  const _DurationStepper({required this.onDelta});

  final ValueChanged<int> onDelta;

  static const List<int> _deltas = <int>[-60, -30, -5, 5, 30, 60];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 7,
      children: <Widget>[
        for (final int minutes in _deltas)
          ToastButton(
            label: minutes > 0
                ? '+${fmtDuration(Duration(minutes: minutes))}'
                : '-${fmtDuration(Duration(minutes: -minutes))}',
            height: 42,
            onPressed: () => onDelta(minutes),
          ),
      ],
    );
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
