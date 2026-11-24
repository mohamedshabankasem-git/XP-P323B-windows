import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'windows_printer_bridge.dart';

const _driverPage = 'https://www.xprintertech.com/kiosk-mecha/xp-p323b';

void main() => runApp(const XpPrinterWindowsApp());

class XpPrinterWindowsApp extends StatelessWidget {
  const XpPrinterWindowsApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'XP-P323B Printer',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1769AA)),
          scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        ),
        home: const PrinterHomePage(),
      );
}

class PrinterHomePage extends StatefulWidget {
  const PrinterHomePage({super.key});

  @override
  State<PrinterHomePage> createState() => _PrinterHomePageState();
}

class _PrinterHomePageState extends State<PrinterHomePage> {
  String _paper = '58 mm - 384 dots';
  String _connection = 'USB';
  String _language = 'العربية';
  String? _connectedDevice;
  bool _isSearching = false;

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
                        await WindowsPrinterBridge.connectBluetooth(name);
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
          body: Center(
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
                              'سيظهر الجهاز هنا بعد إضافة اكتشاف USB وBluetooth في طبقة Windows الأصلية.'),
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
                                'سيتم ربط الإرسال الخام عبر USB وBluetooth في طبقة Windows الأصلية.'),
                          ),
                          const Divider(),
                          const ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: Icon(Icons.preview_outlined),
                            title: Text('معاينة الصور وPDF والنصوص'),
                            subtitle: Text(
                                'واجهة استقبال الملفات والمعاينة والطباعة ضمن المرحلة التالية.'),
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
      );

  Widget _sectionTitle(String title) => Padding(
        padding: const EdgeInsetsDirectional.only(bottom: 8, start: 4),
        child: Text(title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
      );
}
