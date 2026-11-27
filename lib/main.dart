import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'windows_printer_bridge.dart';
import 'printer/print_document_loader.dart';
import 'printer/print_workspace_page.dart';
import 'printer/raster_print.dart';

const _driverPage = 'https://www.xprintertech.com/kiosk-mecha/xp-p323b';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(XpPrinterWindowsApp(
    initialFilePath: args.isEmpty ? null : args.first,
  ));
}

class XpPrinterWindowsApp extends StatelessWidget {
  const XpPrinterWindowsApp({super.key, this.initialFilePath});

  final String? initialFilePath;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'XP-P323B Printer',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1769AA)),
          scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        ),
        home: PrinterHomePage(initialFilePath: initialFilePath),
      );
}

class PrinterHomePage extends StatefulWidget {
  const PrinterHomePage({super.key, this.initialFilePath});

  final String? initialFilePath;

  @override
  State<PrinterHomePage> createState() => _PrinterHomePageState();
}

class _PrinterHomePageState extends State<PrinterHomePage> {
  String _paper = '58 mm - 384 dots';
  String _connection = 'USB';
  String _language = 'العربية';
  String? _connectedDevice;
  bool _isSearching = false;
  bool _isOpeningFile = false;
  bool _directPrintOnOpen = false;
  bool _settingsLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadPrintPreferences();
    final initialPath = widget.initialFilePath;
    if (initialPath != null && initialPath.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openDocumentFromPath(initialPath);
      });
    }
  }

  int get _paperWidth {
    if (_paper == '58 mm - 400 dots') return 400;
    if (_paper == '80 mm') return 576;
    return 384;
  }

  Future<void> _loadPrintPreferences() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _directPrintOnOpen = preferences.getBool('directPrintOnOpen') ?? false;
      _settingsLoaded = true;
    });
  }

  Future<void> _setDirectPrintOnOpen(bool value) async {
    setState(() => _directPrintOnOpen = value);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setBool('directPrintOnOpen', value);
  }

  Future<void> _printDocumentDirectly(
    PrintDocument document, {
    required int paperWidth,
  }) async {
    if (_connectedDevice == null) {
      throw StateError('لا توجد طابعة متصلة. اتصل بالطابعة أولاً.');
    }
    for (var index = 0; index < document.pages.length; index++) {
      final payload = await RasterPrint.imageToEscPosAsync(
        document.pages[index],
        maxWidth: paperWidth,
        alignment: 'left',
        mode: 'floydSteinberg',
      );
      final written = await WindowsPrinterBridge.write(payload);
      if (written != payload.length) {
        throw StateError('لم يتم إرسال الصفحة ${index + 1} بالكامل.');
      }
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال الملف مباشرة إلى الطابعة.')),
      );
    }
  }

  Future<void> _pickImage() async {
    await _pickAndOpen(allowed: const [
      'png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp', 'tif', 'tiff',
    ]);
  }

  Future<void> _pickFile() async {
    await _pickAndOpen(allowed: const [
      'png', 'jpg', 'jpeg', 'bmp', 'gif', 'webp', 'tif', 'tiff',
      'pdf', 'txt', 'csv', 'log',
    ]);
  }

  Future<void> _pickAndOpen({required List<String> allowed}) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: allowed,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;
      final path = result.files.single.path;
      if (path == null || path.isEmpty) {
        throw const FormatException('تعذر الحصول على مسار الملف.');
      }
      await _openDocumentFromPath(path);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فتح الملف: $error')),
        );
      }
    }
  }

  Future<void> _openDocumentFromPath(String path) async {
    if (_isOpeningFile) return;
    setState(() => _isOpeningFile = true);
    try {
      final document = await PrintDocumentLoader.fromPath(
        path,
        paperWidth: _paperWidth,
      );
      if (!mounted) return;
      if (_directPrintOnOpen) {
        await _printDocumentDirectly(document, paperWidth: _paperWidth);
        return;
      }
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PrintWorkspacePage(
            name: document.name,
            pages: document.pages,
            paperWidth: _paperWidth,
            connected: _connectedDevice != null,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تجهيز الملف للطباعة: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isOpeningFile = false);
    }
  }

  Future<void> _searchPrinters() async {
    setState(() => _isSearching = true);
    try {
      final devices = _connection == 'USB'
          ? await WindowsPrinterBridge.listUsbPrinters()
          : await WindowsPrinterBridge.listBluetoothPorts();
      if (!mounted) return;
      if (devices.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_connection == 'USB'
              ? 'لم يتم العثور على طابعات Windows. تحقق من توصيل USB وتثبيت التعريف.'
              : 'لم يتم العثور على منافذ Bluetooth. قم بإقران الطابعة من إعدادات Windows أولاً.')),
        );
        return;
      }
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(_connection == 'USB' ? 'طابعات Windows' : 'منافذ Bluetooth'),
          content: SizedBox(
            width: 460,
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: devices.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final device = devices[index];
                final name = (device['name'] ?? '').toString();
                final detail = (device['port'] ?? device['description'] ?? '').toString();
                return ListTile(
                  leading: Icon(_connection == 'USB' ? Icons.print : Icons.bluetooth),
                  title: Text(name),
                  subtitle: detail.isEmpty ? null : Text(detail),
                  onTap: () async {
                    Navigator.of(dialogContext).pop();
                    try {
                      if (_connection == 'USB') {
                        await WindowsPrinterBridge.connectUsb(name);
                      } else {
                        await WindowsPrinterBridge.connectBluetooth(detail);
                      }
                      if (!mounted) return;
                      setState(() => _connectedDevice = name);
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text('تم الاتصال بـ $name')),
                      );
                    } on PlatformException catch (error) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(content: Text('فشل الاتصال: ${error.message ?? error.code}')),
                      );
                    }
                  },
                );
              },
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('إغلاق'))],
        ),
      );
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر البحث: ${error.message ?? error.code}')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('حدث خطأ أثناء البحث: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSearching = false);
    }
  }

  Future<void> _disconnectPrinter() async {
    try {
      await WindowsPrinterBridge.disconnect();
      if (mounted) setState(() => _connectedDevice = null);
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر قطع الاتصال: ${error.message ?? error.code}')),
        );
      }
    }
  }

  Future<void> _openDriverPage() async {
    final opened = await launchUrl(
      Uri.parse(_driverPage),
      mode: LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر فتح موقع Xprinter الرسمي')),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection:
            _language == 'العربية' ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          appBar: AppBar(
            title: const Text('XP-P323B Printer'),
            actions: [
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 16),
                child: DropdownButton<String>(
                  value: _language,
                  underline: const SizedBox.shrink(),
                  items: const [
                    DropdownMenuItem(value: 'العربية', child: Text('العربية')),
                    DropdownMenuItem(value: 'English', child: Text('English')),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _language = value);
                  },
                ),
              ),
            ],
          ),
          body: DropTarget(
            onDragDone: (detail) {
              if (detail.files.isEmpty) return;
              final path = detail.files.first.path;
              if (path.isEmpty) return;
              _openDocumentFromPath(path);
              if (detail.files.length > 1 && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('تم استلام أول ملف فقط. اسحب ملفًا واحدًا في كل مرة.'),
                  ),
                );
              }
            },
            child: Center(
              child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Row(
                        children: [
                          const Icon(Icons.print_rounded,
                              size: 54, color: Color(0xFF1769AA)),
                          const SizedBox(width: 20),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Xprinter XP-P323B',
                                    style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.bold)),
                                SizedBox(height: 6),
                                Text('إدارة الطابعة والطباعة الحرارية على Windows'),
                              ],
                            ),
                          ),
                          Chip(
                            avatar: const Icon(Icons.info_outline, size: 18),
                            label: Text(_connectedDevice == null ? 'غير متصل' : 'متصل'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle('الملفات والطباعة'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Text(
                            'اختر صورة أو ملف PDF أو نصًا، ثم راجع معاينة الورق قبل إرسال أمر الطباعة.',
                          ),
                          const SizedBox(height: 14),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _isOpeningFile ? null : _pickImage,
                                  icon: const Icon(Icons.add_photo_alternate_outlined),
                                  label: const Text('إدراج صورة'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isOpeningFile ? null : _pickFile,
                                  icon: const Icon(Icons.folder_open),
                                  label: const Text('فتح ملف'),
                                ),
                              ),
                            ],
                          ),
                          if (_isOpeningFile) ...[
                            const SizedBox(height: 12),
                            const LinearProgressIndicator(),
                            const SizedBox(height: 6),
                            const Text('جارٍ تجهيز الملف والمعاينة...'),
                          ],
                          const SizedBox(height: 8),
                          const Text(
                            'يمكن أيضًا فتح الملف من مستكشف Windows عبر Open with أو Send to بعد تسجيل التطبيق.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle('الاتصال بالطابعة'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _connection,
                            decoration: const InputDecoration(
                                labelText: 'طريقة الاتصال',
                                border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(
                                  value: 'USB', child: Text('USB')),
                              DropdownMenuItem(
                                  value: 'Bluetooth', child: Text('Bluetooth')),
                            ],
                            onChanged: (value) {
                              if (value != null) {
                                setState(() => _connection = value);
                              }
                            },
                          ),
                          const SizedBox(height: 12),
                          const Text(
                              'اختر طريقة الاتصال ثم ابحث عن الطابعة المتصلة عبر USB أو Bluetooth.'),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: _isSearching ? null : _searchPrinters,
                            icon: _isSearching
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                                : const Icon(Icons.search),
                            label: Text(_isSearching ? 'جارٍ البحث...' : 'البحث عن الطابعة'),
                          ),
                          if (_connectedDevice != null) ...[
                            const SizedBox(height: 10),
                            Text('الطابعة المتصلة: $_connectedDevice'),
                            Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: TextButton.icon(
                                onPressed: _disconnectPrinter,
                                icon: const Icon(Icons.link_off),
                                label: const Text('قطع الاتصال'),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle('تعريف Windows الرسمي'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                              'لتظهر الطابعة في إعدادات Printers & scanners وتعمل مع برامج Windows الأخرى، يجب تثبيت حزمة Xprinter الرسمية بصلاحيات المسؤول.'),
                          const SizedBox(height: 8),
                          const Text(
                              'الموقع الرسمي يعرض تعريف Windows لطراز XP-P323B (حجم الحزمة المعلن 85 MB).'),
                          const SizedBox(height: 14),
                          OutlinedButton.icon(
                            onPressed: _openDriverPage,
                            icon: const Icon(Icons.open_in_new),
                            label: const Text('فتح تعريف XP-P323B الرسمي'),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                              'هذا الزر يفتح صفحة الشركة الرسمية؛ ولا ينفذ تثبيتًا صامتًا أو غير موثّق للتعريف.',
                              style: TextStyle(color: Colors.black54)),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  _sectionTitle('إعدادات الطباعة'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _paper,
                            decoration: const InputDecoration(
                                labelText: 'عرض الورق',
                                border: OutlineInputBorder()),
                            items: const [
                              DropdownMenuItem(
                                  value: '58 mm - 384 dots',
                                  child: Text('58 مم - 384 نقطة')),
                              DropdownMenuItem(
                                  value: '58 mm - 400 dots',
                                  child: Text('58 مم - 400 نقطة')),
                              DropdownMenuItem(
                                  value: '80 mm',
                                  child: Text(
                                      '80 مم (حد الطباعة الفعلي 576 نقطة)')),
                            ],
                            onChanged: (value) {
                              if (value != null) setState(() => _paper = value);
                            },
                          ),
                          const SizedBox(height: 14),
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.receipt_long),
                            title: Text('محرك ESC/POS Raster'),
                            subtitle: Text(
                                'يتم إرسال بيانات ESC/POS Raster مباشرة عبر اتصال الطابعة المحدد.'),
                          ),
                          const Divider(),
                          const Divider(),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            value: _directPrintOnOpen,
                            onChanged: _settingsLoaded ? _setDirectPrintOnOpen : null,
                            secondary: const Icon(Icons.print),
                            title: const Text('الطباعة المباشرة عند فتح الملف'),
                            subtitle: const Text(
                              'عند التفعيل، يرسل البرنامج الملف للطابعة فور فتحه دون عرض شاشة المعاينة. عند الإيقاف، تظهر المعاينة أولاً.',
                            ),
                          ),
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.preview_outlined),
                            title: Text('معاينة الصور وPDF والنصوص'),
                            subtitle: Text(
                                'اختر صورة أو PDF أو نصًا من قسم الملفات والطباعة لمعاينته قبل الإرسال.'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              ),
            ),
          ),
        ),
      );

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 8, start: 4),
        child: Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      );
}
