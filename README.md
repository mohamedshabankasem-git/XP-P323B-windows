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

## البناء والتحقق

يتطلب Windows 10/11 وFlutter stable وVisual Studio Desktop development with C++.

أوامر البناء:
- flutter config --enable-windows-desktop
- flutter create --platforms=windows --project-name xp_p323b_windows .
- flutter pub get
- flutter analyze
- flutter test
- flutter build windows --release

يتم تنفيذ نفس الخطوات في GitHub Actions على windows-latest ورفع مجلد Release كـ artifact.

## حالة التنفيذ

- [x] أساس واجهة Windows وإعدادات الورق الأولية.
- [x] رابط صفحة تعريف Xprinter الرسمية.
- [x] سير عمل التحقق وبناء Windows Release.
- [ ] تثبيت التعريف آليًا بعد التحقق من ملف الشركة وتوقيعه وطريقة تثبيته.
- [ ] جسر Windows أصلي لاكتشاف USB وBluetooth وإرسال ESC/POS الخام.
- [ ] استقبال الملفات ومعاينة Raster والطباعة.
- [ ] اختبار فعلي على XP-P323B عبر USB وBluetooth.
