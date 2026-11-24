import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
                          const Chip(
                            avatar: Icon(Icons.info_outline, size: 18),
                            label: Text('غير متصل'),
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
                            value: _connection,
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
                          const FilledButton.icon(
                            onPressed: null,
                            icon: Icon(Icons.search),
                            label: Text('البحث عن الطابعة - قيد التنفيذ'),
                          ),
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
                            value: _paper,
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
