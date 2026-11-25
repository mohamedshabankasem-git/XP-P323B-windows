# XP-P323B Windows

تطبيق Windows مستقل لإدارة طابعة **Xprinter XP-P323B**. هذا المستودع منفصل عن تطبيق Android.

## النطاق المستهدف

- تثبيت تعريف الشركة الرسمي ليظهر الجهاز في Windows Printers & scanners.
- اتصال مباشر من داخل التطبيق عبر USB وBluetooth.
- إرسال أوامر ESC/POS Raster مباشرة دون الاعتماد على مسار تعريف Windows.
- استقبال الصور وPDF والنصوص، معاينة المخرجات ثم الطباعة.
- إعدادات الورق: 58 مم / 384 نقطة، 58 مم / 400 نقطة، و80 مم مع مراعاة أقصى عرض طباعة فعلي 72 مم (576 نقطة).
- واجهة عربية وإنجليزية.

## تعريف الشركة

صفحة Xprinter الرسمية للطراز XP-P323B:
https://www.xprintertech.com/kiosk-mecha/xp-p323b

تعرض الصفحة حزمة Windows Driver بحجم معلن 85 MB وWindows SDK. زر التعريف في التطبيق يفتح صفحة الشركة الرسمية؛ لا يقوم التطبيق في هذه المرحلة بتثبيت حزمة غير مفحوصة أو تشغيلها بصلاحيات المسؤول تلقائيًا.

## حزمة Windows ومتطلبات التشغيل

يحتوي مجلد الإصدار على ملف التطبيق التنفيذي وملفات Flutter والإضافات التابعة له. أثناء تجهيز الإصدار، ينسخ GitHub Actions ملفات Visual C++ Runtime المطابقة لمعمارية x64 إلى جانب ملف EXE، بما فيها الملفات الأساسية:

- `MSVCP140.dll`
- `VCRUNTIME140.dll`
- `VCRUNTIME140_1.dll`

ويتم تضمين بقية ملفات DLL والـ manifest الموجودة في مجلد Microsoft.VC143.CRT الخاص ببيئة البناء. كما يتحقق سير العمل من وجود الملفات الأساسية قبل رفع الحزمة، ويفشل إذا كانت ناقصة.

هذا يجعل حزمة التطبيق مستقلة عن تثبيت Microsoft Visual C++ Redistributable على أجهزة Windows 10/11 المدعومة، لكنه لا يضمّن تعريف الطابعة نفسه أو مكونات Windows النظامية.

## البناء والتحقق

يتطلب بناء المشروع Windows 10/11 وFlutter stable وVisual Studio Desktop development with C++.

أوامر البناء:
- flutter config --enable-windows-desktop
- flutter create --platforms=windows --project-name xp_p323b_windows .
- flutter pub get
- flutter analyze
- flutter test
- flutter build windows --release

يتم تنفيذ الخطوات في GitHub Actions على windows-latest، ثم تجهيز ملفات Visual C++ Runtime والتحقق منها ورفع مجلد Release كـ artifact.

## حالة التنفيذ

- [x] أساس واجهة Windows وإعدادات الورق الأولية.
- [x] رابط صفحة تعريف Xprinter الرسمية.
- [x] سير عمل التحقق وبناء Windows Release.
- [x] تضمين ملفات Visual C++ Runtime الأساسية في حزمة Windows والتحقق منها أثناء البناء.
- [ ] تثبيت التعريف آليًا بعد التحقق من ملف الشركة وتوقيعه وطريقة تثبيته.
- [x] إضافة جسر Windows أصلي مبدئي عبر MethodChannel: طوابير الطباعة المثبتة (RAW spooler) ومنافذ COM.
- [ ] تضييق اكتشاف Bluetooth إلى منافذ SPP التابعة لأجهزة Bluetooth فقط، والتحقق من اسم/هوية XP-P323B.
- [ ] اختبار الاتصال والإرسال على طابعة فعلية عبر USB وBluetooth.
- [ ] اختيار الصور وملفات PDF والنصوص من داخل التطبيق (بانتظار نجاح CI والاختبار الفعلي).
- [ ] تجهيز معاينة Raster من نفس بيانات الطباعة (بانتظار نجاح CI والاختبار الفعلي).
- [ ] تسجيل Open with وSend to لأنواع الصور وPDF والنصوص عبر سكربتات PowerShell.
- [ ] اختبار فتح الملفات من Windows Shell والطباعة الفعلية على XP-P323B.
- [x] نقل محرك تحويل الصور إلى ESC/POS Raster مع Floyd-Steinberg وAtkinson وOrdered وThreshold، ومحاذاة برمجية واختبارات.
- [ ] اختبار فعلي على XP-P323B عبر USB وBluetooth.

## جسر الاتصال الأصلي - المرحلة الأولى

تمت إضافة `lib/windows_printer_bridge.dart` وطبقة C++ في `windows/runner/xp_printer_bridge.*`. يقوم سير البناء بتوليد Windows runner ثم يدمج الجسر تلقائيًا عبر `scripts/configure_windows_bridge.ps1`.

- USB: يستخدم الجسر طابور طابعة Windows المثبت ويرسل البيانات كـ RAW عبر Windows Print Spooler. يتطلب ظهور طابعة XP-P323B في قائمة طابعات Windows بعد تثبيت تعريف الشركة. هذا المسار ليس اتصال WinUSB مباشرًا.
- Bluetooth: يستخدم منفذ COM افتراضيًا ينشئه Windows بعد إقران الطابعة وتفعيل منفذ Serial Port Profile (إن وفره التعريف/الجهاز). القراءة الحالية لخريطة COM في Windows قد تتضمن منافذ تسلسلية أخرى؛ لذلك لم نعتبر اكتشاف Bluetooth المخصص مكتملًا بعد.
- أزرار البحث والاتصال وقطع الاتصال مرتبطة بالجسر الأصلي. لا يتم تأكيد الاتصال إلا بعد نجاح فتح طابور الطباعة أو منفذ COM.
- تمت إضافة واجهة أولية لإرسال ESC/POS Raster من شاشة المعاينة؛ ما زال البناء والاختبار الفعلي مطلوبين.

**مهم:** يجب إقران الطابعة في إعدادات Windows أولًا عند استخدام Bluetooth، وتثبيت تعريف Windows الرسمي عند استخدام طابور USB.


## فتح الملفات من Windows

بعد استخراج مجلد Release، شغّل PowerShell داخل المجلد ونفّذ:

```powershell
.\\register_file_associations.ps1 -ExePath ".\\xp_p323b_windows.exe"
```

يسجل السكربت التطبيق ضمن **Open with** ويضيف اختصارًا إلى **Send to** للصور وPDF والملفات النصية. عند اختيار ملف، يفتح التطبيق الملف مباشرة في شاشة المعاينة. لا يغيّر السكربت التطبيق الافتراضي للملفات. لإلغاء التسجيل شغّل `unregister_file_associations.ps1`.

ملاحظة: هذا تكامل Windows Shell الكلاسيكي (Open with / Send to)، وليس تطبيق UWP يظهر كهدف داخل لوحة مشاركة Windows الحديثة.
