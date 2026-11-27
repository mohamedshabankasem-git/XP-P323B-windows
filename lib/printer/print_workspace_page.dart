import 'package:flutter/foundation.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';

import '../windows_printer_bridge.dart';
import 'print_document_loader.dart';
import 'raster_print.dart';

class PrintWorkspacePage extends StatefulWidget {
  const PrintWorkspacePage({
    super.key,
    required this.name,
    required this.pages,
    required this.paperWidth,
    required this.connected,
  });

  final String name;
  final List<Uint8List> pages;
  final int paperWidth;
  final bool connected;

  @override
  State<PrintWorkspacePage> createState() => _PrintWorkspacePageState();
}

class _PrintWorkspacePageState extends State<PrintWorkspacePage> {
  int _pageIndex = 0;
  String _alignment = 'left';
  String _mode = 'floydSteinberg';
  bool _busy = false;
  bool _replacingFile = false;
  late String _documentName;
  late List<Uint8List> _pages;
  late Future<Uint8List> _previewFuture;

  @override
  void initState() {
    super.initState();
    _documentName = widget.name;
    _pages = List<Uint8List>.of(widget.pages);
    _refreshPreview();
  }

  void _refreshPreview() {
    _previewFuture = compute(_previewWorker, <String, Object>{
      'bytes': _pages[_pageIndex],
      'width': widget.paperWidth,
      'alignment': _alignment,
      'mode': _mode,
    });
  }

  Future<void> _replaceDocument(String path) async {
    if (_busy || _replacingFile) return;
    setState(() => _replacingFile = true);
    try {
      final document = await PrintDocumentLoader.fromPath(
        path,
        paperWidth: widget.paperWidth,
      );
      if (!mounted) return;
      setState(() {
        _documentName = document.name;
        _pages = document.pages;
        _pageIndex = 0;
        _refreshPreview();
      });
      _message('تم استبدال الملف السابق بالملف الجديد.');
    } catch (error) {
      if (mounted) _message('تعذر استبدال الملف: $error');
    } finally {
      if (mounted) setState(() => _replacingFile = false);
    }
  }

  Future<void> _print({required bool allPages}) async {
    if (_replacingFile) return;
    if (!widget.connected) {
      _message('اتصل بالطابعة أولاً قبل الطباعة.');
      return;
    }
    setState(() => _busy = true);
    try {
      final indices = allPages
          ? List<int>.generate(_pages.length, (index) => index)
          : <int>[_pageIndex];
      for (final index in indices) {
        final payload = await RasterPrint.imageToEscPosAsync(
          _pages[index],
          maxWidth: widget.paperWidth,
          alignment: _alignment,
          mode: _mode,
        );
        final written = await WindowsPrinterBridge.write(payload);
        if (written != payload.length) {
          throw StateError(
            'لم يتم إرسال كامل بيانات الصفحة ${index + 1}: $written/${payload.length} بايت',
          );
        }
      }
      if (mounted) {
        _message(allPages ? 'تم إرسال جميع الصفحات للطابعة.' : 'تم إرسال الصفحة للطابعة.');
      }
    } catch (error) {
      if (mounted) _message('فشلت الطباعة: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _message(String value) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(value)),
    );
  }

  @override
  void didUpdateWidget(covariant PrintWorkspacePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.pages != widget.pages || oldWidget.paperWidth != widget.paperWidth) {
      _refreshPreview();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('معاينة الطباعة')),
      body: DropTarget(
        onDragDone: (detail) {
          if (detail.files.isNotEmpty) {
            _replaceDocument(detail.files.first.path);
            if (detail.files.length > 1) {
              _message('تم استلام أول ملف فقط. اسحب ملفًا واحدًا في كل مرة.');
            }
          }
        },
        child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 920),
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(_documentName, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text('الصفحة ${_pageIndex + 1} من ${_pages.length}'),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _alignment,
                        decoration: const InputDecoration(
                          labelText: 'المحاذاة',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'left', child: Text('يسار')),
                          DropdownMenuItem(value: 'center', child: Text('وسط')),
                          DropdownMenuItem(value: 'right', child: Text('يمين')),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  _alignment = value ?? 'left';
                                  _refreshPreview();
                                }),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _mode,
                        decoration: const InputDecoration(
                          labelText: 'تحويل الصورة الحرارية',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'floydSteinberg', child: Text('Floyd-Steinberg')),
                          DropdownMenuItem(value: 'atkinson', child: Text('Atkinson')),
                          DropdownMenuItem(value: 'ordered', child: Text('Ordered')),
                          DropdownMenuItem(value: 'threshold', child: Text('أسود وأبيض')),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(() {
                                  _mode = value ?? 'floydSteinberg';
                                  _refreshPreview();
                                }),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        color: Colors.white,
                        alignment: Alignment.topCenter,
                        padding: const EdgeInsets.all(8),
                        child: FutureBuilder<Uint8List>(
                          future: _previewFuture,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return Text('تعذرت معاينة الملف: ${snapshot.error}');
                            }
                            if (!snapshot.hasData) {
                              return const Padding(
                                padding: EdgeInsets.all(28),
                                child: CircularProgressIndicator(),
                              );
                            }
                            return Image.memory(
                              snapshot.data!,
                              fit: BoxFit.contain,
                              width: 420,
                            );
                          },
                        ),
                      ),
                      if (widget.pages.length > 1) ...[
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _busy || _pageIndex == 0
                                  ? null
                                  : () => setState(() {
                                    _pageIndex--;
                                    _refreshPreview();
                                  }),
                              icon: const Icon(Icons.chevron_right),
                              label: const Text('السابق'),
                            ),
                            OutlinedButton.icon(
                              onPressed: _busy || _pageIndex == widget.pages.length - 1
                                  ? null
                                  : () => setState(() {
                                    _pageIndex++;
                                    _refreshPreview();
                                  }),
                              icon: const Icon(Icons.chevron_left),
                              label: const Text('التالي'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _busy || _replacingFile ? null : () => _print(allPages: false),
                icon: _busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.print),
                label: Text(_replacingFile ? 'جارٍ استبدال الملف...' : _busy ? 'جارٍ الإرسال...' : 'طباعة الصفحة الحالية'),
              ),
              if (widget.pages.length > 1) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy || _replacingFile ? null : () => _print(allPages: true),
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('طباعة جميع الصفحات'),
                ),
              ],
            ],
          ),
        ),
        ),
      ),
    );
  }
}

Uint8List _previewWorker(Map<String, Object> args) {
  return RasterPrint.imageToPreviewPng(
    args['bytes']! as Uint8List,
    maxWidth: args['width']! as int,
    alignment: args['alignment']! as String,
    mode: args['mode']! as String,
  );
}
